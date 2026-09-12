#!/bin/bash
# stability.sh — speexrelay 장시간 안정성 테스트 (크래시 재현)
cd "$(dirname "$0")"
for i in $(seq 1 10); do
  echo "--- run $i ---"
  ./speexrelay --mode aec --farfile /tmp/far_test.f32 --duration 15 > /tmp/stab.log 2>&1
  RC=$?
  echo "exit=$RC"
  if [ $RC -ne 0 ]; then
    echo "!! 크래시 발생 (run $i)"; tail -5 /tmp/stab.log; break
  fi
done
echo "done"
