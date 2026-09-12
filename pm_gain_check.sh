#!/bin/bash
# 판별: AEC가 에코를 못 지우는 것인가, 릴레이가 신호를 키우는 것인가.
#
# far 재생을 끄고(--farfile 미지정) 릴레이만 돌린다. 이때 BH2에 실리는 것은
# 마이크가 주워온 방 소음뿐이다. AEC 켬/끔 값이 여기서도 벌어지면,
# 차이의 정체는 에코 제거 실패가 아니라 릴레이 경로의 이득 차이다.
#
# 대조: far 재생 있는 조건도 같이 재서 두 쌍을 비교한다.
cd "$(dirname "$0")"
V="${1:-0.0625}"
betterdisplaycli set -tagID=134 -volume=$V >/dev/null 2>&1
sleep 2
echo "CLI볼륨=$(betterdisplaycli get -tagID=134 -volume)"
echo ""

run() {  # $1=bypass $2=farfile인자 $3=라벨
  local EXTRA=""
  [ "$1" = "1" ] && EXTRA="--bypass"
  ./maecrelay --mode b $2 --duration 16 $EXTRA > /tmp/pmg.log 2>&1 &
  local P=$!
  sleep 4
  printf "  %-18s AEC %s  BH2: " "$3" "$([ "$1" = 1 ] && echo "끔" || echo "켬")"
  ffmpeg -hide_banner -nostats -f avfoundation -i ":1" -t 10 -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB"
  wait $P
  sleep 2
}

echo "[far 재생 없음 — 방 소음만]"
run 1 "" "무음조건"
run 0 "" "무음조건"
echo ""
echo "[far 재생 있음 — 에코 존재]"
run 1 "--farfile /tmp/far_test.f32" "에코조건"
run 0 "--farfile /tmp/far_test.f32" "에코조건"
