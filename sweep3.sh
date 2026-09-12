#!/bin/bash
# sweep3.sh — 볼츠만 성공: delay 하한 마진 축소 + 시작 백로그 제어.
# 성공 조건: 마지막 세그먼트 out peak ≤ -60dB.
# 사용법: bash sweep3.sh
set -u
FAR=/tmp/far_test.f32
DUR=14

run() {  # delay tail
  D=$1; T=$2
  for i in 1 2 3 4; do
    TAG="s3_d${D}_t${T}_$i"
    ./speexrelay --mode aec --refdelay "$D" --tail "$T" --frame 960 \
      --farfile "$FAR" --duration $DUR --record "/tmp/${TAG}.f32" > "/tmp/${TAG}.log" 2>&1
    LAST=$(grep -oE "\[ *1[0-4]s\] mic   [-0-9.]+/  [-0-9.]+  ref   [-0-9.]+/  [-0-9.]+  out   [-0-9.]+" "/tmp/${TAG}.log" | tail -1 | grep -oE "out   [-0-9.]+" | grep -oE "[-0-9.]+")
    echo "d=${D} t=${T} rep$i: 마지막 out peak ${LAST} dB"
  done
}

for CFG in "300 120" "320 120"; do
  set -- $CFG
  run "$1" "$2"
done
