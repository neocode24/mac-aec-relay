#!/usr/bin/env python3
"""seg_suppress.py — speexrelay 로그에서 [Ns] 세그먼트 mic/out 억제량 파싱."""
import re
import sys

path = sys.argv[1]
rows = []
for line in open(path, encoding="utf-8", errors="replace"):
    m = re.match(r"\[\s*(\d+)s\] mic\s+(-?[\d.]+)/\s*(-?[\d.]+)\s+ref\s+(-?[\d.]+)/\s*(-?[\d.]+)\s+out\s+(-?[\d.]+)/\s*(-?[\d.]+)", line)
    if m:
        t, mp, mr, rp, rr, op, orr = m.groups()
        rows.append((int(t), float(mp), float(mr), float(op), float(orr)))

for t, mp, mr, op, orr in rows:
    flag = " *SPIKE*" if mp > -40 else ""
    print(f"  t={t:2d}s mic {mp:6.1f}/{mr:6.1f}  out {op:6.1f}/{orr:6.1f}  억제 peak {mp-op:+5.1f} rms {mr-orr:+5.1f} dB{flag}")
if rows:
    import statistics
    pk = [mp - op for _, mp, _, op, _ in rows]
    rm = [mr - orr for _, _, mr, _, orr in rows]
    print(f"  세그먼트 억제 median: peak {statistics.median(pk):+.1f} dB / rms {statistics.median(rm):+.1f} dB")
