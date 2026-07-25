#!/bin/bash
# MARKETING_VERSION patch(0.0.1) 상향 — 앱+위젯 두 타깃(project.pbxproj 4곳) 동시.
# main 머지 전 반드시 실행(pre-push 훅이 상향 여부를 강제 검증한다).
set -euo pipefail

PBX="$(cd "$(dirname "$0")/.." && pwd)/ios/Waito/Waito.xcodeproj/project.pbxproj"

cur=$(grep -m1 -o 'MARKETING_VERSION = [0-9][0-9.]*' "$PBX" | grep -o '[0-9][0-9.]*')
[ -n "$cur" ] || { echo "MARKETING_VERSION 을 찾지 못했습니다: $PBX" >&2; exit 1; }

IFS='.' read -ra p <<< "$cur"
major=${p[0]:-1}; minor=${p[1]:-0}; patch=${p[2]:-0}
new="$major.$minor.$((patch+1))"

# "= <cur>;" 세미콜론 경계로 정확히 치환 (1.2 가 1.2.1 을 잘못 건드리지 않음)
sed -i '' "s/MARKETING_VERSION = ${cur};/MARKETING_VERSION = ${new};/g" "$PBX"

n=$(grep -c "MARKETING_VERSION = ${new};" "$PBX")
echo "MARKETING_VERSION ${cur} → ${new}  (${n}곳 갱신)"
