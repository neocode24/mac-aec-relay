#!/usr/bin/env python3
"""track_delay.py — 세션 내 지연 드리프트 추정.

far와 bypass rec을 2초 창으로 잘라 각 창의 상관 lag을 잰다.
세션마다/창마다 지연이 얼마나 흔들리는지가 수렴 성패를 설명하는지.
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
F_full = np.fft.rfft(far[:win], N)

print(f"{'rec시각':>8} {'lag(ms)':>9}")
for s in range(0, min(len(rec) - win, 20 * fs), win):
    seg = rec[s : s + win]
    R = np.fft.rfft(seg, N)
    xc = np.fft.irfft(np.conj(F_full) * R, N)
    zone = int(0.7 * fs)
    lags = np.concatenate([xc[:zone], xc[-zone:]])
    pk = int(np.argmax(np.abs(lags)))
    if pk >= zone:
        pk -= N
    c = np.abs(xc[pk]) / (np.linalg.norm(seg) * np.linalg.norm(far[:win]) + 1e-12)
    print(f"{s/fs:8.1f} {pk/fs*1000:+9.1f}  corr {c:.3f}")
