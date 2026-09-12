#!/bin/bash
# dbg_bh16_ffmpeg.sh — afplay→BH16 루프백을 ffmpeg(외부 독자)이 보는지 확인
VOICE=/tmp/echo_test.aiff
echo "== afplay로 BH16 재생 + ffmpeg :2 직접 녹음 =="
afplay -d "BlackHole 16ch" "$VOICE" >/dev/null 2>&1 &
AP=$!
sleep 0.5
ffmpeg -hide_banner -nostats -f avfoundation -i ":2" -t 6 -af volumedetect -f null - 2>&1 | grep -E "max_volume|Error|error"
wait $AP 2>/dev/null
echo "== 대조: 시스템 기본 출력으로 재생 + ffmpeg :2 (BH16) 녹음 (안 들려야 정상) =="
afplay "$VOICE" >/dev/null 2>&1 &
AP=$!
sleep 0.5
ffmpeg -hide_banner -nostats -f avfoundation -i ":2" -t 4 -af volumedetect -f null - 2>&1 | grep -E "max_volume|Error|error"
wait $AP 2>/dev/null
echo done
