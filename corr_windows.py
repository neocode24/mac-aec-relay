#!/usr/bin/env python3
"""corr_windows.py — rec 대신 far 템플릿 상관을 창별로: 성공/실패 런의
정합 지연을 재구성한다. AEC rec의 잔여 에코 lag는 'mic 대비 far' 지연.
여기에 우리가 준 refdelay(전기)를 더하면 필터가 본 effective delay.

실패 런: 잔여 lag ≈ +233~326ms (far 기준). 우리 refdelay 300/320ms를
더하면 533~646ms? 아니 — rec의 lag는 'far 원본 대비 잔여 에코 위치'다.
필터가 못 잡은 에코가 그 만큼 뒤에 있다는 뜻.
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

for s in range(0, min(len(rec) - win, 14 * fs), win):
    seg = rec[s : s + win]
    # far 전체를 템플릿 소스로: far의 해당 구간이 어디에 상관最大的인지
    # → rec 창을 far 길이 전체와 상관
    R = np.fft.rfft(seg, N)
    best = (None, -1)
    for fs_start in range(0, len(far) - win, win):
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
    print(f"rec {s/fs:5.1f}s → far {pos/fs:6.3f}s  corr {c:.3f}  (rec-far 오프셋 {(s-pos)/fs*1000:+8.1f} ms)")
