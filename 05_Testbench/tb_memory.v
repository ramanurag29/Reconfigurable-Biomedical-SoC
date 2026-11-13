`timescale 1ns/1ps
// Self-checking test of regfile_sync (RESET_CLEAR 0 and 1, two geometries) and sample_buffer
// against independent behavioural models.
module tb_memory;
    reg clk = 0; always #5 clk = ~clk; reg rst_n = 0;
    // regfile A: weights 160x8, no reset clear ; regfile B: coefficients 16x12, reset clears
    reg weA = 0; reg [7:0] waA = 0, raA = 0; reg [7:0] wdA = 0; wire [7:0] rdA;
    reg weB = 0; reg [3:0] waB = 0, raB = 0; reg [11:0] wdB = 0; wire [11:0] rdB;
    regfile_sync #(.WIDTH(8),  .DEPTH(160), .RESET_CLEAR(0)) A (clk, rst_n, weA, waA, wdA, raA, rdA);
    regfile_sync #(.WIDTH(12), .DEPTH(16),  .RESET_CLEAR(1)) B (clk, rst_n, weB, waB, wdB, raB, rdB);
    // sample buffer
    reg wr_en = 0; reg [10:0] wr_data = 0; reg [5:0] off = 0; wire [10:0] rd_data; wire rd_valid; wire [6:0] cnt;
    sample_buffer #(.W(11), .DEPTH(64)) SB (clk, rst_n, wr_en, wr_data, off, rd_data, rd_valid, cnt);

    reg [7:0]  mA [0:159]; reg vA [0:159]; reg [11:0] mB [0:15];
    reg [10:0] hist [0:99999]; integer nw = 0;
    integer errors = 0, i, k, r, seed = 5, expv, expc, sec_err;

    task chk(input [255:0] what, input integer got, input integer exp);
        begin errors = errors + 1; if (errors < 8) $display("  %0s: got %0d exp %0d", what, got, exp); end
    endtask

    initial begin
        for (i = 0; i < 160; i = i + 1) vA[i] = 0;
        for (i = 0; i < 16; i = i + 1) mB[i] = 0;
        repeat (3) @(posedge clk); #1; rst_n = 1;
        // B must read zero after reset (RESET_CLEAR=1)
        for (i = 0; i < 16; i = i + 1) begin raB = i; #1; if (rdB !== 12'd0) chk("B reset value", rdB, 0); end
        // random traffic
        for (k = 0; k < 40000; k = k + 1) begin
            r = $random(seed);
            weA = r[0]; waA = {$random(seed)} % 160; wdA = $random(seed);
            weB = r[1]; waB = {$random(seed)} % 16;  wdB = $random(seed);
            raA = {$random(seed)} % 160; raB = {$random(seed)} % 16;
            wr_en = r[2]; wr_data = $random(seed); off = {$random(seed)} % 64;
            #1;
            // async-read checks BEFORE the edge (pre-write contents)
            if (vA[raA] && rdA !== mA[raA]) chk("A read", rdA, mA[raA]);
            if (rdB !== mB[raB]) chk("B read", rdB, mB[raB]);
            expc = (nw < 64) ? nw : 64;
            if (cnt !== expc) chk("sb count", cnt, expc);
            if (rd_valid !== (off < expc)) chk("sb rd_valid", rd_valid, off < expc);
            if (off < expc && rd_data !== hist[nw - 1 - off]) chk("sb rd_data", rd_data, hist[nw - 1 - off]);
            @(posedge clk); #1;
            if (weA) begin mA[waA] = wdA; vA[waA] = 1; end
            if (weB) mB[waB] = wdB;
            if (wr_en) begin hist[nw] = wr_data; nw = nw + 1; end
            if (k == 20000) begin   // reset mid-run: B clears, sample buffer empties, A keeps (no reset)
                wr_en = 0; weA = 0; weB = 0; rst_n = 0; #1; @(posedge clk); #1; rst_n = 1;
                for (i = 0; i < 16; i = i + 1) mB[i] = 0;
                nw = 0;
            end
        end
        $display("[regfile 160x8 (no-reset) / 16x12 (reset-clear) / sample_buffer 64x11, 40k random cycles] errors=%0d -> %0s", errors, errors == 0 ? "PASS" : "FAIL");
        if (errors == 0) $display("\n*** ALL TESTS PASSED (memory) ***"); else $display("\n*** FAILED ***");
        $finish;
    end
    initial begin #(50_000_000); $display("TIMEOUT"); $finish; end
endmodule
