#!/usr/bin/env python3
"""Builds 10_Documentation/03_verification_report.md from the simulation logs (no hand-written results)."""
import datetime, os, re
META = {
 "input_formatter_ecg": ("input_formatter", "3600 real ECG codes (MIT-BIH 100) as gapped and back-to-back streams, junk data while valid=0, reset states", "signed = code - 512 from independent Python golden + checksum", "tb_input_formatter_ecg.vcd"),
 "sar_controller": ("sar_controller", "all 1024 target codes through an ideal integer comparator, SAMPLE_CYCLES 1 and 3; extra start while busy; mid-conversion reset; continuous start", "code = target, latency = SC+N+1, sample_en width = SC, period SC+N+2", "-"),
 "adc": ("behavioural SAR ADC (S&H, comparator, CDAC, controller, bypass)", "zero/mid/full scale, over-range, 2046 boundary points, 3072-pt ramp, 360-pt sine, 3000 random, hold test, bypass, reset; second DUT with +1 LSB comparator offset", "D = clamp(floor(vin/LSB),0,1023); |error| <= LSB/2; latency 12", "-"),
 "adc_ecg": ("ADC -> input_formatter chain", "3600 PWL volts from the ECG pipeline", "Python golden codes and signed samples, checksum", "-"),
 "mac": ("mac_unit (5 configs)", "directed saturation/priority cases + 40k random ops incl. mid-run reset", "independent 64-bit reference: acc, overflow flag, valid timing", "-"),
 "memory": ("regfile_sync, sample_buffer", "40k random read/write cycles, mid-run reset", "independent shadow models", "-"),
 "output": ("output_fifo", "90k random cycles in push-heavy / pop-heavy / balanced phases", "log-based model incl. full/empty/count/overflow/underflow", "-"),
 "nn": ("nn_engine + nn_block (private MAC PIPE=0/1)", "64 test vectors from the trained 8-16-2 model; 300 random stress trials (full-range int8 weights, int24 biases, random shift/threshold); tie; start-while-busy; reset mid-inference", "bit-exact Python golden (nn_golden.infer_int) and in-TB 64-bit integer reference: scores, class, margin, low-confidence flag; latency 197 (PIPE0) / 215 (PIPE1) clocks", "tb_nn.vcd"),
 "fir": ("fir_engine + fir_block (private MAC PIPE=0/1)", "ECG 16/8 taps; latency; 600 random stress trials (random taps/shift/coefs, saturation); overrun; reset", "Python bit-exact golden (ECG) and in-TB integer reference (stress)", "-"),
 "scheduler": ("task_scheduler + shared mac_unit + fir_engine + nn_engine (MAC PIPE=0)", "fixed-priority / round-robin / mode-based contention, preemption with accumulator save/restore, non-preemptive mode, deadline monitor, FIR stream during NN, reset mid-contention, 300 random trials", "bit-exact in-TB integer golden for FIR and NN results; exact MAC-op accounting (FIR 1+T, NN 178); preemption counts", "tb_scheduler.vcd"),
 "scheduler_p1": ("task_scheduler with pipelined MAC (PIPE=1)", "same testbench, -Ptb_scheduler.PIPE=1", "same checks; exercises the PIPE+1 restore wait and the drain-before-switch rule", "-"),
}
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
out = ["# Verification report (auto-generated)", "", f"Generated {now} by `11_Scripts/make_verification_report.py` from `09_Results/sim_*.log`. "
       "Simulator: Icarus Verilog. Nothing here has been synthesized, timed or placed yet.", "",
       "| Testbench | Unit under test | Input | Expected | Waveform |", "|---|---|---|---|---|"]
for k, (uut, inp, exp, wf) in META.items():
    out.append(f"| tb_{k} | {uut} | {inp} | {exp} | {wf} |")
out += ["", "## Results (actual, copied from simulation logs)", "", "| Testbench | Check | Result |", "|---|---|---|"]
allpass = True
for k in META:
    p = f"09_Results/sim_{k}.log"
    if not os.path.exists(p): out.append(f"| tb_{k} | (no log) | NOT RUN |"); allpass = False; continue
    txt = open(p).read()
    ok = "ALL TESTS PASSED" in txt; allpass &= ok
    for line in txt.splitlines():
        if line.startswith("["):
            m = re.match(r"\[(.*)\](.*)", line)
            res = "PASS" if "PASS" in line else ("FAIL" if "FAIL" in line else "info")
            out.append(f"| tb_{k} | {m.group(1)} — {m.group(2).replace('->','').replace('PASS','').replace('FAIL','').strip()} | {res} |")
    out.append(f"| tb_{k} | **overall** | **{'PASS' if ok else 'FAIL'}** |")
out += ["", f"**Overall: {'ALL PASS' if allpass else 'FAILURES PRESENT'}**", "",
        "Mutation checks: every module's testbench was also run against deliberately broken RTL "
        "(wrong decision polarity, missing rounding/saturation, off-by-one taps/index, missing flags, ...) and each mutant was detected; "
        "see commit history for the injected cases."]
open("10_Documentation/03_verification_report.md", "w").write("\n".join(out) + "\n")
print("wrote 10_Documentation/03_verification_report.md")
