#!/usr/bin/env bash
# Copies the scheduler dry-run design into your OpenLane 1.0.2 tree. Never touches other designs.
#   bash 11_Scripts/ol_prep.sh            -> ~/OpenLane/designs/biomed_dry
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OL="${OPENLANE_ROOT:-$HOME/OpenLane}"
NAME="${1:-biomed_dry}"
[ "$NAME" = "biomed_chip" ] && { echo "refusing to overwrite existing design biomed_chip"; exit 1; }
D="$OL/designs/$NAME"
mkdir -p "$D/src"
cp "$REPO/04_RTL/mac/mac_unit.v" "$REPO/04_RTL/scheduler/task_scheduler.v" "$D/src/"
cp "$REPO/07_OpenLane/task_scheduler_dry/config.json" "$D/config.json"
echo "prepared $D"; ls -R "$D"
echo "next:  cd $OL && make mount     then inside the container:  ./flow.tcl -design $NAME -tag dry1"
