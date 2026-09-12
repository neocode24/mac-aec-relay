#!/usr/bin/env python3
"""eff_delay3.py — 최종 가설: 성공 조건은 합계가 특정 창 안.
전체 런에서 성공/실패를 합계 구간별로 나눠 최적 창을 찾는다."""
import glob
import re

rows = []
for path in sorted(glob.glob("/tmp/s3_*.log") + glob.glob("/tmp/v[0-9]_*.log") + glob.glob("/tmp/rep_d*.log") + glob.glob("/tmp/s2_*.log")):
    segs, refspk, delay = [], None, None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\[\s*(\d+)s\] mic\s+(-?[\d.]+)/.*?out\s+(-?[\d.]+)/", line)
        if m:
            segs.append(float(m.group(3)))
        m2 = re.search(r"refdelay=(\d+)smp", line)
        if m2:
            delay = int(m2.group(1)) // 48
        m3 = re.search(r"refSpk=(\d+)", line)
        if m3 and refspk is None:
            refspk = int(m3.group(1))
    if not segs or delay is None:
        continue
    tailv = segs[-3:]
    ok = all(v <= -60 for v in tailv)
    boot_ms = (refspk or 0) / 48.0
    rows.append((delay + boot_ms, ok))

rows.sort()
print("합계 구간별 성패 (50ms 바구니):")
from collections import defaultdict
b = defaultdict(lambda: [0, 0])
for s, ok in rows:
    k = int(s // 50) * 50
    b[k][0 if ok else 1] += 1
for k in sorted(b):
    w, l = b[k]
    print(f"  {k:4d}-{k+50:4d} ms: 성공 {w} / 실패 {l}  {'<<<' if w and not l else ('!!!혼합' if w and l else '')}")
