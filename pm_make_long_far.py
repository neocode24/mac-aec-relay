#!/usr/bin/env python3
"""긴 발화 참조 신호를 만든다.

기존 far_test.f32는 짧은 신호라 "긴 대화에서 에코가 샌다"를 재현하지 못했다.
이 파일은 8초 연속 발화 + 1초 침묵을 3회 반복해 실통화의 긴 발화 구간을 흉내낸다.
음성 대역(200-3400Hz)을 채우도록 여러 성분을 섞는다.
"""
import math
import struct
import sys

RATE = 48000
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/far_long.f32"

samples = []
for block in range(3):
    # 8초 연속 발화
    n = RATE * 8
    for i in range(n):
        t = i / RATE
        # 기본 주파수를 천천히 흔들어 단조로운 톤이 되지 않게 한다
        f0 = 140 + 40 * math.sin(2 * math.pi * 0.7 * t)
        v = 0.0
        for h, amp in ((1, 1.0), (2, 0.6), (3, 0.4), (5, 0.25), (8, 0.15), (13, 0.1)):
            v += amp * math.sin(2 * math.pi * f0 * h * t)
        # 음절 리듬(4Hz)로 진폭 변조
        env = 0.5 + 0.5 * abs(math.sin(2 * math.pi * 4 * t))
        samples.append(0.28 * env * v / 2.5)
    # 1초 침묵
    samples.extend([0.0] * RATE)

with open(OUT, "wb") as f:
    f.write(struct.pack("<%df" % len(samples), *samples))

print("%s  %.1f초  %d샘플" % (OUT, len(samples) / RATE, len(samples)))
