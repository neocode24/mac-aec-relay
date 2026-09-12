#!/bin/bash
# 렌더 게인 검증 v3 — afplay -d 오용 수정판.
#
# 중요: afplay 의 -d 는 device 가 아니라 debug 다. 출력 장치를 고르는 기능이
# afplay 에는 없다. 앞선 스크립트들이 이것을 device 로 착각해 전부 기본 출력
# (DELL)으로 재생됐고, 그 결과 BH16 참조가 항상 0(-999 dB)이었다.
#
# 릴레이의 --farfile 은 BH16 출력에 직접 쓰는 기능이므로 그것을 쓴다.
#
# 두 조건에서 Maono 직접 입력을 재서 스피커 음량을 비교한다.
#   A) afplay → DELL 직접 (기준)
#   B) 릴레이 --farfile → BH16 루프백 → 릴레이 → DELL
# 두 값이 비슷하면 렌더 게인 손실이 없는 것이다.
set -u
cd "$(dirname "$0")"

VOICE=/tmp/echo_test.aiff
FAR=/tmp/far_test.f32
[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."
[ -f "$FAR" ] || ffmpeg -hide_banner -loglevel error -y -i "$VOICE" -f f32le -acodec pcm_f32le -ac 1 -ar 48000 "$FAR"

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
echo "(측정 중 볼륨을 바꾸지 마세요)"
echo ""

mic() { ffmpeg -hide_banner -nostats -f avfoundation -i ":$MAONO" -t "$1" -af volumedetect -f null - 2>&1 \
  | grep -oE "max_volume: [-0-9.]+ dB"; }

volcheck() {
  local v=$(betterdisplaycli get -tagID=134 -volume)
  [ "$v" != "$VOL0" ] && echo "      !! 볼륨 $VOL0 -> $v 변경됨. 이 회차 무효 !!"
}

for i in 1 2 3; do
  printf "[%d] A) DELL 직접        : " "$i"
  afplay "$VOICE" >/dev/null 2>&1 &
  P=$!; sleep 0.5; mic 8; wait $P 2>/dev/null
  volcheck
  sleep 1

  printf "[%d] B) 릴레이 경유      : " "$i"
  ./speexrelay --mode aec --farfile "$FAR" --duration 14 > "/tmp/gv3_$i.log" 2>&1 &
  R=$!
  sleep 3
  mic 8
  volcheck
  wait $R
  printf "      참조 peak: "; grep "OVERALL ref" "/tmp/gv3_$i.log" | grep -oE "peak=[-0-9.]+"
  echo ""
  sleep 1
done
