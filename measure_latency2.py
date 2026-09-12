#!/usr/bin/env python3
"""measure_latency2.py — 상호상관 기반 에코 지연 측정 (개정판).

rec의 각 버스트 구간을 far 전체와 상호상관해 개별 지연을 잡는다.
far는 루프 재생되므로 여러 루프 위치를 다 검색한다.
"""
import sys
import numpy as np

def load_f32(path):
    data = open(path, "rb").read()
    n = len(data) // 4
    return np.frombuffer(data[: n * 4], dtype="<f4").astype(np.float64)

def xcorr_lag(ref, sig):
    """ref(짧은 창)가 sig 안의 어디에 있는지 정규화 상관으로."""
    n = len(ref)
    ref = ref - ref.mean()
    rn = np.sqrt(np.sum(ref * ref))
    if rn < 1e-12:
        return None
    best = (None, -2.0)
    m = len(sig)
    for start in range(0, m - n, 240):
        w = sig[start : start + n]
        w = w - w.mean()
        wn = np.sqrt(np.sum(w * w))
        if wn < 1e-12:
            continue
        c = np.abs(np.dot(ref, w) / (rn * wn))
        if c > best[1]:
            best = (start, c)
    return best

def main():
    rec_path, far_path = sys.argv[1], sys.argv[2]
    fs = 48000
    rec = load_f32(rec_path)
    far = load_f32(far_path)
    # rec에서 강한 활동 구간 검출: 50ms 윈도우 에너지 상위
    win = int(0.05 * fs)
    nwin = len(rec) // win
    energy = np.array([np.sum(rec[i * win : (i + 1) * win] ** 2) for i in range(nwin)])
    thr = energy.max() * 0.05
    active = energy > thr
    # 연속 활동 구간을 버스트로 묶기 (300ms 이상 간격으로 분리)
    bursts = []
    i = 0
    while i < nwin:
        if active[i]:
            j = i
            while j < nwin and (active[j] or (j + 6 < nwin and energy[j : j + 6].max() > thr)):
                j += 1
            bursts.append((i * win, j * win))
            i = j + 6
        else:
            i += 1
    print(f"rec 활동 구간 {len(bursts)}개")
    lags = []
    for (a, b) in bursts[:12]:
        seg = rec[a : b]
        if len(seg) < 0.05 * fs:
            continue
        r = xcorr_lag(seg, far)
        if r is None:
            continue
        start, c = r
        # rec의 이 위치 시각 = a/fs. far의 start/fs와 대응.
        # 지연 = rec시각 - far시각. far 루프 길이만큼 모듈로 비교는 별도 표기
        loop = len(far) / fs
        lag_s = a / fs - start / fs
        print(f"  rec {a/fs:7.3f}s ↔ far {start/fs:7.3f}s  corr={c:.3f}  lag={lag_s*1000:+9.1f} ms  (loop 보정 시 {(lag_s % loop)*1000:+9.1f} ms)")
        lags.append(lag_s * 1000)
    if lags:
        loop = len(far) / fs
        mod = [((l / 1000) % loop) * 1000 for l in lags]
        print(f"lag 중앙값: {np.median(lags):+.1f} ms | loop 모듈로 중앙값: {np.median(mod):+.1f} ms")

if __name__ == "__main__":
    main()
