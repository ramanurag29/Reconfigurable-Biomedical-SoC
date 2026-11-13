`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mac_unit [synthesizable]  : signed multiply-accumulate
// Ops (priority clear > load > en):
//   clear : acc <= 0, overflow <= 0
//   load  : acc <= load_val (low ACC_W bits), overflow <= 0
//   en    : acc <= acc + a*b ; on signed overflow -> saturate (SATURATE=1) or wrap,
//           and the sticky `overflow` flag is set (cleared by clear/load).
// acc_valid pulses 1 clock after the op is *applied* (PIPE=0: next edge,
// PIPE=1: product registered first, one extra clock of latency).
// Defaults match the architecture: 11b x 12b signed, 32b accumulator.
// Worst case |a*b| = 2^20 -> 16 FIR taps need 26 bits (see architecture doc).
// -----------------------------------------------------------------------------
module mac_unit #(
    parameter A_W      = 11,
    parameter B_W      = 12,
    parameter ACC_W    = 32,
    parameter SATURATE = 1,
    parameter PIPE     = 0
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire                     clear,
    input  wire                     load,
    input  wire signed [A_W-1:0]    a,
    input  wire signed [B_W-1:0]    b,
    input  wire signed [ACC_W-1:0]  load_val,
    output reg  signed [ACC_W-1:0]  acc,
    output reg                      acc_valid,
    output reg                      overflow
);
    localparam P_W = A_W + B_W;
    initial if (ACC_W < P_W) begin
        $display("mac_unit: ACC_W (%0d) must be >= A_W+B_W (%0d)", ACC_W, P_W); $finish;
    end
    localparam signed [ACC_W-1:0] ACC_MAX = {1'b0, {(ACC_W-1){1'b1}}};
    localparam signed [ACC_W-1:0] ACC_MIN = {1'b1, {(ACC_W-1){1'b0}}};

    // optional product pipeline register
    reg                     s_en, s_clear, s_load;
    reg signed [P_W-1:0]    s_prod;
    reg signed [ACC_W-1:0]  s_lv;
    wire signed [P_W-1:0]   prod_c = a * b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_en <= 1'b0; s_clear <= 1'b0; s_load <= 1'b0; s_prod <= 0; s_lv <= 0;
        end else begin
            s_en <= en; s_clear <= clear; s_load <= load; s_prod <= prod_c; s_lv <= load_val;
        end
    end

    wire                    x_en    = PIPE ? s_en    : en;
    wire                    x_clear = PIPE ? s_clear : clear;
    wire                    x_load  = PIPE ? s_load  : load;
    wire signed [P_W-1:0]   x_prod  = PIPE ? s_prod  : prod_c;
    wire signed [ACC_W-1:0] x_lv    = PIPE ? s_lv    : load_val;

    wire signed [ACC_W:0] sum_full = acc + x_prod;               // ACC_W+1 bits, sign-extended
    wire                  ovf_now  = (sum_full[ACC_W] != sum_full[ACC_W-1]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 0; acc_valid <= 1'b0; overflow <= 1'b0;
        end else begin
            acc_valid <= 1'b0;
            if (x_clear) begin
                acc <= 0; overflow <= 1'b0; acc_valid <= 1'b1;
            end else if (x_load) begin
                acc <= x_lv; overflow <= 1'b0; acc_valid <= 1'b1;
            end else if (x_en) begin
                acc_valid <= 1'b1;
                if (ovf_now) begin
                    overflow <= 1'b1;
                    acc <= SATURATE ? (sum_full[ACC_W] ? ACC_MIN : ACC_MAX) : sum_full[ACC_W-1:0];
                end else begin
                    acc <= sum_full[ACC_W-1:0];
                end
            end
        end
    end
endmodule
