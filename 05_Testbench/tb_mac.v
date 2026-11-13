`timescale 1ns/1ps
// Self-checking randomized + directed test for mac_unit. Five configurations run in
// lock-step against an independent 64-bit integer reference model (in mac_checker).
module mac_checker #(parameter ACC_W = 32, parameter SATURATE = 1, parameter PIPE = 0) (
    input  wire clk, input wire rst_n,
    input  wire en, input wire clear, input wire load,
    input  wire signed [10:0] a, input wire signed [11:0] b, input wire signed [31:0] load_val,
    output reg  [31:0] errors, output reg [31:0] checked, output reg [31:0] ovf_seen
);
    localparam LAT = 1 + PIPE;
    wire signed [ACC_W-1:0] acc; wire acc_valid, overflow;
    mac_unit #(.A_W(11), .B_W(12), .ACC_W(ACC_W), .SATURATE(SATURATE), .PIPE(PIPE)) dut (
        .clk(clk), .rst_n(rst_n), .en(en), .clear(clear), .load(load), .a(a), .b(b),
        .load_val(load_val[ACC_W-1:0]), .acc(acc), .acc_valid(acc_valid), .overflow(overflow));

    reg signed [63:0] r_acc, sum, mx, mn;
    reg               r_ovf, nv;
    reg signed [63:0] q_acc [0:2]; reg q_ovf [0:2]; reg q_v [0:2];
    integer i;
    initial begin errors = 0; checked = 0; ovf_seen = 0; r_acc = 0; r_ovf = 0;
        for (i = 0; i < 3; i = i + 1) begin q_v[i] = 0; q_acc[i] = 0; q_ovf[i] = 0; end end

    always @(posedge clk) begin
        if (!rst_n) begin
            r_acc = 0; r_ovf = 0;
            for (i = 0; i < 3; i = i + 1) q_v[i] = 0;
        end else begin
            // check what is due now
            if (q_v[LAT-1]) begin
                checked = checked + 1;
                if (acc_valid !== 1'b1 || acc !== q_acc[LAT-1] || overflow !== q_ovf[LAT-1]) begin
                    errors = errors + 1;
                    if (errors < 6) $display("  [ACC_W=%0d SAT=%0d PIPE=%0d] got acc=%0d ovf=%0b valid=%0b exp acc=%0d ovf=%0b",
                        ACC_W, SATURATE, PIPE, acc, overflow, acc_valid, q_acc[LAT-1], q_ovf[LAT-1]);
                end
                if (q_ovf[LAT-1]) ovf_seen = ovf_seen + 1;
            end else if (acc_valid !== 1'b0) begin
                errors = errors + 1; if (errors < 6) $display("  [ACC_W=%0d] spurious acc_valid", ACC_W);
            end
            // compute expectation for the op presented at this edge
            mx = (64'sd1 <<< (ACC_W-1)) - 1; mn = -(64'sd1 <<< (ACC_W-1)); nv = 0;
            if (clear) begin r_acc = 0; r_ovf = 0; nv = 1; end
            else if (load) begin r_acc = {{(64-ACC_W){load_val[ACC_W-1]}}, load_val[ACC_W-1:0]}; r_ovf = 0; nv = 1; end
            else if (en) begin
                sum = r_acc + a * b; nv = 1;
                if (sum > mx || sum < mn) begin
                    r_ovf = 1;
                    if (SATURATE) r_acc = (sum > mx) ? mx : mn;
                    else          r_acc = {{(64-ACC_W){sum[ACC_W-1]}}, sum[ACC_W-1:0]};
                end else r_acc = sum;
            end
            q_v[2] = q_v[1]; q_acc[2] = q_acc[1]; q_ovf[2] = q_ovf[1];
            q_v[1] = q_v[0]; q_acc[1] = q_acc[0]; q_ovf[1] = q_ovf[0];
            q_v[0] = nv;     q_acc[0] = r_acc;    q_ovf[0] = r_ovf;
        end
    end
endmodule

module tb_mac;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, en = 0, clear = 0, load = 0;
    reg signed [10:0] a = 0; reg signed [11:0] b = 0; reg signed [31:0] lv = 0;
    wire [31:0] e [0:4], c [0:4], o [0:4];

    mac_checker #(32,1,0) k0 (clk,rst_n,en,clear,load,a,b,lv,e[0],c[0],o[0]);
    mac_checker #(32,1,1) k1 (clk,rst_n,en,clear,load,a,b,lv,e[1],c[1],o[1]);
    mac_checker #(24,1,0) k2 (clk,rst_n,en,clear,load,a,b,lv,e[2],c[2],o[2]);
    mac_checker #(24,0,0) k3 (clk,rst_n,en,clear,load,a,b,lv,e[3],c[3],o[3]);
    mac_checker #(24,0,1) k4 (clk,rst_n,en,clear,load,a,b,lv,e[4],c[4],o[4]);

    task op(input e_, input c_, input l_, input signed [10:0] aa, input signed [11:0] bb, input signed [31:0] ll);
        begin @(posedge clk); #1; en = e_; clear = c_; load = l_; a = aa; b = bb; lv = ll; end
    endtask

    integer i, seed = 7, rr; reg [31:0] x;
    initial begin
        repeat (3) @(posedge clk); #1; rst_n = 1;
        op(0,1,0,0,0,0);                                   // clear
        op(1,0,0, 11'sd3, 12'sd5, 0);                      // 15
        op(1,0,0, -11'sd7, 12'sd9, 0);                     // -63 -> -48
        for (i = 0; i < 3000; i = i + 1) op(1,0,0, -11'sd512, -12'sd2048, 0);   // +2^20 each: saturate/overflow
        op(0,1,0,0,0,0);
        for (i = 0; i < 3000; i = i + 1) op(1,0,0, -11'sd512,  12'sd2047, 0);   // large negative
        op(0,0,1,0,0, 32'sh7FFFFFF0); op(1,0,0, 11'sd1, 12'sd100, 0);          // load near max, +100
        op(0,0,1,0,0, 32'sh80000010); op(1,0,0, -11'sd1, 12'sd100, 0);         // near min, -100
        op(1,1,1, 11'sd5, 12'sd5, 32'sd77);                // clear beats load beats en
        op(1,0,1, 11'sd5, 12'sd5, 32'sd77);                // load beats en
        op(0,0,0, 11'sd9, 12'sd9, 0);                      // idle: no valid expected
        for (i = 0; i < 40000; i = i + 1) begin
            x = $random(seed); rr = $random(seed);
            op((x[7:0] < 8'd180), (x[15:8] < 8'd8), (x[23:16] < 8'd8),
               $random(seed), $random(seed), $random(seed));
            if (i == 20000) begin @(posedge clk); #1; rst_n = 0; @(posedge clk); #1; @(posedge clk); #1; rst_n = 1; end
        end
        op(0,0,0,0,0,0); repeat (6) @(posedge clk);
        $display("[MAC 32b sat  PIPE=0] checked=%0d overflow_events=%0d errors=%0d -> %0s", c[0], o[0], e[0], e[0]==0 && o[0]>0 ? "PASS" : "FAIL");
        $display("[MAC 32b sat  PIPE=1] checked=%0d overflow_events=%0d errors=%0d -> %0s", c[1], o[1], e[1], e[1]==0 && o[1]>0 ? "PASS" : "FAIL");
        $display("[MAC 24b sat  PIPE=0] checked=%0d overflow_events=%0d errors=%0d -> %0s", c[2], o[2], e[2], e[2]==0 && o[2]>0 ? "PASS" : "FAIL");
        $display("[MAC 24b wrap PIPE=0] checked=%0d overflow_events=%0d errors=%0d -> %0s", c[3], o[3], e[3], e[3]==0 && o[3]>0 ? "PASS" : "FAIL");
        $display("[MAC 24b wrap PIPE=1] checked=%0d overflow_events=%0d errors=%0d -> %0s", c[4], o[4], e[4], e[4]==0 && o[4]>0 ? "PASS" : "FAIL");
        if (e[0]+e[1]+e[2]+e[3]+e[4] == 0 && o[0]>0 && o[1]>0 && o[2]>0 && o[3]>0 && o[4]>0)
            $display("\n*** ALL TESTS PASSED (mac_unit, 5 configs) ***");
        else $display("\n*** FAILED ***");
        $finish;
    end
    initial begin #(50_000_000); $display("TIMEOUT"); $finish; end
endmodule
