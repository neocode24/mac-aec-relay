#!/usr/bin/env python3
"""녹음 파일을 구간별로 나눠 레벨을 재고, 긴 발화에서 에코가 새는지 본다.

pm_make_long_far.py가 만든 참조(8초 발화 + 1초 침묵 x3)에 맞춰
각 발화 블록의 전반부와 후반부를 따로 잰다.
발화가 길어질수록 억제가 무너지면 후반부가 전반부보다 높게 나온다.
"""
import array
import math
import sys

RATE = 48000


def load(path):
    a = array.array("f")
    with open(path, "rb") as f:
        a.frombytes(f.read())
    return a


def db(vals):
    if not vals:
        return -999.0
    p = max(abs(v) for v in vals)
    return 20 * math.log10(p) if p > 1e-12 else -999.0


def rms_db(vals):
    if not vals:
        return -999.0
    s = sum(v * v for v in vals) / len(vals)
    return 10 * math.log10(s) if s > 1e-24 else -999.0


def main():
    if len(sys.argv) < 2:
        print("사용법: pm_split_measure.py <녹음.f32> [오프셋초]")
        return 1
    data = load(sys.argv[1])
    off = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0

    print("블록  구간        peak      rms")
    early_all, late_all = [], []
    for b in range(3):
        base = off + b * 9.0          # 8초 발화 + 1초 침묵
        # 발화 시작 1초는 적응 중이라 뺀다
        e0, e1 = base + 1.0, base + 3.5
        l0, l1 = base + 5.0, base + 8.0
        seg_e = data[int(e0 * RATE):int(e1 * RATE)]
        seg_l = data[int(l0 * RATE):int(l1 * RATE)]
        if not len(seg_e) or not len(seg_l):
            continue
        early_all.extend(seg_e)
        late_all.extend(seg_l)
        print("%d     전반 1-3.5s  %7.1f  %7.1f" % (b + 1, db(seg_e), rms_db(seg_e)))
        print("%d     후반 5-8s    %7.1f  %7.1f" % (b + 1, db(seg_l), rms_db(seg_l)))

    if early_all and late_all:
        de, dl = rms_db(early_all), rms_db(late_all)
        print("")
        print("전체 전반 rms %.1f / 후반 rms %.1f  차이 %+.1f dB" % (de, dl, dl - de))
        if dl - de > 2.0:
            print("=> 발화가 길어질수록 에코가 샌다")
        else:
            print("=> 긴 발화에서도 유지된다")
    return 0


sys.exit(main())
