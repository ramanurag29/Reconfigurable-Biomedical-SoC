`timescale 1ns/1ps
// BEHAVIOURAL ONLY. Ideal binary-weighted capacitive DAC: vdac = VREF * code / 2^N.
// No mismatch, parasitics or settling (those belong to the transistor-level design).
module cdac_behav #(parameter N = 10, parameter real VREF = 2.0) (
    input  wire [N-1:0] code,
    output real         vdac
);
    always @* vdac = VREF * code / (2.0 ** N);
endmodule
