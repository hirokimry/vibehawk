#!/usr/bin/env bash
# 用途: shellcheck.yml の scripts/ci/**/*.sh 走査ステップ本体（Issue #175 エピック #174 完了条件）
#
# scripts/ci/ 配下は除外なし severity=warning で走査する（全件 pass が完了条件）。

set -euo pipefail

# shopt -s globstar は bash 4.0+ 限定で macos-latest が bash 3.2 のため使えない。
# find -print0 + while read で bash 3.2 互換の再帰探索を行う。
files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find scripts/ci -type f -name '*.sh' -print0 | sort -z)

if [ ${#files[@]} -eq 0 ]; then
  echo "scripts/ci/ 配下にシェルがない（基盤未配置）"
  exit 1
fi
echo "scripts/ci/ 対象 ${#files[@]} 件:"
printf '  %s\n' "${files[@]}"
shellcheck --severity=warning --shell=bash "${files[@]}"
