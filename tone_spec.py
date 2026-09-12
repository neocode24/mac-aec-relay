#!/usr/bin/env python3
"""정렬 불필요 에코 측정: 스펙트럼 빈 비교.

far 버스트(순수 톤 1k/2k/500/4k)가 스피커로 재생될 때
BH2 녹음 전체에서 각 톤 주파수의 에너지를 Goertzel로 측정하고,
인접 주파수(±40Hz, 톤 없음)를 노이즈 참조로 삼아 SNR을 낸다.

- SNR > 0 (톤이 뚜렷) → 에코가 마이크에 유입되고 있다
- SNR ≈ 0 → 톤 없음 = 에코가 플로어 아래

bypass(처리 없음)에서 톤이 안 보이면 측정 체인 자체가 무효다.

사용법: tone_spec.py <rec.f32> [skip_seconds]
"""
import struct
import sys
import math

fs = 48000

def load_f32(path):
    with open(path, "rb") as f:
        data = f.read()
    n = len(data) // 4
    return list(struct.unpack(f"<{n}f", data[: n * 4]))

def goertzel_amp(x, freq):
    n = len(x)
    if n == 0:
        return 0.0
    w = 2 * math.pi * freq / fs
    coeff = 2 * math.cos(w)
    s1 = s2 = 0.0
    for v in x:
        s0 = v + coeff * s1 - s2
        s2 = s1
        s1 = s0
    power = s1 * s1 + s2 * s2 - coeff * s1 * s2
    return math.sqrt(max(power, 0)) / (n / 2)

def main():
    rec = load_f32(sys.argv[1])
    skip = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    rec = rec[int(skip * fs):]
    if len(rec) < fs:
        print("녹음이 너무 짧음")
        return

    targets = [500.0, 1000.0, 2000.0, 4000.0]
    print(f"분석 길이: {len(rec)/fs:.2f}s (skip {skip:.1f}s)")
    print(f"{'freq':>6} {'tone dB':>9} {'ref dB':>9} {'SNR':>7}")
    snrs = []
    for f in targets:
        a = goertzel_amp(rec, f)
        # 참조: 톤이 아닌 인접 주파수 두 개 평균
        r1 = goertzel_amp(rec, f - 40)
        r2 = goertzel_amp(rec, f + 40)
        ref = (r1 + r2) / 2
        adb = 20 * math.log10(a) if a > 0 else -999
        rdb = 20 * math.log10(ref) if ref > 0 else -999
        snr = adb - rdb
        snrs.append(snr)
        print(f"{f:6.0f} {adb:9.1f} {rdb:9.1f} {snr:7.1f}")
    avg = sum(snrs) / len(snrs)
    print(f"\n평균 SNR: {avg:.1f} dB  ({'톤 검출 = 에코 유입' if avg > 3 else '톤 없음 = 에코가 플로어 아래'})")

if __name__ == "__main__":
    main()
