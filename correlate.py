#!/usr/bin/env python3
"""상관 기반 에코 측정 (ERLE 근사).

BH2에 녹음된 신호(릴레이 처리 후)와 far 원본 사이의 정규화 상관을
시간 지연 래그로 스캔해 최대 상관을 찾는다. 에코가 존재하면 특정
래그에서 상관이 뚜렷해진다. 상관 계수로 에코 세기를 추정한다.

사용법: correlate.py <bh2녹음.f32> <far원본.f32>
출력: 최대 |상관|, 해당 래그(ms), 에코 성분 감쇠 추정 dB
"""
import sys
import struct

def load_f32(path):
    with open(path, "rb") as f:
        data = f.read()
    n = len(data) // 4
    return struct.unpack(f"<{n}f", data[: n * 4])

def norm(x):
    m = max(abs(v) for v in x) or 1.0
    return [v / m for v in x]

def corr(x, y):
    # x, y 같은 길이 정규화 상관
    n = len(x)
    mx = sum(x) / n
    my = sum(y) / n
    num = sum((a - mx) * (b - my) for a, b in zip(x, y))
    dx = sum((a - mx) ** 2 for a in x) ** 0.5
    dy = sum((b - my) ** 2 for b in y) ** 0.5
    return num / (dx * dy) if dx > 0 and dy > 0 else 0.0

def main():
    rec_path, far_path = sys.argv[1], sys.argv[2]
    rec = load_f32(rec_path)
    far = load_f32(far_path)
    fs = 48000

    # 10초 등 길이 제한
    L = min(len(rec), len(far), 10 * fs)
    rec = rec[:L]
    far = far[:L]
    print(f"rec={len(rec)/fs:.2f}s far={len(far)/fs:.2f}s")

    # 대역 제한(단순 이동평균) 후 상관 — 음성 대역 기준
    def lowpass(x, k=5):
        out = []
        acc = 0.0
        q = []
        for v in x:
            q.append(v)
            acc += v
            if len(q) > k:
                acc -= q.pop(0)
            out.append(acc / len(q))
        return out

    rec_f = lowpass(norm(rec))
    far_f = lowpass(norm(far))

    # 래그 스캔: -1000 ~ +1000 샘플 (±21ms)
    best = (0.0, 0)
    seg = 4 * fs  # 4초 세그먼트
    lags = range(-1000, 1001, 4)
    for lag in lags:
        cs = []
        for start in range(0, L - seg, seg):
            r = rec_f[start : start + seg]
            s = far_f[start + lag : start + lag + seg] if start + lag >= 0 and start + lag + seg <= L else None
            if s is None or len(s) != seg:
                continue
            cs.append(corr(r, s))
        if cs:
            m = sum(cs) / len(cs)
            if abs(m) > abs(best[0]):
                best = (m, lag)

    c, lag = best
    print(f"max_corr={c:+.4f} lag={lag} samples ({lag/fs*1000:.1f} ms)")
    if abs(c) > 0.05:
        import math
        db = 20 * math.log10(abs(c))
        print(f"에코 상관 성분 {db:.1f} dB (상관 기준)")
    else:
        print("유의미한 상관 없음 — 에코가 잡음 레벨 아래")

if __name__ == "__main__":
    main()
