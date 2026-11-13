`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// adc_frontend_behav : behavioural SAR ADC + bypass mux (simulation model).
// Config A (bypass=0): vin -> S&H -> comparator/CDAC -> sar_controller -> adc_data.
// Config B (bypass=1): bypass_data/bypass_valid pass straight through (digital core
//                      verification without the ADC); SAR is held idle.
// Only sar_controller is synthesizable; the other blocks use real numbers.
// -----------------------------------------------------------------------------
module adc_frontend_behav #(
    parameter N             = 10,
    parameter real VREF     = 2.0,
    parameter real CMP_OFFSET = 0.0,
    parameter SAMPLE_CYCLES = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  real         vin,
    input  wire         start,
    input  wire         bypass,
    input  wire [N-1:0] bypass_data,
    input  wire         bypass_valid,
    output wire [N-1:0] adc_data,
    output wire         adc_valid,
    output wire         busy
);
    real vhold, vdac;
    wire sample_en, cmp_out, sar_busy, sar_done;
    wire [N-1:0] dac_code, sar_data;

    sample_hold_behav u_sh (.sample_en(sample_en), .vin(vin), .vhold(vhold));
    cdac_behav #(.N(N), .VREF(VREF)) u_dac (.code(dac_code), .vdac(vdac));
    comparator_behav #(.OFFSET(CMP_OFFSET)) u_cmp (.vin(vhold), .vdac(vdac), .cmp_out(cmp_out));
    sar_controller #(.N(N), .SAMPLE_CYCLES(SAMPLE_CYCLES)) u_sar (
        .clk(clk), .rst_n(rst_n), .start(start & ~bypass), .cmp_out(cmp_out),
        .sample_en(sample_en), .dac_code(dac_code), .busy(sar_busy),
        .done(sar_done), .data_out(sar_data));

    assign adc_data  = bypass ? bypass_data  : sar_data;
    assign adc_valid = bypass ? bypass_valid : sar_done;
    assign busy      = bypass ? 1'b0         : sar_busy;
endmodule
