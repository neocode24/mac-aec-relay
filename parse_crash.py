#!/usr/bin/env python3
import json, sys
path = sys.argv[1]
with open(path) as f:
    lines = f.read().split('\n', 1)
    body = json.loads(lines[1])
print('exception:', body.get('exception'))
print('termination:', body.get('termination'))
faults = body.get('faultingThread', 0)
threads = body.get('threads', [])
t = threads[faults]
print('faulting thread frames:')
imgs = body.get('usedImages', [])
for fr in t.get('frames', [])[:15]:
    img = imgs[fr['imageIndex']] if fr['imageIndex'] < len(imgs) else {}
    print(' ', img.get('name', '?'), hex(fr.get('imageOffset', 0)), fr.get('symbol', ''), fr.get('sourceLine', ''))
