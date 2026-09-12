#!/bin/bash
# tune_speex.sh — tail/frame 파라미터 스윕 (한 프로파일 1회 측정, 빠른 스케닝)
# 사용법: ./tune_speex.sh
set -u
FAR=/tmp/far_test.f32
DUR=12

for TAIL in 200 300 400 500; do
  for FRAME in 480 960; do
    TAG="t${TAIL}_f${FRAME}"
    ./speexrelay --mode aec --tail $TAIL --frame $FRAME --farfile "$FAR" --duration $DUR --record /tmp/tune_$TAG.f32 > /tmp/tune_$TAG.log 2>&1
    RC=$?
    if [ $RC -ne 0 ]; then echo "$TAG: FAIL rc=$RC"; continue; fi
    V=$(ffmpeg -hide_banner -nostats -f f32le -ar 48000 -ac 1 -ss 2 -t 8 -i /tmp/tune_$TAG.f32 -af volumedetect -f null - 2>&1 | grep -oE "max_volume: [-0-9.]+")
    M=$(grep -oE "OVERALL mic  peak=[-0-9.]+" /tmp/tune_$TAG.log | grep -oE "[-0-9.]+$")
    echo "$TAG: BH2 $V  (mic 원본 peak ${M} dB)"
  done
done
