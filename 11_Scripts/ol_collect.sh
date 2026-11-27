#!/usr/bin/env bash
# Copies the reports of an OpenLane 1.x run into the repo and prints the sign-off checklist.
#   bash 11_Scripts/ol_collect.sh [design=biomed_soc] [tag=full1]
# Nothing is typed in by hand: every number comes from the run directory.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OL="${OPENLANE_ROOT:-$HOME/OpenLane}"
NAME="${1:-biomed_soc}"; TAG="${2:-full1}"
RUN="$OL/designs/$NAME/runs/$TAG"
[ -d "$RUN" ] || { echo "no run at $RUN"; exit 1; }
OUT="$REPO/09_Results/openlane/$NAME-$TAG"
mkdir -p "$OUT"
cp -r "$RUN/reports" "$OUT/" 2>/dev/null
cp "$RUN"/reports/metrics.csv "$OUT/" 2>/dev/null
cp "$RUN"/*.log "$OUT/" 2>/dev/null
cp "$RUN/config.tcl" "$OUT/" 2>/dev/null
mkdir -p "$OUT/final"
for d in gds lef def verilog/gl sdc spef; do
  ls "$RUN/results/final/$d" >/dev/null 2>&1 && echo "final/$d: $(ls "$RUN/results/final/$d" | tr '\n' ' ')"
done
# keep the small final artefacts in git; the GDS is copied but ignored by .gitignore if > 50 MB
cp "$RUN"/results/final/gds/*.gds "$OUT/final/" 2>/dev/null
cp "$RUN"/results/final/lef/*.lef "$OUT/final/" 2>/dev/null
cp "$RUN"/results/final/verilog/gl/*.v "$OUT/final/" 2>/dev/null
echo "=== metrics.csv (all columns) ==="
python3 - "$OUT/metrics.csv" <<'PY'
import csv, sys
try:
    rows = list(csv.reader(open(sys.argv[1])))
except FileNotFoundError:
    print("metrics.csv missing (flow did not finish?)"); sys.exit()
for k, v in zip(rows[0], rows[-1]):
    print(f"{k:40s} {v}")
PY
echo "=== sign-off checklist (look for these in the list above / logs) ==="
echo "flow_status = flow completed | Magic_violations = 0 | klayout_violations 0 (or -1 = not run)"
echo "lvs_total_errors = 0 | pin_antenna_violations = 0 and net_antenna_violations = 0"
echo "wns = 0 / tns = 0 at every corner (see reports/signoff/*sta*)"
grep -rhiE "total.*violation|antenna|lvs.*(match|error)" "$RUN/reports/signoff" 2>/dev/null | head -20
echo "copied to $OUT"
