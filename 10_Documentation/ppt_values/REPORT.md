# 1. MATLAB processing values (MIT-BIH)
## Dataset files
total 75244
drwxr-xr-x  3 ramanurag ramanurag     4096 Nov 11 09:31 .
drwxr-xr-x 15 ramanurag ramanurag     4096 Nov 13 06:41 ..
drwxr-xr-x  4 ramanurag ramanurag     4096 Nov 11 09:31 mit-bih-arrhythmia-database-1.0.0
-rw-r--r--  1 ramanurag ramanurag 77030320 Nov 29  2023 mitdb.zip

## MATLAB scripts

## Record / sampling / filter parameters (grep from MATLAB code)

## Any config/summary/log files MATLAB produced
# 2. FIR coefficient data (16-tap requirement)
Files found:


## taps in RTL / testbench
04_RTL/fir/fir_block.v:14:    input  wire [4:0]          taps_cfg,
04_RTL/fir/fir_block.v:30:    regfile_sync #(.WIDTH(12), .DEPTH(16)) u_coef (.clk(clk), .rst_n(rst_n), .we(cfg_we),
04_RTL/fir/fir_block.v:34:        .taps_cfg(taps_cfg), .shift_cfg(shift_cfg), .coef_addr(coef_addr), .coef_data($signed(coef_data)),
04_RTL/fir/fir_engine.v:4://   y[n] = sat( (sum_{k<T} h[k]*x[n-k] + 2^(S-1)) >>> S ),  T = taps (1..16), S = shift
04_RTL/fir/fir_engine.v:18:    parameter MAX_TAPS = 16
04_RTL/fir/fir_engine.v:24:    input  wire [4:0]               taps_cfg,
04_RTL/fir/fir_engine.v:49:    localparam [4:0] TMAX = MAX_TAPS;
04_RTL/fir/fir_engine.v:59:    reg signed [X_W-1:0] x_hist [0:MAX_TAPS-1];
04_RTL/fir/fir_engine.v:62:    wire [4:0] taps_eff = (taps_cfg == 5'd0) ? 5'd1 : (taps_cfg > TMAX) ? TMAX : taps_cfg;
04_RTL/fir/fir_engine.v:89:            for (i = 0; i < MAX_TAPS; i = i + 1) x_hist[i] <= 0;
04_RTL/fir/fir_engine.v:98:                    for (i = MAX_TAPS-1; i > 0; i = i - 1) x_hist[i] <= x_hist[i-1];
05_Testbench/tb_fir.v:5://  P1 ECG, 16 taps vs Python golden   P2 ECG, 8 taps vs Python golden
05_Testbench/tb_fir.v:7://     (random taps 1..16, shift 0..12, full-range coefficients/samples -> rounding + saturation)
05_Testbench/tb_fir.v:13:    reg [4:0] taps = 16, shift = 11; reg signed [10:0] sample_in = 0;
05_Testbench/tb_fir.v:87:        // ---------------- P1: ECG 16 taps
05_Testbench/tb_fir.v:88:        $readmemh(`FIR_COEF16_FILE, cmem); for (i = 0; i < 16; i = i + 1) wr_coef(i, cmem[i]);
05_Testbench/tb_fir.v:89:        $readmemh(`FIR_Y16_FILE, ex); taps = 16; shift = `FIR_SHIFT;
05_Testbench/tb_fir.v:94:        if (lat0 !== 16 + 3 || lat1 !== 16 + 4 || ll0 !== 16 + 2 || ll1 !== 16 + 3) begin errors = errors + 1; $display("  latency got %0d/%0d (busy %0d/%0d)", lat0, lat1, ll0, ll1); end
05_Testbench/tb_fir.v:95:        $display("[latency 16 taps] sample->y: PIPE0=%0d clk, PIPE1=%0d clk; MAC-busy cycles %0d/%0d -> %0s", lat0, lat1, ll0, ll1, errors == 0 ? "PASS" : "FAIL");
05_Testbench/tb_fir.v:97:        do_reset; c0 = 0; c1 = 0; mon_en = 1; stream(40); mon_en = 0; phase_result("ECG 16-tap vs Python golden", c0, c1);
05_Testbench/tb_fir.v:104:            do_reset; mT = 1 + ({$random(seed)} % 16); mshift = {$random(seed)} % 13;
05_Testbench/tb_fir.v:106:            for (i = 0; i < 16; i = i + 1) begin
05_Testbench/tb_fir.v:111:            for (i = 0; i < 16; i = i + 1) mh[i] = 0;
05_Testbench/tb_fir.v:121:        do_reset; taps = 16; shift = 11; for (i = 0; i < 16; i = i + 1) wr_coef(i, 12'h040);
## fir_engine parameters
15:    parameter X_W      = 11,
16:    parameter H_W      = 12,
17:    parameter ACC_W    = 32,
18:    parameter MAX_TAPS = 16
48:    localparam [2:0] S_IDLE = 3'd0, S_CLR = 3'd1, S_MAC = 3'd2, S_DRAIN = 3'd3;
49:    localparam [4:0] TMAX = MAX_TAPS;
50:    localparam signed [ACC_W:0] YMAX =  (1 <<< (X_W-1)) - 1;
51:    localparam signed [ACC_W:0] YMIN = -(1 <<< (X_W-1));
# 3. SAR ADC values
## RTL parameters
04_RTL/adc/comparator_behav.v:4:module comparator_behav #(parameter real OFFSET = 0.0) (
04_RTL/adc/sar_controller.v:14:    parameter N             = 10,
04_RTL/adc/sar_controller.v:15:    parameter SAMPLE_CYCLES = 1
04_RTL/adc/sar_controller.v:27:    localparam [1:0] S_IDLE = 2'd0, S_SAMP = 2'd1, S_CONV = 2'd2, S_FIN = 2'd3;
04_RTL/adc/adc_frontend_behav.v:10:    parameter N             = 10,
04_RTL/adc/adc_frontend_behav.v:11:    parameter real VREF     = 2.0,
04_RTL/adc/adc_frontend_behav.v:12:    parameter real CMP_OFFSET = 0.0,
04_RTL/adc/adc_frontend_behav.v:13:    parameter SAMPLE_CYCLES = 1
04_RTL/adc/cdac_behav.v:4:module cdac_behav #(parameter N = 10, parameter real VREF = 2.0) (

## ADC files
04_RTL/adc
04_RTL/adc/sar_controller.v
04_RTL/adc/adc_frontend_behav.v
05_Testbench/tb_sar_controller.v
05_Testbench/tb_adc_ecg.v
05_Testbench/tb_adc.v

## Quantization code in MATLAB

## Derived (D = round(Vin/Vref*1023), Vref=2.0 V, 10 bit)
LSB = Vref/(2^N-1) = 1.9550 mV
Full-scale codes: 0..1023; signed = D-512 -> -512..511
Ideal quantization error: +/-0.9775 mV (+/-0.5 LSB)
Ideal SNR = 6.02*N+1.76 = 61.96 dB
Conditioned range 0.5-1.5 V -> codes 256..767 (512 codes used)
Vin=0.92 V -> D=471  signed=-41
Vin=1.04 V -> D=532  signed=20
Vin=1.14 V -> D=583  signed=71
Vin=1.0 V -> D=512  signed=0

## ADC testbench result lines
| tb_sar_controller | sar_controller | all 1024 target codes through an ideal integer comparator, SAMPLE_CYCLES 1 and 3; extra start while busy; mid-conversion reset; continuous start | code = target, latency = SC+N+1, sample_en width = SC, period SC+N+2 | - |
| tb_adc | behavioural SAR ADC (S&H, comparator, CDAC, controller, bypass) | zero/mid/full scale, over-range, 2046 boundary points, 3072-pt ramp, 360-pt sine, 3000 random, hold test, bypass, reset; second DUT with +1 LSB comparator offset | D = clamp(floor(vin/LSB),0,1023); |error| <= LSB/2; latency 12 | - |
| tb_adc_ecg | ADC -> input_formatter chain | 3600 PWL volts from the ECG pipeline | Python golden codes and signed samples, checksum | - |
| tb_sar_controller | sar_controller SC=1 exhaustive 1024 codes — errors=0 | PASS |
| tb_sar_controller | sar_controller SC=3 exhaustive 1024 codes — errors=0 | PASS |
| tb_sar_controller | **overall** | **PASS** |
| tb_adc | scale points + overrange — errors=0 | info |
| tb_adc | boundary transitions 2046 pts — errors=0 | info |
| tb_adc | ramp 3072 pts — errors=0 max|err|=0.976562 mV (LSB/2=0.976562 mV) latency=12 clk | info |
| tb_adc | sine 360 pts — errors=0 | info |
| tb_adc | random 3000 pts incl. out-of-range — errors=0 | info |
| tb_adc | hold behaviour — errors=0 | info |
| tb_adc | bypass — errors=0 | info |
| tb_adc | reset during conversion — errors=0 | info |
| tb_adc | **overall** | **PASS** |
| tb_adc_ecg | ECG 3600 samples: PWL volts -> SAR ADC -> formatter vs Python golden — checksum=-2289 errors=0 | info |
| tb_adc_ecg | **overall** | **PASS** |
# 4. Digital SoC block: widths, parameters, interfaces

## 04_RTL/adc/adc_frontend_behav.v
10:    parameter N             = 10,
11:    parameter real VREF     = 2.0,
12:    parameter real CMP_OFFSET = 0.0,
13:    parameter SAMPLE_CYCLES = 1
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

## 04_RTL/adc/cdac_behav.v
input  wire [N-1:0] code,
output real         vdac

## 04_RTL/adc/comparator_behav.v
input  real vin,
input  real vdac,
output wire cmp_out

## 04_RTL/adc/sample_hold_behav.v
input  wire sample_en,
input  real vin,
output real vhold

## 04_RTL/adc/sar_controller.v
14:    parameter N             = 10,
15:    parameter SAMPLE_CYCLES = 1
27:    localparam [1:0] S_IDLE = 2'd0, S_SAMP = 2'd1, S_CONV = 2'd2, S_FIN = 2'd3;
input  wire         clk,
input  wire         rst_n,
input  wire         start,
input  wire         cmp_out,
output wire         sample_en,
output wire [N-1:0] dac_code,
output wire         busy,
output reg          done,
output reg  [N-1:0] data_out

## 04_RTL/fir/fir_block.v
input  wire                clk,
input  wire                rst_n,
input  wire                cfg_we,
input  wire [3:0]          cfg_addr,
input  wire [11:0]         cfg_wdata,
input  wire [4:0]          taps_cfg,
input  wire [4:0]          shift_cfg,
input  wire                sample_valid,
input  wire signed [10:0]  sample_in,
output wire                y_valid,
output wire signed [10:0]  y_data,
output wire                y_sat,
output wire                y_ovf,
output wire                busy,
output wire                overrun,
output wire [7:0]          last_latency

## 04_RTL/fir/fir_engine.v
15:    parameter X_W      = 11,
16:    parameter H_W      = 12,
17:    parameter ACC_W    = 32,
18:    parameter MAX_TAPS = 16
48:    localparam [2:0] S_IDLE = 3'd0, S_CLR = 3'd1, S_MAC = 3'd2, S_DRAIN = 3'd3;
49:    localparam [4:0] TMAX = MAX_TAPS;
50:    localparam signed [ACC_W:0] YMAX =  (1 <<< (X_W-1)) - 1;
51:    localparam signed [ACC_W:0] YMIN = -(1 <<< (X_W-1));
input  wire                     clk,
input  wire                     rst_n,
input  wire                     sample_valid,
input  wire signed [X_W-1:0]    sample_in,
input  wire [4:0]               taps_cfg,
input  wire [4:0]               shift_cfg,
output wire [3:0]               coef_addr,
input  wire signed [H_W-1:0]    coef_data,
output wire                     mac_req,
input  wire                     mac_grant,
output wire                     mac_clear,
output wire                     mac_en,
output wire signed [X_W-1:0]    mac_a,
output wire signed [H_W-1:0]    mac_b,
input  wire signed [ACC_W-1:0]  mac_acc,
input  wire                     mac_acc_valid,
input  wire                     mac_overflow,
output reg                      y_valid,
output reg  signed [X_W-1:0]    y_data,
output reg                      y_sat,
output reg                      y_ovf,
output wire                     busy,
output wire                     at_boundary,   // 1 = safe preemption point (no MAC result pending use)
output reg                      overrun,
output reg  [7:0]               last_latency

## 04_RTL/interfaces/input_formatter.v
11:    parameter ADC_BITS = 10
20:    localparam [ADC_BITS:0] MIDSCALE = (1 << (ADC_BITS-1));   // 2^(ADC_BITS-1)
module input_formatter #(
input  wire                       clk,
input  wire                       rst_n,
input  wire                       in_valid,
input  wire [ADC_BITS-1:0]        adc_code,
output reg                        out_valid,
output reg  signed [ADC_BITS:0]   x_signed

## 04_RTL/mac/mac_unit.v
15:    parameter A_W      = 11,
16:    parameter B_W      = 12,
17:    parameter ACC_W    = 32,
18:    parameter SATURATE = 1,
19:    parameter PIPE     = 0
33:    localparam P_W = A_W + B_W;
37:    localparam signed [ACC_W-1:0] ACC_MAX = {1'b0, {(ACC_W-1){1'b1}}};
38:    localparam signed [ACC_W-1:0] ACC_MIN = {1'b1, {(ACC_W-1){1'b0}}};
input  wire                     clk,
input  wire                     rst_n,
input  wire                     en,
input  wire                     clear,
input  wire                     load,
input  wire signed [A_W-1:0]    a,
input  wire signed [B_W-1:0]    b,
input  wire signed [ACC_W-1:0]  load_val,
output reg  signed [ACC_W-1:0]  acc,
output reg                      acc_valid,
output reg                      overflow

## 04_RTL/memory/output_fifo.v
9:    parameter W     = 16,
10:    parameter DEPTH = 16
25:    localparam AW = $clog2(DEPTH);
module output_fifo #(
input  wire                  clk,
input  wire                  rst_n,
input  wire                  push,
input  wire [W-1:0]          din,
input  wire                  pop,
input  wire                  clr_flags,
output wire [W-1:0]          dout,
output wire                  full,
output wire                  empty,
output reg  [$clog2(DEPTH):0] count,
output reg                   overflow,
output reg                   underflow

## 04_RTL/memory/regfile_sync.v
10:    parameter WIDTH = 12,
11:    parameter DEPTH = 16,
12:    parameter RESET_CLEAR = 0
input  wire                     clk,
input  wire                     rst_n,
input  wire                     we,
input  wire [$clog2(DEPTH)-1:0] waddr,
input  wire [WIDTH-1:0]         wdata,
input  wire [$clog2(DEPTH)-1:0] raddr,
output wire [WIDTH-1:0]         rdata

## 04_RTL/memory/sample_buffer.v
9:    parameter W     = 11,
10:    parameter DEPTH = 64
21:    localparam AW = $clog2(DEPTH);
input  wire                  clk,
input  wire                  rst_n,
input  wire                  wr_en,
input  wire [W-1:0]          wr_data,
input  wire [$clog2(DEPTH)-1:0] rd_offset,
output wire [W-1:0]          rd_data,
output wire                  rd_valid,
output reg  [$clog2(DEPTH):0] count

## 04_RTL/neural_network/nn_block.v
input  wire               clk,
input  wire               rst_n,
input  wire               cfg_we,
input  wire [1:0]         cfg_sel,
input  wire [7:0]         cfg_addr,
input  wire [23:0]        cfg_wdata,
input  wire               start,
input  wire [4:0]         shift_cfg,
input  wire [15:0]        conf_thr,
output wire               nn_valid,
output wire               nn_class,
output wire signed [31:0] nn_score0,
output wire signed [31:0] nn_score1,
output wire [15:0]        nn_margin,
output wire               nn_lowconf,
output wire               nn_ovf,
output wire               busy,
output wire [15:0]        last_latency

## 04_RTL/neural_network/nn_engine.v
15:    parameter ACC_W = 32
52:    localparam [2:0] S_IDLE = 3'd0, S_LOAD = 3'd1, S_MAC = 3'd2, S_DRAIN = 3'd3, S_FIN = 3'd4;
input  wire                     clk,
input  wire                     rst_n,
input  wire                     start,
input  wire [4:0]               shift_cfg,     // S1 (hidden requantization shift)
input  wire [15:0]              conf_thr,
output wire [2:0]               feat_addr,
input  wire signed [7:0]        feat_data,
output wire [7:0]               w_addr,
input  wire signed [7:0]        w_data,
output wire [4:0]               b_addr,
input  wire signed [23:0]       b_data,
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
output reg                      nn_valid,
output reg                      nn_class,
output reg  signed [ACC_W-1:0]  nn_score0,
output reg  signed [ACC_W-1:0]  nn_score1,
output reg  [15:0]              nn_margin,
output reg                      nn_lowconf,
output reg                      nn_ovf,
output wire                     busy,
output wire                     at_boundary,   // 1 = safe preemption point (between MAC ops)
output reg  [15:0]              last_latency

## Register map

## NN / quality specs
features.npz
nn_int_model.json
# 5. Verification results and pipeline status
## Regression
tb_input_formatter_ecg PASS
tb_sar_controller      PASS
tb_adc                 PASS
tb_adc_ecg             PASS
tb_mac                 PASS
tb_memory              PASS
tb_output              PASS
tb_fir                 PASS
tb_nn                  PASS
tb_scheduler           PASS
tb_scheduler_p1        PASS
wrote 10_Documentation/03_verification_report.md
REGRESSION: ALL PASS

## Verification report
# Verification report (auto-generated)

Generated 2026-11-17 06:40 by `11_Scripts/make_verification_report.py` from `09_Results/sim_*.log`. Simulator: Icarus Verilog. Nothing here has been synthesized, timed or placed yet.

| Testbench | Unit under test | Input | Expected | Waveform |
|---|---|---|---|---|
| tb_input_formatter_ecg | input_formatter | 3600 real ECG codes (MIT-BIH 100) as gapped and back-to-back streams, junk data while valid=0, reset states | signed = code - 512 from independent Python golden + checksum | tb_input_formatter_ecg.vcd |
| tb_sar_controller | sar_controller | all 1024 target codes through an ideal integer comparator, SAMPLE_CYCLES 1 and 3; extra start while busy; mid-conversion reset; continuous start | code = target, latency = SC+N+1, sample_en width = SC, period SC+N+2 | - |
| tb_adc | behavioural SAR ADC (S&H, comparator, CDAC, controller, bypass) | zero/mid/full scale, over-range, 2046 boundary points, 3072-pt ramp, 360-pt sine, 3000 random, hold test, bypass, reset; second DUT with +1 LSB comparator offset | D = clamp(floor(vin/LSB),0,1023); |error| <= LSB/2; latency 12 | - |
| tb_adc_ecg | ADC -> input_formatter chain | 3600 PWL volts from the ECG pipeline | Python golden codes and signed samples, checksum | - |
| tb_mac | mac_unit (5 configs) | directed saturation/priority cases + 40k random ops incl. mid-run reset | independent 64-bit reference: acc, overflow flag, valid timing | - |
| tb_memory | regfile_sync, sample_buffer | 40k random read/write cycles, mid-run reset | independent shadow models | - |
| tb_output | output_fifo | 90k random cycles in push-heavy / pop-heavy / balanced phases | log-based model incl. full/empty/count/overflow/underflow | - |
| tb_nn | nn_engine + nn_block (private MAC PIPE=0/1) | 64 test vectors from the trained 8-16-2 model; 300 random stress trials (full-range int8 weights, int24 biases, random shift/threshold); tie; start-while-busy; reset mid-inference | bit-exact Python golden (nn_golden.infer_int) and in-TB 64-bit integer reference: scores, class, margin, low-confidence flag; latency 197 (PIPE0) / 215 (PIPE1) clocks | tb_nn.vcd |
| tb_fir | fir_engine + fir_block (private MAC PIPE=0/1) | ECG 16/8 taps; latency; 600 random stress trials (random taps/shift/coefs, saturation); overrun; reset | Python bit-exact golden (ECG) and in-TB integer reference (stress) | - |
| tb_scheduler | task_scheduler + shared mac_unit + fir_engine + nn_engine (MAC PIPE=0) | fixed-priority / round-robin / mode-based contention, preemption with accumulator save/restore, non-preemptive mode, deadline monitor, FIR stream during NN, reset mid-contention, 300 random trials | bit-exact in-TB integer golden for FIR and NN results; exact MAC-op accounting (FIR 1+T, NN 178); preemption counts | tb_scheduler.vcd |
| tb_scheduler_p1 | task_scheduler with pipelined MAC (PIPE=1) | same testbench, -Ptb_scheduler.PIPE=1 | same checks; exercises the PIPE+1 restore wait and the drain-before-switch rule | - |

## Results (actual, copied from simulation logs)

| Testbench | Check | Result |
|---|---|---|
| tb_input_formatter_ecg | reset_state — errors=0 | PASS |
| tb_input_formatter_ecg | gapped_stream — samples=3600 checksum=-2289 errors=0 | PASS |
| tb_input_formatter_ecg | back_to_back — samples=3600 checksum=-2289 errors=0 | PASS |
| tb_input_formatter_ecg | reset_recovery — samples=3600 checksum=-2289 errors=0 | PASS |
| tb_input_formatter_ecg | **overall** | **PASS** |
| tb_sar_controller | sar_controller SC=1 exhaustive 1024 codes — errors=0 | PASS |
| tb_sar_controller | sar_controller SC=3 exhaustive 1024 codes — errors=0 | PASS |
| tb_sar_controller | **overall** | **PASS** |
| tb_adc | scale points + overrange — errors=0 | info |
| tb_adc | boundary transitions 2046 pts — errors=0 | info |
| tb_adc | ramp 3072 pts — errors=0 max|err|=0.976562 mV (LSB/2=0.976562 mV) latency=12 clk | info |
| tb_adc | sine 360 pts — errors=0 | info |
| tb_adc | random 3000 pts incl. out-of-range — errors=0 | info |
| tb_adc | hold behaviour — errors=0 | info |
| tb_adc | bypass — errors=0 | info |
| tb_adc | reset during conversion — errors=0 | info |
| tb_adc | **overall** | **PASS** |
| tb_adc_ecg | ECG 3600 samples: PWL volts -> SAR ADC -> formatter vs Python golden — checksum=-2289 errors=0 | info |
| tb_adc_ecg | **overall** | **PASS** |
| tb_mac | MAC 32b sat  PIPE=0 — checked=34826 overflow_events=1907 errors=0 | PASS |
| tb_mac | MAC 32b sat  PIPE=1 — checked=34826 overflow_events=1907 errors=0 | PASS |
| tb_mac | MAC 24b sat  PIPE=0 — checked=34826 overflow_events=8220 errors=0 | PASS |
| tb_mac | MAC 24b wrap PIPE=0 — checked=34826 overflow_events=8220 errors=0 | PASS |
| tb_mac | MAC 24b wrap PIPE=1 — checked=34826 overflow_events=8220 errors=0 | PASS |
| tb_mac | **overall** | **PASS** |
| tb_memory | regfile 160x8 (no-reset) / 16x12 (reset-clear) / sample_buffer 64x11, 40k random cycles — errors=0 | PASS |
| tb_memory | **overall** | **PASS** |
| tb_output | output_fifo 16x16: 90000 cycles; full=19873 empty=19432 overflow-events=12225 underflow-events=12058 — errors=0 | PASS |
| tb_output | **overall** | **PASS** |
| tb_nn | P1 trained-model vectors=64 —  | info |
| tb_nn | P1 python-golden — errors=0 | PASS |
| tb_nn | P2 latency PIPE0 min/max=197/197 PIPE1 min/max=215/215 cycles —  | info |
| tb_nn | P2 latency — errors=0 | PASS |
| tb_nn | P3 random-stress — errors=0 | PASS |
| tb_nn | P4 tie — errors=0 | PASS |
| tb_nn | P5 start-while-busy — errors=0 | PASS |
| tb_nn | P6 reset — errors=0 | PASS |
| tb_nn | **overall** | **PASS** |
| tb_fir | latency 16 taps — sampley: PIPE0=19 clk, PIPE1=20 clk; MAC-busy cycles 18/19 | PASS |
| tb_fir | ECG 16-tap vs Python golden — outputs=3600/3600 errors=0 | PASS |
| tb_fir | ECG 8-tap vs Python golden — outputs=3600/3600 errors=0 | PASS |
| tb_fir | stress 600 trials x 24 samples, random taps/shift/coef; saturating outputs seen=11203 — errors=0 | PASS |
| tb_fir | overrun flagged, engine recovers, reset clears — errors=0 | PASS |
| tb_fir | reset during computation — errors=0 | PASS |
| tb_fir | **overall** | **PASS** |
| tb_scheduler | 16-tap ops=17 tasks=1 preempts=0 —  | PASS |
| tb_scheduler | aits <=4 cycles when MAC is free —  | PASS |
| tb_scheduler | T1b 8-tap x2 ops=18 tasks=2 —  | PASS |
| tb_scheduler | T2 NN ops=178 tasks=1 —  | PASS |
| tb_scheduler | at least one preemption happened —  | PASS |
| tb_scheduler | T3 all ops executed exactly once —  | PASS |
| tb_scheduler | T3 restore overhead counted —  | PASS |
| tb_scheduler | mption of the higher-priority NN —  | PASS |
| tb_scheduler | T4 FIR waited for the NN —  | PASS |
| tb_scheduler | 5 RR time-slices between clients —  | PASS |
| tb_scheduler | T5 ops exact —  | PASS |
| tb_scheduler | T6 FIR preempted NN —  | PASS |
| tb_scheduler | T6 ops exact —  | PASS |
| tb_scheduler | T6b NN preempted FIR —  | PASS |
| tb_scheduler |  preemption, results still exact —  | PASS |
| tb_scheduler | T8a NN misses 50-cycle deadline —  | PASS |
| tb_scheduler | T8b NN meets 1000-cycle deadline —  | PASS |
| tb_scheduler | T9 10 FIR + 1 NN, ops exact —  | PASS |
| tb_scheduler | T9 no FIR overrun —  | PASS |
| tb_scheduler |  NN was preempted by FIR samples —  | PASS |
| tb_scheduler | s and scheduler idle after reset —  | PASS |
| tb_scheduler | T10 clean run after reset —  | PASS |
| tb_scheduler | als: FIR+NN bit-exact, ops exact —  | PASS |
| tb_scheduler | **overall** | **PASS** |
| tb_scheduler_p1 | 16-tap ops=17 tasks=1 preempts=0 —  | PASS |
| tb_scheduler_p1 | aits <=4 cycles when MAC is free —  | PASS |
| tb_scheduler_p1 | T1b 8-tap x2 ops=18 tasks=2 —  | PASS |
| tb_scheduler_p1 | T2 NN ops=178 tasks=1 —  | PASS |
| tb_scheduler_p1 | at least one preemption happened —  | PASS |
| tb_scheduler_p1 | T3 all ops executed exactly once —  | PASS |
| tb_scheduler_p1 | T3 restore overhead counted —  | PASS |
| tb_scheduler_p1 | mption of the higher-priority NN —  | PASS |
| tb_scheduler_p1 | T4 FIR waited for the NN —  | PASS |
| tb_scheduler_p1 | 5 RR time-slices between clients —  | PASS |
| tb_scheduler_p1 | T5 ops exact —  | PASS |
| tb_scheduler_p1 | T6 FIR preempted NN —  | PASS |
| tb_scheduler_p1 | T6 ops exact —  | PASS |
| tb_scheduler_p1 | T6b NN preempted FIR —  | PASS |
| tb_scheduler_p1 |  preemption, results still exact —  | PASS |
| tb_scheduler_p1 | T8a NN misses 50-cycle deadline —  | PASS |
| tb_scheduler_p1 | T8b NN meets 1000-cycle deadline —  | PASS |
| tb_scheduler_p1 | T9 10 FIR + 1 NN, ops exact —  | PASS |
| tb_scheduler_p1 | T9 no FIR overrun —  | PASS |
| tb_scheduler_p1 |  NN was preempted by FIR samples —  | PASS |
| tb_scheduler_p1 | s and scheduler idle after reset —  | PASS |
| tb_scheduler_p1 | T10 clean run after reset —  | PASS |
| tb_scheduler_p1 | als: FIR+NN bit-exact, ops exact —  | PASS |
| tb_scheduler_p1 | **overall** | **PASS** |

**Overall: ALL PASS**

Mutation checks: every module's testbench was also run against deliberately broken RTL (wrong decision polarity, missing rounding/saturation, off-by-one taps/index, missing flags, ...) and each mutant was detected; see commit history for the injected cases.

## Milestone history (git)
2026-11-17  M4: quality estimator, result manager, config/host regs, register map
2026-11-17  checkpoint: status sync
2026-11-16  checkpoint
2026-11-13  Add project summary script
2026-11-13  OpenLane dry run (task_scheduler+mac): LVS match, DRC 0, typical-corner timing met, antenna 98/101 open
2026-11-13  Scheduler: shared-MAC task_scheduler (fixed/RR/mode, safe preemption, ctx save/restore), tb_scheduler PIPE0/1
2026-11-13  NN engine (shared-MAC 8-16-2), bit-exact golden model, patient-independent trainer, tb_nn
2026-11-13  NN engine (shared-MAC 8-16-2), bit-exact golden model, patient-independent trainer, tb_nn
2026-11-13  NN engine (shared-MAC 8-16-2), bit-exact golden model, patient-independent trainer, tb_nn
2026-11-13  Memories, FIR engine + bit-exact golden model, FIFO, auto verification report, README, block specs
2026-11-13  SAR ADC (behavioural + controller), MAC unit, 5 self-checking TBs, regression script; D1=B
2026-11-13  M1: ECG -> 10-bit hex -> input_formatter testbench passes; architecture v0.1

## Module/testbench inventory
RTL: 15 files, 974 lines
TB : 10 files
OpenLane dir: 1 files (0 = not started, no GDS)
