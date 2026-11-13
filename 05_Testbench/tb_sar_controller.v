`timescale 1ns/1ps
// Exhaustive self-checking test of sar_controller against an ideal integer comparator
// (cmp_out = dac_code <= T  <=>  held input >= trial voltage). Two sample-phase lengths.
module sar_ctrl_chk #(parameter N = 10, parameter SC = 1) (
    input  wire clk,
    output reg  [31:0] errors,
    output reg  finished
);
    reg rst_n = 0, start = 0; integer T = 0;
    wire sample_en, busy, done; wire [N-1:0] dac_code, data_out;
    wire cmp_out = (dac_code <= T);
    sar_controller #(.N(N), .SAMPLE_CYCLES(SC)) dut (.clk(clk), .rst_n(rst_n), .start(start),
        .cmp_out(cmp_out), .sample_en(sample_en), .dac_code(dac_code), .busy(busy),
        .done(done), .data_out(data_out));

    integer k, dones;
    task err(input [255:0] msg, input integer a, input integer b);
        begin errors = errors + 1; if (errors < 8) $display("  [SC=%0d] %0s: got %0d exp %0d", SC, msg, a, b); end
    endtask

    task convert(input integer t);
        integer n, samp;
        begin
            T = t; start = 1; @(posedge clk); #1; start = 0;
            n = 0; samp = 0;
            while (!done && n < 100) begin
                if (sample_en) samp = samp + 1;
                if (!busy) err("busy low during conversion", 0, 1);
                @(posedge clk); #1; n = n + 1;
            end
            if (data_out !== t[N-1:0]) err("code", data_out, t);
            if (n !== SC + N + 1)      err("latency", n, SC + N + 1);
            if (samp !== SC)           err("sample_en cycles", samp, SC);
            @(posedge clk); #1;
            if (done !== 1'b0 || busy !== 1'b0) err("done/busy after", done, 0);
        end
    endtask

    initial begin
        errors = 0; finished = 0;
        repeat (3) @(posedge clk); #1;
        if (busy !== 0 || done !== 0 || sample_en !== 0) err("reset state", 1, 0);
        rst_n = 1; @(posedge clk); #1;
        for (k = 0; k < (1 << N); k = k + 1) convert(k);          // exhaustive
        // start ignored while busy
        T = 300; start = 1; @(posedge clk); #1; start = 0;
        repeat (3) @(posedge clk); #1;
        start = 1; @(posedge clk); #1; start = 0; dones = 0;
        repeat (40) begin @(posedge clk); #1; if (done) dones = dones + 1; end
        if (dones !== 1)          err("done count with extra start", dones, 1);
        if (data_out !== 300)     err("code with extra start", data_out, 300);
        // reset mid-conversion
        T = 777; start = 1; @(posedge clk); #1; start = 0;
        repeat (5) @(posedge clk); #1;
        rst_n = 0; @(posedge clk); #1;
        if (busy !== 0 || done !== 0) err("busy/done after mid reset", busy, 0);
        rst_n = 1; @(posedge clk); #1; convert(555);
        // continuous start (back-to-back): period must be SC+N+2
        T = 10; start = 1; dones = 0;
        begin : b2b
            integer first, last, cyc;
            cyc = 0; first = -1; last = -1;
            repeat (5 * (SC + N + 2) + 5) begin
                @(posedge clk); #1; cyc = cyc + 1;
                if (done) begin dones = dones + 1; if (first < 0) first = cyc; last = cyc; end
            end
            start = 0;
            if (dones < 4) err("back-to-back dones", dones, 4);
            else if ((last - first) !== (dones - 1) * (SC + N + 2)) err("b2b period", last - first, (dones-1)*(SC+N+2));
        end
        repeat (SC + N + 4) @(posedge clk);
        finished = 1;
    end
endmodule

module tb_sar_controller;
    reg clk = 0; always #5 clk = ~clk;
    wire [31:0] e1, e3; wire f1, f3;
    sar_ctrl_chk #(.N(10), .SC(1)) c1 (.clk(clk), .errors(e1), .finished(f1));
    sar_ctrl_chk #(.N(10), .SC(3)) c3 (.clk(clk), .errors(e3), .finished(f3));
    initial begin
        wait (f1 && f3); #10;
        $display("[sar_controller SC=1 exhaustive 1024 codes] errors=%0d -> %0s", e1, e1==0 ? "PASS" : "FAIL");
        $display("[sar_controller SC=3 exhaustive 1024 codes] errors=%0d -> %0s", e3, e3==0 ? "PASS" : "FAIL");
        if (e1 + e3 == 0) $display("\n*** ALL TESTS PASSED (sar_controller) ***");
        else              $display("\n*** FAILED ***");
        $finish;
    end
    initial begin #(500_000_000); $display("TIMEOUT"); $finish; end
endmodule
