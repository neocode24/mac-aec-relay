#!/usr/bin/env python3
# parse_rec.py — rec f32 파일 프레임 수/길이 확인
import struct, sys
path = sys.argv[1]
data = open(path, 'rb').read()
n = len(data) // 4
print(f"frames={n} dur={n/48000:.2f}s")
