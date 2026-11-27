# biomed_soc_top: pins and register map

Source of truth: `04_RTL/interfaces/host_regs.v` and `04_RTL/top/biomed_soc_top.v`. Every reset value and field
here is checked by `05_Testbench/tb_config.v`.

## Top-level pins

| Pin | Dir | Width | Meaning |
|---|---|---|---|
| clk | in | 1 | single clock domain |
| rst_n | in | 1 | active-low reset, async assert / sync release (`reset_sync`) |
| host_we / host_re | in | 1 | one-cycle write / read strobe |
| host_addr | in | 12 | **word** address |
| host_wdata / host_rdata | in / out | 32 | read data valid one cycle after `host_re`, with `host_rvalid` |
| adc_cmp_in | in | 1 | comparator decision from the analog SAR macro (config A); assumed synchronous to clk |
| adc_sample_en | out | 1 | S&H track phase (config A) |
| adc_dac_code | out | 10 | CDAC trial code (config A) |
| adc_bypass_valid / adc_bypass_data | in | 1 / 10 | direct digital sample injection (config B) |
| irq | out | 1 | OR of enabled IRQ_STATUS bits |
| busy | out | 1 | FIR or NN or SAR busy |
| done | out | 1 | = IRQ_STATUS[1] (NN decision ready, sticky, W1C) |
| abnormal / uncertain | out | 1 | latest quality-aware NN decision |
| result_valid / result_data | out | 1 / 16 | head of the output FIFO (popped through RESULT_POP) |

## Control / status registers (0x000-0x01F)

| Addr | Name | Access | Fields (reset) |
|---|---|---|---|
| 0x000 | CTRL | W / R | [0] soft_reset (pulse) · [1] nn_start (pulse) · [2] stat_clr (pulse) · [3] flag_clr (pulse) · [4] run (level, 0). Read returns run only. **Every CTRL write also rewrites run.** |
| 0x001 | STATUS | R | [0] fir_busy [1] nn_busy [2] sar_busy [3] fifo_empty [4] fifo_full [5] fifo_overflow [6] fifo_underflow [7] fir_overrun [8] result_lost [9] abnormal [10] uncertain [12:11] last quality class (3 = not assessed) [20:16] fifo_count [22:21] scheduler state [23] MAC owner (0 FIR, 1 NN) |
| 0x002 | MODE | RW | [1:0] mode 0 FIR / 1 NN / 2 FIR+NN (2) · [2] adc_bypass (1) · [3] FIR records to FIFO (1) · [4] quality records to FIFO (1) |
| 0x003 | SCHED | RW | [1:0] policy 0 fixed / 1 round-robin / 2 mode-based (0) · [2] mode_sel (1 = NN) · [3] preempt_en (1) · [6:4] prio FIR (3) · [10:8] prio NN (4) · [23:16] RR quantum in MAC ops (8) |
| 0x004 | FIR_CFG | RW | [4:0] taps 1..16 (16) · [12:8] output shift S (11) |
| 0x005 | ADC_CFG | RW | [15:0] clocks between conversions in config A, 0 = stopped (100) |
| 0x006 | Q_CFG | RW | [3:0] window log2, clamped 4..10 (9) · [15:8] clip_max (4) · [26:16] amp_min (40) |
| 0x007 | Q_CFG2 | RW | [7:0] noise_k, 1/16 units (1) · [17:8] base_max (64) |
| 0x008 | NN_CFG | RW | [4:0] hidden shift S1 (6) · [31:16] confidence threshold (1220) |
| 0x009 | DEADLINE | RW | [15:0] FIR task deadline · [31:16] NN task deadline, cycles, 0 = off (0) |
| 0x00A | IRQ_EN | RW | [0] data ready · [1] NN done · [2] deadline miss · [3] POOR quality window (0) |
| 0x00B | IRQ_STATUS | R / W1C | [0] FIFO not empty (level) · [1] NN done · [2] deadline miss · [3] POOR window (sticky; a new event in the clear cycle wins) |
| 0x00C | NN_RESULT | R | [0] class (1 = abnormal score wins) [1] low confidence [2] overflow [3] uncertain [4] abnormal (final) [31:16] margin |
| 0x00D / 0x00E | NN_SCORE0 / 1 | R | signed 32-bit output scores |
| 0x00F | Q_RESULT | R | [1:0] class [7:4] flags {base, noise, flat, clip} [15:8] score [26:16] p2p |
| 0x010 | LATENCY | R | [7:0] last FIR busy cycles · [31:16] last NN latency (start to valid, cycles) |
| 0x011 | M_CYCLES | R | cycles since stat_clr |
| 0x012 | M_MAC_OPS | R | MAC operations issued (restore loads excluded) |
| 0x013 | M_PREEMPTS | R | [15:0] preemptions |
| 0x014 | M_OVERHEAD | R | cycles lost in context restore |
| 0x015 | M_TASKS | R | [15:0] FIR tasks · [31:16] NN tasks |
| 0x016 / 0x017 | M_WAIT_SUM0 / 1 | R | total wait cycles FIR / NN |
| 0x018 | M_WAIT_MAX | R | [15:0] FIR · [31:16] NN |
| 0x019 | M_LAT_MAX | R | [15:0] FIR · [31:16] NN |
| 0x01A / 0x01B | M_EXEC_SUM0 / 1 | R | total granted cycles FIR / NN |
| 0x01C | M_MISSES | R | [15:0] FIR · [31:16] NN deadline misses |
| 0x01F | CHIP_ID | R | 0xB10C0001 |

## Memories and data windows

| Addr | Name | Access | Content |
|---|---|---|---|
| 0x100-0x10F | COEF[16] | W | FIR coefficients, 12-bit Q1.11 in [11:0] |
| 0x200-0x29F | WEIGHT[160] | W | NN weights int8 in [7:0]; 0..127 layer 1 (neuron·8 + input), 128..159 layer 2 |
| 0x300-0x311 | BIAS[18] | W | NN biases int24 in [23:0] (accumulator domain) |
| 0x400-0x407 | FEATURE[8] | W | NN input features int8 (written by the host; feature extraction is offline) |
| 0x500 | RESULT_POP | R | [16] valid · [15:0] FIFO record; reading pops it |
| 0x600-0x63F | SAMPLE_BUF[64] | R | [31] valid · [10:0] centred sample; offset 0 = newest |

Writes beyond a memory's depth are ignored. These memories are write-only (the engines read them) and are **not**
cleared by any reset: load them before use. Soft reset (CTRL[0]) restarts the datapath (engines, scheduler,
quality, FIFO, sample buffer) and keeps every register above plus all memories.

## Output FIFO record (16 bits)

| [15:14] | Type | Layout |
|---|---|---|
| 00 | FIR sample | [13] saturated · [10:0] y (signed) |
| 01 | NN decision | [13] uncertain · [12] abnormal · [11] raw class · [10] low confidence · [9:8] quality class at decision time · [7:0] min(margin >> 4, 255) |
| 10 | Quality window | [13:12] class 0 GOOD / 1 MODERATE / 2 POOR · [11:8] flags {base, noise, flat, clip} · [7:0] score |

Decision rule (result_manager): `uncertain = lowconf | nn_overflow | (quality == POOR)`, `abnormal = class & ~uncertain`.
A poor-quality window or a low-margin inference is reported as UNCERTAIN, never as a confident abnormal result.
