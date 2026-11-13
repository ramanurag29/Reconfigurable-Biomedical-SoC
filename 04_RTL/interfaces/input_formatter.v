`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// input_formatter
// Purpose : Convert an unsigned ADC code (0 .. 2^N-1) into a centred signed sample
//           x_signed = D - 2^(N-1)   (N=10 -> -512..+511, 11-bit two's complement)
// Interface: single-cycle latency, valid-qualified. Registered outputs.
// Params  : ADC_BITS - ADC resolution (default 10)
// Reset   : asynchronous assert, synchronous release use is the integrator's job.
// -----------------------------------------------------------------------------
module input_formatter #(
    parameter ADC_BITS = 10
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       in_valid,
    input  wire [ADC_BITS-1:0]        adc_code,
    output reg                        out_valid,
    output reg  signed [ADC_BITS:0]   x_signed
);
    localparam [ADC_BITS:0] MIDSCALE = (1 << (ADC_BITS-1));   // 2^(ADC_BITS-1)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            x_signed  <= {(ADC_BITS+1){1'b0}};
        end else begin
            out_valid <= in_valid;
            if (in_valid)
                x_signed <= {1'b0, adc_code} - MIDSCALE;   // wraps to two's complement
        end
    end
endmodule
