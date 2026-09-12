#!/bin/bash
# measure3_speex.sh — 최종 측정: relay 자체 기록 + Maono 원본 대조
#
# 한 반복의 절차:
#   1) relay <mode> 기동 (farfile을 BH16에 쓰고 DELL로 재생, AEC는 모드에 따라)
#   2) 12초 유지 후 자동 종료 — BH2 출력(rec)과 함께
#      Maono 원본(mic_raw)도 relay가 별도 기록
#   3) 같은 구간(2-10s)을 오프라인 volumedetect
#
# "Maono 원본"은 relay 내부에서 AEC 직전 시점의 마이크 신호라
# 외부 장치 의존이 없다.
#
# 사용법: ./measure3_speex.sh <mode> <반복>
set -u
MODE="${1:-aec}"
N="${2:-3}"
VOICE=/tmp/echo_test.aiff
FAR=/tmp/far_test.f32
DUR=12

[ -f "$VOICE" ] || say -o "$VOICE" "This is an echo level test. I am speaking through the monitor speaker so we can measure how much of this sound leaks back into the microphone."
[ -f "$FAR" ] || ffmpeg -hide_banner -loglevel error -y -i "$VOICE" -f f32le -acodec pcm_f32le -ac 1 -ar 48000 "$FAR"

echo "== 조건: DDC=$(betterdisplaycli get -tagID=134 -volume) mode=$MODE 반복=$N DUR=${DUR}s =="

sum=0
for i in $(seq 1 "$N"); do
  echo "--- 반복 $i/$N ($MODE) ---"
  rm -f /tmp/rec.f32
  ./speexrelay --mode "$MODE" --farfile "$FAR" --duration $DUR --record /tmp/rec.f32 > /tmp/m3.log 2>&1
  RC=$?
  if [ $RC -ne 0 ]; then echo "relay 비정상 종료 rc=$RC"; tail -3 /tmp/m3.log; exit 1; fi
  sleep 1
  if [ ! -s /tmp/rec.f32 ]; then echo "녹음 없음"; exit 1; fi
  printf "  BH2 출력(2-10s): "
  ffmpeg -hide_banner -nostats -f f32le -ar 48000 -ac 1 -ss 2 -t 8 -i /tmp/rec.f32 -af volumedetect -f null - 2>&1 | grep -oE "max_volume: [-0-9.]+ dB"
  cp /tmp/rec.f32 "/tmp/rec_${MODE}_$i.f32"
done
echo ""
echo "== 전체 mic(원본 에코) 미터 =="
grep -E "OVERALL (mic|ref|out)" /tmp/m3.log
