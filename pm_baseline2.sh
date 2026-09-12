#!/bin/bash
# Sound Control 제거 후 기준선. 더 이상 SC를 내리고 올릴 필요가 없다.
# 사용법: pm_baseline2.sh <ffmpeg입력인덱스> <반복>
IDX="${1:-0}"
N="${2:-3}"

VOICE=/tmp/echo_test.aiff
[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."

echo "DDC=$(betterdisplaycli get -tagID=134 -volume)  입력 인덱스=:$IDX"
echo ""

lvl() {
  ffmpeg -hide_banner -nostats -f avfoundation -i ":$IDX" -t "$1" -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB"
}

for i in $(seq 1 "$N"); do
  printf "  [%d] 무음: " "$i"; lvl 3
  afplay "$VOICE" >/dev/null 2>&1 &
  AP=$!
  sleep 0.5
  printf "  [%d] 에코: " "$i"; lvl 8
  wait $AP 2>/dev/null
done
