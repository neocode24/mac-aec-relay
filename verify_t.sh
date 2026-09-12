#!/bin/bash
# t 모드 검증: Sound Control 내린 상태에서 HALOutput 출력이 물리적으로 나오는가.
# 릴레이(t) 재생 + Maono 직접 녹음(ffmpeg)으로 톤 검출 확인.
cd "$(dirname "$0")"

SC_WAS_RUNNING=0
pgrep -f "[S]ound Control.app" > /dev/null && SC_WAS_RUNNING=1
if [ "$SC_WAS_RUNNING" = 1 ]; then
  osascript -e 'quit app "Sound Control"' 2>/dev/null
  for i in $(seq 1 8); do pgrep -f "[S]ound Control.app" >/dev/null || break; sleep 1; done
  pgrep -f "[S]ound Control.app" >/dev/null && { pkill -9 -f "Sound Control.app"; sleep 2; }
fi

echo "=== t 모드 (HALOutput → DELL) + Maono 녹음 ==="
./maecrelay --mode t --farfile /tmp/far_burst.f32 --duration 12 > /tmp/tmode3.log 2>&1 &
RPID=$!
sleep 2
ffmpeg -hide_banner -loglevel error -y -f avfoundation -i ":0" -t 9 -c:a pcm_f32le -ar 48000 -ac 1 -f f32le /tmp/mic_tmode3.f32 2>&1
wait $RPID
python3 tone_spec.py /tmp/mic_tmode3.f32 0

if [ "$SC_WAS_RUNNING" = 1 ]; then
  open -a "Sound Control"
  sleep 5
  pgrep -f "[S]ound Control.app" >/dev/null && echo "(Sound Control 복원됨)"
fi
