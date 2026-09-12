#!/bin/bash
# 경로 B AEC 효과 측정 — Sound Control 제거 후판.
#   SC가 없으므로 내리고 올리는 절차가 통째로 사라졌다.
#   볼륨은 BetterDisplay 상한을 8로 낮춘 뒤의 CLI 스케일 기준이다.
#   CLI 0.0625 = 에코 -47 dB / 바닥 -59 dB (PM 실측, 판정 가능한 조건)
# 사용법: pm_b_final.sh <CLI볼륨> <세트수>
V="${1:-0.0625}"
N="${2:-3}"
cd "$(dirname "$0")"

betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
sleep 2
echo "조건: SC 제거됨, CLI볼륨=$(betterdisplaycli get -tagID=134 -volume), BH2(:1) 측정"
echo ""

one() {  # $1=bypass(0|1) $2=세트번호
  local EXTRA=""
  [ "$1" = "1" ] && EXTRA="--bypass"
  ./maecrelay --mode b --farfile /tmp/far_test.f32 --duration 18 $EXTRA \
    > "/tmp/pmf_${2}_byp${1}.log" 2>&1 &
  local P=$!
  sleep 4
  printf "  [%d] AEC %s  BH2: " "$2" "$([ "$1" = 1 ] && echo "끔 " || echo "켬 ")"
  ffmpeg -hide_banner -nostats -f avfoundation -i ":1" -t 12 -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB"
  wait $P
}

for s in $(seq 1 "$N"); do
  one 1 "$s"; sleep 2
  one 0 "$s"; sleep 2
done
