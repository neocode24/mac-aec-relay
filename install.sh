#!/bin/bash
# launchd 에이전트를 설치한다.
#
# plist에 절대 경로가 들어가야 하는데 사람마다 다르므로
# 설치 시점에 현재 위치를 넣어 생성한다.
#
#   ./install.sh     설치 + 시작
#   ./install.sh -u  중지 + 제거

set -euo pipefail

LABEL="com.neocode24.aecrelay"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="$HOME/Library/Logs/mac-aec-relay"

if [ "${1:-}" = "-u" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "제거했다. 로그는 $LOGDIR 에 남아 있다."
  exit 0
fi

if [ ! -x "$REPO/speexrelay" ]; then
  echo "speexrelay가 없다. 먼저 ./build_speex.sh 를 실행한다." >&2
  exit 1
fi

mkdir -p "$LOGDIR" "$HOME/Library/LaunchAgents"

# PlistBuddy로 만든다. 히어독으로 쓰면 XML이 이스케이프되는 일이 있었다.
rm -f "$PLIST"
PB=/usr/libexec/PlistBuddy
$PB -c "Add :Label string $LABEL" "$PLIST" >/dev/null
$PB -c "Add :ProgramArguments array" "$PLIST" >/dev/null
$PB -c "Add :ProgramArguments:0 string $REPO/speexrelay" "$PLIST" >/dev/null
$PB -c "Add :ProgramArguments:1 string --mode" "$PLIST" >/dev/null
$PB -c "Add :ProgramArguments:2 string aec" "$PLIST" >/dev/null
$PB -c "Add :ProgramArguments:3 string --autocal" "$PLIST" >/dev/null
$PB -c "Add :WorkingDirectory string $REPO" "$PLIST" >/dev/null
$PB -c "Add :RunAtLoad bool true" "$PLIST" >/dev/null
$PB -c "Add :KeepAlive bool true" "$PLIST" >/dev/null
$PB -c "Add :ThrottleInterval integer 10" "$PLIST" >/dev/null
$PB -c "Add :StandardOutPath string $LOGDIR/relay.log" "$PLIST" >/dev/null
$PB -c "Add :StandardErrorPath string $LOGDIR/relay.err.log" "$PLIST" >/dev/null

# 장치를 고정하고 싶으면 아래 주석을 풀고 UID를 넣는다.
# 비워두면 시스템 기본 입출력 장치를 쓴다.
#   $PB -c "Add :EnvironmentVariables dict" "$PLIST"
#   $PB -c "Add :EnvironmentVariables:AEC_MIC_UID string <UID>" "$PLIST"
#   $PB -c "Add :EnvironmentVariables:AEC_SPK_UID string <UID>" "$PLIST"

plutil -lint "$PLIST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 2

if pgrep -f "$REPO/speexrelay" >/dev/null; then
  echo "설치하고 시작했다. 로그: $LOGDIR/relay.log"
else
  echo "설치는 됐으나 프로세스가 안 보인다. $LOGDIR/relay.err.log 를 본다." >&2
  exit 1
fi
