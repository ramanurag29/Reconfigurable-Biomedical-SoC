# task_scheduler specification (Phase 6, milestone M5)

Status: **simulated** (Icarus Verilog, `tb_scheduler`, MAC PIPE=0 and PIPE=1). Not synthesized, no timing/area numbers.

## Scope
Arbitrates ONE shared `mac_unit` between client 0 = `fir_engine` (T2) and client 1 = `nn_engine` (T4).
T1 (acquisition), T3 (features) and T5 (reporting) use no MAC and are added at SoC integration (Phase 8).

## Safe preemption rule
A switch needs all of: owner `at_boundary`, owner has no MAC op in flight (`settled`), and grant is withdrawn
that cycle (`preempt_req`) so the owner cannot issue an op while the accumulator is being saved.
`at_boundary` = FIR: S_CLR/S_MAC, NN: S_LOAD/S_MAC (never DRAIN, so a finished result is never split).
Context = accumulator (32 b) + sticky overflow, per client; loop counters / hidden buffer stay inside the engine,
which simply holds state while grant is low. Restore: RS1 drives the MAC load port, RS2 absorbs the load's
`acc_valid` for PIPE+1 cycles (not forwarded to engines). Restore cost = 2 clocks (PIPE=0) / 3 (PIPE=1).

## Policies (`policy[1:0]`)
| value | policy | idle pick | preempt when |
|---|---|---|---|
| 0 | fixed priority (default) | higher `prio`, tie -> client 0 | other `prio` strictly higher |
| 1 | round-robin | alternate | owner used >= `quantum` MAC ops and other waits |
| 2 | mode-based | `mode_sel` client | owner != `mode_sel` and `mode_sel` client waits |
`preempt_en=0` makes every policy run-to-completion.

## Metrics (cleared by `stat_clr`)
total cycles, MAC ops (client ops only), preemptions, restore overhead cycles, per client: tasks, wait sum/max,
exec sum, latency max, deadline misses (`deadline_c` cycles, 0 = off). MAC utilisation = `m_mac_ops / m_total_cycles`.
Task = interval where the client's `req` is high; latency = cycles req high; wait = req high and no grant.

## Interface change to existing blocks
`fir_engine` and `nn_engine` gained one output `at_boundary` (additive; existing testbenches unchanged).
