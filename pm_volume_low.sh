#!/bin/bash
# DDC 1% 미만 청감 테스트. 인자로 받은 볼륨들을 순서대로 재생한다.
# Sound Control은 정상 종료(quit)로 내린다 — SIGKILL하면 mute가 남는다.
# 사용법: pm_volume_low.sh 0.01 0.005 0.003 0.001

VOICE=/tmp/echo_test.aiff
[ -f "$VOICE" ] || say -o "$VOICE" "This is a volume test. Listen and tell me if this level is comfortable for everyday use."

SC_WAS=0
pgrep -f "[S]ound Control.app" >/dev/null && SC_WAS=1
if [ "$SC_WAS" = 1 ]; then
  osascript -e 'quit app "Sound Control"' 2>/dev/null
  for i in $(seq 1 10); do pgrep -f "[S]ound Control.app" >/dev/null || break; sleep 1; done
fi
pgrep -f "[S]ound Control.app" >/dev/null && { echo "Sound Control 종료 실패 — 중단"; exit 1; }

for V in "$@"; do
  betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
  sleep 1
  echo ">>> DDC $V 재생"
  afplay "$VOICE"
  sleep 1
done

betterdisplaycli set -tagID=134 -volume=0.01 >/dev/null 2>&1
if [ "$SC_WAS" = 1 ]; then
  open -a "Sound Control"
  sleep 6
  pgrep -f "[S]ound Control.app" >/dev/null && echo "Sound Control 복원됨" || echo "Sound Control 복원 실패"
fi
