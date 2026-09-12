#!/usr/bin/env python3
"""마이크 녹음과 far 원본의 상호상관으로 실제 에코 지연을 잰다.

speexdsp AEC는 참조가 마이크보다 '먼저' 도착해야 하고, 그 시간차가
filter length(tail) 안에 들어와야 에코를 제거할 수 있다.

측정된 지연이
  - 음수  : 참조가 마이크보다 늦게 들어온다 -> AEC 원리상 불가능. 정렬 오류
  - tail 초과 : 필터가 에코를 표현 못 함 -> tail을 키워야 함
  - 0~tail 내 : 정렬은 맞음. 억제 부진은 다른 원인

사용법: pm_delay_probe.py <mic녹음.f32> <far원본.f32> [최대탐색ms]
"""
import sys
import struct
import math


def load(path):
    with open(path, "rb") as f:
        b = f.read()
    n = len(b) // 4
    return list(struct.unpack(f"<{n}f", b[: n * 4]))


def energy_window(x, win, hop):
    """신호 에너지가 가장 큰 구간의 시작 인덱스를 찾는다."""
    best, bi = -1.0, 0
    i = 0
    while i + win <= len(x):
        e = sum(v * v for v in x[i : i + win : 8])
        if e > best:
            best, bi = e, i
        i += hop
    return bi


def xcorr_lag(mic, far, sr, max_lag_ms):
    """far를 기준으로 mic가 얼마나 뒤에 오는지 래그(샘플)를 찾는다."""
    win = min(sr, len(mic) // 2, len(far) // 2)
    if win < sr // 4:
        return None, 0.0
    fi = energy_window(far, win, sr // 20)
    ref = far[fi : fi + win]
    rm = sum(ref) / len(ref)
    ref = [v - rm for v in ref]
    rnorm = math.sqrt(sum(v * v for v in ref)) or 1.0

    max_lag = int(sr * max_lag_ms / 1000)
    best_c, best_l = -2.0, 0
    step = 16  # 거친 탐색
    for lag in range(0, max_lag, step):
        s = fi + lag
        if s + win > len(mic):
            break
        seg = mic[s : s + win]
        sm = sum(seg) / len(seg)
        num = sum((a - sm) * b for a, b in zip(seg, ref))
        den = (math.sqrt(sum((a - sm) ** 2 for a in seg)) or 1.0) * rnorm
        c = num / den
        if c > best_c:
            best_c, best_l = c, lag
    # 정밀 탐색
    for lag in range(max(0, best_l - step), min(max_lag, best_l + step)):
        s = fi + lag
        if s + win > len(mic):
            break
        seg = mic[s : s + win]
        sm = sum(seg) / len(seg)
        num = sum((a - sm) * b for a, b in zip(seg, ref))
        den = (math.sqrt(sum((a - sm) ** 2 for a in seg)) or 1.0) * rnorm
        c = num / den
        if c > best_c:
            best_c, best_l = c, lag
    return best_l, best_c


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    mic = load(sys.argv[1])
    far = load(sys.argv[2])
    max_ms = int(sys.argv[3]) if len(sys.argv) > 3 else 600
    sr = 48000
    lag, c = xcorr_lag(mic, far, sr, max_ms)
    if lag is None:
        print("신호가 너무 짧다")
        sys.exit(1)
    print(f"최대 상관 = {c:.3f}  래그 = {lag} 샘플 ({lag/48:.1f} ms)")
    if c < 0.15:
        print("=> 상관이 약하다. 에코 성분이 뚜렷하지 않거나 정렬 불가")
    elif lag / 48 > 400:
        print("=> 지연이 tail(400ms)을 넘는다. tail을 키워야 한다")
    else:
        print("=> 지연은 tail 안에 있다. 억제 부진은 다른 원인")


if __name__ == "__main__":
    main()
