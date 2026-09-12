#!/bin/bash
# PM 독립 검증: autocal AEC 억제 효과가 재현되는가.
#
# 워커 보고를 그대로 믿지 않고 PM이 직접 돌린다.
# bypass(AEC 없음)와 autocal(AEC 켬)을 번갈아 N세트 돌려
# mic(원본 에코)와 out(처리 후)을 함께 본다.
#
# 판정 규칙:
#   - mic가 -45 dB보다 작으면(조용하면) 그 회차는 무효. 스피커가 안 운 것이다.
#   - 억제량 = mic - out. out 절대값만 보고 판정하지 않는다.
#
# 사용법: pm_verify_autocal.sh <세트수>
set -u
N="${1:-3}"
cd "$(dirname "$0")"

VOICE=/tmp/echo_test.aiff
FAR=/tmp/far_test.f32
[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."
[ -f "$FAR" ] || ffmpeg -hide_banner -loglevel error -y -i "$VOICE" -f f32le -acodec pcm_f32le -ac 1 -ar 48000 "$FAR"

betterdisplaycli set -tagID=134 -volume=0.0625 >/dev/null 2>&1
sleep 2
echo "DDC=$(betterdisplaycli get -tagID=134 -volume)  세트=$N"
echo ""
printf "%-8s %-10s %-10s %-10s %s\n" "회차" "조건" "mic" "out" "억제량"

run() {  # $1=세트 $2=라벨 $3=모드 $4=추가인자
  local log="/tmp/pmv_$2_$1.log"
  ./speexrelay --mode "$3" --farfile "$FAR" --duration 12 $4 > "$log" 2>&1
  local mic=$(grep "OVERALL mic" "$log" | grep -oE "peak=[-0-9.]+" | cut -d= -f2)
  local out=$(grep "OVERALL out" "$log" | grep -oE "peak=[-0-9.]+" | cut -d= -f2)
  if [ -z "$mic" ] || [ -z "$out" ]; then
    printf "%-8s %-10s %s\n" "$1" "$2" "측정 실패"
    return
  fi
  local sup=$(echo "$mic $out" | awk '{printf "%.1f", $1 - $2}')
  local flag=""
  awk -v m="$mic" 'BEGIN{exit !(m < -52)}' && flag="  <- mic 조용함, 무효 의심"
  printf "%-8s %-10s %-10s %-10s %s%s\n" "$1" "$2" "$mic" "$out" "$sup" "$flag"
}

for s in $(seq 1 "$N"); do
  run "$s" "bypass"  "bypass" ""
  sleep 2
  run "$s" "autocal" "aec"    "--autocal"
  sleep 2
done
