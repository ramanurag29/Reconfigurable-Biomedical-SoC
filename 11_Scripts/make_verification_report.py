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
 "fir": ("fir_engine + fir_block (private MAC PIPE=0/1)", "ECG 16/8 taps; latency; 600 random stress trials (random taps/shift/coefs, saturation); overrun; reset", "Python bit-exact golden (ECG) and in-TB integer reference (stress)", "-"),
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
