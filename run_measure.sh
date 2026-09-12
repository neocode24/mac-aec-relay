#!/bin/bash
# 릴레이 + BH2 에코 측정을 한 번에. 사용법: ./run_measure.sh <mode> [회차인덱스]
# mode: raw | a | ai | b
MODE="${1:-a}"
SETNO="${2:-1}"
cd "$(dirname "$0")"

echo "=== 회차 $SETNO / mode=$MODE ==="
./maecrelay --mode "$MODE" --duration 22 > "/tmp/relay_${MODE}_${SETNO}.log" 2>&1 &
RPID=$!
sleep 4   # 릴레이 기동 대기
./measure.sh 1 2>&1 | grep -E "baseline|echo|복원"
wait $RPID
echo "--- relay log tail ---"
tail -5 "/tmp/relay_${MODE}_${SETNO}.log"
