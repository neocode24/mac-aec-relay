#!/usr/bin/env python3
"""measure_latency3.py — far↔mic 지연 측정 (버스트 흐름 기준, 루프 무관).

원리: far가 DELL에서 나오면 방에서 소리가 된다. far 버스트(0.5-4kHz 톤)
대역만 FFT 대역통과로 골라 mic 신호(bypass rec = mic 그대로)에서 시작
시각을 찾는다. far는 루프 재생되지만 루프 위치가 아니라 '실제 재생된'
버스트 시각 흐름을 쓰므로 루프 위치는 무관하다.

경로 지연 = rec의 k번째 루프 첫 버스트 시각 - far의 첫 버스트 시각(≈0)
에서 (k-1)*loop를 뺀 값.
"""
import sys
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

def bandpass(x, fs, lo, hi):
    X = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / fs)
    X[(freqs < lo) | (freqs > hi)] = 0
    return np.fft.irfft(X, n=len(x))

fs = 48000
rec = load_f32(sys.argv[1])
far = load_f32(sys.argv[2])

rec_b = bandpass(rec, fs, 600, 4200)
far_b = bandpass(far, fs, 600, 4200)

def edges(x, rel_thr_db=-30, hang_ms=350, min_gap_ms=1000):
    env = np.abs(x)
    win = int(0.01 * fs)
    env = np.convolve(env, np.ones(win) / win, mode="same")
    thr = env.max() * 10 ** (rel_thr_db / 20)
    on = env > thr
    hang = int(hang_ms / 1000 * fs)
    min_gap = int(min_gap_ms / 1000 * fs)
    out = []
    i = 0
    last = -10 ** 9
    while i < len(on):
        if on[i] and i - last >= min_gap:
            out.append(i)
            last = i
            i += hang
        else:
            i += 1
    return out

fe = edges(far_b)
re_ = edges(rec_b)
print(f"far 버스트: {[f'{t/fs:.3f}' for t in fe]}")
print(f"rec 버스트: {[f'{t/fs:.3f}' for t in re_]}")
loop = len(far) / fs
print(f"far 루프 길이 {loop:.2f}s")
if fe and re_:
    t0 = re_[0] / fs
    print(f"rec 첫 버스트 {t0:.3f}s")
    devs = []
    for t in re_:
        k = round((t / fs - t0) / loop)
        dev = (t / fs - t0) - k * loop
        devs.append(dev)
        print(f"  rec {t/fs:7.3f}s  루프#{k}  편차 {dev*1000:+7.1f} ms")
    print(f"루프 간격 정합성 편차: min {min(devs)*1000:+.1f} / max {max(devs)*1000:+.1f} ms")
    print(f"경로 지연(첫 버스트 기준): {t0*1000:.1f} ms")
