#!/usr/bin/env bash
# Regression: regenerate golden data, compile + run every testbench, write summary and the
# verification report (10_Documentation/03_verification_report.md).
# Run from anywhere:  bash 11_Scripts/regress.sh      (activate .venv first)
cd "$(dirname "$0")/.." || exit 1
mkdir -p 06_Simulation 06_Simulation/mem 09_Results/milestone1 09_Results/fir 09_Results/nn 03_AI_Model 10_Documentation
python 11_Scripts/ecg_pipeline.py     > 09_Results/milestone1/pipeline_log.txt 2>&1 || { echo "ecg_pipeline failed"; exit 1; }
python 11_Scripts/fir_golden_model.py > 09_Results/fir/golden_log.txt 2>&1         || { echo "fir_golden_model failed"; exit 1; }
mkdir -p 09_Results/quality
python 11_Scripts/quality_golden.py   > 09_Results/quality/golden_log.txt 2>&1     || { echo "quality_golden failed"; exit 1; }
# NN model: trained once (needs MIT-BIH via wfdb), then reused. Retrain with  RETRAIN=1 bash 11_Scripts/regress.sh
if [ -n "$RETRAIN" ] || [ ! -f 06_Simulation/mem/nn_params.vh ]; then
  python 11_Scripts/train_nn.py $NN_ARGS > 09_Results/nn/train_log.txt 2>&1 || { echo "train_nn failed (see 09_Results/nn/train_log.txt)"; exit 1; }
fi
R=04_RTL; T=05_Testbench; fail=0
ADC="$R/adc/sar_controller.v $R/adc/sample_hold_behav.v $R/adc/comparator_behav.v $R/adc/cdac_behav.v $R/adc/adc_frontend_behav.v"
CORE="$R/controller/reset_sync.v $R/controller/quality_est.v $R/controller/result_manager.v $R/interfaces/host_regs.v \
 $R/interfaces/input_formatter.v $R/adc/sar_controller.v $R/mac/mac_unit.v $R/memory/regfile_sync.v $R/memory/sample_buffer.v \
 $R/memory/output_fifo.v $R/fir/fir_engine.v $R/neural_network/nn_engine.v $R/scheduler/task_scheduler.v $R/top/biomed_soc_top.v"
declare -a NAMES=(input_formatter_ecg sar_controller adc adc_ecg mac memory output fir nn scheduler scheduler_p1 config soc)
declare -A SRC=(
 [input_formatter_ecg]="$R/interfaces/input_formatter.v $T/tb_input_formatter_ecg.v"
 [sar_controller]="$R/adc/sar_controller.v $T/tb_sar_controller.v"
 [adc]="$ADC $T/tb_adc.v"
 [adc_ecg]="$ADC $R/interfaces/input_formatter.v $T/tb_adc_ecg.v"
 [mac]="$R/mac/mac_unit.v $T/tb_mac.v"
 [memory]="$R/memory/regfile_sync.v $R/memory/sample_buffer.v $T/tb_memory.v"
 [output]="$R/memory/output_fifo.v $T/tb_output.v"
 [fir]="$R/mac/mac_unit.v $R/memory/regfile_sync.v $R/fir/fir_engine.v $R/fir/fir_block.v $T/tb_fir.v"
 [nn]="$R/mac/mac_unit.v $R/memory/regfile_sync.v $R/neural_network/nn_engine.v $R/neural_network/nn_block.v $T/tb_nn.v"
  [scheduler]="$R/mac/mac_unit.v $R/fir/fir_engine.v $R/neural_network/nn_engine.v $R/scheduler/task_scheduler.v $T/tb_scheduler.v"
  [scheduler_p1]="$R/mac/mac_unit.v $R/fir/fir_engine.v $R/neural_network/nn_engine.v $R/scheduler/task_scheduler.v $T/tb_scheduler.v"
  [config]="$CORE $T/tb_config.v"
  [soc]="$CORE $R/adc/sample_hold_behav.v $R/adc/comparator_behav.v $R/adc/cdac_behav.v $T/tb_soc.v")
declare -A FLAGS=([scheduler_p1]="-Ptb_scheduler.PIPE=1")
: > 09_Results/regression_summary.txt
for n in "${NAMES[@]}"; do
  if iverilog -g2012 ${FLAGS[$n]} -o 06_Simulation/tb_$n.vvp ${SRC[$n]} 2> 06_Simulation/tb_$n.compile.log; then
    vvp 06_Simulation/tb_$n.vvp > 09_Results/sim_$n.log 2>&1
    if grep -q "ALL TESTS PASSED" 09_Results/sim_$n.log; then r=PASS; else r=FAIL; fail=1; fi
  else r="FAIL(compile)"; fail=1; fi
  printf '%-22s %s\n' "tb_$n" "$r" | tee -a 09_Results/regression_summary.txt
done
# lint of the synthesizable top (verilator, if installed): any warning = failure
if command -v verilator >/dev/null; then
  if verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY --top-module biomed_soc_top $CORE \
       > 09_Results/lint.txt 2>&1; then r=PASS; else r=FAIL; fail=1; fi
  printf '%-22s %s\n' "lint(verilator)" "$r" | tee -a 09_Results/regression_summary.txt
fi
python 11_Scripts/make_verification_report.py
[ $fail = 0 ] && echo "REGRESSION: ALL PASS" || echo "REGRESSION: FAILURES (see 09_Results/sim_*.log)"
exit $fail
