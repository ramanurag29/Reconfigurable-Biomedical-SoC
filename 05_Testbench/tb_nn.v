`timescale 1ns/1ps
`include "06_Simulation/mem/nn_params.vh"
// Self-checking NN test. Two DUTs (private MAC PIPE=0 / PIPE=1) share the stimulus.
//  P1 trained model + test vectors from Python (nn_golden.infer_int)   P2 latency (PIPE0 = 197, PIPE1 = 215)
//  P3 300 random stress trials vs in-TB integer reference (full-range weights/biases -> saturation, margin clamp)
//  P4 tie -> class 0                                                   P5 start-while-busy ignored
//  P6 reset during inference, then clean re-run
module tb_nn;
    localparam NV = `NN_NVEC;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, cfg_we = 0, start = 0; reg [1:0] cfg_sel = 0; reg [7:0] cfg_addr = 0; reg [23:0] cfg_wdata = 0;
    reg [4:0] shift = `NN_S1; reg [15:0] thr = `NN_CONF_THR;
    wire v0, v1, c0, c1, lc0, lc1, o0, o1, b0, b1; wire signed [31:0] a0, a1, s00, s01, s10, s11;
    wire [15:0] m0, m1, l0, l1;
    nn_block #(.PIPE(0)) d0 (clk, rst_n, cfg_we, cfg_sel, cfg_addr, cfg_wdata, start, shift, thr, v0, c0, s00, s01, m0, lc0, o0, b0, l0);
    nn_block #(.PIPE(1)) d1 (clk, rst_n, cfg_we, cfg_sel, cfg_addr, cfg_wdata, start, shift, thr, v1, c1, s10, s11, m1, lc1, o1, b1, l1);

    reg [7:0]  wmem [0:159]; reg [23:0] bmem [0:17]; reg [7:0] fmem [0:7];
    reg [7:0]  fvec [0:NV*8-1]; reg [31:0] exv [0:NV*5-1];
    integer errors = 0, total_err = 0, i, j, t;

    task wr(input [1:0] sel, input [7:0] a, input [23:0] d);
        begin cfg_sel = sel; cfg_addr = a; cfg_wdata = d; cfg_we = 1; @(posedge clk); #1; cfg_we = 0; end
    endtask
    task load_shadow;      // push shadow arrays into both DUTs
        integer q;
        begin
            for (q = 0; q < 160; q = q + 1) wr(2'd0, q, wmem[q]);
            for (q = 0; q < 18;  q = q + 1) wr(2'd1, q, bmem[q]);
            for (q = 0; q < 8;   q = q + 1) wr(2'd2, q, fmem[q]);
        end
    endtask
    task load_feat; integer q; begin for (q = 0; q < 8; q = q + 1) wr(2'd2, q, fmem[q]); end endtask
    reg g0 = 0, g1 = 0; integer cnt0 = 0, cnt1 = 0;
    always @(posedge clk) begin if (v0) begin g0 <= 1; cnt0 <= cnt0 + 1; end if (v1) begin g1 <= 1; cnt1 <= cnt1 + 1; end end
    task go_raw; begin start = 1; @(posedge clk); #1; start = 0; end endtask
    task go; begin g0 = 0; g1 = 0; cnt0 = 0; cnt1 = 0; go_raw; end endtask
    task wait_done; integer w; begin w = 0; while (!(g0 && g1) && w < 2000) begin @(posedge clk); #1; w = w + 1; end
        if (w >= 2000) begin errors = errors + 1; $display("  TIMEOUT"); end end endtask

    // ---- integer reference ----
    reg signed [63:0] r_s0, r_s1; reg r_cls, r_low, r_ovf; reg [15:0] r_marg;
    task ref_infer(input [4:0] S, input [15:0] th);
        integer jj, ii; reg signed [63:0] acc, tmp; reg signed [63:0] hh [0:15]; reg signed [63:0] dd; reg [63:0] ad;
        begin
            r_ovf = 0;
            for (jj = 0; jj < 16; jj = jj + 1) begin
                acc = $signed(bmem[jj]);
                for (ii = 0; ii < 8; ii = ii + 1) begin
                    acc = acc + $signed(fmem[ii]) * $signed(wmem[jj*8+ii]);
                    if (acc > 64'sd2147483647) begin acc = 64'sd2147483647; r_ovf = 1; end else if (acc < -64'sd2147483648) begin acc = -64'sd2147483648; r_ovf = 1; end
                end
                tmp = acc + ((S == 0) ? 0 : (64'sd1 <<< (S-1))); tmp = tmp >>> S;
                hh[jj] = (tmp < 0) ? 0 : (tmp > 127) ? 127 : tmp;
            end
            for (jj = 0; jj < 2; jj = jj + 1) begin
                acc = $signed(bmem[16+jj]);
                for (ii = 0; ii < 16; ii = ii + 1) begin
                    acc = acc + hh[ii] * $signed(wmem[128+jj*16+ii]);
                    if (acc > 64'sd2147483647) begin acc = 64'sd2147483647; r_ovf = 1; end else if (acc < -64'sd2147483648) begin acc = -64'sd2147483648; r_ovf = 1; end
                end
                if (jj == 0) r_s0 = acc; else r_s1 = acc;
            end
            dd = r_s1 - r_s0; ad = (dd < 0) ? -dd : dd;
            r_cls = (r_s1 > r_s0); r_marg = (ad > 65535) ? 16'hFFFF : ad[15:0]; r_low = (r_marg < th);
        end
    endtask
    task check(input [255:0] what, input signed [63:0] es0, input signed [63:0] es1, input ec, input [15:0] em, input el);
        begin
            if (o0 !== r_ovf || o1 !== r_ovf || s00 !== es0[31:0] || s01 !== es1[31:0] || c0 !== ec || m0 !== em || lc0 !== el) begin
                errors = errors + 1; if (errors < 8) $display("  D0 %0s got s0=%0d s1=%0d c=%b m=%0d l=%b exp s0=%0d s1=%0d c=%b m=%0d l=%b", what, s00, s01, c0, m0, lc0, es0, es1, ec, em, el); end
            if (s10 !== es0[31:0] || s11 !== es1[31:0] || c1 !== ec || m1 !== em || lc1 !== el) begin
                errors = errors + 1; if (errors < 8) $display("  D1 %0s got s0=%0d s1=%0d c=%b m=%0d l=%b exp s0=%0d s1=%0d c=%b m=%0d l=%b", what, s10, s11, c1, m1, lc1, es0, es1, ec, em, el); end
        end
    endtask
    task phase_result(input [255:0] name);
        begin $display("[%0s] errors=%0d -> %0s", name, errors, errors == 0 ? "PASS" : "FAIL"); total_err = total_err + errors; errors = 0; end
    endtask
    task do_reset; begin rst_n = 0; repeat (3) @(posedge clk); #1; rst_n = 1; @(posedge clk); #1; end endtask

    integer lat_min0 = 99999, lat_max0 = 0, lat_min1 = 99999, lat_max1 = 0;
    integer ok_cls = 0;
    reg signed [63:0] e0, e1;
    initial begin
        $dumpfile("06_Simulation/tb_nn.vcd"); $dumpvars(0, tb_nn);
        $readmemh("06_Simulation/mem/nn_weights.hex", wmem); $readmemh("06_Simulation/mem/nn_bias.hex", bmem);
        $readmemh("06_Simulation/mem/nn_feat_vec.hex", fvec); $readmemh("06_Simulation/mem/nn_expected.txt", exv);
        do_reset;
        // ---- P1 trained model vs Python golden ----
        load_shadow;                                 // shadow arrays hold the trained model
        for (t = 0; t < NV; t = t + 1) begin
            for (i = 0; i < 8; i = i + 1) fmem[i] = fvec[t*8+i];
            load_feat; go; wait_done;
            r_ovf = 0;   // a sane trained model must not saturate the accumulator
            e0 = $signed(exv[t*5]); e1 = $signed(exv[t*5+1]);
            check("vec", e0, e1, exv[t*5+2][0], exv[t*5+3][15:0], exv[t*5+4][0]);
            if (l0 < lat_min0) lat_min0 = l0; if (l0 > lat_max0) lat_max0 = l0;
            if (l1 < lat_min1) lat_min1 = l1; if (l1 > lat_max1) lat_max1 = l1;
            ok_cls = ok_cls + (c0 === exv[t*5+2][0]);
            @(posedge clk); #1;
        end
        $display("[P1 trained-model vectors=%0d]", NV); phase_result("P1 python-golden");
        // ---- P2 latency ----
        $display("[P2 latency PIPE0 min/max=%0d/%0d PIPE1 min/max=%0d/%0d cycles]", lat_min0, lat_max0, lat_min1, lat_max1);
        if (lat_min0 !== lat_max0 || lat_min1 !== lat_max1 || lat_min0 !== 197 || lat_min1 !== 215) errors = errors + 1;
        phase_result("P2 latency");
        // ---- P3 random stress ----
        for (t = 0; t < 300; t = t + 1) begin
            for (i = 0; i < 160; i = i + 1) wmem[i] = (t % 3 == 0) ? ((i % 2) ? 8'h7F : 8'h80) : $urandom;
            for (i = 0; i < 18;  i = i + 1) bmem[i] = (t % 5 == 0) ? (($urandom & 1) ? 24'h7FFFFF : 24'h800000) : (t % 5 == 1 ? ($urandom & 24'h00FFFF) : $urandom);
            for (i = 0; i < 8;   i = i + 1) fmem[i] = (t % 3 == 0) ? 8'h7F : $urandom;
            shift = $urandom % 21; thr = (t % 4 == 0) ? 16'd0 : (t % 4 == 1) ? 16'hFFFF : $urandom;
            load_shadow; go; wait_done;
            ref_infer(shift, thr);
            check("rand", r_s0, r_s1, r_cls, r_marg, r_low);
            @(posedge clk); #1;
        end
        shift = `NN_S1; thr = `NN_CONF_THR;
        phase_result("P3 random-stress");
        // ---- P4 tie -> class 0 ----
        for (i = 0; i < 160; i = i + 1) wmem[i] = 0; for (i = 0; i < 18; i = i + 1) bmem[i] = 24'd5; for (i = 0; i < 8; i = i + 1) fmem[i] = 8'd9;
        load_shadow; go; wait_done; ref_infer(shift, thr);
        if (c0 !== 1'b0 || c1 !== 1'b0 || m0 !== 16'd0) errors = errors + 1;
        check("tie", r_s0, r_s1, r_cls, r_marg, r_low);
        phase_result("P4 tie");
        // ---- P5 start while busy ignored (result of first run only, latency unchanged) ----
        for (i = 0; i < 160; i = i + 1) wmem[i] = $urandom; for (i = 0; i < 18; i = i + 1) bmem[i] = $urandom & 24'h00FFFF; for (i = 0; i < 8; i = i + 1) fmem[i] = $urandom;
        load_shadow; go; repeat (20) @(posedge clk); #1; go_raw; wait_done; ref_infer(shift, thr);
        check("busy-start", r_s0, r_s1, r_cls, r_marg, r_low);
        if (l0 !== 197) errors = errors + 1;
        repeat (400) @(posedge clk);
        if (cnt0 !== 1 || cnt1 !== 1) begin errors = errors + 1; $display("  result pulses %0d/%0d (expected 1/1)", cnt0, cnt1); end
        phase_result("P5 start-while-busy");
        // ---- P6 reset during inference, then re-run ----
        go; repeat (50) @(posedge clk); #1; do_reset; g0 = 0; g1 = 0;
        if (b0 || b1 || v0 || v1) errors = errors + 1;
        load_shadow; go; wait_done; ref_infer(shift, thr);
        check("post-reset", r_s0, r_s1, r_cls, r_marg, r_low);
        phase_result("P6 reset");
        if (total_err == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED: %0d errors", total_err);
        $finish;
    end
endmodule
