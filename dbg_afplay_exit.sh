#!/bin/bash
# dbg_afplay_exit.sh — afplay -d BH16 의 실제 동작 확인 (오류 출력 포함)
echo "== afplay -d 'BlackHole 16ch' stderr 포함 =="
afplay -d "BlackHole 16ch" /tmp/echo_test.aiff
echo "exit=$?"
echo ""
echo "== afplay -d '?' 장치 목록 =="
afplay -d "?" /dev/null 2>&1 | head -20
