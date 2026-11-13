# Reconfigurable Biomedical SoC

Priority-aware reconfigurable mixed-signal biomedical SoC: real MIT-BIH ECG → behavioural 10-bit SAR ADC → shared MAC engine
(FIR + small NN) → hardware task scheduler → quality-aware output. Digital part targets OpenLane 1.0.2 / Sky130A; the analog
ADC is a later, separate transistor-level design. Academic demonstrator, **not** a medical device.

## Status (honest labels)
| Block | Status |
|---|---|
| ECG pipeline (Python): load, baseline, band-pass, scale, 10-bit quantize, hex/PWL export | implemented + verified vs RTL |
| `input_formatter` | implemented, simulated |
| `sar_controller` | implemented, simulated (exhaustive 1024 codes); **not yet synthesized** |
| Behavioural S&H / comparator / CDAC / `adc_frontend_behav` (with bypass) | simulation models only — not analog silicon |
| `mac_unit` | implemented, simulated (5 configs); not yet synthesized |
| `regfile_sync`, `sample_buffer`, `output_fifo` | implemented, simulated |
| `fir_engine`, `fir_block` | implemented, simulated bit-exact vs Python golden (8 and 16 taps) |
| NN training/inference, scheduler, quality estimator, config/host interface, `biomed_soc_top` | **not started** (see 10_Documentation/01_system_architecture.md) |
| MATLAB `.m` scripts | **not written** (Python reference exists; MATLAB availability unconfirmed) |
| OpenLane flow, PPA numbers | **not run — no PPA results exist** |
| Transistor-level analog (xschem/ngspice) | next semester |

## Quick start
```bash
source .venv/bin/activate          # numpy scipy matplotlib wfdb
bash 11_Scripts/regress.sh         # golden data + all testbenches + 10_Documentation/03_verification_report.md
```
Dataset: place MIT-BIH under `01_Dataset/mit-bih-arrhythmia-database-1.0.0/` (not tracked in git).

## Key conventions
ADC `D = clamp(floor(Vin/LSB),0,1023)`, `LSB = 2 V/1024`; `x = D − 512` (11-bit signed); FIR coefficients Q1.11 (12-bit);
FIR output `sat11((acc + 2^(S−1)) >>> S)`, S = 11; accumulator 32-bit with saturate + sticky overflow.
Details: `10_Documentation/01_system_architecture.md`, module specs: `02_block_specs.md`, results: `03_verification_report.md`.

## Layout
`01_Dataset` `02_MATLAB` `03_AI_Model` `04_RTL/{adc,mac,memory,fir,neural_network,scheduler,controller,interfaces,top}`
`05_Testbench` `06_Simulation` `07_OpenLane` `08_Analog` `09_Results` `10_Documentation` `11_Scripts`
