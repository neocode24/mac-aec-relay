#!/bin/bash
# PM 측정: 경로 B, Sound Control 유지 + DELL 볼륨 100%
#
# 워커 스크립트와 다른 점 (중요):
#   - Sound Control을 죽이지 않는다. 죽이면 DELL로 소리가 사실상 안 나가
#     에코 자체가 생기지 않아 AEC 효과를 측정할 수 없다 (PM 실측: 볼륨 30%에서도
#     Sound Control 없으면 에코 -59 dB = 무음 수준, 있으면 -49.7 dB).
#   - DELL 볼륨을 100%로 올린다. 1.0%에서는 에코가 바닥소음에 묻힌다.
#
# 사용법: pm_measure_b.sh <회차> <bypass 0|1>
SETNO="${1:-1}"
BYP="${2:-0}"
cd "$(dirname "$0")"

pgrep -f "[S]ound Control.app" >/dev/null || { open -a "Sound Control"; sleep 5; }

EXTRA=""
[ "$BYP" = "1" ] && EXTRA="--bypass"

OUT="/tmp/pmb_${SETNO}_byp${BYP}"
echo "=== 회차 $SETNO / mode=b bypass=$BYP ==="

./maecrelay --mode b --farfile /tmp/far_test.f32 --duration 18 $EXTRA > "${OUT}.log" 2>&1 &
RPID=$!
sleep 4
ffmpeg -hide_banner -nostats -f avfoundation -i ":1" -t 12 -af volumedetect -f null - 2>&1 \
  | grep -oE "(max|mean)_volume: [-0-9.]+ dB" | tr '\n' '  '
echo ""
wait $RPID
grep -E "OVERALL" "${OUT}.log"
