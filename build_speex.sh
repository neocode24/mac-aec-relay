#!/bin/bash
# build_speex.sh — speexrelay 빌드
# 사용법: ./build_speex.sh
set -e
cd "$(dirname "$0")"
swiftc -O -o speexrelay speexrelay.swift \
  -I CSpeexDsp -I /opt/homebrew/include \
  -L /opt/homebrew/lib -lspeexdsp 2>&1 | grep -v "forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'" || true
echo "빌드 완료: $(pwd)/speexrelay"
