#!/bin/bash
# dbg_bh16_scope.sh — BH16의 실제 IOProc 콜백 스코프/프레임을 덤프
./speexrelay --mode bypass > /tmp/dbg_relay.log 2>&1 &
RELAY=$!
sleep 2
afplay -d "BlackHole 16ch" /tmp/echo_test.aiff >/dev/null 2>&1
sleep 1
kill $RELAY 2>/dev/null
wait $RELAY 2>/dev/null
grep -E "BH16|ref|OVERALL" /tmp/dbg_relay.log | tail -6
echo "---- 콜백 통계 ----"
grep -oE "ref -?[0-9.]+/-?[0-9.]+" /tmp/dbg_relay.log | head -5
