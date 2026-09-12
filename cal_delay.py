#!/usr/bin/env python3
"""cal_delay.py — rec와 far의 세그먼트 상관으로 세밀 지연 스윕.

방법: rec(bypass)를 세그먼트로 자르고 far 안에서의 최대 상관 위치를
샘플 단위로 찾는다. cross-correlation을 FFT로 계산해 서브-샘플은
 아니어도 1샘플 단위 지연을 얻는다.
"""
import sys
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

fs = 48000
rec = load_f32("/tmp/lat_rec.f32")
far = load_f32("/tmp/burst_far.f32")

# far의 두 번째 버스트(1.2s) 근처 0.3s를 템플릿으로
tpl_start = int(1.15 * fs)
tpl = far[tpl_start : tpl_start + int(0.3 * fs)]
tpl = tpl - tpl.mean()

# FFT 상관: rec 전체와 tpl의 상관
n = len(rec) + len(tpl)
N = 1 << int(np.ceil(np.log2(n)))
T = np.fft.rfft(tpl, N)
R = np.fft.rfft(rec, N)
xc = np.fft.irfft(np.conj(T) * R, N)
# 최대 위치 = tpl가 rec에서 발견된 시작 지점
peak = int(np.argmax(xc))
if peak > N // 2:
    peak -= N
corr_val = xc[peak] / (np.linalg.norm(tpl) * np.linalg.norm(rec[max(0, peak): peak + len(tpl)]) + 1e-12)
print(f"tpl(1.15s far 버스트) → rec 위치: {peak} samples = {peak/fs*1000:.1f} ms")
print(f"첫 감지: mic 도달 - far 버스트(1.197s) = {peak/fs - 1.197:.3f}s → {(peak/fs - 1.197)*1000:+.1f} ms")
print(f"corr={corr_val:.3f}")

# 여러 버스트에 반복
print()
print("버스트별 (rec 위치 - far 원래 위치):")
for k, fstart in enumerate([0.0, 1.197, 2.400, 3.597, 4.797, 5.997, 7.199, 8.397]):
    ts = int((fstart + 0.0) * fs)
    t_end = ts + int(0.35 * fs)
    if t_end > len(far):
        break
    t = far[ts:t_end]
    t = t - t.mean()
    T = np.fft.rfft(t, N)
    xc = np.fft.irfft(np.conj(T) * R, N)
    pk = int(np.argmax(xc))
    if pk > N // 2:
        pk -= N
    # rec 위치 pk / fs. far 원래 fstart. 지연 = pk/fs - fstart - (루프 보정)
    lag_ms = (pk / fs - fstart) * 1000
    print(f"  burst{k+1} far@{fstart:.3f}s → rec@{pk/fs:.3f}s  lag {lag_ms:+8.1f} ms")
