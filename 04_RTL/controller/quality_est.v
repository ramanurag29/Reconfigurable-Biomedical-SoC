`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// quality_est [synthesizable] : windowed ECG signal-quality estimator (task T3 helper).
// Window W = 2^L samples, L = win_log2 clamped to 4..10 (16..1024 samples; default 9 = 1.42 s @360 Hz).
// Per window, on the centred samples x (signed 11 b):
//   clip_cnt = #samples with x <= -512 or x >= 511      (ADC code 0 or 1023 -> clipping)
//   p2p      = max(x) - min(x)                          (amplitude; small -> flat / lead-off)
//   mad      = (sum |x[n]-x[n-1]|) >> L                 (mean abs first difference -> HF noise)
//   mean     = (sum x) >>> L   (floor)                  (baseline offset / wander)
// Flags (all thresholds programmable):
//   f_clip  = clip_cnt > clip_max
//   f_flat  = p2p < amp_min
//   f_noise = 16*mad > p2p*noise_k        (noise relative to amplitude; noise_k in 1/16 units)
//   f_base  = |mean| > base_max
// penalty = 2*f_clip + 2*f_flat + f_noise + f_base ; class 0 GOOD (0) / 1 MODERATE (1) / 2 POOR (>=2)
// score   = 255 - 80*f_clip - 80*f_flat - 48*f_noise - 32*f_base       (15..255)
// The first-difference term uses the previous sample even across window borders (x[-1] after reset/clr
// does not exist -> that one difference is skipped). Bit-exact reference: 11_Scripts/quality_golden.py.
// This is a heuristic, programmable quality screen for an academic demonstrator, not a clinical SQI.
// -----------------------------------------------------------------------------
module quality_est (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clr,          // synchronous restart of the window
    input  wire               in_valid,
    input  wire signed [10:0] x,
    input  wire [3:0]         win_log2,
    input  wire [7:0]         clip_max,
    input  wire [10:0]        amp_min,
    input  wire [7:0]         noise_k,
    input  wire [9:0]         base_max,
    output reg                q_valid,
    output reg  [1:0]         q_class,
    output reg  [3:0]         q_flags,      // {f_base, f_noise, f_flat, f_clip}
    output reg  [7:0]         q_score,
    output reg  [10:0]        q_p2p,
    output reg  [10:0]        q_mad,
    output reg  signed [10:0] q_mean
);
    wire [3:0] L = (win_log2 < 4'd4) ? 4'd4 : (win_log2 > 4'd10) ? 4'd10 : win_log2;
    wire [10:0] last_idx = (11'd1 << L) - 11'd1;

    reg  [10:0]        cnt;
    reg  signed [20:0] sum;
    reg  [19:0]        sad;
    reg  signed [10:0] mn, mx, prev;
    reg                prev_v;
    reg  [10:0]        clip_cnt;
    reg                fin;

    wire               is_clip = (x <= -11'sd512) || (x >= 11'sd511);
    wire signed [11:0] dx      = {x[10], x} - {prev[10], prev};
    wire [10:0]        adx     = dx[11] ? (~dx[10:0] + 11'd1) : dx[10:0];
    wire [10:0]        adx_g   = prev_v ? adx : 11'd0;
    wire               first   = (cnt == 11'd0);

    // end-of-window arithmetic (registers are stable during the `fin` cycle)
    wire signed [20:0] mean_w  = sum >>> L;
    wire [19:0]        mad_w   = sad >> L;
    wire [10:0]        p2p_w   = mx - mn;
    wire [10:0]        absmean = mean_w[20] ? (~mean_w[10:0] + 11'd1) : mean_w[10:0];
    wire [14:0]        lhs_n   = {mad_w[10:0], 4'b0000};
    wire [18:0]        rhs_n   = p2p_w * noise_k;
    wire               f_clip  = clip_cnt > {3'b000, clip_max};
    wire               f_flat  = p2p_w < amp_min;
    wire               f_noise = {4'b0000, lhs_n} > rhs_n;
    wire               f_base  = absmean > {1'b0, base_max};
    wire [2:0]         pen     = {f_clip, 1'b0} + {f_flat, 1'b0} + {2'b00, f_noise} + {2'b00, f_base};
    wire [7:0]         score   = 8'd255 - (f_clip ? 8'd80 : 8'd0) - (f_flat ? 8'd80 : 8'd0)
                                        - (f_noise ? 8'd48 : 8'd0) - (f_base ? 8'd32 : 8'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0; sum <= 0; sad <= 0; mn <= 0; mx <= 0; prev <= 0; prev_v <= 1'b0; clip_cnt <= 0; fin <= 1'b0;
            q_valid <= 1'b0; q_class <= 2'd0; q_flags <= 4'd0; q_score <= 8'd0; q_p2p <= 0; q_mad <= 0; q_mean <= 0;
        end else if (clr) begin
            cnt <= 0; sum <= 0; sad <= 0; prev_v <= 1'b0; clip_cnt <= 0; fin <= 1'b0; q_valid <= 1'b0;
        end else begin
            q_valid <= 1'b0;
            fin     <= 1'b0;
            if (fin) begin
                q_valid <= 1'b1;
                q_class <= (pen == 3'd0) ? 2'd0 : (pen == 3'd1) ? 2'd1 : 2'd2;
                q_flags <= {f_base, f_noise, f_flat, f_clip};
                q_score <= score;
                q_p2p   <= p2p_w;
                q_mad   <= mad_w[10:0];
                q_mean  <= mean_w[10:0];
            end
            if (in_valid) begin          // a sample in the fin cycle starts the next window (fin uses old regs)
                prev <= x; prev_v <= 1'b1;
                if (first) begin
                    sum <= {{10{x[10]}}, x}; sad <= {9'd0, adx_g}; mn <= x; mx <= x;
                    clip_cnt <= {10'd0, is_clip};
                end else begin
                    sum <= sum + {{10{x[10]}}, x}; sad <= sad + {9'd0, adx_g};
                    if (x < mn) mn <= x;
                    if (x > mx) mx <= x;
                    if (is_clip) clip_cnt <= clip_cnt + 11'd1;
                end
                if (cnt == last_idx) begin cnt <= 11'd0; fin <= 1'b1; end
                else                  cnt <= cnt + 11'd1;
            end
        end
    end
endmodule
