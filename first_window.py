#!/usr/bin/env python3
"""first_window.py — 성공/실패 런의 '첫 2초' mic 입력 차이.

가설: 수렴 실패는 시작 수십 ms의 정합이 아니라, 세션 초반 mic에 들어온
비례성분(웅크러짐/이동)이 필터를 오염시켜 발산하는 것. 첫 세그먼트
mic 레벨을 비교한다."""
import glob
import re

rows = []
for path in sorted(glob.glob("/tmp/s3_*.log") + glob.glob("/tmp/v[0-9]_*.log") + glob.glob("/tmp/rep_d*.log") + glob.glob("/tmp/s2_*.log")):
    segs = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\[\s*(\d+)s\] mic\s+(-?[\d.]+)/\s*(-?[\d.]+).*?out\s+(-?[\d.]+)/", line)
        if m:
            segs.append((int(m.group(1)), float(m.group(2)), float(m.group(3)), float(m.group(4))))
    if not segs:
        continue
    tailv = [s[3] for s in segs[-3:]]
    ok = all(v <= -60 for v in tailv)
    first = segs[0]
    rows.append((path.split("/")[-1], first[1], first[2], first[3], ok))

print(f"{'런':>26} {'첫mic_pk':>9} {'첫mic_rms':>9} {'첫out_pk':>9} 판정")
for name, mp, mr, op, ok in sorted(rows, key=lambda r: r[4]):
    print(f"{name:>26} {mp:9.1f} {mr:9.1f} {op:9.1f} {'성공' if ok else '실패'}")
