#!/usr/bin/env python3
"""find_confounds.py — 합계만으론 부족하다. 다른 후보 인자 검토:
micCb(마이크 콜백 시작 타이밍), farW(far 재생 시작 지점), micFrames.
성공/실패를 이 인자들로 나눠본다."""
import glob
import re

rows = []
for path in sorted(glob.glob("/tmp/s3_*.log") + glob.glob("/tmp/v[0-9]_*.log") + glob.glob("/tmp/rep_d*.log") + glob.glob("/tmp/s2_*.log")):
    segs, refspk, delay = [], None, None
    miccb = farw = micframes = None
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
        m4 = re.search(r"micCb=(\d+)", line)
        if m4 and miccb is None:
            miccb = int(m4.group(1))
        m5 = re.search(r"farW=(\d+)", line)
        if m5 and farw is None:
            farw = int(m5.group(1))
        m6 = re.search(r"micFrames=(\d+)", line)
        if m6 and micframes is None:
            micframes = int(m6.group(1))
    if not segs or delay is None:
        continue
    tailv = segs[-3:]
    ok = all(v <= -60 for v in tailv)
    rows.append((path.split("/")[-1], delay, refspk, miccb, farw, micframes, ok))

print(f"{'런':>24} {'dly':>4} {'refSpk':>7} {'micCb':>6} {'farW':>7} {'micFr':>8} 판정")
for name, d, rs, mc, fw, mf, ok in sorted(rows, key=lambda r: (r[6], r[3] or 0)):
    print(f"{name:>24} {d:4d} {str(rs):>7} {str(mc):>6} {str(fw):>7} {str(mf):>8} {'성공' if ok else '실패'}")

# 상관 확인: micCb는 성공군이 큰가?
succ = [mc for *_, mc, ok in [(r[0], r[1], r[2], r[3], r[4], r[5], r[6]) for r in rows] if mc and ok]
fail = [mc for *_, mc, ok in [(r[0], r[1], r[2], r[3], r[4], r[5], r[6]) for r in rows] if mc and not ok]
print()
print(f"성공 micCb: {sorted(succ)}")
print(f"실패 micCb: {sorted(fail)}")
