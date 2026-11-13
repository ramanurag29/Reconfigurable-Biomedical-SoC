#!/usr/bin/env bash
# Regression: regenerate ECG golden data, compile + run every testbench, print a summary.
# Run from anywhere:  bash 11_Scripts/regress.sh      (activate .venv first)
cd "$(dirname "$0")/.." || exit 1
mkdir -p 06_Simulation 09_Results
python 11_Scripts/ecg_pipeline.py > 09_Results/milestone1/pipeline_log.txt 2>&1 || { echo "pipeline failed"; exit 1; }
R=04_RTL; T=05_Testbench; fail=0
declare -a NAMES=(input_formatter_ecg sar_controller adc adc_ecg mac)
declare -A SRC=(
 [input_formatter_ecg]="$R/interfaces/input_formatter.v $T/tb_input_formatter_ecg.v"
 [sar_controller]="$R/adc/sar_controller.v $T/tb_sar_controller.v"
 [adc]="$R/adc/sar_controller.v $R/adc/sample_hold_behav.v $R/adc/comparator_behav.v $R/adc/cdac_behav.v $R/adc/adc_frontend_behav.v $T/tb_adc.v"
 [adc_ecg]="$R/adc/sar_controller.v $R/adc/sample_hold_behav.v $R/adc/comparator_behav.v $R/adc/cdac_behav.v $R/adc/adc_frontend_behav.v $R/interfaces/input_formatter.v $T/tb_adc_ecg.v"
 [mac]="$R/mac/mac_unit.v $T/tb_mac.v")
: > 09_Results/regression_summary.txt
for n in "${NAMES[@]}"; do
  if iverilog -g2012 -o 06_Simulation/tb_$n.vvp ${SRC[$n]} 2> 06_Simulation/tb_$n.compile.log; then
    vvp 06_Simulation/tb_$n.vvp > 09_Results/sim_$n.log 2>&1
    if grep -q "ALL TESTS PASSED" 09_Results/sim_$n.log; then r=PASS; else r=FAIL; fail=1; fi
  else r="FAIL(compile)"; fail=1; fi
  printf '%-22s %s\n' "tb_$n" "$r" | tee -a 09_Results/regression_summary.txt
done
[ $fail = 0 ] && echo "REGRESSION: ALL PASS" || echo "REGRESSION: FAILURES (see 09_Results/sim_*.log)"
exit $fail
