#!/bin/bash
# refdelay를 명시로 주며 억제량을 훑는다.
#
# pm_delay_probe.py로 잰 실제 에코 지연은 115.5ms. autocal은 실통화에서
# "레벨 부족"으로 실패하므로, 그 값을 직접 넣었을 때 억제가 오르는지 본다.
#
# 판정: 억제량(mic - out). out 절대값만 보지 않는다.
set -u
cd "$(dirname "$0")"
FAR=/tmp/far_test.f32
N="${1:-2}"

betterdisplaycli set -tagID=134 -volume=0.0625 >/dev/null 2>&1
sleep 2
echo "DDC=$(betterdisplaycli get -tagID=134 -volume)  실측 에코지연=115.5ms"
echo ""
printf "%-12s %-8s %-9s %-9s %s\n" "refdelay" "회차" "mic" "out" "억제량"

one() {  # $1=refdelay(ms) $2=회차
  local log="/tmp/rd_$1_$2.log"
  local extra=""
  [ "$1" != "auto" ] && extra="--refdelay $1"
  [ "$1" = "auto" ] && extra="--autocal"
  ./speexrelay --mode aec --farfile "$FAR" --duration 12 $extra > "$log" 2>&1
  local mic=$(grep "OVERALL mic" "$log" | grep -oE "peak=[-0-9.]+" | cut -d= -f2)
  local out=$(grep "OVERALL out" "$log" | grep -oE "peak=[-0-9.]+" | cut -d= -f2)
  [ -z "$mic" ] && { printf "%-12s %-8s 측정실패\n" "$1" "$2"; return; }
  local sup=$(echo "$mic $out" | awk '{printf "%.1f", $1 - $2}')
  printf "%-12s %-8s %-9s %-9s %s\n" "$1" "$2" "$mic" "$out" "$sup"
}

for d in 0 60 90 115 140 180 auto; do
  for s in $(seq 1 "$N"); do
    one "$d" "$s"
    sleep 2
  done
done
