#!/usr/bin/env bash
# scripts/ci/shellcheck/run-scripts-ci.sh
#
# CI workflow `.github/workflows/shellcheck.yml` の
# 「scripts/ci/**/*.sh を走査（strict）」ステップ本体。
#
# `scripts/ci/` 配下は **エピック #174 完了条件**「shellcheck が全
# scripts/ci/**/*.sh で pass」（Issue #175）を満たすため除外なしで
# severity=warning で走査する。
#
# 使用例（workflow から）:
#   - name: scripts/ci/**/*.sh を走査（strict）
#     run: bash scripts/ci/shellcheck/run-scripts-ci.sh
#
# 入力: なし（カレントディレクトリがリポジトリルートである前提）
# 出力: stdout に対象一覧と shellcheck の結果。終了コードで pass/fail を返す。

set -euo pipefail

# 再帰探索は bash 3.2 (macOS デフォルト) 互換のため find -print0 + while read
# パターンを使う（shopt -s globstar は bash 4.0+ 限定で test-matrix の
# macos-latest で fail するため）
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
