`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// reset_sync [synthesizable] : asynchronous-assert, synchronous-release reset.
//   rst_in_n low  -> rst_out_n low immediately (async)
//   rst_in_n high -> rst_out_n goes high after 2 clean clock edges (no metastable release).
// Used twice in biomed_soc_top: hard reset (pin) and core reset (pin AND NOT soft-reset).
// -----------------------------------------------------------------------------
module reset_sync (
    input  wire clk,
    input  wire rst_in_n,
    output wire rst_out_n
);
    reg [1:0] sync;
    always @(posedge clk or negedge rst_in_n) begin
        if (!rst_in_n) sync <= 2'b00;
        else           sync <= {sync[0], 1'b1};
    end
    assign rst_out_n = sync[1];
endmodule
