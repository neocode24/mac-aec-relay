#!/bin/bash
# dbg_ref.sh — BH16 루프백 참조가 relay에 들어오는지 단독 확인
cd "$(dirname "$0")"
./speexrelay --mode bypass > /tmp/dbg_relay.log 2>&1 &
RELAY=$!
sleep 2
afplay -d "BlackHole 16ch" /tmp/echo_test.aiff >/dev/null 2>&1
sleep 1
kill $RELAY 2>/dev/null
wait $RELAY 2>/dev/null
tail -8 /tmp/dbg_relay.log
