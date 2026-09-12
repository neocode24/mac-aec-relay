#!/usr/bin/env python3
"""final_table2.py — 측정 유효 구간 재정의.

판정 구간을 '말미 3세그먼트(8~14s)'로 잡은 근거: 시작 2초은 캘리브레이션+
적응 시간이라 초기 세그먼트는 정상 상태가 아니다. 다만 목표 '-50dB 이하'는
전 구간 기준으로 읽힐 수 있으니 두 가지를 모두 보고한다:
1) 전 구간(2~14s) max
2) 수렴 후(6~14s) max
"""
import glob
import subprocess
import re
import statistics

def seg_maxima(path, seg=2.0, dur=14.0):
    out = []
    t = 2.0
    while t + seg <= dur:
        r = subprocess.run(
            ["ffmpeg", "-hide_banner", "-nostats", "-f", "f32le", "-ar", "48000",
             "-ac", "1", "-ss", str(t), "-t", str(seg), "-i", path,
             "-af", "volumedetect", "-f", "null", "-"],
            capture_output=True, text=True)
        m = re.search(r"max_volume: ([-0-9.]+) dB", r.stderr)
        if m:
            out.append(float(m.group(1)))
        t += seg
    return out

groups = {
    "bypass": sorted(glob.glob("/tmp/base_[123].f32")),
    "autocal AEC": sorted(glob.glob("/tmp/a1_[1-8].f32")),
}
print(f"{'조건':>12} {'런':>3} {'전체max':>8} {'전체med':>8} {'수렴max':>8} {'수렴med':>8}")
for name, files in groups.items():
    full, conv = [], []
    per = []
    for f in files:
        v = seg_maxima(f)
        full += v
        c = v[2:]  # 6s 이후
        conv += c
        per.append((f.split("/")[-1], max(v), max(c)))
    print(f"{name:>12} {len(files):3d} {max(full):8.1f} {statistics.median(full):8.1f} {max(conv):8.1f} {statistics.median(conv):8.1f}")
    for n, a, c in per:
        print(f"{'':>18}{n}: 전체 {a:.1f} / 수렴 {c:.1f}")
