`timescale 1ns/1ps
// BEHAVIOURAL ONLY (real-valued, not synthesizable, not a transistor-level circuit).
// Ideal track-and-hold: follows vin while sample_en=1, holds the last value after.
module sample_hold_behav (
    input  wire sample_en,
    input  real vin,
    output real vhold
);
    always @* if (sample_en) vhold = vin;
endmodule
