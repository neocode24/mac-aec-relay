#!/usr/bin/env python3
"""measure_latency.py — 버스트 도달 시각으로 에코 경로 지연 측정.

far 원본(버스트 파일)과 relay 녹음(rec, bypass 모드 권장)을 읽어
각 버스트의 시작 에지를 감지해 시각 차의 중앙값으로 경로 지연을 잡는다.

사용법: python3 measure_latency.py <rec.f32> <far.f32> [--fs 48000]
출력: 버스트별 도달 시각, far 대비 지연(ms), 중앙값
"""
import sys
import struct
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

def edge_times(x, fs, thresh_db=-40.0, hang_ms=150.0, min_gap_ms=300.0):
    """에너지가 임계를 넘는 구간의 시작 시각 목록."""
    win = max(1, int(0.005 * fs))
    env = np.convolve(np.abs(x), np.ones(win) / win, mode="same")
    if env.max() <= 0:
        return []
    thresh = env.max() * 10 ** (thresh_db / 20.0)
    on = env > thresh
    hang = int(hang_ms / 1000 * fs)
    min_gap = int(min_gap_ms / 1000 * fs)
    edges = []
    i = 0
    last = -10 ** 9
    while i < len(on):
        if on[i] and i - last >= min_gap:
            edges.append(i)
            last = i
            i += hang
        else:
            i += 1
    return edges

def main():
    rec_path, far_path = sys.argv[1], sys.argv[2]
    fs = 48000
    rec = load_f32(rec_path)
    far = load_f32(far_path)
    re_ = edge_times(rec, fs)
    fe = edge_times(far, fs)
    print(f"rec={len(rec)/fs:.2f}s far={len(far)/fs:.2f}s")
    print(f"far 버스트 {len(fe)}개: {[f'{t/fs:.3f}s' for t in fe]}")
    print(f"rec 버스트 {len(re_)}개: {[f'{t/fs:.3f}s' for t in re_]}")
    if not fe or not re_:
        print("버스트 감지 실패")
        return
    n = min(len(fe), len(re_))
    # far 시작 대비 rec 도달 지연 (음수면 rec이 앞섬 — 원본 기준 보정 불가 상태)
    lags = [(re_[i] - fe[i]) / fs * 1000.0 for i in range(n)]
    for i in range(n):
        print(f"  burst {i+1}: far {fe[i]/fs:7.3f}s → rec {re_[i]/fs:7.3f}s  지연 {lags[i]:+8.1f} ms")
    print(f"지연 중앙값: {np.median(lags):+.1f} ms (min {min(lags):+.1f}, max {max(lags):+.1f})")

if __name__ == "__main__":
    main()
