`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// fir_engine [synthesizable] : programmable FIR sequencer that drives a SHARED MAC.
//   y[n] = sat( (sum_{k<T} h[k]*x[n-k] + 2^(S-1)) >>> S ),  T = taps (1..16), S = shift
// The engine does not contain a multiplier: it requests the MAC (mac_req / mac_grant) and
// issues one MAC operation per clock. The scheduler (later) owns the grant and must route
// mac_acc_valid only to the engine that owns the MAC.
// Formats: x signed 11b, h signed 12b (Q1.11), acc signed 32b, y signed 11b saturated.
// Input handling: a sample arriving while busy is held (1 deep); a second one overwrites it
//   and raises sticky `overrun`.
// Latency: busy cycles = T+2 (PIPE=0 MAC) / T+3 (PIPE=1); sample_valid edge -> y_valid
//   visible = T+3 / T+4 edges. last_latency reports the busy-cycle count.
// -----------------------------------------------------------------------------
module fir_engine #(
    parameter X_W      = 11,
    parameter H_W      = 12,
    parameter ACC_W    = 32,
    parameter MAX_TAPS = 16
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     sample_valid,
    input  wire signed [X_W-1:0]    sample_in,
    input  wire [4:0]               taps_cfg,
    input  wire [4:0]               shift_cfg,
    output wire [3:0]               coef_addr,
    input  wire signed [H_W-1:0]    coef_data,
    // shared-MAC port
    output wire                     mac_req,
    input  wire                     mac_grant,
    output wire                     mac_clear,
    output wire                     mac_en,
    output wire signed [X_W-1:0]    mac_a,
    output wire signed [H_W-1:0]    mac_b,
    input  wire signed [ACC_W-1:0]  mac_acc,
    input  wire                     mac_acc_valid,
    input  wire                     mac_overflow,
    // result
    output reg                      y_valid,
    output reg  signed [X_W-1:0]    y_data,
    output reg                      y_sat,
    output reg                      y_ovf,
    output wire                     busy,
    output reg                      overrun,
    output reg  [7:0]               last_latency
);
    localparam [2:0] S_IDLE = 3'd0, S_CLR = 3'd1, S_MAC = 3'd2, S_DRAIN = 3'd3;
    localparam [4:0] TMAX = MAX_TAPS;
    localparam signed [ACC_W:0] YMAX =  (1 <<< (X_W-1)) - 1;
    localparam signed [ACC_W:0] YMIN = -(1 <<< (X_W-1));

    reg [2:0] state;
    reg [4:0] k;
    reg [2:0] pend_ops;
    reg [7:0] lat;
    reg       pend;
    reg signed [X_W-1:0] s_hold;
    reg signed [X_W-1:0] x_hist [0:MAX_TAPS-1];
    integer i;

    wire [4:0] taps_eff = (taps_cfg == 5'd0) ? 5'd1 : (taps_cfg > TMAX) ? TMAX : taps_cfg;

    assign coef_addr = k[3:0];
    assign mac_a     = x_hist[k[3:0]];
    assign mac_b     = coef_data;
    assign mac_req   = (state != S_IDLE);
    assign mac_clear = (state == S_CLR) && mac_grant;
    assign mac_en    = (state == S_MAC) && mac_grant;
    assign busy      = (state != S_IDLE) || pend;

    // rounding + shift + saturation of the final accumulator
    wire [ACC_W:0] rnd_u = (shift_cfg == 5'd0) ? {(ACC_W+1){1'b0}}
                         : ({{ACC_W{1'b0}}, 1'b1} << (shift_cfg - 5'd1));
    wire signed [ACC_W:0] sum_r   = $signed({mac_acc[ACC_W-1], mac_acc}) + $signed(rnd_u);
    wire signed [ACC_W:0] shifted = sum_r >>> shift_cfg;
    wire                  hi_sat  = (shifted > YMAX);
    wire                  lo_sat  = (shifted < YMIN);

    wire issue      = mac_clear | mac_en;
    wire drain_done = (state == S_DRAIN) && (pend_ops == {2'b00, mac_acc_valid});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; k <= 5'd0; pend_ops <= 3'd0; lat <= 8'd0; pend <= 1'b0;
            s_hold <= 0; y_valid <= 1'b0; y_data <= 0; y_sat <= 1'b0; y_ovf <= 1'b0;
            overrun <= 1'b0; last_latency <= 8'd0;
            for (i = 0; i < MAX_TAPS; i = i + 1) x_hist[i] <= 0;
        end else begin
            y_valid <= 1'b0;
            if (state != S_IDLE) begin
                pend_ops <= pend_ops + issue - mac_acc_valid;
                if (lat != 8'hFF) lat <= lat + 8'd1;
            end
            case (state)
                S_IDLE: if (pend) begin
                    for (i = MAX_TAPS-1; i > 0; i = i - 1) x_hist[i] <= x_hist[i-1];
                    x_hist[0] <= s_hold;
                    k <= 5'd0; pend_ops <= 3'd0; lat <= 8'd0; pend <= 1'b0; state <= S_CLR;
                end
                S_CLR: if (mac_grant) begin state <= S_MAC; k <= 5'd0; end
                S_MAC: if (mac_grant) begin
                    if (k == taps_eff - 5'd1) state <= S_DRAIN; else k <= k + 5'd1;
                end
                S_DRAIN: if (drain_done) begin
                    y_data <= hi_sat ? YMAX[X_W-1:0] : lo_sat ? YMIN[X_W-1:0] : shifted[X_W-1:0];
                    y_sat  <= hi_sat | lo_sat;
                    y_ovf  <= mac_overflow;
                    y_valid <= 1'b1;
                    last_latency <= lat + 8'd1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
            // sample capture (after the case so a same-cycle arrival re-arms `pend`)
            if (sample_valid) begin
                if (pend && state != S_IDLE) overrun <= 1'b1;
                s_hold <= sample_in; pend <= 1'b1;
            end
        end
    end
endmodule
