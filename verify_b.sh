#!/bin/bash
# b 모드 물리 재생 검증: 릴레이(b) 재생 중 Maono 직접 녹음(mic2file).
# Sound Control 종료 상태에서 스피커로 소리가 나면 톤이 잡혀야 한다.
# 사용법: ./verify_b.sh [bypass 0|1]
BYP="${1:-0}"
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

echo "=== b 모드 물리 재생 검증 (bypass=$BYP) ==="
./maecrelay --mode b --farfile /tmp/far_burst.f32 --duration 14 $EXTRA > /tmp/vb_${BYP}.log 2>&1 &
RPID=$!
sleep 2
./mic2file "/tmp/mic_vb_${BYP}.f32" 10
wait $RPID
echo "--- Maono 직접 녹음 톤 분석 (스피커→공기→마이크) ---"
python3 tone_spec.py "/tmp/mic_vb_${BYP}.f32" 1

if [ "$SC_WAS_RUNNING" = 1 ]; then
  open -a "Sound Control"
  sleep 5
  pgrep -f "[S]ound Control.app" >/dev/null && echo "(Sound Control 복원됨)"
fi
