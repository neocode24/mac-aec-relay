#!/usr/bin/env python3
"""eff_delay2.py — tail 포함 3인자 관계. 성공 = (delay + boot) ∈ [443, 629]인데
실패도 [283, 559]로 겹친다. tail이 다르므로 tail별로 나눠 본다."""
import glob
import re

rows = []
for path in sorted(glob.glob("/tmp/s3_*.log") + glob.glob("/tmp/v[0-9]_*.log") + glob.glob("/tmp/rep_d*.log") + glob.glob("/tmp/s2_*.log")):
    segs, refspk, delay, tail = [], None, None, None
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
        m4 = re.search(r"tail=(\d+)ms", line)
        if m4:
            tail = int(m4.group(1))
    if not segs or delay is None:
        continue
    tailv = segs[-3:]
    ok = all(v <= -60 for v in tailv)
    boot_ms = (refspk or 0) / 48.0
    rows.append((path.split("/")[-1], delay, tail, boot_ms, delay + boot_ms, ok))

from collections import defaultdict
by = defaultdict(list)
for name, d, t, b, s, ok in rows:
    by[(d, t)].append((s, ok))

print(f"{'delay':>6} {'tail':>5} {'성공합계범위':>16} {'실패합계범위':>16} {'n성/n실'}")
for (d, t), lst in sorted(by.items()):
    succ = [s for s, ok in lst if ok]
    fail = [s for s, ok in lst if not ok]
    sr = f"{min(succ):.0f}~{max(succ):.0f}" if succ else "-"
    fr = f"{min(fail):.0f}~{max(fail):.0f}" if fail else "-"
    print(f"{d:6d} {t:5d} {sr:>16} {fr:>16}   {len(succ)}/{len(fail)}")
