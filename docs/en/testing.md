# Testing on a real call

**Language** · English · [한국어](../ko-KR/testing.md) · [日本語](../ja-JP/testing.md) · [← README](../../README.md)

How to put the speexdsp relay (`speexrelay`) in front of an actual call.

## Order matters

**Start the relay first, then place the call.** The other way around and you hear
nothing from the far side. BlackHole is only a pipe; the relay is what moves the
audio from it to your real speakers. With no relay, sound goes into BlackHole and
vanishes.

If the launchd agent is installed (`./install.sh`) the relay is already running
and there is nothing to start.

## 1. Run the relay

```bash
cd mac-aec-relay
./speexrelay --mode aec --autocal
```

- Without `--duration` it runs until Ctrl-C
- Keep this terminal open for the whole call. Closing it or pressing Ctrl-C cuts
  the far side's audio instantly

## 2. Select devices in FaceTime

In FaceTime's Video menu:

- **Microphone = BlackHole 2ch**
- **Output = BlackHole 16ch**

The Phone app has no device menu of its own and follows FaceTime, so setting it
here covers both.

**Careful:** when a menu has only one option, the checkmark shown is an automatic
selection, not an explicit one. Click the item to pin it.

## 3. Restore afterwards

If you are running the relay by hand, stop it with Ctrl-C and set FaceTime's
microphone and output back to your real devices.

Leaving them on BlackHole with no relay running breaks the next call.

---

## What to watch in the log

```
[ 30s] mic -42.9/-60.7  ref -29.9/-50.3  out -43.4/-61.8  aecFrames=2929 refZero=2917
       ring mic=32 ref=4800(100ms drop=1200) refSpk=4288(89ms drop=5440) out=1024
```

| Field | Healthy | If it isn't |
|---|---|---|
| `ref` | -20 to -40 dB while the far side talks | A constant -999 means the call app's output isn't reaching BlackHole 16ch |
| `refZero` | As low as possible against `aecFrames` | Past half means the reference keeps dropping out |
| `ref=N(Xms)` | Steady near 100 ms | Climbing means latency is accumulating |
| `refSpk=N(Xms)` | Steady at 89-100 ms | Climbing means the far side sounds progressively slower |
| `out` vs `mic` | `out` must be lower | Equal means the AEC is doing nothing |
| `underrun spk=` | Stays 0 | Rising means audio is dropping out |

At startup you get:

```
정합 캘리브레이션: 신호 대기 중 (통화가 시작되면 자동 보정)
```

Once the far side speaks, calibration lands and prints:

```
정합 캘리브레이션: lag=5542 samples (115.5 ms) corr=0.395 (12s 후)
refdelay 적용: 5542 samples (115.5 ms) — AEC 상태 리셋
```

**Without those two lines the AEC is running with no delay alignment,** and in
that state it cancels almost nothing.

---

## Fixes made so far (2026-09-12)

| Problem | Symptom | Fix |
|---|---|---|
| Render gain -18 dB | Far side sounded quiet | Averaged only the active channels instead of all 16, 14 of which are silent |
| refSpk latency accumulating | Voice progressively slower (352 → 651 ms) | Added a 100 ms backlog cap |
| Reference runaway | Reference reached the AEC 320 ms behind the mic | Gave the reference its own cap, independent of the mic |
| Calibration failing on real calls | Alignment never applied, "level too low" | Wait up to 90 s for signal, moved to a background thread |

## Bench results

| Condition | mic | out | Suppression |
|---|---|---|---|
| bypass | −45.6 | −45.6 | 0.0 |
| autocal | −46.0 | −53.8 | 7.8 |
| autocal | −46.0 | −53.4 | 7.4 |
| autocal | −28.3 | −37.7 | 9.4 |
| autocal | −46.5 | −52.1 | 5.6 |

**5.6 to 9.4 dB on the bench.** All four bypass runs measured exactly 0, which
rules out mistaking silence for cancellation.

That said, **the bench and a real call are not the same conditions.** The bench
plays a test signal immediately; a real call has no reference at the moment it
starts. These numbers do not predict real-call performance — you have to place a
call.

**Also beware of mixing measurement bases.** Suppression here is microphone
minus output. A reference-to-output figure includes the air path's own
attenuation and will look far larger for the same cancellation quality; the two
cannot be compared. Getting this wrong once produced a bogus "47 dB on the bench
vs 8-14 dB on calls" gap and sent three fixes down the wrong path.
