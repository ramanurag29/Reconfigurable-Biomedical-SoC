`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// sar_controller  [synthesizable, digital]
// Purpose : N-bit successive-approximation control. One bit decided per clock.
// Protocol: pulse `start` while idle -> SAMP (sample_en=1, SAMPLE_CYCLES clocks)
//           -> CONV (N clocks, dac_code = decided bits | trial bit)
//           -> FIN (1 clock) -> `done` pulses 1 clock with data_out valid.
//           `start` is ignored while busy.
// Latency : start edge -> done visible = SAMPLE_CYCLES + N + 1 clocks.
// cmp_out : 1 when held input >= DAC trial voltage (keep the trial bit).
// Result  : D = floor(Vin / (Vref/2^N)), clipped to 0..2^N-1  (decision D1-B).
// -----------------------------------------------------------------------------
module sar_controller #(
    parameter N             = 10,
    parameter SAMPLE_CYCLES = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         cmp_out,
    output wire         sample_en,
    output wire [N-1:0] dac_code,
    output wire         busy,
    output reg          done,
    output reg  [N-1:0] data_out
);
    localparam [1:0] S_IDLE = 2'd0, S_SAMP = 2'd1, S_CONV = 2'd2, S_FIN = 2'd3;

    reg [1:0]          state;
    reg [N-1:0]        result;
    reg [$clog2(N):0]  bitpos;
    reg [7:0]          cnt;

    wire [N-1:0] mask = {{(N-1){1'b0}}, 1'b1} << bitpos;

    assign sample_en = (state == S_SAMP);
    assign busy      = (state != S_IDLE);
    assign dac_code  = (state == S_CONV) ? (result | mask) : {N{1'b0}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; result <= {N{1'b0}}; bitpos <= 0; cnt <= 8'd0;
            done <= 1'b0; data_out <= {N{1'b0}};
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                    state <= S_SAMP; cnt <= 8'd0; result <= {N{1'b0}};
                end
                S_SAMP: begin
                    cnt <= cnt + 8'd1;
                    if (cnt == SAMPLE_CYCLES - 1) begin
                        state <= S_CONV; bitpos <= N - 1;
                    end
                end
                S_CONV: begin
                    if (cmp_out) result <= result | mask;
                    if (bitpos == 0) state <= S_FIN;
                    else             bitpos <= bitpos - 1'b1;
                end
                S_FIN: begin
                    data_out <= result; done <= 1'b1; state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
