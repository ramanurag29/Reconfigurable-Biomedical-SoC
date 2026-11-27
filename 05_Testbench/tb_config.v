`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_config : self-checking test of the host interface / register map through biomed_soc_top.
//  C1 reset defaults of every RW register + CHIP_ID      C2 write/read-back of every RW field
//  C3 coefficient memory path (impulse through a 4-tap FIR, bit-exact vs integer reference)
//  C4 sample buffer read-back (0x600, newest first) + rd_valid
//  C5 RESULT_POP on empty FIFO -> valid bit 0, no underflow side effects on data
//  C6 IRQ: enable, data-ready level, sticky W1C bits, irq pin
//  C7 soft reset keeps configuration + coefficients, clears datapath (FIFO, sample buffer)
//  C8 out-of-range memory addresses are ignored (weight 0x2A0 must not alias weight 0x200)
// -----------------------------------------------------------------------------
module tb_config;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0;
    reg host_we = 0, host_re = 0; reg [11:0] host_addr = 0; reg [31:0] host_wdata = 0;
    wire [31:0] host_rdata; wire host_rvalid;
    wire adc_sample_en; wire [9:0] adc_dac_code;
    reg byp_v = 0; reg [9:0] byp_d = 0;
    wire irq, busy, done, abnormal, uncertain, result_valid; wire [15:0] result_data;

    biomed_soc_top dut (.clk(clk), .rst_n(rst_n), .host_we(host_we), .host_re(host_re), .host_addr(host_addr),
        .host_wdata(host_wdata), .host_rdata(host_rdata), .host_rvalid(host_rvalid),
        .adc_cmp_in(1'b0), .adc_sample_en(adc_sample_en), .adc_dac_code(adc_dac_code),
        .adc_bypass_valid(byp_v), .adc_bypass_data(byp_d), .irq(irq), .busy(busy), .done(done),
        .abnormal(abnormal), .uncertain(uncertain), .result_valid(result_valid), .result_data(result_data));

    integer errors = 0, i;
    reg [31:0] rd_data;
    task wr(input [11:0] a, input [31:0] d); begin host_addr = a; host_wdata = d; host_we = 1; @(posedge clk); #1; host_we = 0; end endtask
    task rd(input [11:0] a); begin host_addr = a; host_re = 1; @(posedge clk); #1; host_re = 0; rd_data = host_rdata; end endtask
    task chk(input [11:0] a, input [31:0] exp, input [255:0] what);
        begin rd(a); if (rd_data !== exp) begin errors = errors + 1; $display("  %0s @%h got %h exp %h", what, a, rd_data, exp); end end
    endtask
    task inject(input [9:0] c); begin byp_d = c; byp_v = 1; @(posedge clk); #1; byp_v = 0; repeat (30) @(posedge clk); #1; end endtask

    reg signed [11:0] h [0:3];
    reg signed [31:0] acc; reg signed [10:0] ye;
    integer k, n;
    initial begin
        repeat (4) @(posedge clk); #1; rst_n = 1; repeat (4) @(posedge clk); #1;
        // ---- C1 defaults
        chk(12'h01F, 32'hB10C0001, "CHIP_ID");
        chk(12'h000, 32'h0, "CTRL");
        chk(12'h002, 32'h0000001E, "MODE default (FIR+NN, bypass, fir_out, q_out)");
        chk(12'h003, {8'd0, 8'd8, 5'd0, 3'd4, 1'b0, 3'd3, 1'b1, 1'b1, 2'd0}, "SCHED default");
        chk(12'h004, {19'd0, 5'd11, 3'd0, 5'd16}, "FIR_CFG default");
        chk(12'h005, 32'd100, "ADC_CFG default");
        chk(12'h006, {5'd0, 11'd40, 8'd4, 4'd0, 4'd9}, "Q_CFG default");
        chk(12'h007, {14'd0, 10'd64, 8'd1}, "Q_CFG2 default");
        chk(12'h008, {16'd1220, 11'd0, 5'd6}, "NN_CFG default");
        chk(12'h009, 32'd0, "DEADLINE default");
        chk(12'h00A, 32'd0, "IRQ_EN default");
        chk(12'h00B, 32'd0, "IRQ_STATUS default");
        chk(12'h0FF, 32'd0, "unmapped");
        // ---- C2 write / read-back
        wr(12'h002, 32'hFFFF_FFE5); chk(12'h002, 32'h05, "MODE rw");
        wr(12'h003, 32'h00AB_0675); chk(12'h003, 32'h00AB_0675 & {8'd0, 8'hFF, 5'd0, 3'h7, 1'b0, 3'h7, 4'hF}, "SCHED rw");
        wr(12'h004, 32'h0000_0A08); chk(12'h004, 32'h0000_0A08, "FIR_CFG rw");
        wr(12'h005, 32'h1234_5678); chk(12'h005, 32'h0000_5678, "ADC_CFG rw");
        wr(12'h006, 32'h07FF_AB0C); chk(12'h006, 32'h07FF_AB0C, "Q_CFG rw");
        wr(12'h007, 32'h0003_FF55); chk(12'h007, 32'h0003_FF55, "Q_CFG2 rw");
        wr(12'h008, 32'hBEEF_0013); chk(12'h008, 32'hBEEF_0013, "NN_CFG rw");
        wr(12'h009, 32'h1111_2222); chk(12'h009, 32'h1111_2222, "DEADLINE rw");
        wr(12'h00A, 32'h0000_0005); chk(12'h00A, 32'h0000_0005, "IRQ_EN rw");
        // restore working configuration
        wr(12'h002, 32'h1E); wr(12'h003, {8'd0, 8'd8, 5'd0, 3'd4, 1'b0, 3'd3, 1'b1, 1'b1, 2'd0});
        wr(12'h006, {5'd0, 11'd40, 8'd4, 4'd0, 4'd9}); wr(12'h007, {14'd0, 10'd64, 8'd1}); wr(12'h00A, 32'h0);

        // ---- C3 coefficient path: 4 taps, S = 11, impulse x = +100 then zeros
        h[0] = 12'sd1024; h[1] = -12'sd512; h[2] = 12'sd300; h[3] = -12'sd2048;
        for (i = 0; i < 4; i = i + 1) wr(12'h100 + i, {20'd0, h[i]});
        wr(12'h004, {19'd0, 5'd11, 3'd0, 5'd4});
        wr(12'h002, 32'h0C);                         // FIR only, bypass, FIR records on, quality records off
        wr(12'h000, 32'h10);                         // run
        inject(10'd612);
        for (i = 0; i < 5; i = i + 1) inject(10'd512);
        for (n = 0; n < 6; n = n + 1) begin
            acc = (n < 4) ? h[n] * 100 : 0;
            ye = (acc + 1024) >>> 11;
            rd(12'h500);
            if (rd_data[16] !== 1'b1 || rd_data[15:14] !== 2'b00 || $signed(rd_data[10:0]) !== ye) begin
                errors = errors + 1; $display("  C3 FIR n=%0d got %h exp y=%0d", n, rd_data, ye); end
        end
        // ---- C5 empty pop
        rd(12'h500); if (rd_data[16] !== 1'b0) begin errors = errors + 1; $display("  C5 pop on empty FIFO reported valid"); end
        rd(12'h001); if (rd_data[6] !== 1'b0) begin errors = errors + 1; $display("  C5 underflow set by guarded pop"); end
        // ---- C4 sample buffer: 6 samples injected (newest = 0 -> code 512), oldest = +100
        rd(12'h600); if (rd_data !== {1'b1, 20'd0, 11'd0})   begin errors = errors + 1; $display("  C4 newest %h", rd_data); end
        rd(12'h605); if (rd_data !== {1'b1, 20'd0, 11'd100}) begin errors = errors + 1; $display("  C4 oldest %h", rd_data); end
        rd(12'h606); if (rd_data[31] !== 1'b0)               begin errors = errors + 1; $display("  C4 rd_valid beyond count"); end
        // ---- C6 IRQ
        wr(12'h00A, 32'h1);
        if (irq !== 1'b0) begin errors = errors + 1; $display("  C6 irq without data"); end
        inject(10'd512);
        if (irq !== 1'b1) begin errors = errors + 1; $display("  C6 data-ready irq missing"); end
        chk(12'h00B, 32'h1, "IRQ_STATUS data-ready");
        rd(12'h500);
        if (irq !== 1'b0) begin errors = errors + 1; $display("  C6 irq stuck after pop"); end
        // NN done sticky: run one inference on zero weights
        for (i = 0; i < 160; i = i + 1) wr(12'h200 + i, 0);
        for (i = 0; i < 18; i = i + 1)  wr(12'h300 + i, 0);
        for (i = 0; i < 8; i = i + 1)   wr(12'h400 + i, i);
        wr(12'h002, 32'h02 | 32'h4);                // FIR+NN, bypass, no FIR/quality records
        wr(12'h00A, 32'h2);
        wr(12'h000, 32'h12);                        // run + nn_start
        k = 0; while (!done && k < 1000) begin @(posedge clk); #1; k = k + 1; end
        if (!done || !irq) begin errors = errors + 1; $display("  C6 NN done / irq missing"); end
        wr(12'h00A, 32'hE);                         // writing another register must not clear sticky bits
        if (!done) begin errors = errors + 1; $display("  C6 sticky done cleared by a non-IRQ_STATUS write"); end
        rd(12'h00C); if (rd_data[0] !== 1'b0 || rd_data[1] !== 1'b1) begin errors = errors + 1; $display("  C6 zero-net result %h (exp class0, lowconf)", rd_data); end
        wr(12'h00B, 32'h2);
        if (done || irq) begin errors = errors + 1; $display("  C6 W1C did not clear done"); end
        rd(12'h500); if (rd_data[16] !== 1'b1 || rd_data[15:14] !== 2'b01 || rd_data[13] !== 1'b1) begin
            errors = errors + 1; $display("  C6 NN record %h (exp uncertain)", rd_data); end

        // ---- C8 out-of-range weight write must not alias: write 0x2A0 (=160) with 0x7F
        wr(12'h2A0, 32'h7F);
        wr(12'h000, 32'h12); k = 0; while (!done && k < 1000) begin @(posedge clk); #1; k = k + 1; end
        rd(12'h00D); if (rd_data !== 0) begin errors = errors + 1; $display("  C8 alias changed score0 %h", rd_data); end
        wr(12'h00B, 32'h2); rd(12'h500);

        // ---- C7 soft reset
        inject(10'd700);
        wr(12'h000, 32'h1);                         // soft reset, run = 0
        repeat (5) @(posedge clk); #1;
        chk(12'h004, {19'd0, 5'd11, 3'd0, 5'd4}, "C7 FIR_CFG kept");
        chk(12'h002, 32'h06, "C7 MODE kept");
        rd(12'h600); if (rd_data[31] !== 1'b0) begin errors = errors + 1; $display("  C7 sample buffer not cleared"); end
        if (result_valid) begin errors = errors + 1; $display("  C7 FIFO not cleared"); end
        // coefficients survive: repeat the impulse test
        wr(12'h002, 32'h0C); wr(12'h000, 32'h10);
        inject(10'd612); for (i = 0; i < 3; i = i + 1) inject(10'd512);
        for (n = 0; n < 4; n = n + 1) begin
            acc = h[n] * 100; ye = (acc + 1024) >>> 11; rd(12'h500);
            if ($signed(rd_data[10:0]) !== ye) begin errors = errors + 1; $display("  C7 coef lost n=%0d got %h", n, rd_data); end
        end

        $display("[register map / host interface] errors=%0d -> %0s", errors, errors == 0 ? "PASS" : "FAIL");
        if (errors == 0) $display("\n*** ALL TESTS PASSED (tb_config) ***"); else $display("\n*** FAILED ***");
        $finish;
    end
    initial begin #(5_000_000); $display("TIMEOUT"); $finish; end
endmodule
