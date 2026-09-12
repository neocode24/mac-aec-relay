#!/usr/bin/env python3
"""why_fail.py — 실패 런 rec의 잔여 에코가 어느 시점에 살아있는지.
far와의 세그먼트 상관 크기(에코 세기)를 시간축으로.
"""
import sys
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

fs = 48000
rec = load_f32(sys.argv[1])
far = load_f32(sys.argv[2])
win = 2 * fs
N = 1 << int(np.ceil(np.log2(2 * win)))

print(f"{'rec시각':>7} {'에코상관':>8} {'lag(ms)':>9}  (실패 런은 잔여가 계속 살아있어야)")
for s in range(0, min(len(rec) - win, 14 * fs), win):
    seg = rec[s : s + win]
    R = np.fft.rfft(seg, N)
    best = (None, -1)
    for fs_start in range(0, len(far) - win, win // 2):
        F = np.fft.rfft(far[fs_start : fs_start + win], N)
        xc = np.fft.irfft(np.conj(F) * R, N)
        zone = int(0.7 * fs)
        lags = np.concatenate([xc[:zone], xc[-zone:]])
        pk = int(np.argmax(np.abs(lags)))
        if pk >= zone:
            pk -= N
        c = np.abs(xc[pk]) / (np.linalg.norm(seg) * np.linalg.norm(far[fs_start:fs_start+win]) + 1e-12)
        if c > best[1]:
            best = (fs_start + pk, c)
    pos, c = best
    print(f"{s/fs:7.1f} {c:8.3f} {(s-pos)/fs*1000:+9.1f}")
