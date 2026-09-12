#!/bin/bash
# 깨끗한 조건 기준선: Sound Control 정상 종료(quit) + DDC 지정 볼륨.
# pkill -9 금지 — Sound Control은 모든 프로세스를 mute해두고 자기가 되돌려주는
# 구조라, 강제 종료하면 mute가 남아 스피커가 사실상 무음이 된다(PM 실측).
# 사용법: pm_clean_baseline.sh <DDC볼륨> <반복>
V="${1:-0.005}"
N="${2:-3}"

VOICE=/tmp/echo_test.aiff
[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."

SC_WAS=0
pgrep -f "[S]ound Control.app" >/dev/null && SC_WAS=1
if [ "$SC_WAS" = 1 ]; then
  osascript -e 'quit app "Sound Control"' 2>/dev/null
  for i in $(seq 1 10); do pgrep -f "[S]ound Control.app" >/dev/null || break; sleep 1; done
fi
pgrep -f "[S]ound Control.app" >/dev/null && { echo "Sound Control 종료 실패 — 중단"; exit 1; }

betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
sleep 1
echo "조건: Sound Control 종료, DDC=$(betterdisplaycli get -tagID=134 -volume)"
echo ""

lvl() {
  ffmpeg -hide_banner -nostats -f avfoundation -i ":0" -t "$1" -af volumedetect -f null - 2>&1 \
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

echo ""
if [ "$SC_WAS" = 1 ]; then
  open -a "Sound Control"
  sleep 6
  pgrep -f "[S]ound Control.app" >/dev/null && echo "(Sound Control 복원됨)"
fi
