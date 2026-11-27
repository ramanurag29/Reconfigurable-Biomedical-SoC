`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// result_manager [synthesizable] : quality-aware decision + result packing (task T5).
// Decision on every NN result (nn_v):
//   uncertain = nn_lowconf | nn_ovf | (last quality class == POOR)
//   abnormal  = nn_class & ~uncertain          (poor signal / low confidence never yields a confident alarm)
// Quality state before the first window completes is 3 = "not assessed" (not treated as POOR).
// Output FIFO records (16 b), [15:14] = type:
//   00 FIR   : {2'b00, y_sat, 2'b00, y[10:0]}
//   01 NN    : {2'b01, uncertain, abnormal, nn_class, lowconf, qclass[1:0], margin8[7:0]}
//              margin8 = min(margin >> 4, 255)
//   10 QUAL  : {2'b10, qclass[1:0], flags[3:0], score[7:0]}
// One push per cycle, priority NN > QUAL > FIR. Each source has a 1-deep pending slot; an event that
// finds its slot still occupied is dropped and sets sticky `lost`. Nothing is pushed while the FIFO is full.
// -----------------------------------------------------------------------------
module result_manager (
    input  wire               clk,
    input  wire               rst_n,
    // FIR
    input  wire               fir_v,
    input  wire signed [10:0] fir_y,
    input  wire               fir_sat,
    input  wire               fir_out_en,
    // quality
    input  wire               q_v,
    input  wire [1:0]         q_class,
    input  wire [3:0]         q_flags,
    input  wire [7:0]         q_score,
    input  wire               q_out_en,
    // NN
    input  wire               nn_v,
    input  wire               nn_class,
    input  wire               nn_lowconf,
    input  wire               nn_ovf,
    input  wire [15:0]        nn_margin,
    // FIFO
    input  wire               fifo_full,
    output wire               push,
    output wire [15:0]        din,
    // decision state
    output reg                dec_valid,      // 1-cycle pulse per NN decision
    output reg                dec_uncertain,
    output reg                dec_abnormal,
    output reg  [1:0]         q_last,
    output reg                lost,
    input  wire               lost_clr
);
    reg        pf, pq, pn;
    reg [15:0] wf, wq, wn;

    wire [1:0]  q_now     = q_v ? q_class : q_last;        // same-cycle quality result counts
    wire        unc       = nn_lowconf | nn_ovf | (q_now == 2'd2);
    wire [11:0] m_sh      = nn_margin[15:4];
    wire [7:0]  margin8   = (|m_sh[11:8]) ? 8'hFF : m_sh[7:0];

    wire        sel_n = pn;
    wire        sel_q = pq & ~pn;
    wire        sel_f = pf & ~pn & ~pq;
    assign push = (pn | pq | pf) & ~fifo_full;
    assign din  = sel_n ? wn : sel_q ? wq : wf;
    wire   pop_n = push & sel_n, pop_q = push & sel_q, pop_f = push & sel_f;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pf <= 1'b0; pq <= 1'b0; pn <= 1'b0; wf <= 16'd0; wq <= 16'd0; wn <= 16'd0;
            dec_valid <= 1'b0; dec_uncertain <= 1'b0; dec_abnormal <= 1'b0; q_last <= 2'd3; lost <= 1'b0;
        end else begin
            dec_valid <= 1'b0;
            if (lost_clr) lost <= 1'b0;
            if (pop_n) pn <= 1'b0;
            if (pop_q) pq <= 1'b0;
            if (pop_f) pf <= 1'b0;

            if (q_v) q_last <= q_class;

            if (nn_v) begin
                dec_valid     <= 1'b1;
                dec_uncertain <= unc;
                dec_abnormal  <= nn_class & ~unc;
                if (pn && !pop_n) lost <= 1'b1;
                else begin pn <= 1'b1; wn <= {2'b01, unc, nn_class & ~unc, nn_class, nn_lowconf, q_now, margin8}; end
            end
            if (q_v && q_out_en) begin
                if (pq && !pop_q) lost <= 1'b1;
                else begin pq <= 1'b1; wq <= {2'b10, q_class, q_flags, q_score}; end
            end
            if (fir_v && fir_out_en) begin
                if (pf && !pop_f) lost <= 1'b1;
                else begin pf <= 1'b1; wf <= {2'b00, fir_sat, 2'b00, fir_y}; end
            end
        end
    end
endmodule
