#!/usr/bin/env python3
"""버스트 신호 대비 녹음의 에코 성분 분석.

녹음에서 각 버스트 시각 주변 에너지를 잰다:
- burst window: 버스트가 재생되는 구간 (스피커→마이크 유입 확인)
- gap window:   버스트 사이 정숙 구간 (잔향/처리 지연 확인)

에코 억제량 = gap/burst 에너지 비.

사용법: analyze_burst.py <녹음.f32> <burst.f32>
"""
import struct
import sys
import math

fs = 48000

def load_f32(path):
    with open(path, "rb") as f:
        data = f.read()
    n = len(data) // 4
    return struct.unpack(f"<{n}f", data[: n * 4])

def rms_db(x):
    if not x:
        return -999
    r = math.sqrt(sum(v * v for v in x) / len(x))
    return 20 * math.log10(r) if r > 0 else -999

def main():
    rec = load_f32(sys.argv[1])
    bursts = load_f32(sys.argv[2])
    BURST = int(0.4 * fs)
    GAP = int(0.8 * fs)
    PERIOD = BURST + GAP

    # 원본에서 버스트 위치 파악 (에너지로)
    orig_positions = []
    i = 0
    while i < len(bursts):
        if any(abs(v) > 0.1 for v in bursts[i:i+480]):
            orig_positions.append(i)
            i += PERIOD
        else:
            i += 480
    print(f"원본 버스트 수: {len(orig_positions)}")

    # 녹음에서 각 버스트 탐색: 원본 위치 + 오프셋 ±3s 스캔
    # 녹음 시작 시각이 far 재생 시작과 다르므로 상호상관으로 정렬
    # 간단화: 녹음 전체에서 1kHz/2kHz 성분 에너지 프로파일 → 피크 = 버스트
    WIN = 2400  # 50ms
    prof = []
    for s in range(0, len(rec) - WIN, WIN):
        prof.append(rms_db(rec[s:s+WIN]))

    # 버스트성 피크(프로파일에서 -40dB 초과하는 구간) 카운트
    thr = -60
    peaks = []
    in_peak = False
    for idx, v in enumerate(prof):
        if v > thr and not in_peak:
            peaks.append(idx * WIN)
            in_peak = True
        elif v <= thr:
            in_peak = False
    print(f"녹음 버스트 피크 수(thr {thr}dB): {len(peaks)} @ {[f'{p/fs:.2f}s' for p in peaks[:10]]}")

    if len(peaks) < 2:
        print("버스트를 못 찾음 — 에코가 매우 낮거나 녹음 실패")
        print("프로파일:", " ".join(f"{v:.0f}" for v in prof[:40]))
        return

    # 각 피크 주변: burst 에너지 vs 이후 0.3~0.8s 에너지(처리 지연 고려)
    suppress = []
    for p in peaks:
        b = rms_db(rec[p:p+int(0.3*fs)])
        # 다음 버스트 직전 구간 (잔향+누화)
        g_start = p + int(0.45*fs)
        g_end = min(p + int(0.7*fs), len(rec))
        g = rms_db(rec[g_start:g_end])
        if b > -60:
            suppress.append((p, b, g, b - g))
    print(f"{'위치':>8} {'burst':>8} {'gap':>8} {'차이dB':>7}")
    for p, b, g, d in suppress:
        print(f"{p/fs:8.2f}s {b:8.1f} {g:8.1f} {d:7.1f}")
    if suppress:
        avg = sum(s[3] for s in suppress) / len(suppress)
        print(f"평균 억제: {avg:.1f} dB (높을수록 버스트가 확실히 구분됨 = 에코 없음)")

if __name__ == "__main__":
    main()
