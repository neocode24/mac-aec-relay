#!/bin/bash
# sweep2.sh — 안전 마진 그리드: applied delay를 최소 요구치 이하로,
# tail로 상단을 덮는다. 요구치 관측 범위 326~436ms.
# 사용법: bash sweep2.sh
set -u
FAR=/tmp/far_test.f32
DUR=16

for CFG in "240 200" "260 200" "240 150"; do
  set -- $CFG
  D=$1; T=$2
  TAG="s2_d${D}_t${T}"
  echo "== delay=${D}ms tail=${T}ms (frame 960) =="
  for i in 1 2 3; do
    ./speexrelay --mode aec --refdelay "$D" --tail "$T" --frame 960 \
      --farfile "$FAR" --duration $DUR --record "/tmp/${TAG}_$i.f32" > "/tmp/${TAG}_$i.log" 2>&1
    echo "-- 반복 $i:"
    python3 seg_suppress.py "/tmp/${TAG}_$i.log"
  done
done
