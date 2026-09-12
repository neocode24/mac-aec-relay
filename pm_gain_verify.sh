#!/bin/bash
# 렌더 게인 검증: 릴레이 경유 재생이 직접 재생과 같은 음량인가.
#
# 2026-09-12 발견: monoFromABL이 BH16의 16채널 전체로 평균을 내
# 신호가 8분의 1(-18 dB)로 줄었다. 실통화에서 상대 목소리가 작게 들리고,
# 스피커가 조용해져 에코가 준 것을 AEC 효과로 오인하게 만든 원인.
#
# 두 조건에서 Maono 직접 입력(:Maono)을 재서 스피커 음량을 비교한다.
#   A) afplay → DELL 직접
#   B) afplay → BH16 → speexrelay → DELL
# 두 값이 비슷하면 게인 손실이 해결된 것이다.
set -u
cd "$(dirname "$0")"

VOICE=/tmp/echo_test.aiff
[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."

idx_of() {
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | grep -iE "^\[AVFoundation.*\] \[[0-9]+\] .*$1" | head -1 | sed -E 's/.*\[([0-9]+)\].*/\1/'
}
MAONO=$(idx_of "Maono PD300X")
[ -z "$MAONO" ] && { echo "Maono 못 찾음"; exit 1; }

betterdisplaycli set -tagID=134 -volume=0.0625 >/dev/null 2>&1
sleep 2
VOL0=$(betterdisplaycli get -tagID=134 -volume)
echo "DDC=$VOL0  Maono=:$MAONO"
echo "(측정 중 볼륨을 바꾸지 마세요 - 각 측정 후 자동 확인합니다)"
echo ""

mic() { ffmpeg -hide_banner -nostats -f avfoundation -i ":$MAONO" -t "$1" -af volumedetect -f null - 2>&1 \
  | grep -oE "max_volume: [-0-9.]+ dB"; }

volcheck() {
  local v=$(betterdisplaycli get -tagID=134 -volume)
  [ "$v" != "$VOL0" ] && echo "      !! 볼륨이 $VOL0 -> $v 로 바뀜. 이 회차 무효 !!"
}

for i in 1 2 3; do
  printf "[%d] A) DELL 직접           : " "$i"
  afplay "$VOICE" >/dev/null 2>&1 &
  P=$!; sleep 0.5; mic 8; wait $P 2>/dev/null
  volcheck
  sleep 1

  printf "[%d] B) BH16 → 릴레이 → DELL: " "$i"
  ./speexrelay --mode aec --duration 14 > "/tmp/gaincheck_$i.log" 2>&1 &
  R=$!
  sleep 3
  afplay -d "BlackHole 16ch" "$VOICE" >/dev/null 2>&1 &
  P=$!; sleep 0.5; mic 8; wait $P 2>/dev/null
  volcheck
  wait $R
  printf "      릴레이 참조: "
  grep "OVERALL ref" "/tmp/gaincheck_$i.log" | grep -oE "peak=[-0-9.]+"
  echo ""
  sleep 1
done
