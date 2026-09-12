#!/bin/bash
# maecrelay를 N초 띄운 뒤 종료. 실행 중에 외부 검사(audiodiag 등)를 하려면
# 별도 터미널에서 이 스크립트를 돌리고 있으면 된다.
cd /Users/user/Git/mac-aec-relay
exec ./maecrelay --mode a
