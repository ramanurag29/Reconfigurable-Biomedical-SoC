# Reconfigurable Biomedical SoC — System Architecture (v0.1)

**Status key used throughout:** `[IMPL+SIM]` implemented and simulated · `[SPEC]` specified only, not yet written · `[OPEN]` decision pending.
`[IMPL+SIM]` so far (all pass `11_Scripts/regress.sh`; 9/9 injected bugs caught): `input_formatter`, `sar_controller` (exhaustive 1024 codes), behavioural S&H / comparator / CDAC / `adc_frontend_behav` (incl. bypass), `mac_unit` (5 configs, randomized + directed), and the ECG→codes pipeline. Everything else below is a specification. No synthesis or timing results exist yet.

---

## 1. Block diagram and signal flow

```
 ┌────────────── OFFLINE (MATLAB / Python) ─────────────┐
 │ MIT-BIH → condition → scale 0.5–1.5 V → ecg_vin.pwl   │──► ngspice (next semester)
 │                     → 10-bit codes → ecg_adc_10b.hex  │──► Verilog testbench
 │ golden FIR / NN / features / quality outputs          │──► compare_hardware_results
 └───────────────────────────────────────────────────────┘

 ══════════════ ANALOG / DIGITAL BOUNDARY (behavioural now, custom analog later) ══════════════
  vin ─► S&H ─► Comparator ◄── CDAC ◄── SAR code reg
                   │ cmp_out                  ▲ dac_code[9:0]
 ═════════════════ │ ═════════════════════════│═══════════════════════════════════════════════
                   ▼                          │
  ┌─────────────────────────── biomed_soc_top (single clock domain) ───────────────────────┐
  │  sar_controller ──► adc_out[9:0], adc_done                                               │
  │  adc_bypass_in[9:0] ─┐ (direct digital injection, config B)                              │
  │                      ▼                                                                   │
  │             input_formatter ──► x_signed[10:0] ──► sample_buffer                         │
  │                                                      │                                   │
  │   host/config bus ─► config_regs ─► coef_mem, weight_mem, bias_mem, feature_regs         │
  │                                                      ▼                                   │
  │  task_scheduler ◄── requests T1..T5 ──► [ fir_engine | nn_engine | feature_if ]          │
  │        │ grant / ctx save-restore                        │ operands                      │
  │        └──────────────────────────────►  shared mac_unit (11×12 signed, 32-b acc)        │
  │                                                      ▼                                   │
  │              result_manager (round, saturate, quality flag, confidence) ─► output_fifo   │
  └──────────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. Module hierarchy `[SPEC]` (one directory each under `04_RTL/`)

| Module | Dir | Purpose |
|---|---|---|
| `biomed_soc_top` | top | Integration, config A (ADC) / B (bypass) |
| `sar_adc_behav` (S&H, comparator, CDAC models) | adc | Behavioural only; **not** a claim about analog silicon |
| `sar_controller` | adc | 10-cycle successive-approximation FSM (synthesizable) |
| `input_formatter` | interfaces | **`[IMPL+SIM]`** code → signed sample |
| `host_if` / `config_regs` | interfaces | Memory-mapped bus, register file |
| `sample_buffer`, `coef_mem`, `weight_mem`, `bias_mem`, `feature_regs` | memory | Flop-based storage (no SRAM macro assumed) |
| `mac_unit` | mac | Signed MAC, clear/load/overflow |
| `fir_engine` | fir | 8/16-tap FIR sequencer, round + saturate |
| `nn_engine` | neural_network | 8→16→2 inference sequencer, ReLU, argmax |
| `task_scheduler` | scheduler | Arbitration, context save/restore, counters |
| `quality_est`, `result_manager`, `output_fifo` | controller | Quality score, confidence gating, results |

## 3. Clock and reset strategy `[SPEC]`
- **One clock domain** (`clk`). The sample rate is a **clock-enable** (`sample_tick`) derived from a programmable divider, *not* a divided clock. Real 360 Hz operation leaves the MAC mostly idle; scheduler experiments use accelerated sample rates (documented in results).
- **Reset:** `rst_n` asynchronous assert, synchronous release via a 2-flop synchroniser in a `reset_ctrl` block; a soft reset bit in `CTRL` clears datapath state but keeps coefficients/weights.
- Clock management interface: a single `clk_en` input is reserved for a future clock gate; no gating is implemented in phase 1.

## 4. Number formats and bit-width budget (computed, not assumed)

| Quantity | Format | Range |
|---|---|---|
| ADC code `D` | unsigned 10 b | 0 … 1023 |
| Centred sample `x` | signed 11 b | −512 … +511 (`x = D − 512`) |
| FIR coefficient `h` | signed 12 b, **Q1.11** (value = h/2048) | −2048 … +2047 |
| NN feature | signed 8 b | −128 … +127 |
| NN weight | signed 8 b | −128 … +127 |
| NN bias | signed 24 b (accumulator domain) | |
| MAC accumulator | signed 32 b | |

**FIR:** worst product = (−512)(−2048) = 2²⁰ → 22 b signed. Worst 16-tap sum → **26 b**, 8-tap → 25 b. The 32-b accumulator therefore has **6 b headroom** at 16 taps; overflow is detected but cannot occur for valid inputs.
**NN:** int8×int8 product 16 b; layer 1 (8 terms) → 19 b; layer 2 (16 terms, post-ReLU activations 0…127) → 19 b. 13 b headroom on layer 1.
**MAC operand ports are 11 b × 12 b**; NN operands are sign-extended into them.

**Output scaling (FIR):** `y = sat11( (acc + 2^(S−1)) >>> S )`, `S = 11` default (coefficient fractional bits), round-half-up, saturate to −512…+511. `S` is a register. **NN:** after layer 1, `a = sat_relu8((acc1 + bias) >>> S1)` with `S1` chosen at quantization time. Overflow/saturation events increment a sticky counter.

**Quantisation convention D1 = B (decided):** `D = clamp(floor(Vin / LSB), 0, 1023)`, `LSB = Vref/2^N = 1.953 mV`; reconstruction at bin centre, error ≤ LSB/2; Vin = 1.0 V → D = 512 → x = 0 exactly. `mac_unit` requires `ACC_W ≥ A_W+B_W` (checked at elaboration).

## 5. Memory map `[SPEC]` (12-bit word address, 32-bit data)

| Address | Name | Notes |
|---|---|---|
| 0x000 | CTRL | start, soft_reset, run/stop |
| 0x004 | STATUS (RO) | busy, done, fifo_empty, overflow_sticky |
| 0x008 | MODE | 0=FIR, 1=NN, 2=FIR+NN pipeline; adc_bypass |
| 0x00C | SCHED_POLICY | 0=fixed-priority (default), 1=round-robin, 2=mode-based |
| 0x010 | FIR_CFG | taps (8/16), shift S |
| 0x014 | ADC_CFG | sample divider, bypass |
| 0x018 | Q_THRESH | quality thresholds (good/moderate) |
| 0x01C | CONF_THRESH | confidence threshold |
| 0x020 | IRQ_EN / 0x024 IRQ_STATUS | data-ready, deadline-miss |
| 0x030–0x03C | LAT_*, WAIT_*, UTIL_* (RO) | scheduler counters |
| 0x100–0x13C | COEF[0..15] | 12 b used |
| 0x200–0x29C | WEIGHT[0..159] | 8 b used (L1: 128, L2: 32) |
| 0x300–0x344 | BIAS[0..17] | 24 b used |
| 0x400–0x41C | FEATURE[0..7] | 8 b used |
| 0x500 | RESULT_POP (RO) | pops output FIFO |

## 6. Storage budget (flop-based) 
Coefficients 192 b · weights 1,280 b · biases 432 b · sample buffer 64×11 = 704 b (parameter `SAMPLE_DEPTH`). About 2.6 kb in total, small enough for register storage. This is arithmetic, not a synthesis result.

## 7. Scheduler task model `[SPEC]`
T1 acquisition, T2 FIR, T3 feature, T4 NN, T5 reporting. Default fixed priority T4 > T2 > T3 > T1 > T5 is `[OPEN]` and will be revisited with measurements. **Preemption only at MAC-operation boundaries** (after a completed multiply-accumulate step); saved context = accumulator, address pointers, loop counters, state ID.

## 8. Fidelity ladder (what counts as what)
Behavioural ADC (simulated) → digital RTL (simulated, then synthesized/placed by OpenLane) → analog transistor-level (next semester) → mixed-signal layout (not started). No behavioural model will be described as a physical circuit.

## 9. Schedule (≈15 weeks from 9 Nov 2026) and risks

| Weeks | Phase |
|---|---|
| 1–2 | 0–1: environment, M1 done, golden models (FIR/NN/feature), MATLAB `.m` port if MATLAB exists |
| 3 | 2: behavioural SAR ADC + sar_controller |
| 4–5 | 3: MAC + memories (**early OpenLane dry-run of MAC**) |
| 6 | 4: FIR engine |
| 7–8 | 5: NN training (patient-independent split) + RTL |
| 9–10 | 6: scheduler + contention tests |
| 11 | 7: quality assessment |
| 12 | 8: integration |
| 13–14 | 9–10: full verification, OpenLane |
| 15 | 11: experiments and report (buffer) |

Risks: (1) NN data — class imbalance and leakage; mitigation: split by record. (2) Python 3.14 may lack PyTorch wheels; mitigation: NumPy/scikit-learn or a separate 3.12 env. (3) Flop-based memories may dominate area and congestion; mitigation: early OpenLane dry-run. (4) Scheduler is the largest scope-creep risk; mitigation: fixed-priority first, other policies later. (5) ECG uses only ~27 % of the ADC span (record 100), so the 8-bit vs 10-bit experiment needs per-record scaling. (6) No MATLAB confirmed: `.m` files cannot be validated until confirmed.

## 10. Open decisions
- **D1 (convention): RESOLVED → B** (`floor(Vin/Vref·1024)`), deviating from the prompt's `round(…·1023)` because that is what a binary-search SAR produces; Python reference updated and re-verified.
- **D2:** FIR output 11 b saturated (default, assumed) vs 12 b — revisit when the FIR golden model shows saturation counts.
- **D3:** default task priorities (§7).
