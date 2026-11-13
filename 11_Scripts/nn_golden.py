#!/usr/bin/env python3
"""
nn_golden.py - integer golden model + quantizer + exporter for the 8->16->2 shared-MAC NN.
Single source of truth for the RTL (04_RTL/neural_network/nn_engine.v). Integers only in infer_int().

Formats
  feature  : int8   x_q  = clip(round(z * 2^FX), -128, 127)   z = (f - mu)/sigma   (FX = 4)
  weights  : int8   per layer scale s1 / s2 (max|w| -> 127)
  bias     : int24  accumulator domain, b1_q = round(b1 * 2^FX * s1), b2_q = round(b2 * hs * s2)
  layer 1  : acc1 = b1_q + sum_i x_q[i]*w1_q[j][i]          (MAC load = bias, then 8 MAC ops)
  hidden   : h_q  = clamp((acc1 + 2^(S1-1)) >>> S1, 0, 127)  (ReLU folded into the clamp)
  layer 2  : acc2 = b2_q + sum_j h_q[j]*w2_q[o][j]          (MAC load = bias, then 16 MAC ops)
  class    : 1 if acc2[1] > acc2[0] else 0   (ties -> 0)
  margin   : min(|acc2[1]-acc2[0]|, 65535)   ; low_conf = margin < conf_thr
Memory layout (matches 10_Documentation/01_system_architecture.md):
  weights[0..127] = w1[j*8+i], weights[128..159] = w2[o*16+j] ; bias[0..15]=b1, bias[16..17]=b2 ; feat[0..7]
"""
import json, os
import numpy as np

NF, NH, NO = 8, 16, 2
FX = 4
ACC_MIN, ACC_MAX = -(1 << 31), (1 << 31) - 1
B_MIN, B_MAX = -(1 << 23), (1 << 23) - 1


def sat32(v):
    return max(ACC_MIN, min(ACC_MAX, int(v)))


def infer_int(x_q, m):
    """Bit-exact model of nn_engine. x_q: 8 ints (int8). m: dict with w1,b1,w2,b2,S1. Returns dict."""
    S1 = m["S1"]
    h = []
    for j in range(NH):
        acc = sat32(m["b1"][j])
        for i in range(NF):
            acc = sat32(acc + int(x_q[i]) * m["w1"][j][i])
        r = (acc + ((1 << (S1 - 1)) if S1 > 0 else 0)) >> S1
        h.append(max(0, min(127, r)))
    sc = []
    for o in range(NO):
        acc = sat32(m["b2"][o])
        for j in range(NH):
            acc = sat32(acc + h[j] * m["w2"][o][j])
        sc.append(acc)
    cls = 1 if sc[1] > sc[0] else 0
    margin = min(abs(sc[1] - sc[0]), 65535)
    return {"h": h, "s0": sc[0], "s1": sc[1], "cls": cls, "margin": margin}


def quantize_features(F, mu, sigma):
    z = (np.asarray(F, float) - mu) / sigma
    return np.clip(np.round(z * (1 << FX)), -128, 127).astype(np.int64)


def quantize_model(W1, b1, W2, b2, Xq_train):
    """W1 [16,8], b1 [16], W2 [2,16], b2 [2] float (acting on z = Xq/2^FX). Returns int model dict."""
    s1 = 127.0 / np.max(np.abs(W1)); s2 = 127.0 / np.max(np.abs(W2))
    w1 = np.round(W1 * s1).astype(np.int64); w2 = np.round(W2 * s2).astype(np.int64)
    b1q = np.clip(np.round(b1 * (1 << FX) * s1), B_MIN, B_MAX).astype(np.int64)
    # choose S1 so that the largest train hidden activation fits 127
    acc1 = Xq_train @ w1.T + b1q
    mx = max(1, int(np.max(acc1)))
    S1 = 0
    while (mx >> S1) > 127: S1 += 1
    hs = (1 << FX) * s1 / (1 << S1)             # hidden-code per real hidden unit
    b2q = np.clip(np.round(b2 * hs * s2), B_MIN, B_MAX).astype(np.int64)
    return {"w1": w1.tolist(), "b1": b1q.tolist(), "w2": w2.tolist(), "b2": b2q.tolist(), "S1": int(S1),
            "s1": float(s1), "s2": float(s2)}


def float_forward(W1, b1, W2, b2, Xq):
    z = np.asarray(Xq, float) / (1 << FX)
    h = np.maximum(0, z @ W1.T + b1)
    return h @ W2.T + b2


def _hex(v, bits):
    return format(int(v) & ((1 << bits) - 1), "0%dx" % ((bits + 3) // 4))


def export(m, Xq_test, y_test, outdir, conf_thr=64, nvec=64, tag="nn"):
    """Write memory files + test vectors for tb_nn.v. Vectors are golden outputs of infer_int()."""
    os.makedirs(outdir, exist_ok=True)
    wl = [m["w1"][j][i] for j in range(NH) for i in range(NF)] + [m["w2"][o][j] for o in range(NO) for j in range(NH)]
    bl = list(m["b1"]) + list(m["b2"])
    open(f"{outdir}/{tag}_weights.hex", "w").write("\n".join(_hex(v, 8) for v in wl) + "\n")
    open(f"{outdir}/{tag}_bias.hex", "w").write("\n".join(_hex(v, 24) for v in bl) + "\n")
    idx = np.arange(min(nvec, len(Xq_test)))
    open(f"{outdir}/{tag}_feat_vec.hex", "w").write("\n".join(_hex(Xq_test[i][k], 8) for i in idx for k in range(NF)) + "\n")
    lines = []
    for i in idx:
        r = infer_int(Xq_test[i], m)
        lines.append(f"{_hex(r['s0'],32)} {_hex(r['s1'],32)} {r['cls']} {_hex(r['margin'],16)} {1 if r['margin'] < conf_thr else 0}")
    open(f"{outdir}/{tag}_expected.txt", "w").write("\n".join(lines) + "\n")
    open(f"{outdir}/{tag}_params.vh", "w").write(
        f"`define NN_NVEC {len(idx)}\n`define NN_S1 {m['S1']}\n`define NN_CONF_THR {conf_thr}\n")
    json.dump({k: m[k] for k in ("S1", "s1", "s2")} | {"conf_thr": conf_thr, "nvec": int(len(idx))},
              open(f"{outdir}/{tag}_model.json", "w"), indent=1)
