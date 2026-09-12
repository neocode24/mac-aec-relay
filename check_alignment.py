#!/usr/bin/env python3
"""check_alignment.py — 성공/실패 런의 ref-mic 시간 정합 진단.

BH16 loopback ref는 우리가 쓴 far 그 자체다. rec은 BH2에 쓴 out.
bypass rec과 far의 상관 지연이 그 런의 실제 (mic 대비 ref) 지연 차를
말해준다. 성공 런과 실패 런에서 이 값이 다른지 본다.

여기선 '그 런에서 실제로 적용된 refdelay(전기) + 실경로 지연'을
측정하기 위해 aec rec 대신, 같은 세션의 far 시각과 mic 유래 성분이
필요하다 — 대신 우리가 가진 것: 로그의 ring 백로그 + refZero 카운터.
"""
import re
import sys

for path in sys.argv[1:]:
    print(f"== {path}")
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\[\s*(\d+)s\].*?ring mic=(\d+) ref=(\d+) refSpk=(\d+) out=(\d+).*?refZero=(\d+)", line)
        if m:
            t, rm, rr, rs, ro, rz = m.groups()
            # ring mic/ref 잔량은 워커가 같은 양만 읽으므로 대체로 같다.
            print(f"  t={t}s ringMic={rm} ringRef={rr} refSpk={rs} refZero={rz}")
