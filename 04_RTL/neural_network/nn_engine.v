`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// nn_engine [synthesizable] : 8 -> 16 -> 2 inference sequencer driving a SHARED MAC.
// No multiplier inside: one MAC "load bias" op + N MAC ops per neuron through the
// mac_req/mac_grant port (same style as fir_engine). Preemption boundary = between MAC ops
// and between neurons (neuron index n, tap index k and the hidden buffer are the saved context).
//   layer 1 (n=0..15): acc = b1[n] + sum_{k<8}  feat[k]*w1[n*8+k]   -> h[n] = clamp((acc+2^(S-1))>>>S, 0, 127)
//   layer 2 (n=16,17): acc = b2[o] + sum_{k<16} h[k]*w2[o*16+k]      -> score[o] = acc
//   class = score1 > score0 ; margin = min(|score1-score0|, 65535) ; lowconf = margin < conf_thr
// Memories are external (async-read regfiles): weights[160] s8, bias[18] s24, feat[8] s8.
// Bit-exact reference: 11_Scripts/nn_golden.py::infer_int.   start while busy is ignored.
// Latency: last_latency = cycles from accepted start to nn_valid (reported, measured by tb_nn).
// -----------------------------------------------------------------------------
module nn_engine #(
    parameter ACC_W = 32
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [4:0]               shift_cfg,     // S1 (hidden requantization shift)
    input  wire [15:0]              conf_thr,
    // external memories
    output wire [2:0]               feat_addr,
    input  wire signed [7:0]        feat_data,
    output wire [7:0]               w_addr,
    input  wire signed [7:0]        w_data,
    output wire [4:0]               b_addr,
    input  wire signed [23:0]       b_data,
    // shared-MAC port
    output wire                     mac_req,
    input  wire                     mac_grant,
    output wire                     mac_load,
    output wire signed [ACC_W-1:0]  mac_load_val,
    output wire                     mac_en,
    output wire signed [10:0]       mac_a,
    output wire signed [11:0]       mac_b,
    input  wire signed [ACC_W-1:0]  mac_acc,
    input  wire                     mac_acc_valid,
    input  wire                     mac_overflow,
    // result
    output reg                      nn_valid,
    output reg                      nn_class,
    output reg  signed [ACC_W-1:0]  nn_score0,
    output reg  signed [ACC_W-1:0]  nn_score1,
    output reg  [15:0]              nn_margin,
    output reg                      nn_lowconf,
    output reg                      nn_ovf,
    output wire                     busy,
    output reg  [15:0]              last_latency
);
    localparam [2:0] S_IDLE = 3'd0, S_LOAD = 3'd1, S_MAC = 3'd2, S_DRAIN = 3'd3, S_FIN = 3'd4;

    reg [2:0]  state;
    reg [4:0]  n;            // neuron 0..17
    reg [4:0]  k;            // tap
    reg [2:0]  pend_ops;
    reg [15:0] lat;
    reg [6:0]  h [0:15];
    reg signed [ACC_W-1:0] sc0, sc1;
    integer i;

    wire layer2 = (n >= 5'd16);
    wire [4:0] last_k = layer2 ? 5'd15 : 5'd7;

    assign feat_addr    = k[2:0];
    assign w_addr       = layer2 ? (8'd128 | {3'b000, n[0], k[3:0]}) : {1'b0, n[3:0], k[2:0]};   // n*8 + k (k<8)
    assign b_addr       = n;
    assign mac_load_val = {{(ACC_W-24){b_data[23]}}, b_data};
    assign mac_a        = layer2 ? {4'b0000, h[k[3:0]]} : {{3{feat_data[7]}}, feat_data};
    assign mac_b        = {{4{w_data[7]}}, w_data};
    assign mac_req      = (state == S_LOAD) || (state == S_MAC) || (state == S_DRAIN);
    assign mac_load     = (state == S_LOAD) && mac_grant;
    assign mac_en       = (state == S_MAC)  && mac_grant;
    assign busy         = (state != S_IDLE);

    wire issue      = mac_load | mac_en;
    wire drain_done = (state == S_DRAIN) && (pend_ops == {2'b00, mac_acc_valid});

    // requantization of the layer-1 accumulator
    wire signed [ACC_W+1:0] rnd   = (shift_cfg == 5'd0) ? {(ACC_W+2){1'b0}} : ({{(ACC_W+1){1'b0}}, 1'b1} << (shift_cfg - 5'd1));
    wire signed [ACC_W+1:0] sum_r = $signed({{2{mac_acc[ACC_W-1]}}, mac_acc}) + rnd;
    wire signed [ACC_W+1:0] shf   = sum_r >>> shift_cfg;
    wire [6:0]              h_new = shf[ACC_W+1] ? 7'd0 : (shf > 127) ? 7'd127 : shf[6:0];

    // final decision
    wire signed [ACC_W:0] diff   = $signed({sc1[ACC_W-1], sc1}) - $signed({sc0[ACC_W-1], sc0});
    wire [ACC_W:0]        absd   = diff[ACC_W] ? (~diff + 1'b1) : diff;
    wire [15:0]           marg   = (|absd[ACC_W:16]) ? 16'hFFFF : absd[15:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; n <= 0; k <= 0; pend_ops <= 0; lat <= 0;
            sc0 <= 0; sc1 <= 0; nn_valid <= 1'b0; nn_class <= 1'b0; nn_score0 <= 0; nn_score1 <= 0;
            nn_margin <= 0; nn_lowconf <= 1'b0; nn_ovf <= 1'b0; last_latency <= 0;
            for (i = 0; i < 16; i = i + 1) h[i] <= 7'd0;
        end else begin
            nn_valid <= 1'b0;
            if (state != S_IDLE) begin
                pend_ops <= pend_ops + issue - mac_acc_valid;
                if (lat != 16'hFFFF) lat <= lat + 16'd1;
            end
            case (state)
                S_IDLE: if (start) begin
                    n <= 0; k <= 0; pend_ops <= 0; lat <= 16'd0; nn_ovf <= 1'b0; state <= S_LOAD;
                end
                S_LOAD: if (mac_grant) begin state <= S_MAC; k <= 0; end
                S_MAC: if (mac_grant) begin
                    if (k == last_k) state <= S_DRAIN; else k <= k + 5'd1;
                end
                S_DRAIN: if (drain_done) begin
                    if (mac_overflow) nn_ovf <= 1'b1;
                    if (!layer2) h[n[3:0]] <= h_new;
                    else if (n[0]) sc1 <= mac_acc; else sc0 <= mac_acc;
                    if (n == 5'd17) state <= S_FIN;
                    else begin n <= n + 5'd1; k <= 0; state <= S_LOAD; end
                end
                S_FIN: begin
                    nn_score0 <= sc0; nn_score1 <= sc1;
                    nn_class  <= ~diff[ACC_W] & (|diff);       // score1 > score0
                    nn_margin <= marg;
                    nn_lowconf <= (marg < conf_thr);
                    last_latency <= lat + 16'd1;
                    nn_valid <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
