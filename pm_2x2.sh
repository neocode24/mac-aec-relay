#!/bin/bash
# Sound Control 유무 x 재생 주체(afplay vs maecrelay) 2x2.
# DELL 볼륨은 호출 전에 100%로 맞춰 둘 것.
# 측정은 항상 Maono 직접 입력(:0) = 스피커가 실제로 울리는지만 본다.
cd "$(dirname "$0")"

mic_lvl() {
  ffmpeg -hide_banner -nostats -f avfoundation -i ":0" -t "$1" -af volumedetect -f null - 2>&1 \
    | grep -oE "max_volume: [-0-9.]+ dB"
}

sc_up()   { pgrep -f "[S]ound Control.app" >/dev/null || { open -a "Sound Control"; sleep 6; }; }
sc_down() { pkill -9 -f "Sound Control.app" 2>/dev/null; sleep 2; }

run_afplay() {
  afplay /tmp/echo_test.aiff >/dev/null 2>&1 &
  local p=$!
  sleep 0.5
  printf "%-28s " "$1"; mic_lvl 8
  wait $p 2>/dev/null
}

run_relay() {
  ./maecrelay --mode b --farfile /tmp/far_test.f32 --duration 16 > /tmp/pm_2x2_relay.log 2>&1 &
  local p=$!
  sleep 4
  printf "%-28s " "$1"; mic_lvl 9
  wait $p
}

sc_up;   run_afplay "afplay  + SC 실행"
sc_up;   run_relay  "maecrelay b + SC 실행"
sc_down; run_afplay "afplay  + SC 종료"
sc_down; run_relay  "maecrelay b + SC 종료"
sc_up
echo "(Sound Control 복원)"
