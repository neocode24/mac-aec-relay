# mac-aec-relay

macOS 전화 앱/FaceTime 통화의 에코를 제거하는 중계 프로그램.

애플 통화 스택(`avconferenced`)은 이 구성에서 AEC를 하지 않는다. 마이크 모드
"음성 분리"도 FaceTime에서는 선택 불가(회색)다. 그래서 마이크 신호를 가로채
speexdsp AEC로 에코를 지운 뒤 가상 마이크로 되돌려준다.

## 신호 흐름

```
전화앱 출력 → BlackHole 16ch → [릴레이가 읽어 DELL로 재생]
                                      ↓ 같은 신호가 AEC 참조
Maono PD300X → [speexdsp AEC] → BlackHole 2ch → 전화앱 마이크
```

## 사전 준비

```bash
brew install speexdsp
brew install --cask blackhole-2ch blackhole-16ch
sudo killall coreaudiod      # 드라이버 인식
```

## 빌드

```bash
./build_speex.sh
```

`speexrelay` 실행 파일이 생긴다.

## 사용

로그인하면 launchd가 릴레이를 자동으로 띄운다. 터미널을 열 필요가 없다.

FaceTime 비디오 메뉴에서 한 번만 지정한다.

- 마이크 = **BlackHole 2ch**
- 출력 = **BlackHole 16ch**

전화 앱은 자체 장치 메뉴가 없고 FaceTime 설정을 따라간다. 릴레이가 상시
돌므로 통화마다 바꿀 필요가 없다.

### 자동 실행 관리

```bash
launchctl print gui/$(id -u)/com.neocode24.aecrelay          # 상태
launchctl kickstart -k gui/$(id -u)/com.neocode24.aecrelay   # 재빌드 후 반영
launchctl bootout gui/$(id -u)/com.neocode24.aecrelay        # 정지
tail -f ~/Library/Logs/mac-aec-relay/relay.log               # 로그
```

**릴레이를 정지하면 FaceTime도 Maono PD300X / DELL S2725QC로 되돌려야 한다.**
BlackHole로 둔 채 릴레이가 없으면 상대 목소리가 안 들린다.

### 수동 실행

```bash
./speexrelay --mode aec --autocal
```

## 현재 성능과 남은 문제

에코 억제 8-14 dB, 출력 -49에서 -71 dB (2026-09-12 실통화 실측).
짧은 대화는 깨끗하고, **긴 대화에서 에코가 조금 남는다.**

원인은 둘로 좁혔다.

1. 참조 버퍼 지연이 통화 중 움직인다 (68 -> 25 -> 36ms 관측). 캘리브레이션이
   맞춰둔 값과 어긋나고, 말이 길어질수록 어긋남이 쌓인다.
2. 참조가 무음인 구간(실통화 60-86%)에도 AEC를 돌려 필터가
   "참조 없음 = 에코 없음"을 학습한다.

**세 번 고쳐봤고 세 번 다 더 나빠졌다.**

| 시도 | 억제량 |
|---|---|
| 원래 (현재 상태) | 5.6 - 9.4 dB |
| 지연선 정합 + 필터 리셋 | 3.4 - 5.6 |
| 리셋만 제거 | 1.8 - 5.8 |
| 에코 꼬리 대기 후 게이팅 | 0.8 - 4.8 |

분석은 맞다고 보지만 손대는 곳마다 speexdsp 내부 적응 동작과 충돌한다.
같은 자리를 세 번 실패했으므로 speexdsp 안에서 더 파는 것은 접었다.
다음에 손댄다면 WebRTC AEC3로 엔진을 교체하는 쪽이고, 새로 만드는 규모다.

## callwatch (동작하지 않음)

통화 시작을 감지해 릴레이를 켜고 끄려던 것인데, `avconferenced`가 오디오를
잡는 순간을 1초 폴링으로 잡지 못한다. 통화 중에도 아무것도 감지하지 못했다.
릴레이를 상시 돌리는 것으로 대체했다. 코드는 참고용으로 남긴다.

상세 절차와 로그 읽는 법은 `실통화-시험-절차.md` 참조.

## 옵션

| 옵션 | 설명 |
| --- | --- |
| `--mode aec\|bypass` | bypass는 AEC 없이 통과. 대조 측정용 |
| `--autocal` | 참조 지연 자동 보정. 실통화에서는 필수 |
| `--refdelay <ms>` | 지연을 수동 지정 (autocal 미사용 시) |
| `--duration <초>` | 생략하면 Ctrl-C까지 실행 |
| `--frame <샘플>` | AEC 프레임 크기 (기본 480) |
| `--tail <ms>` | 필터 길이 (기본 400) |
| `--farfile <경로>` | f32 mono 48k 파일을 BH16에 재생. 통화 없이 측정할 때 |
| `--record <경로>` | BH2 출력을 f32로 기록 |
| `--devices` | 장치 목록만 출력 |

## 로그 읽기

```
[ 54s] mic -51.6/-70.0  ref -15.2/-32.9  out -64.7/-83.8  aecFrames=5348 refZero=3762
       ring mic=0 ref=4288(89ms drop=8992) refSpk=512(11ms drop=22336) out=832
```

- `mic` 마이크 원본, `ref` 참조 신호, `out` AEC 처리 후 (peak/rms)
- **상대만 말하는 구간에서 mic 대비 out이 얼마나 낮은가**가 에코 억제량이다
- 본인이 말하는 구간은 억제량이 0에 가까운 것이 정상 (목소리를 지우면 안 된다)
- `ref=N(Xms ...)` 참조 지연. 100ms 근처 고정이어야 한다
- `refSpk=N(Xms ...)` 스피커 출력 지연. 늘어나면 상대 목소리가 느려진다
- `underrun` 0이 아니면 소리가 끊긴다

시작 시 `정합 캘리브레이션: 신호 대기 중`이 뜨고, 상대가 말하기 시작하면
`lag=... corr=...` 과 `refdelay 적용:` 두 줄이 나온다. **이게 안 나오면 지연 보정
없이 도는 것이고 에코가 거의 안 지워진다.**

## 실측 성능 (2026-09-12 실통화)

상대만 말하는 구간(에코만 존재):

| ref | mic | out | 억제량 |
| --- | --- | --- | --- |
| −1.0 | −39.5 | −49.0 | 9.5 |
| −5.3 | −41.9 | −51.4 | 9.5 |
| −15.2 | −51.6 | −64.7 | 13.1 |
| −19.0 | −56.6 | −65.2 | 8.6 |
| −22.0 | −56.5 | −71.2 | 14.7 |

목표는 out −50 dB 이하였고 −64 ~ −71 dB에 도달했다. 통화 상대 확인으로 에코 없음.

## 개발 중 밟은 함정

같은 문제를 다시 만나면 여기부터 보라.

**무음과 AEC 성공은 측정값이 같다.** 스피커가 실제로 울리는지 먼저 확인하지 않으면
"에코가 사라졌다"와 "소리가 안 났다"를 구분할 수 없다. 이 프로젝트에서 세 번 오판했다.
`--mode bypass` 대조군에서 억제량이 정확히 0인지 보는 것이 확실한 검사다.

**`afplay`의 `-d`는 device가 아니라 debug다.** afplay에는 출력 장치를 고르는 옵션이
없다. `afplay -d "BlackHole 16ch"`는 그냥 기본 출력으로 재생된다. 특정 장치로 보내려면
릴레이의 `--farfile`을 쓴다.

**다채널 장치를 모노로 접을 때 전체 채널로 나누면 안 된다.** BlackHole 16ch는 앞
2채널에만 신호가 있어서, 16으로 나누면 −18 dB가 빠진다. 실통화에서 상대 목소리가
작게 들리고, 스피커가 조용해져 에코가 준 것을 AEC 효과로 오인하게 만든다.

**모든 링버퍼에 백로그 상한이 필요하다.** 하나라도 빠지면 그 경로의 지연이 단조
증가한다. 스피커 버퍼가 그랬고 352ms에서 651ms까지 늘어 "목소리가 느리다"가 됐다.
`min(a, b)` 기준으로 판정하면 한쪽이 비었을 때 안 걸리므로 각 버퍼를 따로 봐야 한다.

**캘리브레이션은 신호가 있을 때 해야 한다.** 시작 직후 1회만 재면 실통화에서는 늘
실패한다. 통화를 걸어도 그 순간엔 상대가 말하지 않기 때문이다. 측정 모드는 테스트
음성이 즉시 재생돼 이 문제가 드러나지 않는다.

**애플 VoiceProcessingIO(VPIO)는 이 용도로 못 쓴다.** 실측으로 확인한 것들:
- AEC 참조는 그 유닛 자신의 output bus 신호뿐이다. 다른 프로세스가 스피커로 보낸
  소리는 참조에 안 들어간다
- `kAudioOutputUnitProperty_CurrentDevice`에 Aggregate Device를 주면 `-10851`로 거부
- 입력과 출력 장치를 따로 지정할 수 없다

**Core Audio process tap도 안 됐다.** `AudioHardwareCreateProcessTap`은 성공하는데
오디오 콜백이 한 번도 안 불린다. 서명 없는 CLI 바이너리라 시스템 오디오 캡처 권한이
없는 것으로 보인다. 앱 번들 + 코드 서명 + entitlement가 필요하다.

## 파일

| 파일 | 용도 |
| --- | --- |
| `speexrelay.swift` | 본체 |
| `build_speex.sh` | 빌드 |
| `CSpeexDsp/` | speexdsp 모듈맵 |
| `실통화-시험-절차.md` | 통화 시험 절차와 로그 읽는 법 |
| `pm_verify_autocal.sh` | bypass 대비 억제량 측정 |
| `pm_delay_probe.py` | 상호상관으로 실제 에코 지연 측정 |
| `pm_delay_sweep.sh` | refdelay 값별 억제량 훑기 |
| `pm_gain_verify3.sh` | 릴레이 경유 재생의 게인 손실 검사 |
| `maecrelay.swift` | VPIO 시절 구현. 참고용, 동작하지 않음 |

## 환경

Mac mini (Mac16,11), macOS 26.6.2. 마이크 Maono PD300X(USB 다이내믹),
스피커 DELL S2725QC(HDMI). 장치 UID는 소스에 상수로 박혀 있으므로 다른 환경에서는
`--devices`로 확인해 수정해야 한다.
