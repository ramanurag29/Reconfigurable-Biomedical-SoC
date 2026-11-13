`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// sample_buffer [synthesizable] : circular history of the last DEPTH samples.
// wr_en pushes wr_data. rd_offset 0 = newest, 1 = previous, ... (async read).
// rd_valid = rd_offset < min(count, DEPTH). DEPTH must be a power of two.
// Feeds feature extraction / quality estimation (FIR keeps its own tap history).
// -----------------------------------------------------------------------------
module sample_buffer #(
    parameter W     = 11,
    parameter DEPTH = 64
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire [W-1:0]          wr_data,
    input  wire [$clog2(DEPTH)-1:0] rd_offset,
    output wire [W-1:0]          rd_data,
    output wire                  rd_valid,
    output reg  [$clog2(DEPTH):0] count
);
    localparam AW = $clog2(DEPTH);
    reg [W-1:0]  mem [0:DEPTH-1];
    reg [AW-1:0] wptr;
    wire [AW-1:0] ridx = wptr - 1'b1 - rd_offset;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin wptr <= {AW{1'b0}}; count <= 0; end
        else if (wr_en) begin
            mem[wptr] <= wr_data; wptr <= wptr + 1'b1;
            if (count < DEPTH) count <= count + 1'b1;
        end
    end
    assign rd_data  = mem[ridx];
    assign rd_valid = ({1'b0, rd_offset} < count);
endmodule
