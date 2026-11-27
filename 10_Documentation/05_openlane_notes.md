# OpenLane notes (measured on this machine, 2026-11-13)
- OpenLane **1.0.2** (git ff5509f6, 15 Sep 2025) in `~/OpenLane`; flow = `./flow.tcl` inside `make mount` container. Not OpenLane 2.
- Docker 29.1.3 working; tool images (yosys, magic, openroad, klayout, netgen, verilator ...) already pulled.
- `PDK_ROOT` defaults to `$(HOME)/.ciel` per the OpenLane Makefile; env var not exported in the host shell.
- Host has no yosys/magic/ngspice/xschem/verilator (not needed for the digital flow: they run in the container).
- RAM 15 GiB, disk 929 GiB free.
- Pre-flight check done off-machine: yosys 0.33 `synth -flatten` of mac_unit+task_scheduler: no warnings/latches
  (generic-gate count only, NOT Sky130 area). No OpenLane result exists yet.
- Existing design `~/OpenLane/designs/biomed_chip` is left untouched; dry run uses `biomed_dry`.

## Full SoC (biomed_soc_top), prepared 2026-11-27
- Design files: `07_OpenLane/biomed_soc_top/config.json` + `pin_order.cfg` (N: clk/reset/status/result, S: analog SAR
  interface + bypass, E: host read data, W: host write bus). `bash 11_Scripts/ol_prep.sh` copies the 14 synthesizable
  RTL files into `~/OpenLane/designs/biomed_soc/src` and checks every config key exists in the installed OpenLane.
- Pre-flight estimate only (NOT an OpenLane result): yosys 0.33 `synth -flatten` + `abc` mapped to
  sky130_fd_sc_hd tt_025C_1v80 gives ~20.3k cells, ~4.77k flip-flops (3,200 of them the un-reset NN/FIR memories),
  ~0.21 mm² cell area before buffering/CTS/fill. With FP_CORE_UTIL 35 this implies a die of roughly 0.8 x 0.8 mm.
  Real area/timing/power come only from the OpenLane run (`bash 11_Scripts/ol_collect.sh`).
- Clock target 20 ns (50 MHz) for the first run; tighten only after sign-off is clean.
