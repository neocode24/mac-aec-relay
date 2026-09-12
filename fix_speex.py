#!/usr/bin/env python3
import re
p = 'speexrelay.swift'
s = open(p).read()
s = s.replace("    let scratch = [Float32](repeating: 0, count: frames)",
              "    var scratch = [Float32](repeating: 0, count: frames)")
s = s.replace("kAudioObjectNameProperty", "kAudioObjectPropertyName")
for name in ["SPEEX_ECHO_SET_SAMPLING_RATE","SPEEX_PREPROCESS_SET_DENOISE","SPEEX_PREPROCESS_SET_AGC",
             "SPEEX_PREPROCESS_SET_NOISE_SUPPRESS","SPEEX_PREPROCESS_SET_ECHO_SUPPRESS",
             "SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE","SPEEX_PREPROCESS_SET_ECHO_STATE"]:
    s = re.sub(rf'let {name} = (\d+)', rf'let {name}: CInt = \1', s)
open(p,'w').write(s)
print("patched")
