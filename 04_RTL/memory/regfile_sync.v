`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// regfile_sync [synthesizable] : flop-based memory, 1 sync write port, 1 async read port.
// Used for FIR coefficients (16x12), NN weights (160x8), NN biases (18x24), features.
// RESET_CLEAR=0 (default): data flops have no reset (smaller area); contents are
//   undefined until written -> host must load before use.  RESET_CLEAR=1: cleared by rst_n.
// Out-of-range read addresses (DEPTH not a power of two) return X in simulation.
// -----------------------------------------------------------------------------
module regfile_sync #(
    parameter WIDTH = 12,
    parameter DEPTH = 16,
    parameter RESET_CLEAR = 0
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     we,
    input  wire [$clog2(DEPTH)-1:0] waddr,
    input  wire [WIDTH-1:0]         wdata,
    input  wire [$clog2(DEPTH)-1:0] raddr,
    output wire [WIDTH-1:0]         rdata
);
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    integer i;
    generate
        if (RESET_CLEAR) begin : g_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin for (i = 0; i < DEPTH; i = i + 1) mem[i] <= {WIDTH{1'b0}}; end
                else if (we) mem[waddr] <= wdata;
            end
        end else begin : g_norst
            always @(posedge clk) if (we) mem[waddr] <= wdata;
        end
    endgenerate
    assign rdata = mem[raddr];
endmodule
