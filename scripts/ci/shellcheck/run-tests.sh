#!/usr/bin/env bash
# scripts/ci/shellcheck/run-tests.sh
#
# CI workflow `.github/workflows/shellcheck.yml` の
# 「tests/test_*.sh を走査」ステップ本体。
#
# `tests/` は `.claude/rules/testing.md` の規約により本ジョブの走査対象に
# 含める（エピック #174 完了条件「scripts/ci/**/*.sh と tests/test_*.sh を
# 走査して fail させる」）。ただし以下の 2 件は **JSON 文字列を export 経由で
# 後段プロセスに env として渡す既存パターン** に対する shellcheck 側の
# 過検出（false positive）であり、export された変数は word splitting の
# 対象外であるため実害がない:
#   - SC2089: Quotes/backslashes will be treated literally
#   - SC2090: Quotes/backslashes in this variable will not be respected
# これらは tests/ 配下にのみ適用し、scripts/ci/ には適用しない
# （scripts/ci/ 走査は scripts/ci/shellcheck/run-scripts-ci.sh）。
# 新規スクリプトでは `export VAR='value'` 形式（assign + export を 1 行に
# まとめる）を推奨することで本除外に依存しないこと。
#
# 使用例（workflow から）:
#   - name: tests/test_*.sh を走査
#     run: bash scripts/ci/shellcheck/run-tests.sh
#
# 入力: なし（カレントディレクトリがリポジトリルートである前提）
# 出力: stdout に対象一覧と shellcheck の結果。終了コードで pass/fail を返す。

set -euo pipefail

# tests/test_*.sh は単一ディレクトリ単一階層のため nullglob だけで足りる
# （globstar/** は不要、bash 3.2 互換）
shopt -s nullglob
files=(tests/test_*.sh)
if [ ${#files[@]} -eq 0 ]; then
  echo "tests/ 配下にテストがない"
  exit 1
fi
echo "tests/ 対象 ${#files[@]} 件:"
printf '  %s\n' "${files[@]}"
shellcheck --severity=warning --shell=bash --exclude=SC2089,SC2090 "${files[@]}"
