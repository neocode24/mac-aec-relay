#!/bin/bash
# 경로 B AEC 효과 측정 — 깨끗한 조건판.
#   조건: Sound Control 정상 종료(quit), DDC 볼륨은 인자로 지정.
#   비교: bypass ON(AEC 없음) vs OFF(AEC 켬) 을 번갈아 N세트.
#   측정: BlackHole 2ch(:1) = 릴레이가 내보내는 처리 후 마이크 신호.
# 사용법: pm_measure_b_clean.sh <DDC볼륨> <세트수>
V="${1:-0.005}"
N="${2:-3}"
cd "$(dirname "$0")"

SC_WAS=0
pgrep -f "[S]ound Control.app" >/dev/null && SC_WAS=1
if [ "$SC_WAS" = 1 ]; then
  osascript -e 'quit app "Sound Control"' 2>/dev/null
  for i in $(seq 1 10); do pgrep -f "[S]ound Control.app" >/dev/null || break; sleep 1; done
fi
pgrep -f "[S]ound Control.app" >/dev/null && { echo "Sound Control 종료 실패 — 중단"; exit 1; }

betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
sleep 1
echo "조건: SC 종료, DDC=$(betterdisplaycli get -tagID=134 -volume), BH2(:1) 측정"
echo ""

one() {  # $1=bypass(0|1) $2=세트번호
  local EXTRA=""
  [ "$1" = "1" ] && EXTRA="--bypass"
  ./maecrelay --mode b --farfile /tmp/far_test.f32 --duration 18 $EXTRA \
    > "/tmp/pmc_${2}_byp${1}.log" 2>&1 &
  local P=$!
  sleep 4
  printf "  [%d] bypass=%s  BH2: " "$2" "$1"
  ffmpeg -hide_banner -nostats -f avfoundation -i ":1" -t 12 -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB"
  wait $P
}

for s in $(seq 1 "$N"); do
  one 1 "$s"
  sleep 2
  one 0 "$s"
  sleep 2
done

echo ""
if [ "$SC_WAS" = 1 ]; then
  open -a "Sound Control"
  sleep 6
  pgrep -f "[S]ound Control.app" >/dev/null && echo "(Sound Control 복원됨)"
fi
