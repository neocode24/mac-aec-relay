#!/bin/bash
# 판별: VPIO 출력 감쇠가 원인인지 확인.
#   mode b = VPIO 출력으로 far 렌더
#   mode t = HALOutput(음성처리 없음) 출력으로 far 렌더 — 같은 체인의 대조군
# 두 모드에서 Maono 직접 입력(:0)을 재서 스피커 음량을 비교한다.
# 기준: afplay 직접 재생 = -36.8 dB (볼륨 100%, Sound Control 실행중)
cd "$(dirname "$0")"
pgrep -f "[S]ound Control.app" >/dev/null || { open -a "Sound Control"; sleep 5; }

for M in t b; do
  ./maecrelay --mode $M --farfile /tmp/far_test.f32 --duration 16 > "/tmp/pm_cmp_$M.log" 2>&1 &
  RPID=$!
  sleep 4
  printf "mode=%s  Maono직접(:0) : " "$M"
  ffmpeg -hide_banner -nostats -f avfoundation -i ":0" -t 9 -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB"
  wait $RPID
  grep -E "OVERALL bh2|OVERALL mic" "/tmp/pm_cmp_$M.log"
  echo "---"
  sleep 2
done
