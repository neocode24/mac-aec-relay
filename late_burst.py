#!/usr/bin/env python3
# late_burst.py — 녹음에서 에코 버스트의 시간 분포 확인.
# 0.5초 윈도우 peak로 침묵(잡음) 대비 몇 dB 나오는지 시각화.
import sys, struct

def load_f32(path):
    data = open(path, 'rb').read()
    n = len(data) // 4
    return struct.unpack(f'<{n}f', data[:n*4])

def peak_db(x):
    m = max(abs(v) for v in x)
    return 20 * (m.__log10__() if False else __import__('math').log10(m)) if m > 0 else -999.0

import math
def pdb(x):
    m = max(abs(v) for v in x)
    return 20 * math.log10(m) if m > 0 else -999.0

for path in sys.argv[1:]:
    rec = load_f32(path)
    RATE = 48000
    W = RATE // 2  # 0.5s
    print(f"== {path} ==")
    for i in range(0, min(len(rec) - W, 13 * RATE), W):
        v = pdb(rec[i:i+W])
        bar = '#' * max(0, int((v + 90) / 2))
        print(f"  {i/RATE:5.1f}s {v:7.1f} dB {bar}")
