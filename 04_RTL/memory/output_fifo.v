`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// output_fifo [synthesizable] : first-word-fall-through synchronous FIFO.
// push when full  -> rejected (even if pop same cycle), sticky `overflow`.
// pop when empty  -> ignored, sticky `underflow`. push+pop when empty: push accepted.
// DEPTH must be a power of two. clr_flags clears the sticky flags.
// -----------------------------------------------------------------------------
module output_fifo #(
    parameter W     = 16,
    parameter DEPTH = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  push,
    input  wire [W-1:0]          din,
    input  wire                  pop,
    input  wire                  clr_flags,
    output wire [W-1:0]          dout,
    output wire                  full,
    output wire                  empty,
    output reg  [$clog2(DEPTH):0] count,
    output reg                   overflow,
    output reg                   underflow
);
    localparam AW = $clog2(DEPTH);
    reg [W-1:0]  mem [0:DEPTH-1];
    reg [AW-1:0] wptr, rptr;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign dout  = mem[rptr];
    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= 0; rptr <= 0; count <= 0; overflow <= 1'b0; underflow <= 1'b0;
        end else begin
            if (clr_flags) begin overflow <= 1'b0; underflow <= 1'b0; end
            if (push && full)  overflow  <= 1'b1;
            if (pop  && empty) underflow <= 1'b1;
            if (do_push) begin mem[wptr] <= din; wptr <= wptr + 1'b1; end
            if (do_pop)  rptr <= rptr + 1'b1;
            count <= count + do_push - do_pop;
        end
    end
endmodule
