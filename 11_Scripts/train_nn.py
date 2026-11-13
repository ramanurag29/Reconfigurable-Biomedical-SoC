#!/usr/bin/env python3
"""
train_nn.py - ECG beat classifier (Normal vs Abnormal) for the 8->16->2 shared-MAC NN.

  1. features: 8 per-beat features from MIT-BIH (cached in 03_AI_Model/features.npz)
  2. patient-independent split: de Chazal DS1 (train) / DS2 (test); record 202 dropped from DS2
     (same patient as 201, which is in DS1); paced records 102/104/107/217 excluded
  3. train sklearn MLP 8-16-2 (ReLU), quantize to the integer model of nn_golden.py
  4. report float vs quantized (accuracy/sensitivity/specificity/confusion), export RTL memory files
Usage (repo root, venv active):
    python 11_Scripts/train_nn.py                 # real MIT-BIH (local files under 01_Dataset or PhysioNet download)
    python 11_Scripts/train_nn.py --synthetic     # random clustered features: ONLY for RTL plumbing tests, not a result
Not a clinical device; numbers are an academic demonstrator.
"""
import argparse, glob, json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nn_golden as G

DS1 = [101,106,108,109,112,114,115,116,118,119,122,124,201,203,205,207,208,209,215,220,223,230]
DS2 = [100,103,105,111,113,117,121,123,200,210,212,213,214,219,221,222,228,231,232,233,234]  # 202 dropped
NORMAL = set("NLRej"); ABNORMAL = set("AaJSVEF"); BEATS = NORMAL | ABNORMAL | set("/fQ")
FEAT_NAMES = ["rr_prev_s", "hr_avg_bpm", "qrs_dur_ms", "r_amp_mV", "qrs_energy", "win_mean_mV", "win_var_mV2", "rr_std_ms"]
OUT_MEM = "06_Simulation/mem"; OUT_AI = "03_AI_Model"; OUT_RES = "09_Results/nn"


def extract_record(rec):
    import wfdb
    from ecg_pipeline import baseline_removal, bandpass_filter
    loc = glob.glob(f"01_Dataset/**/{rec}.hea", recursive=True)
    if loc:
        base = loc[0][:-4]; r = wfdb.rdrecord(base, channels=[0]); a = wfdb.rdann(base, "atr")
    else:
        r = wfdb.rdrecord(str(rec), pn_dir="mitdb", channels=[0]); a = wfdb.rdann(str(rec), "atr", pn_dir="mitdb")
    fs = r.fs; x = r.p_signal[:, 0].astype(float)
    x = bandpass_filter(baseline_removal(x, fs), fs, 0.5, 40.0)
    idx = [(s, c) for s, c in zip(a.sample, a.symbol) if c in BEATS]
    pos = np.array([s for s, _ in idx]); sym = [c for _, c in idx]
    F, Y = [], []
    w250 = int(0.25 * fs); w100 = int(0.10 * fs); w60 = int(0.06 * fs); w30 = int(0.03 * fs)
    for i in range(8, len(pos) - 1):
        if sym[i] not in NORMAL and sym[i] not in ABNORMAL: continue
        p = pos[i]
        if p - w250 < 0 or p + w250 >= len(x): continue
        rr = np.diff(pos[i - 8:i + 1]) / fs                       # last 8 RR intervals (s)
        seg = x[max(p - w30, 0):p + w30 + 1]; pk = max(p - w30, 0) + int(np.argmax(np.abs(seg)))
        amp = x[pk]; thr = 0.2 * abs(amp)
        l = pk
        while l > pk - w100 and abs(x[l]) > thr: l -= 1
        r_ = pk
        while r_ < pk + w100 and abs(x[r_]) > thr: r_ += 1
        win = x[p - w250:p + w250 + 1]; q = x[pk - w60:pk + w60 + 1]
        F.append([rr[-1], 60.0 / rr.mean(), (r_ - l) / fs * 1000, amp, float(np.sum(q * q) / fs), win.mean(), win.var(),
                  float(np.std(rr[-5:]) * 1000)])
        Y.append(1 if sym[i] in ABNORMAL else 0)
    return np.array(F), np.array(Y)


def load_features():
    cache = f"{OUT_AI}/features.npz"
    if os.path.exists(cache):
        d = np.load(cache); return d["Ftr"], d["ytr"], d["Fte"], d["yte"]
    out = {}
    for name, recs in (("tr", DS1), ("te", DS2)):
        Fs, Ys = [], []
        for r in recs:
            f, y = extract_record(r); Fs.append(f); Ys.append(y); print(f"  record {r}: {len(y)} beats ({int(y.sum())} abnormal)", flush=True)
        out["F" + name] = np.vstack(Fs); out["y" + name] = np.concatenate(Ys)
    os.makedirs(OUT_AI, exist_ok=True); np.savez(cache, **out)
    return out["Ftr"], out["ytr"], out["Fte"], out["yte"]


def synthetic():
    rng = np.random.default_rng(1)
    def mk(n):
        y = (rng.random(n) < 0.3).astype(int)
        F = rng.normal(size=(n, 8)) * np.array([.1, 8, 10, .3, .5, .05, .05, 20]) + np.array([.8, 75, 90, 1, 1, 0, .1, 25])
        F[y == 1] += np.array([-.15, 12, 25, -.3, .6, .02, .08, 40]); return F, y
    Ftr, ytr = mk(6000); Fte, yte = mk(3000); return Ftr, ytr, Fte, yte


def metrics(y, p):
    tn = int(np.sum((y == 0) & (p == 0))); fp = int(np.sum((y == 0) & (p == 1)))
    fn = int(np.sum((y == 1) & (p == 0))); tp = int(np.sum((y == 1) & (p == 1)))
    d = lambda a, b: a / b if b else float("nan")
    return {"confusion[[TN,FP],[FN,TP]]": [[tn, fp], [fn, tp]], "accuracy": d(tp + tn, len(y)), "sensitivity": d(tp, tp + fn),
            "specificity": d(tn, tn + fp), "precision": d(tp, tp + fp), "f1": d(2 * tp, 2 * tp + fp + fn)}


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--synthetic", action="store_true"); a = ap.parse_args()
    Ftr, ytr, Fte, yte = synthetic() if a.synthetic else load_features()
    mu, sg = Ftr.mean(0), Ftr.std(0) + 1e-9
    Xtr, Xte = G.quantize_features(Ftr, mu, sg), G.quantize_features(Fte, mu, sg)
    # balance training set (oversample abnormal up to 1:1, cap size)
    rng = np.random.default_rng(0); i0 = np.where(ytr == 0)[0]; i1 = np.where(ytr == 1)[0]
    i0 = rng.choice(i0, min(len(i0), 30000), replace=False); i1 = rng.choice(i1, len(i0), replace=True)
    sel = np.concatenate([i0, i1]); rng.shuffle(sel)
    from sklearn.neural_network import MLPClassifier
    clf = MLPClassifier((G.NH,), activation="relu", max_iter=400, random_state=0, early_stopping=True)
    clf.fit(Xtr[sel] / (1 << G.FX), ytr[sel])
    W1 = clf.coefs_[0].T; b1 = clf.intercepts_[0]; w = clf.coefs_[1][:, 0]; b = clf.intercepts_[1][0]
    W2 = np.vstack([-w / 2, w / 2]); b2 = np.array([-b / 2, b / 2])      # s1 - s0 = logit
    m = G.quantize_model(W1, b1, W2, b2, Xtr[sel])
    sf = G.float_forward(W1, b1, W2, b2, Xte); pf = (sf[:, 1] > sf[:, 0]).astype(int)
    qi = [G.infer_int(x, m) for x in Xte]; pq = np.array([r["cls"] for r in qi]); mg = np.array([r["margin"] for r in qi])
    mtr = np.array([G.infer_int(x, m)["margin"] for x in Xtr[sel][:5000]])
    conf_thr = int(np.percentile(mtr, 10)); low = mg < conf_thr
    res = {"synthetic": bool(a.synthetic), "train_beats": int(len(ytr)), "test_beats": int(len(yte)), "test_abnormal": int(yte.sum()),
           "S1": m["S1"], "conf_thr": conf_thr, "float": metrics(yte, pf), "quantized": metrics(yte, pq),
           "float_vs_quant_agreement": float(np.mean(pf == pq)), "low_confidence_fraction": float(low.mean()),
           "accuracy_on_confident": float(np.mean(pq[~low] == yte[~low])) if (~low).any() else None,
           "accuracy_on_low_conf": float(np.mean(pq[low] == yte[low])) if low.any() else None,
           "features": FEAT_NAMES, "feat_mu": mu.tolist(), "feat_sigma": sg.tolist(),
           "split": "DS1 train / DS2 test by record (patient-independent; 202 dropped, same patient as 201)"}
    os.makedirs(OUT_RES, exist_ok=True); os.makedirs(OUT_AI, exist_ok=True)
    json.dump(res, open(f"{OUT_RES}/nn_metrics.json", "w"), indent=1)
    json.dump({**m, "mu": mu.tolist(), "sigma": sg.tolist()}, open(f"{OUT_AI}/nn_int_model.json", "w"))
    # test vectors: 32 normal + 32 abnormal (deterministic)
    n0 = np.where(yte == 0)[0][:32]; n1 = np.where(yte == 1)[0][:32]; vi = np.concatenate([n0, n1])
    G.export(m, Xte[vi], yte[vi], OUT_MEM, conf_thr=conf_thr, nvec=len(vi))
    for k in ("float", "quantized"):
        r = res[k]; print(f"{k:9s} acc={r['accuracy']:.4f} sens={r['sensitivity']:.4f} spec={r['specificity']:.4f} cm={r['confusion[[TN,FP],[FN,TP]]']}")
    print(f"float/quant agreement {res['float_vs_quant_agreement']:.4f}  S1={m['S1']}  conf_thr={conf_thr}  low-conf={res['low_confidence_fraction']:.3f}")
    print("SYNTHETIC DATA - plumbing test only" if a.synthetic else "real MIT-BIH split DS1/DS2")


if __name__ == "__main__":
    main()
