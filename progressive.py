#!/usr/bin/env python3
"""progressive.py — rec_*.f32에서 시간축 에코 억제 진행 상황(1초 해상도)."""
import glob
import sys
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

fs = 48000
for path in sorted(sys.argv[1:]):
    x = load_f32(path)
    print(f"== {path} ({len(x)/fs:.1f}s)")
    for s in range(1, min(int(len(x) / fs), 16)):
        w = x[s * fs : (s + 1) * fs]
        if len(w) < fs:
            break
        rms = 20 * np.log10(max(np.sqrt(np.mean(w ** 2)), 1e-12))
        pk = 20 * np.log10(max(np.max(np.abs(w)), 1e-12))
        bar = "#" * max(0, int((rms + 90) / 2))
        print(f"  {s:2d}s  peak {pk:7.1f}  rms {rms:7.1f}  {bar}")
