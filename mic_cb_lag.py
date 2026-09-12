#!/usr/bin/env python3
"""mic_cb_lag.py — micCb(마이크 콜백 수)는 부팅 순서 지표.
성공군 micCb 231~241, 실패군 209~239 — 겹치지만 성공군이 뒤쪽.

정말 중요한 건 'mic 스트림 시작 대비 ref 스트림 시작'의 상대 시각이다.
로그엔 직접 값이 없다. 대신 micFrames - farW(샘플) = 마이크가 앞서
쌓은 양. 이 값이 상대 부트 오프셋의 프록시."""
import glob
import re

rows = []
for path in sorted(glob.glob("/tmp/s3_*.log") + glob.glob("/tmp/v[0-9]_*.log") + glob.glob("/tmp/rep_d*.log") + glob.glob("/tmp/s2_*.log")):
    segs, delay = [], None
    farw = micframes = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\[\s*(\d+)s\] mic\s+(-?[\d.]+)/.*?out\s+(-?[\d.]+)/", line)
        if m:
            segs.append(float(m.group(3)))
        m2 = re.search(r"refdelay=(\d+)smp", line)
        if m2:
            delay = int(m2.group(1)) // 48
        m5 = re.search(r"farW=(\d+)", line)
        if m5 and farw is None:
            farw = int(m5.group(1))
        m6 = re.search(r"micFrames=(\d+)", line)
        if m6 and micframes is None:
            micframes = int(m6.group(1))
    if not segs or delay is None or farw is None:
        continue
    tailv = segs[-3:]
    ok = all(v <= -60 for v in tailv)
    rel = (micframes - farw) / 48.0  # ms: mic가 far보다 앞서 쌓인 양
    rows.append((path.split("/")[-1], delay, rel, ok))

rows.sort(key=lambda r: r[2])
print(f"{'런':>26} {'dly':>4} {'mic-far(ms)':>11} 판정")
for name, d, rel, ok in rows:
    print(f"{name:>26} {d:4d} {rel:11.1f} {'성공' if ok else '실패'}")

succ = [r for _, _, r, ok in [(r[0], r[1], r[2], r[3]) for r in rows] if ok]
fail = [r for _, _, r, ok in [(r[0], r[1], r[2], r[3]) for r in rows] if not ok]
print()
print(f"성공 mic-far: {min(succ):.1f} ~ {max(succ):.1f} ms" if succ else "성공 없음")
print(f"실패 mic-far: {min(fail):.1f} ~ {max(fail):.1f} ms" if fail else "실패 없음")
