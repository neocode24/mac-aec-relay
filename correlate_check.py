#!/usr/bin/env python3
# correlate_check.py — mic(ref)와 rec의 상관으로 AEC 지연 추정.
# relay 로그의 ring 백로그(ref-mic)가 곧 처리 시점 오프셋이다.
# 여기서는 파일 기반으로 far 원본과 rec의 최대 상관 지점을 잡는다.
import sys, struct
import math

def load_f32(path):
    data = open(path, 'rb').read()
    n = len(data) // 4
    vals = struct.unpack(f'<{n}f', data[:n*4])
    return vals

far = load_f32('/tmp/far_test.f32')
rec = load_f32(sys.argv[1] if len(sys.argv) > 1 else '/tmp/rec_aec_2.f32')
RATE = 48000
# rec의 8.4s 지점 버스트가 far의 어느 위치와 상관最大的가?
def norm(x):
    m = max(abs(v) for v in x) or 1e-9
    return [v / m for v in x]

# rec 8.3-9.0s 윈도우
r0 = int(8.3 * RATE); r1 = int(9.0 * RATE)
rw = norm(rec[r0:r1])
best = (0, -2)
step = 240  # 5ms
for lag in range(0, len(far) - len(rw), step):
    fw = norm(far[lag:lag+len(rw)])
    # 정규화 상관 (내적)
    s = sum(a * b for a, b in zip(rw, fw)) / len(rw)
    if s > best[1]:
        best = (lag, s)
print(f"최대 상관 lag={best[0]} samples = {best[0]/RATE:.3f}s, corr={best[1]:.4f}")
print(f"rec 윈도우 시작 8.3s → far 내 위치 {best[0]/RATE:.3f}s")
