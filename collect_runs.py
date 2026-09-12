#!/usr/bin/env python3
"""collect_runs.py — 지금까지 모든 refdelay 런을 표로 집계: 성패 vs refSpk."""
import glob
import re

rows = []
for path in sorted(glob.glob("/tmp/s3_*.log") + glob.glob("/tmp/v[0-9]_*.log") + glob.glob("/tmp/rep_d*.log") + glob.glob("/tmp/s2_*.log")):
    segs = []
    refspk = None
    delay = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\[\s*(\d+)s\] mic\s+(-?[\d.]+)/.*?out\s+(-?[\d.]+)/", line)
        if m:
            segs.append((int(m.group(1)), float(m.group(2)), float(m.group(3))))
        m2 = re.search(r"refdelay=(\d+)smp", line)
        if m2:
            delay = int(m2.group(1)) // 48
        m3 = re.search(r"refSpk=(\d+)", line)
        if m3 and refspk is None:
            refspk = int(m3.group(1))
    if not segs:
        continue
    tail = segs[-3:]
    ok = all(s[2] <= -60 for s in tail)
    rows.append((path.split("/")[-1], delay, refspk, max(s[2] for s in tail), ok))

print(f"{'런':>28} {'delay':>6} {'refSpk':>7} {'말미out':>8} {'판정':>4}")
for name, d, rs, last, ok in rows:
    print(f"{name:>28} {str(d):>6} {str(rs):>7} {last:8.1f} {'성공' if ok else '실패'}")

# 상관: 성공/실패 그룹의 refSpk 분포
succ = [rs for _, _, rs, _, ok in rows if rs and ok]
fail = [rs for _, _, rs, _, ok in rows if rs and not ok]
if succ and fail:
    print()
    print(f"성공 런 refSpk: {sorted(succ)} (median {sorted(succ)[len(succ)//2]})")
    print(f"실패 런 refSpk: {sorted(fail)} (median {sorted(fail)[len(fail)//2]})")
