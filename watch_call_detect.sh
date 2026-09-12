#!/bin/bash
# 통화 감지 확인용. callwatch가 무엇을 보는지 그대로 보여준다.
# 통화를 걸었다 끊으면서 이 창을 보면 감지 시점을 알 수 있다.
#
# 사용법: ./watch_call_detect.sh   (Ctrl-C로 종료)
echo "통화를 걸었다 끊으며 관찰하세요. Ctrl-C로 종료."
echo ""
prev=""
while true; do
  now=$(/Users/user/scripts/audiodiag 2>/dev/null \
        | sed -n '/오디오 프로세스/,$p' \
        | grep -iE "avconference|facetime|mobilephone" | head -1)
  if [ -n "$now" ]; then
    cur="통화중: $now"
  else
    cur="대기"
  fi
  if [ "$cur" != "$prev" ]; then
    echo "$(date '+%H:%M:%S')  $cur"
    prev="$cur"
  fi
  sleep 1
done
