`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_scheduler : self-checking test of task_scheduler + shared mac_unit + fir_engine + nn_engine.
// Golden models are written inside the testbench in plain integer arithmetic (independent of RTL).
// Checks: bit-exact FIR and NN results under contention for all 3 policies, preemption with
// context save/restore, non-preemptive mode, MAC-op accounting, deadline monitor, reset recovery,
// FIR sample streams during an NN run, and 300 randomized trials.
// -----------------------------------------------------------------------------
module tb_scheduler;
    parameter PIPE = 0;     // run with -Ptb_scheduler.PIPE=1 for the pipelined-MAC variant
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // ---------------- scheduler configuration
    reg [1:0]  policy = 0;  reg mode_sel = 0, preempt_en = 1;
    reg [2:0]  prio0 = 3, prio1 = 4;
    reg [7:0]  quantum = 8;
    reg [15:0] deadline0 = 0, deadline1 = 0;
    reg        stat_clr = 0;

    // ---------------- FIR side
    reg         f_sv = 0;  reg signed [10:0] f_sin = 0;
    reg  [4:0]  taps = 16, fshift = 11;
    wire [3:0]  f_caddr;   wire signed [11:0] f_cdata;
    wire        f_req, f_clr, f_en, f_bnd, f_grant, f_accv, f_ovf;
    wire signed [10:0] f_a;  wire signed [11:0] f_b;
    wire        y_valid, y_sat, y_ovf, f_busy, f_overrun;  wire signed [10:0] y_data;  wire [7:0] f_lat;
    reg signed [11:0] hc [0:15];
    assign f_cdata = hc[f_caddr];

    // ---------------- NN side
    reg         n_start = 0;  reg [4:0] nshift = 6;  reg [15:0] conf_thr = 16'd1000;
    wire [2:0]  feat_addr;  wire signed [7:0] feat_data;
    wire [7:0]  w_addr;     wire signed [7:0] w_data;
    wire [4:0]  b_addr;     wire signed [23:0] b_data;
    wire        n_req, n_load, n_en, n_bnd, n_grant, n_accv, n_ovf;
    wire signed [31:0] n_lv;  wire signed [10:0] n_a;  wire signed [11:0] n_b;
    wire        nn_valid, nn_class, nn_lowconf, nn_ovf, n_busy;
    wire signed [31:0] nn_s0, nn_s1;  wire [15:0] nn_margin, n_lat;
    reg signed [7:0]  feat [0:7];
    reg signed [7:0]  wt   [0:159];
    reg signed [23:0] bias [0:17];
    assign feat_data = feat[feat_addr];
    assign w_data    = wt[w_addr];
    assign b_data    = bias[b_addr];

    wire signed [31:0] acc_out;
    wire [1:0] sst;  wire sowner;
    wire [31:0] m_total, m_ops, m_ovh, m_wsum0, m_wsum1, m_esum0, m_esum1;
    wire [15:0] m_pre, m_t0, m_t1, m_wmax0, m_wmax1, m_lmax0, m_lmax1, m_miss0, m_miss1;

    task_scheduler #(.PIPE(PIPE)) u_sch (
        .clk(clk), .rst_n(rst_n), .policy(policy), .mode_sel(mode_sel), .preempt_en(preempt_en),
        .prio0(prio0), .prio1(prio1), .quantum(quantum), .deadline0(deadline0), .deadline1(deadline1),
        .stat_clr(stat_clr),
        .req0(f_req), .bnd0(f_bnd), .clr0(f_clr), .load0(1'b0), .en0(f_en), .a0(f_a), .b0(f_b), .lv0(32'sd0), .grant0(f_grant),
        .req1(n_req), .bnd1(n_bnd), .clr1(1'b0),  .load1(n_load), .en1(n_en), .a1(n_a), .b1(n_b), .lv1(n_lv), .grant1(n_grant),
        .acc_out(acc_out), .acc_valid0(f_accv), .acc_valid1(n_accv), .ovf0(f_ovf), .ovf1(n_ovf),
        .sched_state(sst), .owner_o(sowner),
        .m_total_cycles(m_total), .m_mac_ops(m_ops), .m_preempts(m_pre), .m_ovh_cycles(m_ovh),
        .m_tasks0(m_t0), .m_tasks1(m_t1), .m_wait_sum0(m_wsum0), .m_wait_sum1(m_wsum1),
        .m_wait_max0(m_wmax0), .m_wait_max1(m_wmax1), .m_lat_max0(m_lmax0), .m_lat_max1(m_lmax1),
        .m_exec_sum0(m_esum0), .m_exec_sum1(m_esum1), .m_miss0(m_miss0), .m_miss1(m_miss1));

    fir_engine u_fir (.clk(clk), .rst_n(rst_n), .sample_valid(f_sv), .sample_in(f_sin),
        .taps_cfg(taps), .shift_cfg(fshift), .coef_addr(f_caddr), .coef_data(f_cdata),
        .mac_req(f_req), .mac_grant(f_grant), .mac_clear(f_clr), .mac_en(f_en), .mac_a(f_a), .mac_b(f_b),
        .mac_acc(acc_out), .mac_acc_valid(f_accv), .mac_overflow(f_ovf),
        .y_valid(y_valid), .y_data(y_data), .y_sat(y_sat), .y_ovf(y_ovf), .busy(f_busy),
        .at_boundary(f_bnd), .overrun(f_overrun), .last_latency(f_lat));

    nn_engine u_nn (.clk(clk), .rst_n(rst_n), .start(n_start), .shift_cfg(nshift), .conf_thr(conf_thr),
        .feat_addr(feat_addr), .feat_data(feat_data), .w_addr(w_addr), .w_data(w_data),
        .b_addr(b_addr), .b_data(b_data),
        .mac_req(n_req), .mac_grant(n_grant), .mac_load(n_load), .mac_load_val(n_lv), .mac_en(n_en),
        .mac_a(n_a), .mac_b(n_b), .mac_acc(acc_out), .mac_acc_valid(n_accv), .mac_overflow(n_ovf),
        .nn_valid(nn_valid), .nn_class(nn_class), .nn_score0(nn_s0), .nn_score1(nn_s1),
        .nn_margin(nn_margin), .nn_lowconf(nn_lowconf), .nn_ovf(nn_ovf), .busy(n_busy),
        .at_boundary(n_bnd), .last_latency(n_lat));

    // ---------------- golden models (testbench-local, integer only)
    reg signed [10:0] ghist [0:15];
    reg signed [63:0] g_acc;
    integer gi, gk;

    function signed [10:0] fir_golden(input integer T, input integer S);
        reg signed [63:0] sum, r, sh;
        integer k;
        begin
            sum = 0;
            for (k = 0; k < T; k = k + 1) sum = sum + ghist[k] * hc[k];
            r  = (S == 0) ? 0 : (64'sd1 <<< (S - 1));
            sh = (sum + r) >>> S;
            if (sh > 1023) fir_golden = 11'sd1023;
            else if (sh < -1024) fir_golden = -11'sd1024;
            else fir_golden = sh[10:0];
        end
    endfunction

    reg signed [63:0] g_h [0:15];
    reg signed [63:0] g_sc0, g_sc1;
    reg               g_cls;
    reg [15:0]        g_marg;
    task nn_golden_run;
        integer n, k;  reg signed [63:0] a, sh, d, ad;
        begin
            for (n = 0; n < 16; n = n + 1) begin
                a = bias[n];
                for (k = 0; k < 8; k = k + 1) a = a + feat[k] * wt[n*8 + k];
                sh = (a + (64'sd1 <<< (nshift - 1))) >>> nshift;
                g_h[n] = (sh < 0) ? 0 : (sh > 127) ? 127 : sh;
            end
            a = bias[16]; for (k = 0; k < 16; k = k + 1) a = a + g_h[k] * wt[128 + k];      g_sc0 = a;
            a = bias[17]; for (k = 0; k < 16; k = k + 1) a = a + g_h[k] * wt[128 + 16 + k]; g_sc1 = a;
            g_cls = (g_sc1 > g_sc0);
            d = g_sc1 - g_sc0; ad = (d < 0) ? -d : d;
            g_marg = (ad > 65535) ? 16'hFFFF : ad[15:0];
        end
    endtask

    // ---------------- scoreboards
    reg signed [10:0] fq [0:1023];  integer fq_w, fq_r;
    integer nn_exp_pending;
    reg g_cls_q; reg signed [63:0] g_s0q, g_s1q; reg [15:0] g_mq; reg g_lcq;
    integer errs = 0, checks = 0, fir_done = 0, nn_done = 0;

    always @(posedge clk) if (rst_n) begin
        if (y_valid) begin
            checks = checks + 1; fir_done = fir_done + 1;
            if (fq_r >= fq_w) begin errs = errs + 1; $display("  FAIL unexpected y_valid"); end
            else begin
                if (y_data !== fq[fq_r]) begin errs = errs + 1; $display("  FAIL FIR t=%0t got %0d exp %0d", $time, y_data, fq[fq_r]); end
                fq_r = fq_r + 1;
            end
        end
        if (nn_valid) begin
            checks = checks + 1; nn_done = nn_done + 1;
            if (nn_exp_pending == 0) begin errs = errs + 1; $display("  FAIL unexpected nn_valid"); end
            else begin
                if (nn_s0 !== g_s0q || nn_s1 !== g_s1q || nn_class !== g_cls_q || nn_margin !== g_mq || nn_lowconf !== g_lcq) begin
                    errs = errs + 1;
                    $display("  FAIL NN t=%0t got s0=%0d s1=%0d c=%0d m=%0d exp s0=%0d s1=%0d c=%0d m=%0d",
                             $time, nn_s0, nn_s1, nn_class, nn_margin, g_s0q, g_s1q, g_cls_q, g_mq);
                end
                nn_exp_pending = 0;
            end
        end
    end

    // ---------------- stimulus helpers (all drive on negedge)
    integer seed = 32'h5CED_0001;
    function integer rnd(input integer lo, input integer hi);   // inclusive
        integer r;
        begin r = $random(seed); if (r < 0) r = -r; rnd = lo + (r % (hi - lo + 1)); end
    endfunction

    task randomize_fir_coefs;  integer i;
        begin for (i = 0; i < 16; i = i + 1) hc[i] = rnd(-300, 300); end
    endtask
    task randomize_nn;  integer i;
        begin
            for (i = 0; i < 8; i = i + 1)   feat[i] = rnd(-128, 127);
            for (i = 0; i < 128; i = i + 1) wt[i]   = rnd(-40, 40);
            for (i = 128; i < 160; i = i + 1) wt[i] = rnd(-60, 60);
            for (i = 0; i < 18; i = i + 1)  bias[i] = rnd(-3000, 3000);
        end
    endtask

    task fire_fir;   // inject one random sample (updates golden history + expected queue)
        integer i;
        begin
            @(negedge clk);
            for (i = 15; i > 0; i = i - 1) ghist[i] = ghist[i-1];
            ghist[0] = rnd(-512, 511);
            f_sin = ghist[0]; f_sv = 1;
            fq[fq_w] = fir_golden(taps, fshift); fq_w = fq_w + 1;
            @(negedge clk); f_sv = 0;
        end
    endtask

    task fire_nn;
        begin
            nn_golden_run;
            g_s0q = g_sc0; g_s1q = g_sc1; g_cls_q = g_cls; g_mq = g_marg; g_lcq = (g_marg < conf_thr);
            nn_exp_pending = 1;
            @(negedge clk); n_start = 1; @(negedge clk); n_start = 0;
        end
    endtask

    task wait_idle(input integer timeout);
        integer t;
        begin
            t = 0;
            while ((f_busy || n_busy || nn_exp_pending != 0 || fq_r < fq_w) && t < timeout) begin @(negedge clk); t = t + 1; end
            if (t >= timeout) begin errs = errs + 1; $display("  FAIL TIMEOUT waiting for completion"); end
            repeat (4) @(negedge clk);
        end
    endtask

    task clear_stats; begin @(negedge clk); stat_clr = 1; @(negedge clk); stat_clr = 0; end endtask

    task cfg(input [1:0] p, input msel, input pe, input [2:0] p0, input [2:0] p1, input [7:0] q);
        begin policy = p; mode_sel = msel; preempt_en = pe; prio0 = p0; prio1 = p1; quantum = q; end
    endtask

    reg quiet = 0;
    task expect_true(input cond, input [255:0] name);
        begin
            checks = checks + 1;
            if (!cond) begin errs = errs + 1; $display("[%0s] -> FAIL", name); end
            else if (!quiet) $display("[%0s] -> PASS", name);
        end
    endtask

    // one contention trial: FIR sample after fdel clocks, NN start after ndel clocks (both from now)
    task trial(input integer fdel, input integer ndel);
        integer i;
        begin
            clear_stats;
            fork
                begin repeat (fdel) @(negedge clk); fire_fir; end
                begin repeat (ndel) @(negedge clk); fire_nn;  end
            join
            wait_idle(3000);
        end
    endtask

    integer tr, ops_exp, i2, j, pol;
    reg [1:0] rp;

    initial begin
        $dumpfile("06_Simulation/tb_scheduler.vcd"); $dumpvars(0, tb_scheduler);
        fq_w = 0; fq_r = 0; nn_exp_pending = 0;
        for (i2 = 0; i2 < 16; i2 = i2 + 1) ghist[i2] = 0;
        randomize_fir_coefs; randomize_nn;
        repeat (3) @(negedge clk); rst_n = 1; repeat (3) @(negedge clk);
        $display("== tb_scheduler (MAC PIPE=%0d) ==", PIPE);

        // ---- T1: FIR alone, 16 and 8 taps
        $display("T1 FIR alone");
        taps = 16; clear_stats; fire_fir; wait_idle(200);
        expect_true(m_ops == 17 && m_t0 == 1 && m_t1 == 0 && m_pre == 0, "T1a 16-tap ops=17 tasks=1 preempts=0");
        expect_true(m_wmax0 <= 4, "T1a FIR waits <=4 cycles when MAC is free");
        taps = 8; clear_stats; fire_fir; fire_fir; wait_idle(200);
        expect_true(m_ops == 18 && m_t0 == 2, "T1b 8-tap x2 ops=18 tasks=2");
        taps = 16;

        // ---- T2: NN alone
        $display("T2 NN alone");
        clear_stats; fire_nn; wait_idle(400);
        expect_true(m_ops == 178 && m_t1 == 1 && m_t0 == 0 && m_pre == 0, "T2 NN ops=178 tasks=1");

        // ---- T3: fixed priority, NN (prio 4) preempts a running FIR (prio 3)
        $display("T3 fixed priority: NN preempts FIR (context save/restore)");
        cfg(0, 0, 1, 3, 4, 8); trial(0, 6);
        expect_true(m_pre >= 1, "T3 at least one preemption happened");
        expect_true(m_ops == 17 + 178 && m_t0 == 1 && m_t1 == 1, "T3 all ops executed exactly once");
        expect_true(m_ovh >= 2, "T3 restore overhead counted");
        $display("   preempts=%0d overhead=%0d FIRwait=%0d FIRlat=%0d NNlat=%0d", m_pre, m_ovh, m_wmax0, m_lmax0, m_lmax1);

        // ---- T4: fixed priority, FIR arrives while higher-priority NN runs -> must wait
        $display("T4 fixed priority: low-priority FIR waits for NN");
        trial(20, 0);
        expect_true(m_pre == 0, "T4 no preemption of the higher-priority NN");
        expect_true(m_wmax0 > 100, "T4 FIR waited for the NN");
        $display("   FIRwait=%0d FIRlat=%0d NNlat=%0d", m_wmax0, m_lmax0, m_lmax1);

        // ---- T5: round-robin, both at once, quantum 4
        $display("T5 round-robin quantum=4");
        cfg(1, 0, 1, 3, 4, 4); trial(0, 0);
        expect_true(m_pre >= 5, "T5 RR time-slices between clients");
        expect_true(m_ops == 17 + 178, "T5 ops exact");
        $display("   preempts=%0d overhead=%0d FIRlat=%0d NNlat=%0d", m_pre, m_ovh, m_lmax0, m_lmax1);

        // ---- T6: mode-based, FIR favoured, FIR preempts NN
        $display("T6 mode-based (FIR favoured)");
        cfg(2, 0, 1, 3, 4, 8); trial(20, 0);
        expect_true(m_pre >= 1, "T6 FIR preempted NN");
        expect_true(m_ops == 17 + 178, "T6 ops exact");
        cfg(2, 1, 1, 3, 4, 8); trial(0, 6);       // NN favoured, FIR running
        expect_true(m_pre >= 1, "T6b NN preempted FIR");

        // ---- T7: non-preemptive
        $display("T7 preemption disabled");
        cfg(0, 0, 0, 3, 4, 8); trial(0, 6);
        expect_true(m_pre == 0 && m_ops == 17 + 178, "T7 no preemption, results still exact");

        // ---- T8: deadline monitor
        $display("T8 deadline monitor");
        cfg(0, 0, 1, 3, 4, 8); deadline1 = 50; clear_stats; fire_nn; wait_idle(400);
        expect_true(m_miss1 == 1, "T8a NN misses 50-cycle deadline");
        deadline1 = 1000; clear_stats; fire_nn; wait_idle(400);
        expect_true(m_miss1 == 0, "T8b NN meets 1000-cycle deadline");
        deadline1 = 0;

        // ---- T9: stream of FIR samples during an NN run (FIR favoured, preemptive)
        $display("T9 FIR stream during NN");
        cfg(2, 0, 1, 3, 4, 8); clear_stats;
        fork
            begin repeat (10) @(negedge clk); fire_nn; end
            begin for (j = 0; j < 10; j = j + 1) begin fire_fir; repeat (43) @(negedge clk); end end
        join
        wait_idle(1000);
        expect_true(m_t0 == 10 && m_t1 == 1 && m_ops == 10 * 17 + 178, "T9 10 FIR + 1 NN, ops exact");
        expect_true(f_overrun == 1'b0, "T9 no FIR overrun");
        expect_true(m_pre >= 1, "T9 NN was preempted by FIR samples");
        $display("   preempts=%0d NNlat=%0d FIRmaxlat=%0d total=%0d macops=%0d", m_pre, m_lmax1, m_lmax0, m_total, m_ops);

        // ---- T10: reset in the middle of contention, then clean operation
        $display("T10 reset during contention");
        cfg(0, 0, 1, 3, 4, 8);
        fork
            begin fire_fir; end
            begin repeat (2) @(negedge clk); fire_nn; end
        join
        repeat (25) @(negedge clk);
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
        fq_r = fq_w; nn_exp_pending = 0;
        for (i2 = 0; i2 < 16; i2 = i2 + 1) ghist[i2] = 0;
        expect_true(!f_busy && !n_busy && sst == 2'd0, "T10 engines and scheduler idle after reset");
        trial(0, 6);
        expect_true(m_ops == 17 + 178 && m_t0 == 1 && m_t1 == 1, "T10 clean run after reset");

        // ---- T11: randomized contention, all policies
        $display("T11 300 random trials"); quiet = 1;
        for (tr = 0; tr < 300; tr = tr + 1) begin
            rp = rnd(0, 2);
            cfg(rp, rnd(0, 1), rnd(0, 4) != 0, rnd(0, 7), rnd(0, 7), rnd(1, 20));
            taps = (rnd(0, 1) == 0) ? 8 : 16;
            fshift = rnd(8, 12);
            nshift = rnd(4, 8);
            randomize_fir_coefs; randomize_nn;
            trial(rnd(0, 40), rnd(0, 40));
            ops_exp = (1 + taps) + 178;
            expect_true(m_ops == ops_exp && m_t0 == 1 && m_t1 == 1, "T11 op accounting");
            if (m_pre == 0 && preempt_en == 0) ; // non-preemptive trials simply must stay at 0
            if (!preempt_en) expect_true(m_pre == 0, "T11 preempt_en=0 never preempts");
        end

        quiet = 0; expect_true(errs == 0, "T11 300 random trials: FIR+NN bit-exact, ops exact");
        $display("---- fir results=%0d nn results=%0d checks=%0d errors=%0d", fir_done, nn_done, checks, errs);
        if (errs == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED: %0d", errs);
        $finish;
    end

    initial begin #200_000_000; $display("TESTS FAILED: global timeout"); $finish; end
endmodule
