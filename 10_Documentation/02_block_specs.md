# Block specifications (implemented modules)

Status: all blocks below are **simulated**, none synthesized yet. Port widths in bits.

## input_formatter (`04_RTL/interfaces`)
Purpose: unsigned ADC code → centred signed sample `x = D − 2^(N−1)`. Params: `ADC_BITS=10`. Ports: `clk, rst_n, in_valid, adc_code[N-1:0]` → `out_valid, x_signed[N:0]` (1-clock latency). Verified: 3 ECG streams + reset (tb_input_formatter_ecg).

## sar_controller (`04_RTL/adc`) — synthesizable
Purpose: N-bit successive approximation, one bit/clock. Params: `N=10`, `SAMPLE_CYCLES=1`. Ports: `clk, rst_n, start, cmp_out` → `sample_en, dac_code[N-1:0], busy, done, data_out[N-1:0]`. `cmp_out=1` ⇒ keep trial bit. `start` ignored while busy. Latency start→done = SAMPLE_CYCLES+N+1 (=12). Verified exhaustively (tb_sar_controller).

## Behavioural ADC models (`04_RTL/adc`) — NOT synthesizable, NOT analog circuits
`sample_hold_behav` (ideal track/hold), `comparator_behav` (`OFFSET` param, zero delay/noise), `cdac_behav` (ideal binary weights, `VREF`, `N`), `adc_frontend_behav` (wires them to `sar_controller`; `bypass` selects `bypass_data/bypass_valid`; ports `vin(real), start, bypass, bypass_data, bypass_valid` → `adc_data, adc_valid, busy`). Matching, parasitics, settling, kT/C noise are **not** modelled.

## mac_unit (`04_RTL/mac`) — synthesizable
Signed MAC. Params `A_W=11, B_W=12, ACC_W=32, SATURATE=1, PIPE=0` (requires `ACC_W ≥ A_W+B_W`, checked at elaboration). Ops priority clear > load > en. Overflow → saturate (or wrap) + sticky `overflow` (cleared by clear/load). `acc_valid` 1 clock after the op is applied (PIPE=1: 2). Worst product 2^20 ⇒ 16 taps need 26 bit.

## regfile_sync / sample_buffer / output_fifo (`04_RTL/memory`) — synthesizable
- `regfile_sync #(WIDTH,DEPTH,RESET_CLEAR)`: 1 sync write, 1 async read; no data reset by default (load before use).
- `sample_buffer #(W=11,DEPTH=64)`: circular history, `rd_offset` 0 = newest, `rd_valid`, `count`.
- `output_fifo #(W,DEPTH)`: FWFT; push-when-full rejected + sticky overflow; pop-when-empty ignored + sticky underflow; `clr_flags`.

## fir_engine / fir_block (`04_RTL/fir`) — synthesizable
`y[n] = sat11((Σ_{k<T} h[k]·x[n−k] + 2^(S−1)) >>> S)`, T=1..16, S=0..31 (typ. 11), h Q1.11 12-bit, y 11-bit signed (−1024…+1023). The engine contains no multiplier: it requests the shared MAC (`mac_req/mac_grant`, one op per clock) and exposes `last_latency` (busy cycles = T+2, or T+3 with a pipelined MAC; sample→y_valid = T+3 / T+4). One held sample while busy; a second raises sticky `overrun`. `fir_block` = engine + coefficient regfile + private MAC (dedicated-MAC reference for the shared-vs-dedicated experiment). Verified bit-exact against `fir_golden_model.py` for 8 and 16 taps on real ECG, plus 600 random stress trials with saturation.

## Golden / reference scripts (`11_Scripts`)
`ecg_pipeline.py` (ECG → codes → hex/PWL), `fir_golden_model.py` (integer FIR + coefficient design, frequency-response and error report in `09_Results/fir`), `regress.sh`, `make_verification_report.py`.
Measured FIR design data (from `09_Results/fir/fir_report.json`): 16 taps stopband ≥90 Hz −46.8 dB vs 8 taps −18.3 dB; RMS error vs float ≈ 0.28 LSB for both — a design-space result, not yet a classification result.

## nn_engine / nn_block  (`04_RTL/neural_network/`) — simulated, not yet synthesized
**Purpose:** 8→16→2 integer inference sequencer on the shared MAC (no multiplier inside). Per neuron: one MAC *load-bias* op, then 8 (layer 1) or 16 (layer 2) MAC ops, then drain. Preemption boundary = between MAC ops / neurons; saved context = neuron index `n`, tap `k`, hidden buffer `h[16]`.
**Interface:** `start`, `shift_cfg` (S1), `conf_thr[15:0]`; external memories `feat_addr/feat_data` (8×s8), `w_addr/w_data` (160×s8), `b_addr/b_data` (18×s24); shared-MAC port `mac_req/grant/load/load_val/en/a/b/acc/acc_valid/overflow`; results `nn_valid, nn_class, nn_score0/1 (s32), nn_margin (u16), nn_lowconf, nn_ovf, busy, last_latency`. `nn_block` adds the three regfiles (host load: `cfg_sel` 0=weights 1=bias 2=features) and a private MAC for unit tests / the dedicated-MAC experiment.
**Arithmetic:** hidden `h = clamp((acc1 + 2^(S1-1)) >>> S1, 0, 127)` (ReLU folded in); `class = score1 > score0` (tie → 0); `margin = min(|score1-score0|, 65535)`; `lowconf = margin < conf_thr`. Bit-exact reference: `11_Scripts/nn_golden.py::infer_int`. Memory layout: `weights[j*8+i]` = W1, `weights[128+o*16+j]` = W2, `bias[0..15]` = b1, `bias[16..17]` = b2.
**Measured (simulation):** latency 197 clocks (private MAC PIPE=0), 215 (PIPE=1) = 18 neurons × (1 load + N taps + 1 drain) + FIN (+1/neuron for the pipelined MAC).
**Known property:** with int8 weights, s24 biases and 11-bit operands, |acc| < 8.7·10⁶ ≪ 2³¹, so `nn_ovf` can never assert for this network; it is kept as a defensive flag for wider models and is *not exercised* by any test.
**Training:** `11_Scripts/train_nn.py` (patient-independent DS1/DS2 split by record; 202 dropped because it is the same patient as 201). Real-data numbers are in `09_Results/nn/nn_metrics.json` once you run it; no accuracy figure is claimed before that.
