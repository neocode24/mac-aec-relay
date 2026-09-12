#!/usr/bin/env python3
# analyze_final.py — rec_*.f32 세그먼트별 에코 레벨 분석 + aec/bypass 비교표
import subprocess, sys, statistics, re, glob

def seg_max(path, start, dur):
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-f", "f32le", "-ar", "48000",
         "-ac", "1", "-ss", str(start), "-t", str(dur), "-i", path,
         "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True)
    m = re.search(r"max_volume: ([-0-9.]+) dB", r.stderr)
    return float(m.group(1)) if m else None

def analyze(pattern):
    out = []
    for f in sorted(glob.glob(pattern)):
        segs = []
        for start in range(2, 10, 2):  # 2-4,4-6,6-8,8-10
            v = seg_max(f, start, 2)
            if v is not None:
                segs.append(v)
        out.append((f, segs))
    return out

def report(name, runs):
    print(f"== {name} ==")
    all_segs = []
    for f, segs in runs:
        print(f"  {f}: {['%.1f' % s for s in segs]}  max={max(segs):.1f}")
        all_segs += segs
    if all_segs:
        print(f"  세그먼트 {len(all_segs)}개: max={max(all_segs):.1f}  median={statistics.median(all_segs):.1f}  mean={statistics.mean(all_segs):.1f}")
    return all_segs

aec = analyze("/tmp/rec_aec_*.f32")
byp = analyze("/tmp/rec_bypass_*.f32")
a = report("AEC", aec)
b = report("bypass", byp)
if a and b:
    print()
    print(f"== 요약 ==")
    print(f"  bypass max(최악): {max(b):.1f} dB / median: {statistics.median(b):.1f} dB")
    print(f"  aec    max(최악): {max(a):.1f} dB / median: {statistics.median(a):.1f} dB")
    print(f"  감쇠(median 기준): {statistics.median(b) - statistics.median(a):.1f} dB")
    print(f"  감쇠(max 기준):   {max(b) - max(a):.1f} dB")
