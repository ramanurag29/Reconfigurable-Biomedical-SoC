# Pipeline status (from repo evidence only)
| Stage | State |
|---|---|
| ECG dataset -> 10-bit codes -> formatter | done, simulated, bit-exact vs golden |
| Behavioural SAR ADC + controller | done, simulated (exhaustive 1024 codes) |
| MAC unit, memories, FIFO | done, simulated (random + directed) |
| 16-tap FIR | done, 3600/3600 outputs match golden |
| NN 8-16-2 inference | done, 64 vectors bit-exact |
| Shared-MAC scheduler | done, simulated (workflow only in PPT) |
| Quality estimator, result manager, config regs | M4 committed; check 04_inventory.txt |
| biomed_soc_top + tb_soc | NOT done |
| OpenLane | dry run on scheduler+MAC only; full SoC GDS NOT done |
| Analog transistor-level ADC | not started (next semester) |
