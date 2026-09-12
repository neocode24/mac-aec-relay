#!/bin/bash
# measure_speex.sh — speexrelay 에코 레벨 측정 (bypass vs aec 자동 비교)
#
# relay가 farfile을 BH16 출력에 직접 쓴다 → BH16 루프백 입력으로 돌아와
# 참조가 되고, 동시에 DELL에서 물리 재생돼 마이크로 유입된다.
# AEC를 거친 신호는 BH2로 나가고 ffmpeg :1 (BH2)로 레벨을 잰다.
#
# 사용법: ./measure_speex.sh <mode> <반복>   (mode = aec | bypass)

MODE="${1:-aec}"
N="${2:-3}"
VOICE=/tmp/echo_test.aiff
FAR=/tmp/far_test.f32

[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."
[ -f "$FAR" ] || ffmpeg -hide_banner -loglevel error -y -i "$VOICE" -f f32le -acodec pcm_f32le -ac 1 -ar 48000 "$FAR"

echo "== 조건 =="
echo "DDC=$(betterdisplaycli get -tagID=134 -volume)  mode=$MODE  반복=$N"
ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | grep -E "^\[AVFoundation indev.*\[[0-9]+\] (BlackHole 2ch|Maono)" || true
echo ""

RELAY_PID=""
cleanup() {
  [ -n "$RELAY_PID" ] && kill "$RELAY_PID" 2>/dev/null
  wait "$RELAY_PID" 2>/dev/null
}
trap cleanup EXIT

lvl() {  # lvl <입력인덱스> <초>
  ffmpeg -hide_banner -nostats -f avfoundation -i ":$1" -t "$2" -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB"
}

for i in $(seq 1 "$N"); do
  echo "--- 반복 $i/$N ($MODE) ---"
  ./speexrelay --mode "$MODE" --farfile "$FAR" > "/tmp/speexrelay_$MODE.log" 2>&1 &
  RELAY_PID=$!
  sleep 2
  if ! grep -q RUNNING "/tmp/speexrelay_$MODE.log"; then
    echo "relay 기동 실패:"; cat "/tmp/speexrelay_$MODE.log"; exit 1
  fi

  # farfile이 8.8s 루프 재생 중. BH2(AEC 결과)와 Maono 직접(원본 에코) 측정
  printf "  [%d] BH2(%s):      " "$i" "$MODE"; lvl 1 8
  kill "$RELAY_PID" 2>/dev/null
  wait "$RELAY_PID" 2>/dev/null
  RELAY_PID=""
  sleep 1

  # Maono 직접: 같은 음량을 DELL에서 재생해 유입되는 크기 (relay의 DELL 렌더 레벨 확인 겸)
  ./speexrelay --mode bypass --farfile "$FAR" > /tmp/speexrelay_far_direct.log 2>&1 &
  RELAY_PID=$!
  sleep 2
  printf "  [%d] Maono 직접:   " "$i"; lvl 4 8
  kill "$RELAY_PID" 2>/dev/null
  wait "$RELAY_PID" 2>/dev/null
  RELAY_PID=""
  sleep 1
done

echo ""
echo "== relay 로그 ($MODE) =="
grep -E "OVERALL|speex AEC|far samples|WARN|ERROR" "/tmp/speexrelay_$MODE.log" | tail -8
echo ""
echo "== Maono 직접 측정 시 relay 로그 (DELL 렌더 확인용) =="
grep -E "OVERALL|ref " /tmp/speexrelay_far_direct.log | tail -4
