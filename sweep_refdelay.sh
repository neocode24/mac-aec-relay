#!/bin/bash
# sweep_refdelay.sh — ref 지연선 스윕. 측정 경로 지연 359ms 주변.
# 로그의 [Ns] mic/out에서 세그먼트별 억제량을 뽑는다(파싱 단순화: cut 방식).
# 사용법: bash sweep_refdelay.sh <frame> <tail_ms> <delay1> <delay2> ...
set -u
FRAME="${1:-960}"
TAIL="${2:-60}"
shift 2 2>/dev/null || true
DELAYS="${@:-300 340 360 380}"
FAR=/tmp/far_test.f32
DUR=12

for D in $DELAYS; do
  TAG="rd${D}_t${TAIL}_f${FRAME}"
  echo "== refdelay=${D}ms tail=${TAIL} frame=${FRAME} =="
  ./speexrelay --mode aec --refdelay "$D" --tail "$TAIL" --frame "$FRAME" \
    --farfile "$FAR" --duration $DUR --record "/tmp/${TAG}.f32" > "/tmp/${TAG}.log" 2>&1
  RC=$?
  if [ $RC -ne 0 ]; then echo "  rc=$RC"; tail -3 "/tmp/${TAG}.log"; continue; fi
  python3 seg_suppress.py "/tmp/${TAG}.log"
  grep -E "OVERALL" "/tmp/${TAG}.log" | sed 's/^/  /'
  echo
done
