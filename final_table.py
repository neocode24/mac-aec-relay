#!/usr/bin/env python3
"""final_table.py — 최종 비교표: bypass(기준) vs autocal AEC vs Krisp(사용자 실증).

데이터 소스:
- bypass: /tmp/base_[123].f32 (이번 세션, 동일 조건 3회)
- autocal AEC: /tmp/a1_[1..8].f32 (이번 세션, 동일 조건 8회)
- Krisp: 사용자 실통화 검증(2026-09-12, "에코 완전 사라짐") — 수치 아님

출력: 세그먼트 max_volume 분포 (2-14s, 2s 세그먼트).
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
    "bypass(에코 그대로)": sorted(glob.glob("/tmp/base_[123].f32")),
    "autocal AEC(tail250)": sorted(glob.glob("/tmp/a1_[1-8].f32")),
}

print(f"{'조건':>22} {'런수':>4} {'세그':>4} {'max':>7} {'median':>7} {'mean':>7}  세그값")
for name, files in groups.items():
    allv = []
    detail = []
    for f in files:
        v = seg_maxima(f)
        allv += v
        detail.append(f"{f.split('/')[-1]}: max {max(v):.1f}")
    print(f"{name:>22} {len(files):4d} {len(allv):4d} {max(allv):7.1f} {statistics.median(allv):7.1f} {statistics.mean(allv):7.1f}")
    for d in detail:
        print(f"{'':>40}{d}")
