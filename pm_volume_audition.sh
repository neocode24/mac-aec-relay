#!/bin/bash
# DDC 최소 볼륨 청감 테스트.
# Sound Control을 곱게 내린 뒤(SIGKILL 금지 — mute 잔존) 낮은 볼륨부터
# 같은 음성을 재생한다. 사용자가 귀로 판정할 값을 찾는 용도.
# 끝나면 Sound Control을 복원한다.

VOICE=/tmp/echo_test.aiff
[ -f "$VOICE" ] || say -o "$VOICE" "This is a volume test. Listen and tell me if this level is comfortable for everyday use."

SC_WAS=0
pgrep -f "[S]ound Control.app" >/dev/null && SC_WAS=1
if [ "$SC_WAS" = 1 ]; then
  echo "Sound Control 내리는 중 (정상 종료)"
  osascript -e 'quit app "Sound Control"' 2>/dev/null
  for i in $(seq 1 10); do pgrep -f "[S]ound Control.app" >/dev/null || break; sleep 1; done
fi
pgrep -f "[S]ound Control.app" >/dev/null && { echo "종료 실패 — 중단"; exit 1; }
echo ""

for V in 0.01 0.02 0.04 0.06; do
  PCT=$(echo "$V * 100" | bc)
  betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
  sleep 1
  echo ">>> DDC ${PCT}% 재생"
  afplay "$VOICE"
  sleep 1
done

echo ""
echo "복원 중"
betterdisplaycli set -tagID=134 -volume=0.01 >/dev/null 2>&1
if [ "$SC_WAS" = 1 ]; then
  open -a "Sound Control"
  sleep 6
  pgrep -f "[S]ound Control.app" >/dev/null && echo "Sound Control 복원됨" || echo "Sound Control 복원 실패"
fi
