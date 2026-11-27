#!/usr/bin/env bash
# Copies a design from 07_OpenLane/<cfg> into your OpenLane 1.0.2 tree. Never touches other designs.
#   bash 11_Scripts/ol_prep.sh                      -> full SoC: ~/OpenLane/designs/biomed_soc  (default)
#   bash 11_Scripts/ol_prep.sh biomed_dry task_scheduler_dry   -> the earlier scheduler dry run
# Also checks that every key in config.json is a variable known to the installed OpenLane.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OL="${OPENLANE_ROOT:-$HOME/OpenLane}"
NAME="${1:-biomed_soc}"
CFG="${2:-biomed_soc_top}"
[ "$NAME" = "biomed_chip" ] && { echo "refusing to overwrite existing design biomed_chip"; exit 1; }
D="$OL/designs/$NAME"
mkdir -p "$D/src"
rm -f "$D"/src/*.v
R="$REPO/04_RTL"
if [ "$CFG" = "task_scheduler_dry" ]; then
  cp "$R/mac/mac_unit.v" "$R/scheduler/task_scheduler.v" "$D/src/"
else
  # synthesizable RTL only: no *_behav.v (analog models), no fir_block/nn_block (unit-test wrappers)
  cp "$R/controller/reset_sync.v" "$R/controller/quality_est.v" "$R/controller/result_manager.v" \
     "$R/interfaces/host_regs.v" "$R/interfaces/input_formatter.v" "$R/adc/sar_controller.v" \
     "$R/mac/mac_unit.v" "$R/memory/regfile_sync.v" "$R/memory/sample_buffer.v" "$R/memory/output_fifo.v" \
     "$R/fir/fir_engine.v" "$R/neural_network/nn_engine.v" "$R/scheduler/task_scheduler.v" \
     "$R/top/biomed_soc_top.v" "$D/src/"
fi
cp "$REPO/07_OpenLane/$CFG/config.json" "$D/config.json"
[ -f "$REPO/07_OpenLane/$CFG/pin_order.cfg" ] && cp "$REPO/07_OpenLane/$CFG/pin_order.cfg" "$D/"
echo "prepared $D:"; ls "$D" "$D/src"
echo "--- checking config keys against $OL/configuration and $OL/scripts"
for k in $(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))))" "$D/config.json"); do
  if grep -rqw "$k" "$OL/configuration" "$OL/scripts" 2>/dev/null; then echo "  ok      $k"; else echo "  UNKNOWN $k  <- remove or rename before running"; fi
done
echo "next:  cd $OL && make mount     then inside the container:  ./flow.tcl -design $NAME -tag full1 -overwrite"
