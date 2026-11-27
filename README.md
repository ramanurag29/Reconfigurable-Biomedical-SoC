# Reconfigurable Biomedical SoC

Priority-aware reconfigurable mixed-signal biomedical SoC: real MIT-BIH ECG → behavioural 10-bit SAR ADC → shared MAC engine
(FIR + small NN) → hardware task scheduler → quality-aware output. Digital part targets OpenLane 1.0.2 / Sky130A; the analog
ADC is a later, separate transistor-level design. Academic demonstrator, **not** a medical device.

## Status (honest labels)
| Block | Status |
|---|---|
| ECG pipeline (Python): load, baseline, band-pass, scale, 10-bit quantize, hex/PWL export | implemented + verified vs RTL |
| input_formatter, sar_controller, mac_unit, regfile_sync, sample_buffer, output_fifo | implemented, simulated (self-checking) |
| Behavioural S&H / comparator / CDAC / adc_frontend_behav (with bypass) | simulation models only — not analog silicon |
| fir_engine (8/16 taps), nn_engine (8-16-2, patient-independent training) | implemented, simulated bit-exact vs Python golden |
| task_scheduler (fixed / round-robin / mode, safe preemption, context save/restore, metrics) | implemented, simulated |
| quality_est, result_manager, host_regs (register map), reset_sync | implemented, simulated (tb_config, tb_soc) |
| **biomed_soc_top** (full digital SoC, config A = SAR pins, config B = direct injection) | implemented, simulated bit-exact end to end (tb_soc), Verilator lint clean |
| OpenLane flow of biomed_soc_top | config ready (07_OpenLane/biomed_soc_top); see 09_Results/openlane for real results once run |
| MATLAB .m scripts | not written (Python reference exists; MATLAB availability unconfirmed) |
| Transistor-level analog (xschem/ngspice), 08_Analog | not started — next semester |

## Quick start
```bash
source .venv/bin/activate          # numpy scipy matplotlib wfdb
bash 11_Scripts/regress.sh         # golden data + all 13 testbenches + lint + 10_Documentation/03_verification_report.md
bash 11_Scripts/ol_prep.sh         # copy the SoC into ~/OpenLane/designs/biomed_soc and check config keys
bash 11_Scripts/ol_collect.sh      # after the flow: copy reports into 09_Results/openlane and print sign-off metrics
```
Dataset: place MIT-BIH under `01_Dataset/mit-bih-arrhythmia-database-1.0.0/` (not tracked in git).

## Key conventions
ADC `D = clamp(floor(Vin/LSB),0,1023)`, `LSB = 2 V/1024`; `x = D − 512` (11-bit signed); FIR coefficients Q1.11 (12-bit);
FIR output `sat11((acc + 2^(S−1)) >>> S)`, S = 11; accumulator 32-bit with saturate + sticky overflow.
Details: `10_Documentation/01_system_architecture.md`, module specs: `02_block_specs.md`, results: `03_verification_report.md`.

## Layout
`01_Dataset` `02_MATLAB` `03_AI_Model` `04_RTL/{adc,mac,memory,fir,neural_network,scheduler,controller,interfaces,top}`
`05_Testbench` `06_Simulation` `07_OpenLane` `08_Analog` `09_Results` `10_Documentation` `11_Scripts`
