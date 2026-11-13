`timescale 1ns/1ps
// BEHAVIOURAL ONLY. Ideal comparator with optional static input offset (V).
// cmp_out = 1 when vin >= vdac + OFFSET.  Zero delay, noise-free.
module comparator_behav #(parameter real OFFSET = 0.0) (
    input  real vin,
    input  real vdac,
    output wire cmp_out
);
    assign cmp_out = (vin >= vdac + OFFSET);
endmodule
