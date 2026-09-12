#!/bin/bash
# dbg_audiodiag.sh — afplay BH16 재생 중 프로세스-장치 점유 확인
afplay -d "BlackHole 16ch" /tmp/echo_test.aiff >/dev/null 2>&1 &
AP=$!
sleep 2
/Users/user/scripts/audiodiag 2>/dev/null | grep -iA4 "afplay\|BlackHole" | head -40
wait $AP 2>/dev/null
echo done
