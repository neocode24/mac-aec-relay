#!/usr/bin/env python3
"""정밀 에코 측정: 순수 톤 버스트의 주파수 성분으로 에코 레벨 측정.

far 버스트(1k/2k/500/4k 순수 톤 0.4s + 0.8s 갭)가 스피커로 재생될 때
BH2 녹음에서 그 톤이 얼마나 남아 있나를 Goertzel 알고리즘으로 측정.

정렬: 에너지 봉투 상호상관으로 far↔rec 시간 오프셋을 맞춘다.

사용법: tone_echo.py <rec.f32> <far.f32>
출력: 버스트별 톤 레벨(dBFS), 평균, 노이즈 플로어, SNR
"""
import struct
import sys
import math

fs = 48000
BURST = int(0.4 * fs)
GAP = int(0.8 * fs)
PERIOD = BURST + GAP
FREQS = [1000.0, 2000.0, 500.0, 4000.0] * 2  # make_burst.py 순서

def load_f32(path):
    with open(path, "rb") as f:
        data = f.read()
    n = len(data) // 4
    return list(struct.unpack(f"<{n}f", data[: n * 4]))

def goertzel(x, freq, fs_=48000):
    """신호 x에서 freq 성분의 진폭 반환."""
    n = len(x)
    if n == 0:
        return 0.0
    k = round(n * freq / fs_)
    w = 2 * math.pi * k / n
    coeff = 2 * math.cos(w)
    s1 = s2 = 0.0
    for v in x:
        s0 = v + coeff * s1 - s2
        s2 = s1
        s1 = s0
    power = s1 * s1 + s2 * s2 - coeff * s1 * s2
    return math.sqrt(max(power, 0)) / (n / 2)

def env(x, win=480):
    """절대값 이동평균 봉투."""
    out = []
    acc = 0.0
    q = []
    for v in x:
        q.append(abs(v))
        acc += abs(v)
        if len(q) > win:
            acc -= q.pop(0)
        out.append(acc / len(q))
    return out

def align_offset(rec, far):
    """rec 봉투에서 첫 버스트 상승 위치(샘플) 탐색."""
    e = env(rec)
    base = sum(e[:int(0.5*fs)]) / max(int(0.5*fs), 1)  # 첫 0.5s 평균 = 노이즈 기준
    thr = base * 3
    for i in range(len(e)):
        if e[i] > thr:
            return i
    return None

def main():
    rec = load_f32(sys.argv[1])
    far = load_f32(sys.argv[2])

    off = align_offset(rec, far)
    if off is None:
        print("정렬 실패: 녹음에서 버스트 상승을 못 찾음")
        return
    print(f"rec 내 첫 버스트 시작: {off/fs:.3f}s (far 대비 지연)")

    # far는 t=0부터 버스트. rec의 버스트 시작은 off.
    # 각 버스트 i: rec 위치 = off + i*PERIOD + 공기 경로 지연(수 ms) 무시
    results = []
    i = 0
    while True:
        start = off + i * PERIOD
        tone_start = start + int(0.05 * fs)   # 램프 이후 안정 구간
        tone_end = start + int(0.35 * fs)
        gap_start = start + int(0.5 * fs)     # 버스트 직후 잔향 구간 종료 후
        gap_end = start + int(1.1 * fs)
        if tone_end > len(rec):
            break
        f = FREQS[i % len(FREQS)]
        seg = rec[tone_start:tone_end]
        amp = goertzel(seg, f)
        tone_db = 20 * math.log10(amp) if amp > 0 else -999
        # 노이즈: 톤 주파수 성분을 갭에서 측정
        if gap_end <= len(rec):
            nseg = rec[gap_start:gap_end]
            namp = goertzel(nseg, f)
            noise_db = 20 * math.log10(namp) if namp > 0 else -999
        else:
            noise_db = -999
        results.append((i, f, tone_db, noise_db))
        i += 1

    print(f"{'#':>3} {'freq':>6} {'tone dB':>9} {'noise dB':>9} {'SNR':>7}")
    tones = []
    for idx, f, t, n in results:
        snr = t - n if n > -900 else 999
        print(f"{idx:3d} {f:6.0f} {t:9.1f} {n:9.1f} {snr:7.1f}")
        tones.append(t)
    if tones:
        avg = sum(tones) / len(tones)
        print(f"\n평균 톤(에코) 레벨: {avg:.1f} dBFS  — 낮을수록 좋음")

if __name__ == "__main__":
    main()
