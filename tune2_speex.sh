#!/bin/bash
# tune2_speex.sh — 유망 조합 재측정 (3회 반복, 신뢰 구간 확인)
# 사용법: ./tune2_speex.sh
set -u
FAR=/tmp/far_test.f32
DUR=12

for CFG in "300 960" "500 960" "500 480"; do
  set -- $CFG
  TAIL=$1; FRAME=$2
  TAG="t${TAIL}_f${FRAME}"
  echo "== $TAG =="
  for i in 1 2 3; do
    ./speexrelay --mode aec --tail $TAIL --frame $FRAME --farfile "$FAR" --duration $DUR --record /tmp/t2_${TAG}_$i.f32 > /tmp/t2.log 2>&1
    V=$(ffmpeg -hide_banner -nostats -f f32le -ar 48000 -ac 1 -ss 2 -t 8 -i /tmp/t2_${TAG}_$i.f32 -af volumedetect -f null - 2>&1 | grep -oE "max_volume: [-0-9.]+")
    M=$(grep -oE "OVERALL mic  peak=[-0-9.]+" /tmp/t2.log | grep -oE "[-0-9.]+$")
    echo "  [$i] BH2 $V (mic ${M})"
  done
done
