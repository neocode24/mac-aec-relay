#!/usr/bin/env python3
"""eff_delay.py — refdelay + 부트 지연(refSpk/48 ms) 합산과 성패 관계."""
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
    tail = segs[-3:]
    ok = all(v <= -60 for v in tail)
    boot_ms = (refspk or 0) / 48.0
    rows.append((path.split("/")[-1], delay, boot_ms, delay + boot_ms, ok))

print(f"{'런':>24} {'delay':>6} {'boot':>7} {'합계':>7} 판정")
for name, d, b, s, ok in sorted(rows, key=lambda r: r[3]):
    print(f"{name:>24} {d:6d} {b:7.1f} {s:7.1f} {'성공' if ok else '실패'}")

succ = [s for *_, s, ok in [(r[0], r[1], r[2], r[3], r[4]) for r in rows] if ok]
fail = [s for *_, s, ok in [(r[0], r[1], r[2], r[3], r[4]) for r in rows] if not ok]
print()
if succ:
    print(f"성공 합계 범위: {min(succ):.1f} ~ {max(succ):.1f} ms")
if fail:
    print(f"실패 합계 범위: {min(fail):.1f} ~ {max(fail):.1f} ms")
