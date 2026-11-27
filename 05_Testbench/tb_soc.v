`timescale 1ns/1ps
`include "06_Simulation/mem/ecg_params.vh"
`include "06_Simulation/mem/fir_params.vh"
`include "06_Simulation/mem/nn_params.vh"
`include "06_Simulation/mem/q_params.vh"
// -----------------------------------------------------------------------------
// tb_soc : top-level self-checking test of biomed_soc_top (everything through the host bus / pins).
//   P1 config B (direct injection): 3600 real ECG samples streamed while the host runs all 64 NN
//      vectors. Fixed priority, FIR > NN, preemption on -> NN is preempted and resumed (context
//      save/restore). Checked: every FIR output bit-exact vs Python (fir_y16.hex), every NN score/
//      class/margin/lowconf bit-exact vs Python (nn_expected.txt), every quality window bit-exact vs
//      quality_golden.py, quality-aware decision rule, no lost records, scheduler metrics sane.
//   P2 config A (behavioural SAR ADC through the analog pins, real ECG volts from ecg_vin.pwl):
//      same FIR / quality / NN checks -> proves ADC + controller + core end to end.
//   P3 noisy / clipped / flat / baseline-shifted ECG (Experiment 6): quality windows bit-exact,
//      NN decisions made after a POOR window must be reported UNCERTAIN, never abnormal.
//   P4 round-robin policy (quantum 4) with NN > FIR priority irrelevant: results still bit-exact.
// -----------------------------------------------------------------------------
module tb_soc;
    localparam N  = `ECG_N;
    localparam NV = `NN_NVEC;
    reg clk = 0; always #5 clk = ~clk;          // 100 MHz in simulation (time base only)
    reg rst_n = 0;

    // ---------------- DUT
    reg         host_we = 0, host_re = 0; reg [11:0] host_addr = 0; reg [31:0] host_wdata = 0;
    wire [31:0] host_rdata; wire host_rvalid;
    wire        adc_cmp, adc_sample_en; wire [9:0] adc_dac_code;
    reg         byp_v = 0; reg [9:0] byp_d = 0;
    wire        irq, busy, done, abnormal, uncertain, result_valid; wire [15:0] result_data;

    biomed_soc_top dut (.clk(clk), .rst_n(rst_n),
        .host_we(host_we), .host_re(host_re), .host_addr(host_addr), .host_wdata(host_wdata),
        .host_rdata(host_rdata), .host_rvalid(host_rvalid),
        .adc_cmp_in(adc_cmp), .adc_sample_en(adc_sample_en), .adc_dac_code(adc_dac_code),
        .adc_bypass_valid(byp_v), .adc_bypass_data(byp_d),
        .irq(irq), .busy(busy), .done(done), .abnormal(abnormal), .uncertain(uncertain),
        .result_valid(result_valid), .result_data(result_data));

    // ---------------- behavioural analog front end on the macro pins (configuration A)
    real vin = 1.0, vhold, vdac;
    sample_hold_behav u_sh  (.sample_en(adc_sample_en), .vin(vin), .vhold(vhold));
    cdac_behav #(.N(10), .VREF(2.0)) u_dac (.code(adc_dac_code), .vdac(vdac));
    comparator_behav u_cmp (.vin(vhold), .vdac(vdac), .cmp_out(adc_cmp));

    // ---------------- golden data
    reg [9:0]  code_mem [0:N-1];
    reg [10:0] fir_ex   [0:N-1];
    reg [11:0] coef     [0:15];
    reg [7:0]  wmem [0:159]; reg [23:0] bmem [0:17]; reg [7:0] fvec [0:NV*8-1]; reg [31:0] exv [0:NV*5-1];
    reg [11:0] qex  [0:6*`Q_NWIN_CLEAN-1];
    reg [11:0] qnex [0:6*`Q_NWIN_NOISY-1];
    reg [9:0]  noisy_mem [0:`Q_NOISY_N-1];
    real       vin_mem [0:N-1];

    integer errors = 0, total_err = 0, i, j, fd, r;
    real t_r, v_r;

    // ---------------- host bus tasks
    task wr(input [11:0] a, input [31:0] d);
        begin host_addr = a; host_wdata = d; host_we = 1; @(posedge clk); #1; host_we = 0; end
    endtask
    reg [31:0] rd_data;
    task rd(input [11:0] a);
        begin host_addr = a; host_re = 1; @(posedge clk); #1; host_re = 0; rd_data = host_rdata;
              if (!host_rvalid) begin errors = errors + 1; $display("  rvalid missing"); end end
    endtask
    reg [31:0] RUN = 32'h10;          // CTRL.run bit kept by every CTRL write; cleared to stop the ADC
    reg        stop_adc_at_n = 0;     // P2: switch conversions off after exactly N samples

    // ---------------- record checker (FIFO drained by the host through RESULT_POP)
    integer n_fir, n_q, n_nn, nn_seen_poor, qwin_total, uncertain_n, abnormal_n;
    reg     noisy_phase;
    reg [1:0] q_seen;                // last quality class seen in the record stream
    reg [1:0] last_nn_qfield;
    task check_record(input [15:0] w);
        reg [11:0] qe0, qe1, qe2;
        reg exp_unc;
        begin
            case (w[15:14])
                2'b00: begin
                    if (!noisy_phase) begin
                        if (n_fir >= N) begin errors = errors + 1; $display("  extra FIR record"); end
                        else if (w[10:0] !== fir_ex[n_fir]) begin errors = errors + 1;
                            if (errors < 10) $display("  FIR idx=%0d got=%0d exp=%0d", n_fir, $signed(w[10:0]), $signed(fir_ex[n_fir])); end
                    end
                    n_fir = n_fir + 1;
                end
                2'b10: begin
                    if (noisy_phase) begin qe0 = qnex[n_q*6]; qe1 = qnex[n_q*6+1]; qe2 = qnex[n_q*6+2]; end
                    else             begin qe0 = qex[n_q*6];  qe1 = qex[n_q*6+1];  qe2 = qex[n_q*6+2];  end
                    if (w[13:12] !== qe0[1:0] || w[11:8] !== qe1[3:0] || w[7:0] !== qe2[7:0]) begin
                        errors = errors + 1;
                        $display("  QUAL win=%0d got class=%0d flags=%b score=%0d exp class=%0d flags=%b score=%0d",
                                 n_q, w[13:12], w[11:8], w[7:0], qe0[1:0], qe1[3:0], qe2[7:0]);
                    end
                    q_seen = w[13:12]; n_q = n_q + 1; qwin_total = qwin_total + 1;
                end
                2'b01: begin
                    // uncertain = lowconf | ovf | (quality field == POOR) ; abnormal = class & ~uncertain
                    exp_unc = w[10] | (w[9:8] == 2'd2);       // ovf never set by this model (checked via NN_RESULT)
                    if (w[13] !== exp_unc || w[12] !== (w[11] & ~exp_unc)) begin errors = errors + 1;
                        $display("  NN record decision rule violated: %b", w); end
                    if (w[9:8] == 2'd2) nn_seen_poor = nn_seen_poor + 1;
                    if (w[13]) uncertain_n = uncertain_n + 1;
                    if (w[12]) abnormal_n  = abnormal_n + 1;
                    last_nn_qfield = w[9:8];
                    n_nn = n_nn + 1;
                end
                default: begin errors = errors + 1; $display("  bad record type %b", w); end
            endcase
        end
    endtask
    task drain_one; begin rd(12'h500); if (rd_data[16]) check_record(rd_data[15:0]); end endtask
    task drain_all; integer k; begin k = 0; while (result_valid && k < 100) begin drain_one; k = k + 1; end end endtask

    // ---------------- sample sources
    reg stream_go = 0, stream_noisy = 0, stream_done = 0; integer gap = 24;
    initial begin : injector
        integer m, len;
        forever begin
            wait (stream_go);
            stream_done = 0;
            len = stream_noisy ? `Q_NOISY_N : N;
            for (m = 0; m < len; m = m + 1) begin
                byp_d = stream_noisy ? noisy_mem[m] : code_mem[m]; byp_v = 1; @(posedge clk); #1; byp_v = 0;
                repeat (gap - 1) @(posedge clk); #1;
            end
            stream_done = 1; stream_go = 0;
        end
    end
    // configuration A: advance the analog input after every completed sampling phase
    integer vidx = 0; reg samp_q = 0;
    always @(posedge clk) begin
        samp_q <= adc_sample_en;
        if (samp_q && !adc_sample_en) begin vidx = vidx + 1; if (vidx < N) vin = vin_mem[vidx]; end
    end

    // ---------------- NN driver: all NV vectors, back to back, interleaved with FIFO draining
    integer nn_lat_max, nn_lat_sum;
    reg signed [31:0] s0, s1;
    task run_nn_vectors(input integer nvec, input check_scores);
        integer v, q, w;
        begin
            for (v = 0; v < nvec; v = v + 1) begin
                for (q = 0; q < 8; q = q + 1) wr(12'h400 + q, {24'd0, fvec[v*8+q]});
                wr(12'h000, RUN | 32'h2);                       // nn_start
                w = 0;
                while (!done && w < 40000) begin
                    if (stop_adc_at_n && vidx >= N && RUN != 0) begin RUN = 0; wr(12'h000, 32'h0); end
                    if (result_valid) drain_one; else begin @(posedge clk); #1; end
                    w = w + 1;
                end
                if (!done) begin errors = errors + 1; $display("  NN vec %0d timeout", v); end
                rd(12'h00D); s0 = rd_data; rd(12'h00E); s1 = rd_data; rd(12'h00C);
                if (check_scores) begin
                    if (s0 !== exv[v*5] || s1 !== exv[v*5+1] || rd_data[0] !== exv[v*5+2][0] ||
                        rd_data[31:16] !== exv[v*5+3][15:0] || rd_data[1] !== exv[v*5+4][0]) begin
                        errors = errors + 1;
                        if (errors < 10) $display("  NN vec %0d got s0=%0d s1=%0d cls=%0d marg=%0d lc=%0d  exp s0=%0d s1=%0d cls=%0d marg=%0d lc=%0d",
                            v, s0, s1, rd_data[0], rd_data[31:16], rd_data[1],
                            $signed(exv[v*5]), $signed(exv[v*5+1]), exv[v*5+2][0], exv[v*5+3][15:0], exv[v*5+4][0]);
                    end
                    if (rd_data[2]) begin errors = errors + 1; $display("  unexpected NN overflow"); end
                end
                rd(12'h010);
                if (rd_data[31:16] > nn_lat_max) nn_lat_max = rd_data[31:16];
                nn_lat_sum = nn_lat_sum + rd_data[31:16];
                wr(12'h00B, 32'h2);                              // W1C nn_done
            end
        end
    endtask

    task finish_stream; integer w, quiet; begin
        w = 0; quiet = 0;
        while ((!stream_done || quiet < 64) && w < 400000) begin       // 64 idle cycles = pipeline drained
            if (result_valid) begin drain_one; quiet = 0; end
            else begin @(posedge clk); #1; quiet = busy ? 0 : quiet + 1; end
            w = w + 1;
        end
        drain_all;
    end endtask

    task start_phase; begin
        n_fir = 0; n_q = 0; n_nn = 0; nn_seen_poor = 0; qwin_total = 0; uncertain_n = 0; abnormal_n = 0;
        nn_lat_max = 0; nn_lat_sum = 0; q_seen = 3;
        wr(12'h000, 32'h1);                                     // soft reset (datapath only), run = 0
        repeat (4) @(posedge clk); #1;
        RUN = 32'h10;
        wr(12'h000, RUN | 32'h4 | 32'h8);                       // run, stat_clr, flag_clr
    end endtask

    task metrics(input [255:0] name);
        reg [31:0] tot, ops, pre, ovh, t01, ws0, ws1, wm, st;
        begin
            rd(12'h011); tot = rd_data; rd(12'h012); ops = rd_data; rd(12'h013); pre = rd_data; rd(12'h014); ovh = rd_data;
            rd(12'h015); t01 = rd_data; rd(12'h016); ws0 = rd_data; rd(12'h017); ws1 = rd_data; rd(12'h018); wm = rd_data;
            rd(12'h001); st = rd_data;
            $display("  [%0s] cycles=%0d mac_ops=%0d util=%0d%% preempts=%0d restore_ovh=%0d tasks FIR/NN=%0d/%0d",
                     name, tot, ops, (ops * 100) / (tot == 0 ? 1 : tot), pre[15:0], ovh, t01[15:0], t01[31:16]);
            $display("  [%0s] wait avg x100 FIR=%0d NN=%0d cyc, wait max FIR/NN=%0d/%0d, NN latency avg/max=%0d/%0d cyc",
                     name, (ws0 * 100) / (t01[15:0] == 0 ? 1 : t01[15:0]), (ws1 * 100) / (t01[31:16] == 0 ? 1 : t01[31:16]),
                     wm[15:0], wm[31:16], nn_lat_sum / NV, nn_lat_max);
            if (st[8] || st[5] || st[7]) begin errors = errors + 1; $display("  sticky error flags STATUS=%h (lost/fifo_ovf/overrun)", st); end
        end
    endtask

    task phase_end(input [255:0] name, input integer exp_fir, input integer exp_q);
        begin
            if (n_fir !== exp_fir) begin errors = errors + 1; $display("  FIR records %0d exp %0d", n_fir, exp_fir); end
            if (n_q   !== exp_q)   begin errors = errors + 1; $display("  quality records %0d exp %0d", n_q, exp_q); end
            if (n_nn  !== NV)      begin errors = errors + 1; $display("  NN records %0d exp %0d", n_nn, NV); end
            metrics(name);
            $display("[%0s] FIR=%0d QUAL=%0d NN=%0d (uncertain %0d, abnormal %0d) errors=%0d -> %0s",
                     name, n_fir, n_q, n_nn, uncertain_n, abnormal_n, errors, errors == 0 ? "PASS" : "FAIL");
            total_err = total_err + errors; errors = 0;
        end
    endtask

    initial begin
        $readmemh(`ECG_CODE_FILE, code_mem);
        $readmemh(`FIR_Y16_FILE, fir_ex);
        $readmemh(`FIR_COEF16_FILE, coef);
        $readmemh("06_Simulation/mem/nn_weights.hex", wmem);
        $readmemh("06_Simulation/mem/nn_bias.hex", bmem);
        $readmemh("06_Simulation/mem/nn_feat_vec.hex", fvec);
        $readmemh("06_Simulation/mem/nn_expected.txt", exv);
        $readmemh("06_Simulation/mem/q_expected.txt", qex);
        $readmemh("06_Simulation/mem/q_noisy_expected.txt", qnex);
        $readmemh("06_Simulation/mem/ecg_noisy_10b.hex", noisy_mem);
        fd = $fopen(`ECG_VIN_FILE, "r");
        for (i = 0; i < N; i = i + 1) begin r = $fscanf(fd, "%f %f\n", t_r, v_r); vin_mem[i] = v_r; end
        $fclose(fd);
        noisy_phase = 0;

        repeat (5) @(posedge clk); #1; rst_n = 1; repeat (4) @(posedge clk); #1;
        rd(12'h01F); if (rd_data !== 32'hB10C0001) begin errors = errors + 1; $display("  bad CHIP_ID %h", rd_data); end

        // ---- load coefficients / weights / biases through the host bus
        for (i = 0; i < 16; i = i + 1)  wr(12'h100 + i, {20'd0, coef[i]});
        for (i = 0; i < 160; i = i + 1) wr(12'h200 + i, {24'd0, wmem[i]});
        for (i = 0; i < 18; i = i + 1)  wr(12'h300 + i, {8'd0, bmem[i]});
        wr(12'h004, {19'd0, 5'd11, 3'd0, 5'd16});               // 16 taps, S = 11
        wr(12'h008, {16'd`NN_CONF_THR, 11'd0, 5'd`NN_S1});
        wr(12'h00A, 32'hF);                                     // all IRQs enabled

        // ================= P1: configuration B, FIR priority, preemptive
        wr(12'h002, 32'h1C | 32'd2);                            // mode FIR+NN, bypass, fir+q out
        wr(12'h003, {8'd0, 8'd8, 5'd0, 3'd2, 1'b0, 3'd5, 1'b1, 1'b0, 2'd0});   // fixed, preempt, prio0=5 prio1=2
        start_phase; gap = 24; stream_noisy = 0; stream_go = 1;
        run_nn_vectors(NV, 1);
        finish_stream;
        phase_end("P1 cfgB fixed FIR>NN", N, `Q_NWIN_CLEAN);

        // ================= P2: configuration A, behavioural SAR ADC on the analog pins
        wr(12'h002, 32'h18 | 32'd2);                            // bypass = 0
        wr(12'h005, 32'd48);                                    // one conversion every 48 clocks
        vidx = 0; vin = vin_mem[0]; stop_adc_at_n = 1;
        start_phase;
        run_nn_vectors(NV, 1);
        begin : wait_adc
            integer w; w = 0;
            while (vidx < N && w < 400000) begin if (result_valid) drain_one; else begin @(posedge clk); #1; end w = w + 1; end
        end
        if (RUN != 0) begin RUN = 0; wr(12'h000, 32'h0); end   // stop conversions after exactly N
        stop_adc_at_n = 0;
        stream_done = 1; finish_stream;
        phase_end("P2 cfgA SAR ADC", N, `Q_NWIN_CLEAN);

        // ================= P3: noisy stimulus (Experiment 6), quality-gated decisions
        wr(12'h002, 32'h14 | 32'd2);                            // bypass, FIR records off, quality records on
        noisy_phase = 1;
        start_phase; gap = 24; stream_noisy = 1; stream_go = 1;
        run_nn_vectors(NV, 1);
        finish_stream;
        $display("  P3 NN decisions made while quality was POOR: %0d (all reported uncertain)", nn_seen_poor);
        phase_end("P3 noisy quality", 0, `Q_NWIN_NOISY);
        noisy_phase = 0;

        // ================= P4: round-robin, quantum 4, NN higher priority (ignored by RR)
        wr(12'h002, 32'h1C | 32'd2);
        wr(12'h003, {8'd0, 8'd4, 5'd0, 3'd6, 1'b0, 3'd1, 1'b1, 1'b0, 2'd1});
        start_phase; gap = 80; stream_noisy = 0; stream_go = 1;
        run_nn_vectors(NV, 1);
        finish_stream;
        phase_end("P4 cfgB round-robin", N, `Q_NWIN_CLEAN);

        if (total_err == 0) $display("\n*** ALL TESTS PASSED (biomed_soc_top) ***");
        else                $display("\n*** FAILED: %0d errors ***", total_err);
        $finish;
    end
    initial begin #(50_000_000); $display("GLOBAL TIMEOUT"); $finish; end
endmodule
