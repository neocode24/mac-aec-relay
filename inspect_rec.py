#!/usr/bin/env python3
"""녹음 파일 검사: 길이, 피크, RMS, 앞부분 샘플."""
import struct
import sys
import math

def load_f32(path):
    with open(path, "rb") as f:
        data = f.read()
    n = len(data) // 4
    return struct.unpack(f"<{n}f", data[: n * 4])

for p in sys.argv[1:]:
    x = load_f32(p)
    fs = 48000
    peak = max(abs(v) for v in x) if x else 0
    rms = math.sqrt(sum(v * v for v in x) / max(len(x), 1))
    print(f"{p}: {len(x)/fs:.3f}s n={len(x)} peak={20*math.log10(peak) if peak>0 else '-inf':.1f}dB rms={20*math.log10(rms) if rms>0 else '-inf':.1f}dB")
    # 0.5초별 에너지 프로파일
    step = fs // 2
    prof = []
    for i in range(0, len(x) - step, step):
        seg = x[i:i+step]
        r = math.sqrt(sum(v*v for v in seg)/len(seg))
        prof.append(f"{20*math.log10(r):.0f}" if r > 0 else "-inf")
    print("  0.5s rms profile:", " ".join(prof))
