<div align="center">

<img src="../../docs/assets/icon.png" width="160" alt="mac-aec-relay" />

# mac-aec-relay

**유료 서비스 없이 macOS 통화의 에코를 제거하는 중계 프로그램**

[![Platform](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9%2B-orange?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![speexdsp](https://img.shields.io/badge/speexdsp-BSD--3-green?style=flat-square)](https://gitlab.xiph.org/xiph/speexdsp)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](../../LICENSE)

**언어** · [English](../../README.md) · 한국어 · [日本語](../ja-JP/README.md)

</div>

---

## 무엇인가

외장 스피커를 쓰는 맥에서 통화하면 상대가 자기 목소리를 되돌려 듣는다. 상대
목소리가 스피커로 나와 방에 반사된 뒤 내 마이크로 다시 들어가기 때문이다.

macOS에도 에코 제거기(`AUVoiceProcessingIO`)가 있지만 앱이 직접 골라 써야 한다.
FaceTime과 전화 앱은 그 선택지를 노출하지 않고, 그 유닛을 직접 몰아보려 해도 세
갈래로 막힌다. 셋 다 [구조와-배경.md](../../구조와-배경.md)에 적어 뒀다.

그래서 이 릴레이는 장치 사이에 끼어든다. 마이크를 읽고, 통화 앱이 재생하는 것을
읽고, speexdsp로 에코를 빼고, 가상 장치를 통해 통화 앱에 돌려준다.

> **있는 그대로:** 에코를 줄이지 없애지는 못한다. 실통화 억제량 8-14 dB다. 통화
> 상대의 평가가 "에코가 있다"에서 "괜찮다"로 바뀌었고 거기서 작업을 멈췄다.
> 무엇이 검증됐고 무엇이 아닌지는 [측정 결과](#측정-결과)에 적었다.

## 어떻게 동작하나

```
  마이크 ─────────────────┐
                          ├──► [ speexrelay ] ──► BlackHole 2ch ──► 통화 앱 마이크
  BlackHole 16ch ─────────┘         │
       ▲                            └────────────► 스피커
       │
  통화 앱 출력
```

가상 장치가 두 벌 필요한 이유는 신호가 앱 경계를 두 번 넘기 때문이다. 한 번은
통화 앱이 재생하는 것을 잡아오려고(에코 제거의 참조), 한 번은 정리한 마이크
신호를 돌려주려고.

참조가 마이크 속 에코와 시간이 맞아야 제거가 된다. 릴레이는 통화 처음 몇 초
동안 상호상관으로 그 차이를 재서 돌아가는 중에 반영한다.

## 설치

```bash
brew install speexdsp
brew install --cask blackhole-2ch blackhole-16ch
sudo killall coreaudiod          # 새 드라이버 인식
```

```bash
git clone https://github.com/neocode24/mac-aec-relay.git
cd mac-aec-relay
./build_speex.sh
./install.sh                     # launchd 에이전트 등록 후 시작
```

`./install.sh -u`로 제거한다. 로그는 `~/Library/Logs/mac-aec-relay/`에 쌓인다.

### 통화 앱 설정

FaceTime 설정에서 **마이크**를 `BlackHole 2ch`, **출력**을 `BlackHole 16ch`로
지정한다. 전화 앱은 FaceTime 설정을 따라가므로 한 번만 하면 된다.

> **주의:** 통화 앱이 BlackHole을 가리키는 동안에는 릴레이가 돌아야 한다. 설정을
> 되돌리지 않고 릴레이만 끄면 상대 목소리가 안 들린다.

## 사용

launchd가 계속 띄워 주므로 평소에는 할 일이 없다. 측정이나 디버깅 때는 직접
실행한다.

```bash
./speexrelay --mode aec --autocal          # 평소 동작
./speexrelay --mode bypass                 # AEC 없이 통과, 대조 측정용
./speexrelay --devices                     # 장치와 UID 목록
```

장치는 시스템 기본 입출력을 쓴다. 이름 일부나 UID로 바꿀 수 있다.

```bash
./speexrelay --mode aec --autocal --mic Maono --spk DELL
AEC_MIC_UID=... AEC_SPK_UID=... ./speexrelay --mode aec --autocal
```

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `--mode aec\|bypass` | `aec` | bypass는 AEC 없이 통과 |
| `--autocal` | 꺼짐 | 통화 중 참조 지연 자동 보정. 실통화에서는 사실상 필수 |
| `--refdelay <ms>` | 0 | 지연을 손으로 지정 |
| `--tail <ms>` | 400 | 필터 길이. 얼마나 긴 에코까지 다루는가 |
| `--frame <샘플>` | 480 | 처리 단위 |
| `--esup <dB>` | -40 | 아무도 말하지 않을 때의 잔여 에코 억제 |
| `--esup-active <dB>` | -15 | 상대가 말하는 동안의 잔여 에코 억제 |
| `--mic`, `--spk` | 시스템 기본 | UID 또는 이름 일부 |
| `--duration <초>` | Ctrl-C까지 | N초 후 종료 |
| `--record <경로>` | 꺼짐 | 출력을 f32le mono 48k로 기록 |
| `--farfile <경로>` | 꺼짐 | 파일을 참조로 재생. 통화 없이 측정할 때 |
| `--devices` | — | 장치 목록만 출력 |

### 자동 실행 관리

```bash
launchctl print    gui/$(id -u)/com.neocode24.aecrelay   # 상태
launchctl kickstart -k gui/$(id -u)/com.neocode24.aecrelay   # 재빌드 후 반영
launchctl bootout  gui/$(id -u)/com.neocode24.aecrelay   # 정지
tail -f ~/Library/Logs/mac-aec-relay/relay.log
```

## 로그 읽기

```
[ 54s] mic -51.6/-70.0  ref -15.2/-32.9  out -64.7/-83.8  aecFrames=5348 refZero=3762
       ring mic=0 ref=4288(89ms drop=8992) refSpk=512(11ms drop=22336) out=832
```

- `mic` 마이크 원본, `ref` 참조 신호, `out` 처리 후 (peak/rms)
- **상대만 말하는 구간에서 `mic` 빼기 `out`이 억제량이다.** 내가 말하는 구간은
  0에 가까워야 정상이다. 내 목소리를 지우면 안 된다
- `ref=N(Xms)` 참조 지연. 100 ms 근처에서 고정돼야 한다
- `refSpk=N(Xms)` 스피커 출력 지연. 늘어나면 상대 목소리가 느려진다
- `micCb`/`spkCb`/`bh16Cb`/`bh2Cb` 콜백 카운터 넷. 전부 계속 올라야 한다
- `underrun`이 0이 아니면 소리가 끊긴다

시작하면 `정합 캘리브레이션: 신호 대기 중`이 뜨고, 상대가 말하기 시작하면
`lag=... corr=...`과 `refdelay 적용:` 두 줄이 나온다. **이 두 줄이 없으면 보정
없이 도는 것이고 에코가 거의 안 지워진다.**

## 측정 결과

2026-09-12, 이 프로그램을 만든 기계에서 잰 값이다.

| 조건 | 억제량 (mic → out) |
|---|---|
| 실통화 | 8-14 dB |
| 시험대, 상대만 말함 | 5.6-9.4 dB |
| 시험대, 둘 다 말함 | -0.6 ~ 10.8 dB |

실통화에서 상대만 말하는 구간의 상세:

| ref | mic | out | 억제량 |
|---|---|---|---|
| −1.0 | −39.5 | −49.0 | 9.5 |
| −15.2 | −51.6 | −64.7 | 13.1 |
| −22.0 | −56.5 | −71.2 | 14.7 |

셋이 비슷하다는 점이 중요하다. 더블토크가 병목이라고 본 초기 진단은 기준을
통일해 다시 재보니 **유지되지 않았다.** 무엇이 억제량을 붙잡고 있는지는 아직
모른다.

### 나쁘게 만드는 것으로 확인된 것

둘 다 되돌려서 확인했다.

| 바꾼 것 | 억제량 |
|---|---|
| 현재 설정 | 8-14 dB |
| 참조와 스피커 버퍼 100 ms → 50/40 ms | 1-3 dB |
| 스피커 버퍼만 100 → 40 ms | 3-7 dB |
| 참조 끊길 때 지연선 정합 + 필터 리셋 | 3.4-5.6 dB |
| 무음 꼬리 뒤 출력 게이팅 | 0.8-4.8 dB |

그 버퍼에 담긴 샘플이 **곧 필터가 필요로 하는 에코 원본이다.** 버리면 학습한
경로가 안 맞는다. 체감 지연은 제거 경로 밖에 있는 `bh2MaxBacklog`로 조절한다.

## 자가 복구

오디오 장치는 사라질 수 있다. HDMI 모니터가 잠들거나 `coreaudiod`가 재시작하면
IOProc 콜백이 멈추는데, 프로세스는 살아서 로그만 찍는다. 이것 때문에 4시간
45분간 통화 불가 상태로 방치된 적이 있다.

지금은 30초마다 콜백 카운터 넷을 검사해 하나라도 안 오르면 `exit(1)`로 스스로
죽는다. launchd가 새 프로세스를 띄우고, 새 프로세스는 그 시점에 있는 장치로 UID를
다시 해석한다. 판정은 카운터만 보고 dB는 보지 않는다. **무음과 제거 성공은
측정값이 같기 때문이다.** 기동 후 30초 이내와 검사 간격이 35초를 넘은 경우는
건너뛰므로 잠자기에서 깨어날 때 오작동하지 않는다.

`sudo killall -9 coreaudiod`로 검증했다. 30초 안에 프로세스가 죽고 launchd가
되살리며 카운터가 다시 오른다.

## 더 읽을 것

| 문서 | 내용 |
|---|---|
| [구조와-배경.md](../../구조와-배경.md) | 에코가 생기는 원리, VPIO가 막힌 이유, 신호 흐름, 코드 구조, 밟은 함정들 |
| [실통화-시험-절차.md](../../실통화-시험-절차.md) | 실통화 시험 절차와 로그 읽는 법 |

## 측정 도구

측정 장치를 만드는 것이 작업의 대부분이었고, 그 첫 판이 틀려서 세 번을 헛고쳤다.
그래서 같이 둔다.

| 스크립트 | 용도 |
|---|---|
| `pm_verify_autocal.sh` | bypass 대비 억제량 |
| `pm_doubletalk.sh` | 둘이 동시에 말하는 상황 재현 |
| `pm_delay_probe.py` | 상호상관 지연 측정 |
| `pm_delay_sweep.sh` | `--refdelay` 값별 억제량 훑기 |
| `pm_split_measure.py` | 구간별 레벨. 긴 발화에서 흐트러지는지 본다 |

## 한계

- 기계 한 대에서 만들고 검증했다. 수치는 출발점으로만 본다.
- 에코가 줄지 없어지지는 않는다.
- 통화 시작 감지는 시도했다가 접었다. `avconferenced`가 오디오 장치를 잡는
  방식이 폴링으로 안 잡힌다. 릴레이를 상시 돌리는 것으로 대체했다.
- FaceTime과 전화 앱만 거친다. Teams나 Slack은 자체 제거 기능이 있어 두었다.

## 라이선스

[MIT](../../LICENSE) © 2026 neocode24

[speexdsp](https://gitlab.xiph.org/xiph/speexdsp)(BSD 3-Clause)를 쓴다. 헤더는
Homebrew 설치본을 읽고, 이 저장소에 복사해 두지 않는다.
