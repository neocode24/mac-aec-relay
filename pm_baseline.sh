#!/bin/bash
# PM 검증용: 볼륨 조건별 에코 기준선 재측정
# 사용법: pm_baseline.sh <ffmpeg입력인덱스> <반복횟수>
IDX="${1:-0}"
N="${2:-3}"

[ -f /tmp/echo_test.aiff ] || say -o /tmp/echo_test.aiff "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."

lvl() {
  ffmpeg -hide_banner -nostats -f avfoundation -i ":$IDX" -t "$1" -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB" | head -1
}

for i in $(seq 1 "$N"); do
  printf "  [%d] 무음: " "$i"; lvl 3
  afplay /tmp/echo_test.aiff >/dev/null 2>&1 &
  AP=$!
  sleep 0.5
  printf "  [%d] 에코: " "$i"; lvl 8
  wait $AP 2>/dev/null
done
