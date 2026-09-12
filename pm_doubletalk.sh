#!/bin/bash
# 더블토크 재현 시험.
#
# 왜 필요한가:
#   기존 측정은 참조(상대 목소리)만 울리고 사용자는 말하지 않는 조건이었다.
#   그래서 억제량이 47 dB까지 나왔고 실통화의 "긴 대화에서 에코" 가 재현되지 않았다.
#   실통화는 둘이 동시에 말한다. 그때 적응 필터가 내 목소리를 에코로 오인해
#   발산하고, 발화가 길수록 어긋남이 쌓인다.
#
# 방법:
#   상대 목소리 = 릴레이의 --farfile 로 DELL 에 재생 (AEC 참조로도 들어감)
#   내  목소리 = 기본 출력을 Mac mini 스피커로 바꾸고 say 로 재생 (참조에 없음)
#   마이크는 둘 다 주워담는다 = 더블토크.
#
# 사용법: ./pm_doubletalk.sh [esup] [esupActive]
set -u
cd "$(dirname "$0")"

ESUP=${1:--40}
ESUPA=${2:--15}
DUR=36

VOL0=$(betterdisplaycli get -tagID=134 -volume 2>/dev/null)
OUT0=$(./set-default-output 2>/dev/null | sed 's/.*uid=//')

cleanup() {
    ./set-default-output "$OUT0" >/dev/null 2>&1
    betterdisplaycli set -tagID=134 -volume="$VOL0" >/dev/null 2>&1
}
trap cleanup EXIT

# 내 목소리 파일 (없으면 만든다)
if [ ! -f /tmp/near_speech.aiff ]; then
    say -v Suhyun -o /tmp/near_speech.aiff \
        "네 알겠습니다. 그 부분은 제가 확인해서 내일 오전까지 정리해서 보내드리겠습니다. 일정은 말씀하신 대로 조정하면 될 것 같고요. 예산 초과분은 어느 항목에서 발생한 건지 세부 내역을 좀 받아볼 수 있을까요. 그래야 어디를 줄일지 판단이 될 것 같습니다. 인력 충원은 좋은 소식이네요. 합류하시는 분들 온보딩 자료는 제가 준비하겠습니다." >/dev/null 2>&1
fi

betterdisplaycli set -tagID=134 -volume=0.5 >/dev/null 2>&1
sleep 1

# 기본 출력을 Mac mini 스피커로 (내 목소리 경로, 참조에 안 들어감)
./set-default-output BuiltInSpeakerDevice >/dev/null 2>&1
sleep 1

echo "esup=$ESUP esupActive=$ESUPA  더블토크 ${DUR}초"

./speexrelay --mode aec --autocal --esup "$ESUP" --esup-active "$ESUPA" \
    --farfile /tmp/far_speech.f32 --duration $DUR \
    --record /tmp/rec_dt.f32 >/tmp/dt_relay.log 2>&1 &
RELAY=$!

sleep 6                      # 캘리브레이션이 붙을 시간을 준다
afplay /tmp/near_speech.aiff >/dev/null 2>&1 &   # 내 목소리 시작 = 더블토크
wait $RELAY 2>/dev/null

cleanup

python3 - <<'PY'
import array, math
a = array.array('f'); a.frombytes(open('/tmp/rec_dt.f32','rb').read())
R = 48000
def rms(s):
    if not len(s): return -999.0
    v = sum(x*x for x in s)/len(s)
    return 10*math.log10(v) if v > 1e-24 else -999.0
solo = a[1*R:5*R]          # 상대만 말하는 구간
dt   = a[8*R:30*R]         # 더블토크 구간
print("  상대만(1-5s)   rms %7.1f" % rms(solo))
print("  더블토크(8-30s) rms %7.1f" % rms(dt))
for i in range(8, 30, 5):
    seg = a[i*R:(i+5)*R]
    if len(seg): print("    %2d-%2ds  %7.1f" % (i, i+5, rms(seg)))
PY
