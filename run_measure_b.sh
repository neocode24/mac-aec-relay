#!/bin/bash
# 경로 B 측정: 릴레이(b 모드)가 farfile을 BH16→DELL로 재생하는 동안
# BH2 출력 레벨을 측정한다. afplay를 쓰지 않는다(이중 재생 방지).
# 사용법: ./run_measure_b.sh [회차인덱스] [bypass: 0|1]
SETNO="${1:-1}"
BYP="${2:-0}"
cd "$(dirname "$0")"

level() {  # $1=초
  ffmpeg -hide_banner -nostats -f avfoundation -i ":1" -t "$1" -af volumedetect -f null - 2>&1 \
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

EXTRA=""
[ "$BYP" = "1" ] && EXTRA="--bypass"

echo "=== 회차 $SETNO / mode=b bypass=$BYP ==="
./maecrelay --mode b --farfile /tmp/far_test.f32 --duration 20 $EXTRA > "/tmp/relay_b_${SETNO}_byp${BYP}.log" 2>&1 &
RPID=$!
sleep 4   # 릴레이 기동 + far 재생 시작 대기

printf "echo(far 재생 중) : "; level 12
wait $RPID
echo "--- relay log tail ---"
tail -6 "/tmp/relay_b_${SETNO}_byp${BYP}.log"

if [ "$SC_WAS_RUNNING" = 1 ]; then
  open -a "Sound Control"
  sleep 5
  pgrep -f "[S]ound Control.app" >/dev/null && echo "(Sound Control 복원됨)"
fi
