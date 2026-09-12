#!/usr/bin/env python3
"""measure_latency5.py — 정밀 지연 측정 (주파수별 버스트 템플릿, 개별 상관).

버스트마다 주파수가 다르다(1k,2k,0.5k,4k 순환). 각 버스트를 자기 주파수
대역으로 통과한 뒤 상관하면 유령 피크가 사라진다.
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
loop_n = len(far)
BURST = int(0.4 * fs)
GAP = int(0.8 * fs)
PERIOD = BURST + GAP  # 1.2s
FREQS = [1000, 2000, 500, 4000, 1000, 2000, 500, 4000]

def bandpass(x, lo, hi):
    X = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / fs)
    X[(freqs < lo) | (freqs > hi)] = 0
    return np.fft.irfft(X, n=len(x))

N = 1 << int(np.ceil(np.log2(len(rec) + BURST)))
R_all = np.fft.rfft(rec, N)

results = []
# rec 시각 t에서 가장 가까운 'far 루프 내 버스트 k'를 찾는 방식:
# far의 버스트 b (0<=b<8) 시작 = b*PERIOD (far 파일 기준)
for b in range(8):
    f = FREQS[b]
    lo, hi = f * 0.8, f * 1.25
    tpl = far[b * PERIOD + int(0.02 * fs) : b * PERIOD + int(0.35 * fs)].copy()
    tpl = bandpass(tpl, lo, hi)
    tpl -= tpl.mean()
    tpln = np.linalg.norm(tpl)
    if tpln < 1e-9:
        continue
    T = np.fft.rfft(tpl, N)
    xc = np.fft.irfft(np.conj(T) * R_all, N)
    # 전체 피크 대신 최대만
    pk = int(np.argmax(xc))
    corr = xc[pk] / (tpln * np.linalg.norm(rec[pk : pk + len(tpl)]) + 1e-12)
    t_rec = pk / fs
    # 이 rec 위치는 'far의 버스트 b가 n루프째 재생된 것'. 지연 = t_rec - (b*PERIOD/fs)
    # 루프 보정: 총 시간에서 k*loop를 뺀 나머지와 비교
    far_t = b * PERIOD / fs
    k = round((t_rec - far_t - 0.36) / (loop_n / fs))
    delay = (t_rec - far_t) - k * (loop_n / fs)
    results.append((b + 1, f, t_rec, delay * 1000, corr))

print(f"{'burst':>5} {'freq':>5} {'rec시각':>9} {'지연(ms)':>9} {'corr':>6}")
for b, f, t, d, c in results:
    print(f"{b:5d} {f:5d} {t:9.3f} {d:+9.1f} {c:6.3f}")
ds = [d for *_, d, _ in [(b, f, t, d, c) for b, f, t, d, c in results]]
if ds:
    print(f"지연 median {np.median(ds):+.1f} ms / min {min(ds):+.1f} / max {max(ds):+.1f}")
