# Verification report (auto-generated)

Generated 2026-11-13 08:45 by `11_Scripts/make_verification_report.py` from `09_Results/sim_*.log`. Simulator: Icarus Verilog. Nothing here has been synthesized, timed or placed yet.

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
