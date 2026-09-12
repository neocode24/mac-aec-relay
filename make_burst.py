#!/usr/bin/env python3
"""톤 버스트 테스트 신호 생성: 1kHz/2kHz 톤 버스트 + 정숙 구간 교대.
에코 측정용 — 정확한 시각에 정확한 주파수가 나오므로 상관/에너지 분석이 쉽다.

사용법: make_burst.py <출력.f32> [버스트수]
출력: 48kHz mono f32le. 버스트 1개 = 0.4s 톤 + 0.8s 무음.
"""
import struct
import sys
import math

fs = 48000
BURST = int(0.4 * fs)
GAP = int(0.8 * fs)
FREQS = [1000.0, 2000.0, 500.0, 4000.0, 1000.0, 2000.0, 500.0, 4000.0]

def main():
    out_path = sys.argv[1]
    n_bursts = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    samples = []
    for b in range(n_bursts):
        f = FREQS[b % len(FREQS)]
        # 램프 인/아웃 5ms로 클릭 방지
        ramp = int(0.005 * fs)
        for i in range(BURST):
            env = 1.0
            if i < ramp:
                env = i / ramp
            elif i > BURST - ramp:
                env = (BURST - i) / ramp
            samples.append(0.5 * env * math.sin(2 * math.pi * f * i / fs))
        samples.extend([0.0] * GAP)
    with open(out_path, "wb") as f:
        f.write(struct.pack(f"<{len(samples)}f", *samples))
    print(f"{out_path}: {len(samples)} samples = {len(samples)/fs:.2f}s, {n_bursts} bursts")

if __name__ == "__main__":
    main()
