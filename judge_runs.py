#!/usr/bin/env python3
"""judge_runs.py — 로그에서 성공/실패 판정. 성공 = 마지막 3세그먼트 out peak ≤ -60dB."""
import glob
import re
import sys

for path in sorted(sys.argv[1:] if len(sys.argv) > 1 else glob.glob("/tmp/s3_*.log")):
    segs = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\[\s*(\d+)s\] mic\s+(-?[\d.]+)/.*?out\s+(-?[\d.]+)/", line)
        if m:
            segs.append((int(m.group(1)), float(m.group(2)), float(m.group(3))))
    if not segs:
        print(f"{path}: 세그먼트 없음")
        continue
    tail = segs[-3:]
    last_out = min(s[2] for s in tail)
    ok = all(s[2] <= -60 for s in tail)
    peak_supp = max(s[1] - s[2] for s in tail)
    print(f"{path}: 마지막3세그 out peak 최대 {max(s[2] for s in tail):6.1f} dB → {'성공' if ok else '실패'} (말미 억제 {peak_supp:+.1f} dB)")
