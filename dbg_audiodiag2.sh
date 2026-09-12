#!/bin/bash
# dbg_audiodiag2.sh — afplay BH16 재생 중 프로세스별 장치 점유(스코프별) 확인
afplay -d "BlackHole 16ch" /tmp/echo_test.aiff >/dev/null 2>&1 &
AP=$!
sleep 2
echo "== afplay 프로세스 =="
ps aux | grep -E "afplay.*BlackHole" | grep -v grep
echo ""
echo "== audiodiag 전체 (활성 프로세스 섹션) =="
/Users/user/scripts/audiodiag 2>/dev/null | tail -60
wait $AP 2>/dev/null
echo done
