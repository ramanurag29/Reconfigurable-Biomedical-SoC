`timescale 1ns/1ps
`include "06_Simulation/mem/ecg_params.vh"
`include "06_Simulation/mem/fir_params.vh"
// Self-checking FIR test. Two DUTs (private MAC PIPE=0 and PIPE=1) share the stimulus.
//  P1 ECG, 16 taps vs Python golden   P2 ECG, 8 taps vs Python golden
//  P3 latency                          P4 600 random stress trials vs in-TB integer reference
//     (random taps 1..16, shift 0..12, full-range coefficients/samples -> rounding + saturation)
//  P5 overrun handling                 P6 reset during computation
module tb_fir;
    localparam N = `ECG_N;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, cfg_we = 0, sample_valid = 0; reg [3:0] cfg_addr = 0; reg [11:0] cfg_wdata = 0;
    reg [4:0] taps = 16, shift = 11; reg signed [10:0] sample_in = 0;
    wire yv0, yv1, ys0, ys1, yo0, yo1, bz0, bz1, or0, or1; wire signed [10:0] y0, y1; wire [7:0] ll0, ll1;

    fir_block #(.PIPE(0)) d0 (clk, rst_n, cfg_we, cfg_addr, cfg_wdata, taps, shift, sample_valid, sample_in, yv0, y0, ys0, yo0, bz0, or0, ll0);
    fir_block #(.PIPE(1)) d1 (clk, rst_n, cfg_we, cfg_addr, cfg_wdata, taps, shift, sample_valid, sample_in, yv1, y1, ys1, yo1, bz1, or1, ll1);

    reg [11:0] cmem [0:15]; reg [10:0] ex [0:N-1]; reg [10:0] xin [0:N-1];
    integer errors = 0, total_err = 0, i, t, n, c0 = 0, c1 = 0;
    reg mon_en = 0, got0 = 0, got1 = 0; reg signed [10:0] cap0, cap1; reg cs0, cs1;

    always @(posedge clk) begin
        if (yv0) begin
            cap0 = y0; cs0 = ys0; got0 = 1;
            if (mon_en) begin if (y0 !== ex[c0]) begin errors = errors + 1; if (errors < 8) $display("  D0 idx=%0d got=%0d exp=%0d", c0, y0, $signed(ex[c0])); end c0 = c0 + 1; end
        end
        if (yv1) begin
            cap1 = y1; cs1 = ys1; got1 = 1;
            if (mon_en) begin if (y1 !== ex[c1]) begin errors = errors + 1; if (errors < 8) $display("  D1 idx=%0d got=%0d exp=%0d", c1, y1, $signed(ex[c1])); end c1 = c1 + 1; end
        end
    end

    task do_reset; begin rst_n = 0; repeat (3) @(posedge clk); #1; rst_n = 1; @(posedge clk); #1; end endtask
    task wr_coef(input [3:0] a, input [11:0] d); begin cfg_addr = a; cfg_wdata = d; cfg_we = 1; @(posedge clk); #1; cfg_we = 0; end endtask
    task stream(input integer gap);
        integer m;
        begin
            for (m = 0; m < N; m = m + 1) begin
                sample_in = xin[m]; sample_valid = 1; @(posedge clk); #1; sample_valid = 0;
                repeat (gap - 1) begin @(posedge clk); #1; end
            end
            repeat (60) @(posedge clk); #1;
        end
    endtask
    task phase_result(input [255:0] name, input integer cnt0, input integer cnt1);
        begin
            if (cnt0 !== N || cnt1 !== N) begin errors = errors + 1; $display("  %0s: outputs %0d/%0d of %0d", name, cnt0, cnt1, N); end
            $display("[%0s] outputs=%0d/%0d errors=%0d -> %0s", name, cnt0, cnt1, errors, errors == 0 ? "PASS" : "FAIL");
            total_err = total_err + errors; errors = 0;
        end
    endtask

    // ---- independent integer reference for stress
    integer mh [0:15]; integer macc, mshift, mrnd, my, mT;
    reg exp_sat;
    task ref_push(input integer xv);
        integer k;
        begin
            for (k = 15; k > 0; k = k - 1) mh[k] = mh[k-1];
            mh[0] = xv; macc = 0;
            for (k = 0; k < mT; k = k + 1) macc = macc + mh[k] * $signed(cmem[k]);
            mrnd = (mshift == 0) ? 0 : (1 << (mshift - 1));
            my = (macc + mrnd) >>> mshift;
            exp_sat = (my > 1023) || (my < -1024);          // y is 11-bit signed: -1024..+1023
            if (my > 1023) my = 1023; else if (my < -1024) my = -1024;
        end
    endtask
    task send_wait(input integer xv);
        integer w;
        begin
            ref_push(xv); got0 = 0; got1 = 0;
            sample_in = xv; sample_valid = 1; @(posedge clk); #1; sample_valid = 0;
            w = 0; while ((!got0 || !got1) && w < 200) begin @(posedge clk); #1; w = w + 1; end
            if (!got0 || !got1) begin errors = errors + 1; if (errors < 8) $display("  stress timeout"); end
            else begin
                if (cap0 !== my[10:0] || cap1 !== my[10:0]) begin errors = errors + 1; if (errors < 8) $display("  stress T=%0d S=%0d got=%0d/%0d exp=%0d", mT, mshift, cap0, cap1, my); end
                if (cs0 !== exp_sat || cs1 !== exp_sat) begin errors = errors + 1; if (errors < 8) $display("  stress sat flag got=%0b/%0b exp=%0b", cs0, cs1, exp_sat); end
            end
        end
    endtask

    integer lat0, lat1, seed = 99, trial, s, r, nsat = 0;
    initial begin
        $readmemh(`ECG_SIGNED_FILE, xin);
        do_reset;
        // ---------------- P1: ECG 16 taps
        $readmemh(`FIR_COEF16_FILE, cmem); for (i = 0; i < 16; i = i + 1) wr_coef(i, cmem[i]);
        $readmemh(`FIR_Y16_FILE, ex); taps = 16; shift = `FIR_SHIFT;
        // P3 latency (first, on clean history)
        do_reset; got0 = 0; got1 = 0; sample_in = 11'sd100; sample_valid = 1; @(posedge clk); #1; sample_valid = 0;
        lat0 = 0; lat1 = 0; n = 0;
        while ((!got0 || !got1) && n < 100) begin @(posedge clk); #1; n = n + 1; if (yv0 && lat0 == 0) lat0 = n; if (yv1 && lat1 == 0) lat1 = n; end   // sample the pulse itself
        if (lat0 !== 16 + 3 || lat1 !== 16 + 4 || ll0 !== 16 + 2 || ll1 !== 16 + 3) begin errors = errors + 1; $display("  latency got %0d/%0d (busy %0d/%0d)", lat0, lat1, ll0, ll1); end
        $display("[latency 16 taps] sample->y: PIPE0=%0d clk, PIPE1=%0d clk; MAC-busy cycles %0d/%0d -> %0s", lat0, lat1, ll0, ll1, errors == 0 ? "PASS" : "FAIL");
        total_err = total_err + errors; errors = 0;
        do_reset; c0 = 0; c1 = 0; mon_en = 1; stream(40); mon_en = 0; phase_result("ECG 16-tap vs Python golden", c0, c1);
        // ---------------- P2: ECG 8 taps
        $readmemh(`FIR_COEF8_FILE, cmem, 0, 7); for (i = 0; i < 8; i = i + 1) wr_coef(i, cmem[i]);
        $readmemh(`FIR_Y8_FILE, ex); taps = 8;
        do_reset; c0 = 0; c1 = 0; mon_en = 1; stream(24); mon_en = 0; phase_result("ECG 8-tap vs Python golden", c0, c1);
        // ---------------- P4: stress
        for (trial = 0; trial < 600; trial = trial + 1) begin
            do_reset; mT = 1 + ({$random(seed)} % 16); mshift = {$random(seed)} % 13;
            taps = mT; shift = mshift;
            for (i = 0; i < 16; i = i + 1) begin
                r = $random(seed);
                if (trial % 5 == 0) cmem[i] = (r[0]) ? 12'h7FF : 12'h800; else cmem[i] = r[11:0];
                wr_coef(i, cmem[i]);
            end
            for (i = 0; i < 16; i = i + 1) mh[i] = 0;
            for (s = 0; s < 24; s = s + 1) begin
                r = $random(seed);
                if (trial % 3 == 0) send_wait(r[0] ? 511 : -512); else send_wait($signed(r[10:0]));
                if (exp_sat) nsat = nsat + 1;
            end
        end
        $display("[stress 600 trials x 24 samples, random taps/shift/coef; saturating outputs seen=%0d] errors=%0d -> %0s", nsat, errors, (errors == 0 && nsat > 100) ? "PASS" : "FAIL");
        if (nsat <= 100) errors = errors + 1; total_err = total_err + errors; errors = 0;
        // ---------------- P5: overrun
        do_reset; taps = 16; shift = 11; for (i = 0; i < 16; i = i + 1) wr_coef(i, 12'h040);
        for (s = 0; s < 30; s = s + 1) begin sample_in = s; sample_valid = 1; @(posedge clk); #1; sample_valid = 0; repeat (2) @(posedge clk); #1; end
        n = 0; while ((bz0 || bz1) && n < 200) begin @(posedge clk); #1; n = n + 1; end
        if (or0 !== 1 || or1 !== 1 || bz0 || bz1) begin errors = errors + 1; $display("  overrun flags %0b %0b busy %0b %0b", or0, or1, bz0, bz1); end
        do_reset; if (or0 || or1 || bz0 || bz1) begin errors = errors + 1; $display("  reset did not clear overrun/busy"); end
        $display("[overrun flagged, engine recovers, reset clears] errors=%0d -> %0s", errors, errors == 0 ? "PASS" : "FAIL");
        total_err = total_err + errors; errors = 0;
        // ---------------- P6: reset during computation
        sample_in = 11'sd300; sample_valid = 1; @(posedge clk); #1; sample_valid = 0; repeat (6) @(posedge clk); #1;
        got0 = 0; got1 = 0; rst_n = 0; @(posedge clk); #1; rst_n = 1; repeat (60) @(posedge clk); #1;
        if (bz0 || bz1 || got0 || got1) begin errors = errors + 1; $display("  activity after mid-computation reset"); end
        $display("[reset during computation] errors=%0d -> %0s", errors, errors == 0 ? "PASS" : "FAIL");
        total_err = total_err + errors;
        if (total_err == 0) $display("\n*** ALL TESTS PASSED (fir_block, PIPE=0 and PIPE=1) ***"); else $display("\n*** FAILED: %0d errors ***", total_err);
        $finish;
    end
    initial begin #(900_000_000); $display("TIMEOUT"); $finish; end
endmodule
