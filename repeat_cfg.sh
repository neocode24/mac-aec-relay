#!/bin/bash
# repeat_cfg.sh — 한 설정을 N회 반복 측정 (재현성 확인).
# 사용법: bash repeat_cfg.sh <delay_ms> <tail_ms> <frame> <반복>
set -u
D="${1:-300}"
T="${2:-150}"
F="${3:-960}"
N="${4:-3}"
FAR=/tmp/far_test.f32
DUR=12

for i in $(seq 1 "$N"); do
  TAG="rep_d${D}_t${T}_f${F}_$i"
  ./speexrelay --mode aec --refdelay "$D" --tail "$T" --frame "$F" \
    --farfile "$FAR" --duration $DUR --record "/tmp/${TAG}.f32" > "/tmp/${TAG}.log" 2>&1
  echo "--- 반복 $i ($TAG) ---"
  python3 seg_suppress.py "/tmp/${TAG}.log"
done
