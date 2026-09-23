# Architecture and background

**Language** · English · [한국어](../ko-KR/architecture.md) · [日本語](../ja-JP/architecture.md) · [← README](../../README.md)

What `speexrelay` does, and why it ended up shaped this way. Written so the next
person to touch it — including a later me — doesn't dig the same holes again.

Work done 2026-09-12.

---

## 1. Why echo happens

During a call the other person's voice comes out of your speakers. It travels
through the air and back into your microphone. Whatever enters the microphone
goes back down the call, so they hear their own words a few hundred milliseconds
later. That is echo.

**The person who hears it is them, not you.** You cannot verify the problem with
your own ears; you have to ask the other side every single time. That alone made
this work slow.

There are two ways out.

**Keep speaker sound out of the microphone.** A headset solves it completely. It
just doesn't let you take calls on speakers.

**Remove the echo from the microphone signal.** That is AEC, acoustic echo
cancellation. You know what you sent to the speakers, so subtract it from what
the microphone picked up. This repository is that approach.

### Why it isn't plain subtraction

What leaves the speaker and what returns to the microphone are not the same
signal. One trip around the room changes it:

- **Delay.** Time of flight from speaker to mic, plus whatever the audio devices
  hold in their buffers. Measured here: 115 ms.
- **Attenuation and coloration.** Speaker and microphone have different frequency
  responses, and wall reflections pile on top.
- **Reverberation.** One sound arrives many times over, via many paths.

So AEC continuously estimates *what the speaker signal looks like by the time it
reaches the microphone*. That estimate is an **adaptive filter**, and subtracting
it is the cancellation. It keeps learning for the whole call.

---

## 2. Why macOS doesn't just do this

FaceTime and the Phone app get their audio handled by a system daemon,
`avconferenced`. It does contain echo cancellation, but in this setup it never
kicked in.

The AEC Apple exposes to developers is an audio unit called
`AUVoiceProcessingIO` (VPIO). Three ways to reach it, all blocked:

| Attempt | Result |
|---|---|
| Feed VPIO the mic and use system output as reference | Reference callback never fired (`cb=0`) |
| Render the far side through VPIO's output and use that as reference | The mic-to-virtual-device path died |
| Bundle mic and speaker into one Aggregate Device | Rejected with error `-10851` |

**The first failure is the important one.** VPIO's canceller only uses **signal
rendered through its own output bus** as the reference. Audio that
`avconferenced` sent straight to the speakers is invisible to it, so there is no
reference at all — and an AEC without a reference removes nothing.

The third failure comes from the same place.
`kAudioOutputUnitProperty_CurrentDevice` takes exactly one device. Input from the
microphone and output to the monitor means two devices, which means an Aggregate
Device, which VPIO refuses.

One more attempt: Core Audio's **process tap**, an API for intercepting another
process's audio output. Tap creation succeeded, but the callback never fired once
— almost certainly because an unsigned CLI binary has no TCC permission for
system audio capture.

**Conclusion:** Apple's canceller cannot be given a reference, and intercepting
system audio directly is blocked by permissions. Both the reference signal and
the cancellation engine have to come from somewhere else.

---

## 3. Why BlackHole, and why two of them

To get a reference you need the far side's voice **before** it reaches the
speakers. When `avconferenced` sends it straight to a monitor, there is no way to
see it.

So route the call app's output into a **virtual audio device** instead. A virtual
device swallows whatever you play into it and hands the same samples back to
anyone reading it as an input. Point the call app at one and the relay can read
what it plays.

`BlackHole` is that device — open source, installed via Homebrew.

Two instances are needed because the two paths run in opposite directions: one
carries the far side's voice in (call app → relay), the other carries the cleaned
microphone signal out (relay → call app). One device cannot do both.

Homebrew ships `blackhole-2ch`, `blackhole-16ch` and `blackhole-64ch` as separate
casks, with no way to install two copies of 2ch. So this setup uses one 2ch and
one 16ch. **The 16 channels are not wanted — two distinct devices are.**

That choice caused a bug later. See section 6.

---

## 4. Signal flow

Four devices are involved.

```
                   far side's voice
                          |
                [FaceTime / Phone app]
                      |        ^
           output     |        |     microphone
                      v        |
            BlackHole 16ch   BlackHole 2ch
                      |        ^
                      |        |
          +-----------+--------+-----------+
          |          speexrelay            |
          |                                |
          |   reference ---> [speexdsp AEC]|
          |       |               ^        |
          |       v               |        |
          |   [speakers]     mic signal    |
          +-----------|-----------|--------+
                      |           |
                      v           |
                  speakers    microphone
                      |           ^
                      +---echo----+
                      (through the air)
```

Path by path:

**How the far side's voice arrives.** FaceTime outputs to BlackHole 16ch. The
relay reads it and sends it two places: the real speakers (so you can hear it),
and the AEC's reference input. **Splitting one signal into those two roles is the
core of this design.**

**How your voice leaves.** The relay reads your microphone and feeds it to the
AEC. The AEC uses the reference to subtract the echo, and the result is written to
BlackHole 2ch, which FaceTime sees as a microphone.

**How the echo forms.** Sound from the speakers travels through the air into the
microphone. That is what gets cancelled — and it can be cancelled precisely
because it descends from the same original as the reference.

If `speexrelay` is not running, nothing drains BlackHole 16ch and the far side's
voice disappears there. **That is why the relay has to be up before the call.**

---

## 5. Code structure

One file, `speexrelay.swift`.

### Four audio callbacks

CoreAudio calls these on a realtime thread. Anything slow inside them drops
audio, so the callbacks only push and pop ring buffers; the actual work happens on
a separate thread.

| Callback | Job |
|---|---|
| `micInputProc` | Read the microphone into `ringMic` |
| `bh16Proc` | Read BlackHole 16ch into both `ringRef` (for the AEC) and `ringRefSpk` (for the speakers) |
| `spkRenderProc` | Pop `ringRefSpk` out to the real speakers |
| `bh2Proc` | Pop `ringOut` out to BlackHole 2ch |

### Four ring buffers

The `Ring` class — a lock-free circular buffer. Each has a backlog cap and drops
the oldest samples past it; without the cap, latency grows without bound.

| Buffer | Cap | Role |
|---|---|---|
| `ringMic` | 200 ms | Microphone input |
| `ringRef` | 100 ms | AEC reference |
| `ringRefSpk` | 100 ms | Speaker output |
| `ringOut` | — | AEC result |

**`ringRefSpk` and `ringRef` hold the same signal for different purposes.** The
first is what you hear, so it wants low latency; the second is what the AEC aligns
against, so it wants headroom. Treat them as one number and one of them breaks.
See section 7.

### Worker thread

`SpeexAecWorker.loop()` is the body, processing 480 samples (10 ms) at a time:

1. Pop one frame each from `ringMic` and `ringRef`
2. Push the reference through a delay line (`refDelayBuf`) to align it with the mic
3. Convert Float32 to Int16 — speexdsp only takes integers
4. `speex_echo_cancellation()` subtracts the echo
5. `speex_preprocess_run()` suppresses residual echo and noise
6. Convert back to Float32 and write to `ringOut`

### Delay alignment

Cancellation requires the reference and the microphone to line up in time. If the
reference is 100 ms late, the AEC subtracts a 100 ms-shifted signal and removes
nothing.

`calibrateDelay()` finds that offset automatically. It collects 1.5 seconds of
microphone and reference audio and computes their **cross-correlation**: the shift
`d` at which the reference best matches the microphone is the real delay.

Automatic beats a fixed value, measurably:

| refdelay | Suppression (two runs) |
|---|---|
| 0 ms | 7.6 / 2.7 |
| 60 ms | 7.3 / 1.2 |
| 90 ms | 0.5 / 3.9 |
| 115 ms (the measured real delay) | 7.5 / 4.5 |
| 140 ms | 0.5 / 1.9 |
| 180 ms | -0.1 / 0.9 |
| **automatic** | **11.5 / 10.4** |

Even the true 115 ms, pinned, does worse than calibration. The delay appears to
move during a call.

Calibration runs on **its own thread** — blocking the main loop would stall audio.
When it finishes it writes to `pendingRefDelay` and the main loop picks it up at a
frame boundary.

---

## 6. Traps hit along the way

### Silence and successful cancellation measure identically

The trap that cost the most. Fell into it twice.

An echo measured at -59 dB means either the AEC did its job or the speaker never
made a sound. The number alone cannot tell you which.

Once, force-quitting an audio utility left a mute state behind and the silence got
read as cancellation. Another time a playback command produced no sound at all and
that too was scored as success.

**The control group is the answer.** Measure with cancellation off
(`--mode bypass`) alongside, and confirm suppression there is exactly 0. Zero
proves the signal was really present. The verification scripts are built this way.

### `afplay -d` is not a device option

`afplay -d "BlackHole 16ch"` looked like a way to play into a specific device.
`-d` is the debug flag; afplay has no device selection at all. The sound went
quietly to the default output.

Several measurements were void because of this. The relay's `--farfile` option now
writes to BlackHole directly.

### Averaging 16 channels ate 18 dB

BlackHole 16ch reports sixteen channels but the call app only writes the first
two. Folding to mono by dividing by 16 leaves one eighth of the amplitude —
exactly -18 dB.

The symptom was "the other side sounds quiet", and it was first **mistaken for the
echo being gone.** Quieter speakers do mean less echo in the mic.

`monoFromABL()` now averages only the channels that carry signal.

### An uncapped speaker buffer made the far side sound slow

`ringRefSpk` was the one buffer without a backlog cap. On a real call its latency
climbed monotonically: 352 ms, then 523 ms, then 651 ms. Reported as "their voice
is slow."

Capping it pinned the figure at 89 ms.

### The reference arrived 320 ms behind the microphone

`ringRef` did have a cap, but the test was `min(ref, mic) > 200ms`. The microphone
drains immediately, so `min` sits near zero and 320 ms could pile up in the
reference without a single sample being dropped.

Each buffer now gets its own cap.

### Calibration failed on every real call

The original version tried once within three seconds of startup and gave up if the
signal was weak. Bench mode plays a test sound immediately, so it passed there. On
a real call nobody is talking at the moment you dial, so it **failed every time.**

This was the main driver of the "works on the bench, fails on a call" split.

It now retries for up to 90 seconds, until there is enough signal. A real-call log
shows it landing at 17 seconds:

```
정합 캘리브레이션: lag=240 samples (5.0 ms) corr=0.193 (17s 후)
refdelay 적용: 240 samples (5.0 ms) — AEC 상태 리셋
```

---

## 7. Latency and suppression trade against each other

"It's a bit slow" led to shrinking buffers, which made things worse three times
running.

| refMaxBacklog / spkMaxBacklog | Suppression |
|---|---|
| 100 ms / 100 ms | 8-14 dB |
| 50 ms / 40 ms | 1-3 |
| 100 ms / 40 ms | 3-7 |

**The samples dropped from `spkMaxBacklog` are the signal going to the speakers,
and that signal is the origin of the echo returning to the microphone.** Drop them
and the path the AEC learned no longer matches. It is not a latency-only knob.

To reduce perceived latency, adjust `ringOut` — the path carrying the AEC result
back to the call app. That one is outside the cancellation loop.

---

## 8. Fixes that failed

A real-call report — "echo shows up when the talking goes on longer" — narrowed
the cause to two candidates:

1. The reference buffer's delay moves during a call (observed 68 → 25 → 36 ms)
2. The AEC keeps running while the reference is silent (60-86% of a real call),
   teaching the filter that "no reference" means "no echo"

All three fixes made suppression worse.

| Attempt | Suppression |
|---|---|
| Before touching anything | 5.6-9.4 dB |
| Realign the delay line + reset the filter | 3.4-5.6 |
| Same, without the reset | 1.8-5.8 |
| Gate output after waiting out the echo tail | 0.8-4.8 |

All reverted.

### The bench did not reproduce a real call

After three failures the measurement itself became the suspect. A 35-second sample
of real speech measured 47 dB of suppression — nothing like the 8-14 dB seen on
calls.

**There was no double-talk on the bench.** The existing setup played the reference
(the far side) while the user stayed quiet. On a real call both talk at once, and
that is when the adaptive filter mistakes your voice for echo and diverges.

`pm_doubletalk.sh` reproduces it. The far side's voice goes out through the relay's
`--farfile` so it lands in the reference; your voice is played by `say` after
switching the default output to a second speaker, so it is **absent** from the
reference and therefore invisible to the AEC. The microphone picks up both.

With that, the residual suppressor was swept:

| esupActive | Far side only | Double-talk |
|---|---|---|
| -15 (default) | -48.7 | -48.9 |
| -30 | -51.3 | -48.4 |

No difference — that parameter is not the cause. -45 and -60 were never measured;
the sweep was stopped first.

> **Later correction.** The 47 dB figure above is not comparable to the 8-14 dB
> from real calls: it was computed reference-to-output (which includes the air
> path's own attenuation) while the call figures are microphone-to-output. On a
> consistent basis the bench, double-talk and real-call numbers are close, and the
> double-talk conclusion does **not** hold. The real bottleneck remains
> unidentified.

---

## 9. What is still open

**Suppression is limited and the cause is unknown.** Double-talk was the leading
theory until the measurement basis was corrected; on equal footing all three
conditions land in the same range. Whatever is capping suppression at 8-14 dB has
not been identified.

Replacing speexdsp with WebRTC's AEC3 is the obvious next lever — it is what
Chrome uses and is reputed to handle double-talk better — but it is a C++ library
to port and bridge, which is a rewrite, and it should not start before the
bottleneck is actually pinned down.

**Call detection does not work.** `callwatch.swift` polled `avconferenced`'s audio
device usage once a second to detect a call starting, and detected nothing even
mid-call. Running the relay continuously replaced it.

---

## 10. How it runs today

A launchd agent (`com.neocode24.aecrelay`) starts the relay at login and restarts
it if it dies. No terminal needed.

Set the microphone to BlackHole 2ch and the output to BlackHole 16ch once in
FaceTime's settings, and the Phone app follows — the two share the
`avconferenced` backend.

**The system default output is unchanged.** Music and video never touch the relay.
Only FaceTime and the Phone app use BlackHole.

If you ever stop the relay, change FaceTime back to the real microphone and
speakers. Left pointing at BlackHole with no relay running, the far side goes
silent.

Management commands are in the README.
