#!/usr/bin/env python3
"""loop_correct.py — 루프 보정 지연 계산."""
lags = [14769.6, 14819.3, 14773.9, 14818.4, 9971.6, 10019.3, 9987.9, 10018.4]
loop = 9600.0
print("루프 길이:", loop, "ms")
for l in lags:
    k = round((l - 359) / loop)
    print(f"  {l:8.1f} ms → 루프 {k}회 보정 시 {l - k*loop:+7.1f} ms")
