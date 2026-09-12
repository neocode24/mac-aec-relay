#!/bin/bash
# Krisp AEC 정조건 측정.
#
# 앞선 측정이 실패한 이유: afplay가 DELL로 직접 나가 Krisp이 참조 신호를
# 받지 못했다(audiodiag 실측 — krisp 프로세스의 출력장치에 DELL이 없었다).
# AEC는 "스피커로 나간 신호"를 알아야 마이크에서 뺄 수 있다.
#
# 이 스크립트는 재생을 krisp speaker로 보낸다. Krisp이 그 소리를 받아
# 실제 출력(DELL)으로 넘기고, 같은 신호를 참조로 삼는다.
# 사용법: pm_krisp_ref.sh <CLI볼륨> <반복>
V="${1:-0.0625}"
N="${2:-3}"

VOICE=/tmp/echo_test.aiff
[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."

idx_of() {
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | grep -iE "^\[AVFoundation.*\] \[[0-9]+\] .*$1" \
    | head -1 | sed -E 's/.*\[([0-9]+)\].*/\1/'
}
K=$(idx_of "krisp microphone")
[ -z "$K" ] && { echo "krisp microphone 못 찾음"; exit 1; }

betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
sleep 2
echo "CLI볼륨=$(betterdisplaycli get -tagID=134 -volume)  krisp mic=:$K"
echo "비교 기준: Maono 직접 에코 -47 dB / krisp 바닥 -90 dB"
echo "           참조 없던 앞선 측정 = -40.5 dB (실패)"
echo ""

lvl() { ffmpeg -hide_banner -nostats -f avfoundation -i ":$K" -t "$1" -af volumedetect -f null - 2>&1 \
  | grep -oE "max_volume: [-0-9.]+ dB"; }

for i in $(seq 1 "$N"); do
  printf "  [%d] 바닥        : " "$i"; lvl 3
  # 재생을 krisp speaker로 — 이것이 AEC 참조가 된다
  afplay -d "krisp speaker" "$VOICE" >/dev/null 2>&1 &
  AP=$!; sleep 0.5
  printf "  [%d] 에코(참조O) : " "$i"; lvl 8
  wait $AP 2>/dev/null
  sleep 1
done
