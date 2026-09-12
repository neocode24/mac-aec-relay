#!/bin/bash
# maecrelay 단기 실행 후 종료해 stdout 캡처
cd /Users/user/Git/mac-aec-relay
./maecrelay --mode a > /tmp/relay_out.txt 2>&1 &
PID=$!
sleep "${1:-8}"
kill -INT $PID 2>/dev/null
sleep 1
kill -9 $PID 2>/dev/null
echo "--- output ---"
cat /tmp/relay_out.txt
