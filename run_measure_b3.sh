#!/bin/bash
# 경로 B 정밀 측정 v2: 버스트 신호 + BH2 녹음 + 버스트 분석
# 사용법: ./run_measure_b3.sh <회차> <bypass 0|1>
SETNO="${1:-1}"
BYP="${2:-0}"
cd "$(dirname "$0")"

SC_WAS_RUNNING=0
pgrep -f "[S]ound Control.app" > /dev/null && SC_WAS_RUNNING=1
if [ "$SC_WAS_RUNNING" = 1 ]; then
  osascript -e 'quit app "Sound Control"' 2>/dev/null
  for i in $(seq 1 8); do pgrep -f "[S]ound Control.app" >/dev/null || break; sleep 1; done
  pgrep -f "[S]ound Control.app" >/dev/null && { pkill -9 -f "Sound Control.app"; sleep 2; }
fi

EXTRA=""
[ "$BYP" = "1" ] && EXTRA="--bypass"

echo "=== 회차 $SETNO / mode=b bypass=$BYP (버스트) ==="
./maecrelay --mode b --farfile /tmp/far_burst.f32 --duration 20 $EXTRA > "/tmp/relay_b3_${SETNO}_byp${BYP}.log" 2>&1 &
RPID=$!
sleep 4
ffmpeg -hide_banner -loglevel error -y -f avfoundation -i ":1" -t 14 -c:a pcm_f32le -ar 48000 -ac 1 -f f32le "/tmp/bh2_burst_${SETNO}_byp${BYP}.f32" 2>&1
wait $RPID
echo "--- 버스트 분석 ---"
python3 analyze_burst.py "/tmp/bh2_burst_${SETNO}_byp${BYP}.f32" /tmp/far_burst.f32
echo "--- relay log tail ---"
tail -4 "/tmp/relay_b3_${SETNO}_byp${BYP}.log"

if [ "$SC_WAS_RUNNING" = 1 ]; then
  open -a "Sound Control"
  sleep 5
  pgrep -f "[S]ound Control.app" >/dev/null && echo "(Sound Control 복원됨)"
fi
