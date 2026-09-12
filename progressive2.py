#!/usr/bin/env python3
"""progressive2.py — mic(rec_bypass류)와 aec rec의 시간별 비교로 수렴 구간 판별."""
import sys
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

fs = 48000
mic_path, aec_path = sys.argv[1], sys.argv[2]
mic = load_f32(mic_path)
aec = load_f32(aec_path)
n = min(len(mic), len(aec))
print(f"{'초':>3} {'mic_rms':>9} {'aec_rms':>9} {'억제':>7}")
converged = []
for s in range(1, min(n // fs, 20)):
    m = mic[s * fs : (s + 1) * fs]
    a = aec[s * fs : (s + 1) * fs]
    if len(m) < fs or len(a) < fs:
        break
    mr = 20 * np.log10(max(np.sqrt(np.mean(m ** 2)), 1e-12))
    ar = 20 * np.log10(max(np.sqrt(np.mean(a ** 2)), 1e-12))
    print(f"{s:3d} {mr:9.1f} {ar:9.1f} {mr-ar:+7.1f}")
    if mr - ar > 15:
        converged.append(s)
print(f"억제 15dB 이상 구간: {converged}")
