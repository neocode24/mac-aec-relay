#!/usr/bin/env python3
"""what_is_rec.py — rec 파일의 주기 신호 정체 파악 (스펙트럼 + 세그먼트 레벨)."""
import sys
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

fs = 48000
rec = load_f32(sys.argv[1])
print(f"길이 {len(rec)/fs:.2f}s")

# 30초 세그먼트 레벨
seg = fs
for s in range(0, min(len(rec), 12 * fs), fs):
    w = rec[s : s + fs]
    if len(w) == 0:
        break
    rms = 20 * np.log10(max(np.sqrt(np.mean(w ** 2)), 1e-12))
    pk = 20 * np.log10(max(np.max(np.abs(w)), 1e-12))
    print(f"  {s/fs:5.1f}s  peak {pk:7.1f} dB  rms {rms:7.1f} dB")

# 정상(버스트 밖) 구간 스펙트럼: 앞 0.2s (버스트 전)
w = rec[: int(0.2 * fs)]
if len(w) > 0:
    spec = np.abs(np.fft.rfft(w * np.hanning(len(w))))
    freqs = np.fft.rfftfreq(len(w), 1 / fs)
    top = np.argsort(spec)[::-1][:8]
    print("첫 0.2s 상위 주파수:", [(f"{freqs[i]:.0f} Hz", f"{20*np.log10(max(spec[i],1e-12)):.0f} dB") for i in top])

# 1-1.2s 구간 (버스트 사이)
a, b = int(1.0 * fs), int(1.15 * fs)
w = rec[a:b]
if len(w) == fs * 0 // 15 or len(w) > 0:
    spec = np.abs(np.fft.rfft(w * np.hanning(len(w))))
    freqs = np.fft.rfftfreq(len(w), 1 / fs)
    top = np.argsort(spec)[::-1][:8]
    print("1.0-1.15s 상위 주파수:", [(f"{freqs[i]:.0f} Hz", f"{20*np.log10(max(spec[i],1e-12)):.0f} dB") for i in top])
