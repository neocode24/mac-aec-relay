#!/bin/bash
# Krisp 가상 마이크 vs Maono 직접 비교.
# 스피커로 테스트 음성을 재생하며 두 입력의 에코 유입을 번갈아 잰다.
# 인덱스는 실행 시점에 조회한다(장치 추가/제거로 바뀐다).
# 사용법: pm_krisp_test.sh <CLI볼륨> <반복>
V="${1:-0.0625}"
N="${2:-3}"

VOICE=/tmp/echo_test.aiff
[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."

idx_of() {  # $1=장치명 부분 문자열
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | grep -iE "^\[AVFoundation.*\] \[[0-9]+\] .*$1" \
    | head -1 | sed -E 's/.*\[([0-9]+)\].*/\1/'
}

K=$(idx_of "krisp microphone")
M=$(idx_of "Maono PD300X")
[ -z "$K" ] && { echo "krisp microphone 못 찾음"; exit 1; }
[ -z "$M" ] && { echo "Maono 못 찾음"; exit 1; }

betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
sleep 2
echo "CLI볼륨=$(betterdisplaycli get -tagID=134 -volume)   krisp=:$K  maono=:$M"
echo "기준선(오늘 실측): Maono 에코 -47 dB / 바닥 -59 dB"
echo ""

lvl() {  # $1=인덱스 $2=초
  ffmpeg -hide_banner -nostats -f avfoundation -i ":$1" -t "$2" -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB"
}

for i in $(seq 1 "$N"); do
  printf "  [%d] krisp 바닥 : " "$i"; lvl "$K" 3
  afplay "$VOICE" >/dev/null 2>&1 &
  AP=$!; sleep 0.5
  printf "  [%d] krisp 에코 : " "$i"; lvl "$K" 8
  wait $AP 2>/dev/null
  sleep 1

  printf "  [%d] maono 에코 : " "$i"; : 
  afplay "$VOICE" >/dev/null 2>&1 &
  AP=$!; sleep 0.5
  lvl "$M" 8
  wait $AP 2>/dev/null
  echo ""
  sleep 1
done
