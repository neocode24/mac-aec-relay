#!/usr/bin/env python3
"""align_scan.py — AEC rec에서 잔여 에코의 시간별 lag를 정밀 스캔."""
import sys
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

fs = 48000
rec = load_f32(sys.argv[1])
far = load_f32(sys.argv[2])
win = int(1.5 * fs)
N = 1 << int(np.ceil(np.log2(2 * win)))

lags_found = []
for s in range(0, min(len(rec) - win, 10 * fs), win):
    seg = rec[s : s + win]
    R = np.fft.rfft(seg, N)
    best = (None, -1)
    for fs_start in range(0, len(far) - win, win // 2):
        F = np.fft.rfft(far[fs_start : fs_start + win], N)
        xc = np.fft.irfft(np.conj(F) * R, N)
        zone = int(0.6 * fs)
        lags = np.concatenate([xc[:zone], xc[-zone:]])
        pk = int(np.argmax(np.abs(lags)))
        if pk >= zone:
            pk -= N
        c = np.abs(xc[pk]) / (np.linalg.norm(seg) * np.linalg.norm(far[fs_start:fs_start+win]) + 1e-12)
        if c > best[1]:
            best = (fs_start + pk, c)
    pos, c = best
    if c > 0.1:
        lags_found.append(((s - pos) / fs * 1000, c))
print(sys.argv[1])
for l, c in lags_found:
    print(f"  rec 창 lag {l:+8.1f} ms  corr {c:.3f}")
if lags_found:
    print(f"  → 잔여 lag median {np.median([l for l, _ in lags_found]):+.1f} ms")
