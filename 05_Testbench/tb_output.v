`timescale 1ns/1ps
// Self-checking output_fifo test vs an independent log-based model (write log + read counter).
// Phases bias traffic push-heavy / pop-heavy / balanced to hit full, empty, overflow, underflow.
module tb_output;
    reg clk = 0; always #5 clk = ~clk; reg rst_n = 0;
    reg push = 0, pop = 0, clr = 0; reg [15:0] din = 0; wire [15:0] dout; wire full, empty, ovf, unf; wire [4:0] cnt;
    output_fifo #(.W(16), .DEPTH(16)) F (clk, rst_n, push, din, pop, clr, dout, full, empty, cnt, ovf, unf);

    reg [15:0] log [0:199999]; integer wn = 0, rn = 0, errors = 0, k, r, seed = 11, pp, qq, mcount;
    reg m_ovf = 0, m_unf = 0; integer n_full = 0, n_empty = 0, n_ovf = 0, n_unf = 0;

    task chk(input [255:0] what, input integer got, input integer exp);
        begin errors = errors + 1; if (errors < 8) $display("  %0s: got %0d exp %0d", what, got, exp); end
    endtask

    initial begin
        repeat (3) @(posedge clk); #1; rst_n = 1;
        for (k = 0; k < 90000; k = k + 1) begin
            r = $random(seed);
            case ((k / 10000) % 3) 0: begin pp = 160; qq = 60; end 1: begin pp = 60; qq = 160; end default: begin pp = 128; qq = 128; end endcase
            push = (r[7:0] < pp); pop = (r[15:8] < qq); din = $random(seed); clr = (r[31:24] == 8'd0);
            #1;
            mcount = wn - rn;
            if (full !== (mcount == 16)) chk("full", full, mcount == 16);
            if (empty !== (mcount == 0)) chk("empty", empty, mcount == 0);
            if (cnt !== mcount) chk("count", cnt, mcount);
            if (mcount > 0 && dout !== log[rn]) chk("dout", dout, log[rn]);
            if (ovf !== m_ovf) chk("overflow flag", ovf, m_ovf);
            if (unf !== m_unf) chk("underflow flag", unf, m_unf);
            if (full) n_full = n_full + 1; if (empty) n_empty = n_empty + 1;
            @(posedge clk); #1;
            // model update with the same rules
            if (clr) begin m_ovf = 0; m_unf = 0; end
            if (push && mcount == 16) begin m_ovf = 1; n_ovf = n_ovf + 1; end
            if (pop && mcount == 0)   begin m_unf = 1; n_unf = n_unf + 1; end
            if (push && mcount < 16) begin log[wn] = din; wn = wn + 1; end
            if (pop && mcount > 0) rn = rn + 1;
            // note: clr and a same-cycle set -> set wins (matches RTL statement order)
        end
        $display("[output_fifo 16x16: %0d cycles; full=%0d empty=%0d overflow-events=%0d underflow-events=%0d] errors=%0d -> %0s",
                 90000, n_full, n_empty, n_ovf, n_unf, errors, (errors == 0 && n_full > 100 && n_empty > 100 && n_ovf > 10 && n_unf > 10) ? "PASS" : "FAIL");
        if (errors == 0 && n_full > 100 && n_empty > 100 && n_ovf > 10 && n_unf > 10) $display("\n*** ALL TESTS PASSED (output fifo) ***"); else $display("\n*** FAILED ***");
        $finish;
    end
    initial begin #(50_000_000); $display("TIMEOUT"); $finish; end
endmodule
