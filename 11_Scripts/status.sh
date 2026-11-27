#!/bin/bash
cd "$(dirname "$0")/.."
echo "== RTL modules =="; find 04_RTL -name '*.v' | sort
echo "== Testbenches =="; ls 05_Testbench 2>/dev/null
echo "== Missing required =="
for f in biomed_soc_top tb_soc tb_adc tb_sar_controller tb_mac tb_memory tb_fir tb_nn tb_scheduler tb_config tb_output; do
  find . -name "$f.v" -not -path './.venv/*' | grep -q . && echo "  ok   $f"  echo "  MISS $f"
done
echo "== OpenLane =="; ls 07_OpenLane 2>/dev/null  echo "  empty"
echo "== MATLAB scripts =="; ls 02_MATLAB 2>/dev/null | wc -l
echo "== Git =="; git status -s | head; git log --oneline | head -5
