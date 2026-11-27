# OpenLane notes (measured on this machine, 2026-11-13)
- OpenLane **1.0.2** (git ff5509f6, 15 Sep 2025) in `~/OpenLane`; flow = `./flow.tcl` inside `make mount` container. Not OpenLane 2.
- Docker 29.1.3 working; tool images (yosys, magic, openroad, klayout, netgen, verilator ...) already pulled.
- `PDK_ROOT` defaults to `$(HOME)/.ciel` per the OpenLane Makefile; env var not exported in the host shell.
- Host has no yosys/magic/ngspice/xschem/verilator (not needed for the digital flow: they run in the container).
- RAM 15 GiB, disk 929 GiB free.
- Pre-flight check done off-machine: yosys 0.33 `synth -flatten` of mac_unit+task_scheduler: no warnings/latches
  (generic-gate count only, NOT Sky130 area). No OpenLane result exists yet.
- Existing design `~/OpenLane/designs/biomed_chip` is left untouched; dry run uses `biomed_dry`.
