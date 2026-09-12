#!/bin/bash
# 검증: 앞선 -84 dB가 진짜 AEC 효과인가, 아니면 소리가 안 난 것인가.
#
# krisp speaker로 재생하는 동안 Maono를 직접(Krisp을 거치지 않고) 재서
# 스피커가 실제로 울렸는지 확인한다. Maono에서 -47 dB 근처가 나오면
# 소리는 났고 Krisp이 그것을 지운 것이다. Maono도 조용하면 재생 실패다.
V="${1:-0.0625}"
VOICE=/tmp/echo_test.aiff

idx_of() {
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | grep -iE "^\[AVFoundation.*\] \[[0-9]+\] .*$1" \
    | head -1 | sed -E 's/.*\[([0-9]+)\].*/\1/'
}
K=$(idx_of "krisp microphone")
M=$(idx_of "Maono PD300X")

betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
sleep 2
echo "CLI볼륨=$(betterdisplaycli get -tagID=134 -volume)  krisp=:$K maono=:$M"
echo ""

lvl() { ffmpeg -hide_banner -nostats -f avfoundation -i ":$1" -t "$2" -af volumedetect -f null - 2>&1 \
  | grep -oE "max_volume: [-0-9.]+ dB"; }

for i in 1 2; do
  echo "[$i회차] krisp speaker로 재생하며 두 마이크를 각각 측정"
  afplay -d "krisp speaker" "$VOICE" >/dev/null 2>&1 &
  AP=$!; sleep 0.5
  printf "   Maono 직접(소리 났나) : "; lvl "$M" 8
  wait $AP 2>/dev/null
  sleep 1
  afplay -d "krisp speaker" "$VOICE" >/dev/null 2>&1 &
  AP=$!; sleep 0.5
  printf "   krisp(AEC 후)         : "; lvl "$K" 8
  wait $AP 2>/dev/null
  echo ""
  sleep 1
done
