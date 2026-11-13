#!/usr/bin/env bash
# Milestone 1: ECG -> 10-bit codes -> Verilog self-checking testbench. Run from repo root.
set -e
cd "$(dirname "$0")/.."
python 11_Scripts/ecg_pipeline.py --record 100 --start 10 --duration 10 | tail -3
iverilog -g2012 -Wall -o 06_Simulation/tb_m1.vvp \
    04_RTL/interfaces/input_formatter.v 05_Testbench/tb_input_formatter_ecg.v
vvp 06_Simulation/tb_m1.vvp | tee 09_Results/milestone1/sim_log.txt
grep -q "ALL TESTS PASSED" 09_Results/milestone1/sim_log.txt && echo "MILESTONE 1: PASS" || { echo "MILESTONE 1: FAIL"; exit 1; }
echo "Waveform: gtkwave 06_Simulation/tb_input_formatter_ecg.vcd"
