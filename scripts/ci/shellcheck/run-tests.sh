#!/usr/bin/env bash
# 用途: shellcheck.yml の tests/test_*.sh 走査ステップ本体（エピック #174 完了条件）
#
# SC2089/SC2090 を除外するのは、JSON 文字列を export 経由で後段 env に渡す
# 既存パターンに対する shellcheck の過検出（false positive）のため。
# export された変数は word splitting の対象外なので実害はない。
# 新規スクリプトでは `export VAR='value'`（assign + export 1 行）を推奨し、
# この除外に依存しないようにする。

set -euo pipefail

# tests/ は単一階層なので globstar 不要（bash 3.2 互換）
shopt -s nullglob
files=(tests/test_*.sh)
if [ ${#files[@]} -eq 0 ]; then
  echo "tests/ 配下にテストがない"
  exit 1
fi
echo "tests/ 対象 ${#files[@]} 件:"
printf '  %s\n' "${files[@]}"
shellcheck --severity=warning --shell=bash --exclude=SC2089,SC2090 "${files[@]}"
