#!/usr/bin/env python3
"""understand_lag.md 내용의 요약 출력 (실행 불가 코드 아님).

부호 체계 관찰:
- bypass에서 mic의 far 대비 에코 lag = +360~440ms (mic가 늦게 도달)
- AEC 실패 런의 잔여 lag는 align_scan 부호로 -D 부근이지만
  far가 루프 재생이라 절대값은 ambiguous하다.

신뢰할 수 있는 신호:
1. 성공/실패 이분 판정 (judge_runs.py)
2. refSpk 부트 백로그와 성패의 상관
3. 세그먼트별 억제량

이 세 가지로만 결론을 내린다.
"""
print(__doc__)
