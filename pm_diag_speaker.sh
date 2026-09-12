#!/bin/bash
# 진단: mode b 실행 중 Maono 직접 입력(:0)을 재서 스피커가 실제로 울리는지 확인.
# 비교 기준 — 같은 볼륨(100%)에서 afplay 직접 재생 시 Maono는 -36.8 ~ -39.4 dB.
# 여기서 -55 dB대가 나오면 maecrelay의 DELL 출력이 사실상 무음이라는 뜻.
cd "$(dirname "$0")"
pgrep -f "[S]ound Control.app" >/dev/null || { open -a "Sound Control"; sleep 5; }

./maecrelay --mode b --farfile /tmp/far_test.f32 --duration 18 > /tmp/pm_diag.log 2>&1 &
RPID=$!
sleep 4
printf "Maono 직접(:0) : "
ffmpeg -hide_banner -nostats -f avfoundation -i ":0" -t 10 -af volumedetect -f null - 2>&1 \
  | grep -oE "max_volume: [-0-9.]+ dB"
wait $RPID
grep -E "OVERALL" /tmp/pm_diag.log
