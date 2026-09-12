#!/bin/bash
# 측정 사본 — 워크스페이스 독립 버전 (~/scripts/echo-test.sh 기반, 수정 없이 유지)
# 원본과 동일한 절차: Sound Control 내림 → 무음 기준선 → 재생 중 에코 측정 → 복원
VOICE=/tmp/echo_test.aiff
[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."

IDX="${1:-1}"   # avfoundation 오디오 장치 인덱스 (기본 1 = BlackHole 2ch)

level() {  # $1=초
  ffmpeg -hide_banner -nostats -f avfoundation -i ":$IDX" -t "$1" -af volumedetect -f null - 2>&1 \
    | grep -oE "(max|mean)_volume: [-0-9.]+ dB" | tr '\n' ' '
  echo ""
}

SC_WAS_RUNNING=0
pgrep -f "[S]ound Control.app" > /dev/null && SC_WAS_RUNNING=1

if [ "$SC_WAS_RUNNING" = 1 ]; then
  osascript -e 'quit app "Sound Control"' 2>/dev/null
  for i in $(seq 1 8); do pgrep -f "[S]ound Control.app" >/dev/null || break; sleep 1; done
  pgrep -f "[S]ound Control.app" >/dev/null && { pkill -9 -f "Sound Control.app"; sleep 2; }
fi

printf "baseline(mute) : "; level 3
afplay "$VOICE" >/dev/null 2>&1 &
sleep 0.5
printf "echo(playing)  : "; level 8
wait

if [ "$SC_WAS_RUNNING" = 1 ]; then
  open -a "Sound Control"
  sleep 5
  pgrep -f "[S]ound Control.app" >/dev/null && echo "(Sound Control 복원됨)"
fi
