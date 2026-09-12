#!/bin/bash
# measure2_speex.sh — relay 자체 기록(--record) 기반 정밀 비교
#
# ffmpeg 실시간 캡처는 far 루프 위치와 캡처 시작 타이밍에 따라 ±15dB 흔들려
# bypass/aec 차이를 못 가린다. 대신 relay가 BH2에 쓴 신호를 f32 파일로
# 남기고, 같은 구간의 Maono 원본(mic)도 relay 미터로 확인한 뒤
# 파일 오프라인 분석(구간 지정)으로 에코 레벨을 잰다.
#
# 사용법: ./measure2_speex.sh <mode> <반복>
set -u
MODE="${1:-aec}"
N="${2:-3}"
VOICE=/tmp/echo_test.aiff
FAR=/tmp/far_test.f32
DUR=12   # far 1루프(11.6s)보다 약간 길게

[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."
[ -f "$FAR" ] || ffmpeg -hide_banner -loglevel error -y -i "$VOICE" -f f32le -acodec pcm_f32le -ac 1 -ar 48000 "$FAR"

echo "== 조건: DDC=$(betterdisplaycli get -tagID=134 -volume) mode=$MODE 반복=$N =="

for i in $(seq 1 "$N"); do
  echo "--- 반복 $i/$N ($MODE) ---"
  rm -f "/tmp/rec_$MODE.f32"
  ./speexrelay --mode "$MODE" --farfile "$FAR" --duration $DUR --record "/tmp/rec_$MODE.f32" > "/tmp/speexrelay_$MODE.log" 2>&1
  # relay 종료 대기 (--duration 이면 자동 종료)
  # 5초 여유 후 분석 (파일 플러시)
  sleep 1
  if [ ! -s "/tmp/rec_$MODE.f32" ]; then
    echo "녹음 실패"; tail -5 "/tmp/speexrelay_$MODE.log"; continue
  fi
  # 재생 구간(앞 1s 버림 → 2~10s)의 에코 레벨
  printf "  [%d] BH2기록(2-10s): " "$i"
  ffmpeg -hide_banner -nostats -f f32le -ar 48000 -ac 1 -ss 2 -t 8 -i "/tmp/rec_$MODE.f32" -af volumedetect -f null - 2>&1 | grep -oE "max_volume: [-0-9.]+ dB"
  printf "  [%d] mic 원본(ref 로그): " "$i"
  grep -E "OVERALL mic" "/tmp/speexrelay_$MODE.log" | tail -1
done
echo ""
echo "== relay 로그 마지막 =="
grep -E "OVERALL|speex AEC|underrun" "/tmp/speexrelay_$MODE.log" | tail -5
