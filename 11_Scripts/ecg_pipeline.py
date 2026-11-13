#!/usr/bin/env python3
"""
ecg_pipeline.py  -  Milestone 1 reference pipeline (Python implementation)

MIT-BIH record -> condition -> scale to ADC range -> 10-bit quantize -> export
.hex/.csv/.pwl + Verilog parameter header for the self-checking testbench.

Conventions (single source of truth - RTL and MATLAB must match):
    LSB      = VREF / (2^N - 1)                      (endpoint convention)
    D        = floor(Vin/VREF * (2^N - 1) + 0.5)     (round half up, like MATLAB round)
    D        clipped to [0, 2^N - 1]
    x_signed = D - 2^(N-1)                           (N=10 -> D - 512, range -512..+511)
Note: Vin = 1.0 V (common mode) -> D = 512 -> x_signed = 0.  The true analog
midpoint of an endpoint-convention ADC is code 511.5, so a zero-volt-offset
input appears as +0.5 LSB.  This is documented, not hidden.

Run from the repository root:
    python 11_Scripts/ecg_pipeline.py --record 100 --start 10 --duration 10
"""
import argparse, json, os, sys
from fractions import Fraction
import numpy as np
from scipy import signal, ndimage
import wfdb

# ----------------------------------------------------------------- stages
def baseline_removal(x, fs, w1=0.2, w2=0.6):
    """Two-stage median filter baseline estimate (200 ms then 600 ms), subtracted."""
    k1 = int(round(w1 * fs)) | 1
    k2 = int(round(w2 * fs)) | 1
    base = ndimage.median_filter(x, size=k1, mode="nearest")
    base = ndimage.median_filter(base, size=k2, mode="nearest")
    return x - base

def powerline_filter(x, fs, f0=50.0, q=30.0):
    b, a = signal.iirnotch(f0, q, fs=fs)
    return signal.filtfilt(b, a, x)

def bandpass_filter(x, fs, lo=0.5, hi=40.0, order=4):
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=fs, output="sos")
    return signal.sosfiltfilt(sos, x)

def resample_ecg(x, fs_in, fs_out):
    if abs(fs_in - fs_out) < 1e-9:
        return x, fs_in
    fr = Fraction(fs_out / fs_in).limit_denominator(1000)
    return signal.resample_poly(x, fr.numerator, fr.denominator), fs_out

def scale_to_adc(x_mv, xref_mv, vcm, vhalf):
    """Map conditioned ECG (mV) to volts around vcm. +/-xref_mv -> +/-vhalf volts."""
    return vcm + (x_mv / xref_mv) * vhalf

def quantize_adc(vin, vref, nbits):
    full = (1 << nbits) - 1
    raw = np.floor(vin / vref * full + 0.5).astype(np.int64)
    sat = int(np.count_nonzero((raw < 0) | (raw > full)))
    return np.clip(raw, 0, full), sat

# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="01_Dataset/mit-bih-arrhythmia-database-1.0.0")
    ap.add_argument("--record", default="100")
    ap.add_argument("--channel", default="MLII")
    ap.add_argument("--start", type=float, default=10.0, help="segment start, s")
    ap.add_argument("--duration", type=float, default=10.0, help="segment length, s")
    ap.add_argument("--bits", type=int, default=10)
    ap.add_argument("--vref", type=float, default=2.0)
    ap.add_argument("--vcm", type=float, default=1.0)
    ap.add_argument("--vhalf", type=float, default=0.5, help="conditioned swing +/- about vcm")
    ap.add_argument("--hp", type=float, default=0.5)
    ap.add_argument("--lp", type=float, default=40.0)
    ap.add_argument("--notch", action="store_true", help="enable 50 Hz notch")
    ap.add_argument("--fs-target", type=float, default=360.0)
    ap.add_argument("--clip-pct", type=float, default=99.95,
                    help="percentile of |conditioned| (whole record) mapped to full swing")
    ap.add_argument("--memdir", default="06_Simulation/mem")
    ap.add_argument("--resdir", default="09_Results/milestone1")
    a = ap.parse_args()
    os.makedirs(a.memdir, exist_ok=True); os.makedirs(a.resdir, exist_ok=True)

    # A. load real record + annotations
    rec = wfdb.rdrecord(os.path.join(a.db, a.record))
    ann = wfdb.rdann(os.path.join(a.db, a.record), "atr")
    ch = rec.sig_name.index(a.channel)
    fs = float(rec.fs)
    raw_mv = rec.p_signal[:, ch].astype(np.float64)       # physical units (mV)
    print(f"record {a.record}: {len(raw_mv)} samples @ {fs} Hz, channel {a.channel} "
          f"({rec.units[ch]}), {len(ann.sample)} annotations")

    # C-E. conditioning on the whole record (filters need context), then slice
    x = baseline_removal(raw_mv, fs)
    if a.notch:
        x = powerline_filter(x, fs)
    x = bandpass_filter(x, fs, a.hp, a.lp)
    # H. resample only if target rate differs
    x, fs_out = resample_ecg(x, fs, a.fs_target)
    raw_rs, _ = resample_ecg(raw_mv - np.mean(raw_mv), fs, a.fs_target)

    # G. normalisation/scaling (reference taken from whole record -> stable gain)
    xref = float(np.percentile(np.abs(x), a.clip_pct))
    vin_full = scale_to_adc(x, xref, a.vcm, a.vhalf)

    i0 = int(round(a.start * fs_out)); i1 = i0 + int(round(a.duration * fs_out))
    seg_c = x[i0:i1]; seg_raw = raw_rs[i0:i1]; vin_f = vin_full[i0:i1]
    vmin, vmax = a.vcm - a.vhalf, a.vcm + a.vhalf
    front_end_clip = int(np.count_nonzero((vin_f < vmin) | (vin_f > vmax)))
    vin = np.clip(vin_f, vmin, vmax)                       # front-end swing limit

    # I. 10-bit reference representation
    code, adc_sat = quantize_adc(vin, a.vref, a.bits)
    full = (1 << a.bits) - 1
    mid = 1 << (a.bits - 1)
    xs = code - mid                                        # signed, 11-bit range
    lsb = a.vref / full
    vq = code * lsb
    err = vq - vin
    N = len(code)

    # quantization statistics (non-clipped part is what matters for LSB/2 bound)
    snr_q = 10 * np.log10(np.var(vin) / np.var(err))
    stats = dict(
        record=a.record, channel=a.channel, fs_hz=fs_out, start_s=a.start, n_samples=int(N),
        bits=a.bits, vref=a.vref, vcm=a.vcm, vswing=[vmin, vmax], lsb_mV=lsb * 1e3,
        xref_mV=xref, gain_V_per_mV=a.vhalf / xref,
        front_end_clipped_samples=front_end_clip, adc_saturated_samples=adc_sat,
        code_min=int(code.min()), code_max=int(code.max()),
        codes_used=int(len(np.unique(code))),
        signed_min=int(xs.min()), signed_max=int(xs.max()), signed_sum=int(xs.sum()),
        err_max_abs_mV=float(np.max(np.abs(err)) * 1e3), err_rms_mV=float(np.std(err) * 1e3),
        half_lsb_mV=lsb * 0.5e3, quant_SNR_dB=float(snr_q),
        notch=bool(a.notch), bandpass_Hz=[a.hp, a.lp])
    with open(os.path.join(a.resdir, "quantization_report.json"), "w") as f:
        json.dump(stats, f, indent=2)

    # J/K. exports
    nhex = (a.bits + 3) // 4
    with open(os.path.join(a.memdir, "ecg_adc_10b.hex"), "w") as f:
        f.write("\n".join(f"{int(c):0{nhex}X}" for c in code) + "\n")
    sw = a.bits + 1; shex = (sw + 3) // 4
    with open(os.path.join(a.memdir, "ecg_signed_11b.hex"), "w") as f:
        f.write("\n".join(f"{int(v) & ((1 << sw) - 1):0{shex}X}" for v in xs) + "\n")
    t = np.arange(N) / fs_out
    np.savetxt(os.path.join(a.memdir, "ecg_stimulus.csv"),
               np.column_stack([np.arange(N), t, seg_raw, seg_c, vin, code, xs]),
               delimiter=",", header="n,t_s,raw_mV_dc_removed,conditioned_mV,vin_V,code,x_signed",
               comments="", fmt=["%d", "%.9f", "%.6f", "%.6f", "%.6f", "%d", "%d"])
    with open(os.path.join(a.memdir, "ecg_vin.pwl"), "w") as f:     # ngspice PWL (t V)
        for ti, v in zip(t, vin):
            f.write(f"{ti:.9f} {v:.6f}\n")
    with open(os.path.join(a.memdir, "ecg_params.vh"), "w") as f:
        f.write("// AUTO-GENERATED by ecg_pipeline.py - do not edit\n")
        f.write(f"`define ECG_N            {N}\n")
        f.write(f"`define ECG_BITS         {a.bits}\n")
        f.write(f"`define ECG_SUM_SIGNED   {int(xs.sum())}\n")
        f.write(f"`define ECG_CODE_FILE    \"{a.memdir}/ecg_adc_10b.hex\"\n")
        f.write(f"`define ECG_SIGNED_FILE  \"{a.memdir}/ecg_signed_11b.hex\"\n")

    # M. plots
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(4, 1, figsize=(11, 11))
    ax[0].plot(t, seg_raw, lw=.7); ax[0].set_ylabel("raw (mV, DC removed)")
    ax[0].set_title(f"MIT-BIH {a.record} {a.channel}: raw -> conditioned -> 10-bit")
    ax[1].plot(t, seg_c, lw=.7, color="C1"); ax[1].set_ylabel("conditioned (mV)")
    ax[2].step(t, code, where="mid", lw=.7, color="C2"); ax[2].set_ylabel("ADC code (0..1023)")
    ax[3].hist(err * 1e3, bins=60, color="C3"); ax[3].set_xlabel("quantization error (mV)")
    ax[3].set_ylabel("count"); ax[3].axvline(-lsb*.5e3, ls="--", c="k"); ax[3].axvline(lsb*.5e3, ls="--", c="k")
    ax[2].set_xlabel("time (s)")
    fig.tight_layout(); fig.savefig(os.path.join(a.resdir, "milestone1_overview.png"), dpi=130)

    print(json.dumps(stats, indent=2))

if __name__ == "__main__":
    sys.exit(main())
