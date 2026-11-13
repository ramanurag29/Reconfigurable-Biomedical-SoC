#!/usr/bin/env bash
# Project summary from real files only. Run from anywhere: bash 11_Scripts/project_summary.sh
cd "$(dirname "$0")/.."  exit 1
{
echo "=== PROJECT SUMMARY  $(date '+%Y-%m-%d %H:%M') ==="
echo; echo "--- Git (last 12 commits, uncommitted files)"
git log --oneline | head -12; echo "uncommitted: $(git status --short | wc -l) file(s)"
echo; echo "--- RTL modules (lines)"
wc -l 04_RTL/*/*.v 2>/dev/null | sed 's#04_RTL/##'
echo; echo "--- Testbenches"; ls 05_Testbench/ 2>/dev/null | tr '\n' ' '; echo
echo; echo "--- Folders with content (file count)"
for d in 0*_* 1*_*; do printf '%-18s %s\n' "$d" "$(find "$d" -type f 2>/dev/null | wc -l)"; done
echo; echo "--- Regression (last run)"
cat 09_Results/regression_summary.txt 2>/dev/null  echo "none - run: bash 11_Scripts/regress.sh"
grep -h "Overall" 10_Documentation/03_verification_report.md 2>/dev/null
echo; echo "--- NN metrics (09_Results/nn/nn_metrics.json)"
[ -f 09_Results/nn/nn_metrics.json ] && python3 -m json.tool 09_Results/nn/nn_metrics.json | head -40  echo "not found"
echo; echo "--- FIR design report"
[ -f 09_Results/fir/fir_report.json ] && python3 -m json.tool 09_Results/fir/fir_report.json | head -25  echo "not found"
echo; echo "--- OpenLane results saved"
for f in 09_Results/openlane/*/metrics.csv; do
  [ -f "$f" ]  { echo "none"; break; }
  echo "[$f]"
  python3 - "$f" <<'PY'
import csv,sys
r=list(csv.DictReader(open(sys.argv[1])))[0]
for k in ("DESIGN_NAME","synth_cell_count","CoreArea_um^2","critical_path_ns","wns","tns","Magic_violations","tritonRoute_violations","lvs_total_errors","net_antenna_violations","pin_antenna_violations","CLOCK_PERIOD"):
    print(f"  {k:26s} {r.get(k,'n/a')}")
PY
done
echo; echo "--- Master-prompt status check (file present?)"
chk(){ [ -e "$2" ] && echo "[x] $1"  echo "[ ] $1"; }
chk "MATLAB .m scripts" 02_MATLAB/load_ecg.m
chk "ECG pipeline (Python)" 11_Scripts/ecg_pipeline.py
chk "SAR controller" 04_RTL/adc/sar_controller.v
chk "MAC" 04_RTL/mac/mac_unit.v
chk "FIR engine" 04_RTL/fir/fir_engine.v
chk "NN engine" 04_RTL/neural_network/nn_engine.v
chk "Scheduler" 04_RTL/scheduler/task_scheduler.v
chk "Quality estimator" 04_RTL/controller/quality_est.v
chk "Config regs / host if" 04_RTL/interfaces/config_regs.v
chk "SoC top" 04_RTL/top/biomed_soc_top.v
chk "tb_soc" 05_Testbench/tb_soc.v
chk "OpenLane dry run saved" 09_Results/openlane/dry2/metrics.csv
} | tee 09_Results/project_summary.txt
