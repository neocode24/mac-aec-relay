#!/usr/bin/env python3
"""self_corr.py — AEC rec의 잔여 에코를 far와의 상관으로 측정.

실패 런이라도 ref 정합이 맞다면 잔여는 낮아야 한다. 이 스크립트는
rec(aec)과 far의 상관 스펙트럼 밀도 비로 '잔여 상관 성분'을 잰다.
정합이 틀린 런은 잔여 상관이 크게 남는다.
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
n = min(len(rec), len(far), 8 * fs)
rec = rec[2 * fs : n]
far = far[2 * fs : n] if len(far) >= n else far[: len(rec)]
n = min(len(rec), len(far))
rec = rec[:n]
far = far[:n]

# 최대 상관 (±600ms 스캔)
N = 1 << int(np.ceil(np.log2(2 * n)))
R = np.fft.rfft(rec, N)
F = np.fft.rfft(far, N)
xc = np.fft.irfft(np.conj(F) * R, N)
lag_zone = np.concatenate([xc[: int(0.6 * fs)], xc[-int(0.6 * fs):]])
pk = int(np.argmax(np.abs(lag_zone)))
if pk >= int(0.6 * fs):
    pk = pk - N
c = np.abs(xc[pk]) / (np.linalg.norm(rec) * np.linalg.norm(far) + 1e-12)
print(f"{sys.argv[1]}: 최대 상관 {c:.4f} @ lag {pk/fs*1000:+.1f} ms")
