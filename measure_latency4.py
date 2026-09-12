#!/usr/bin/env python3
"""measure_latency4.py — 정밀 지연 측정 (템플릿 상관, 이동 평균 보간).

rec의 각 버스트 구간을 far 템플릿과 FFT 상관해 도달 지연을 잡는다.
far는 루프 재생되므로 lag를 루프 길이로 모듈로 환산한다.
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
loop = len(far)

# far 첫 버스트의 안정 구간 0.05~0.30s를 템플릿으로
tpl = far[int(0.05 * fs) : int(0.30 * fs)].copy()
tpl -= tpl.mean()
tpln = np.linalg.norm(tpl)

# rec을 1초 세그먼트로 자르고 각각 상관
N = 1 << int(np.ceil(np.log2(len(rec) + len(tpl))))
R = np.fft.rfft(rec, N)
T = np.fft.rfft(tpl, N)
xc = np.fft.irfft(np.conj(T) * R, N)

# xc[k] = sum tpl*[n] * rec[n+k] → 최대 k가 템플릿 시작 위치
# 국소 최대 찾기 (루프마다 하나씩)
thr = xc.max() * 0.3
peaks = []
k = 0
while k < len(xc):
    if xc[k] > thr:
        # 국소 최대
        j = k
        while j + 1 < len(xc) and xc[j + 1] >= xc[j]:
            j += 1
        peaks.append(j)
        k = j + int(0.5 * fs)
    else:
        k += 1

print(f"상관 피크 {len(peaks)}개")
# far에서 템플릿이 나온 루프 상 위치: 0.05s.
# rec 위치 pk/fs에서 0.05를 빼면 'far 버스트 시작의 rec 시각'.
# 경로 지연 = (rec 시각 - 0.05s) - k*loop (k=0,1,2,...)
delays = []
for pk in peaks:
    t = pk / fs
    k = int(t // (loop / fs))
    d = (t - 0.05) - k * (loop / fs)
    delays.append(d * 1000)
    print(f"  rec {t:7.3f}s  루프#{k}  지연 {d*1000:+8.1f} ms")
if delays:
    print(f"지연 median {np.median(delays):+.1f} ms / min {min(delays):+.1f} / max {max(delays):+.1f}")
