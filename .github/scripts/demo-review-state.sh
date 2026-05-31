#!/usr/bin/env bash
# 用途: レビュー state 遷移のデモ用ターゲット（#282 検証、マージしない）
set -euo pipefail

# Round 1: 外部入力を eval（コマンドインジェクション = actionable な脆弱性）
run_user_command() {
  local user_input="$1"
  eval "$user_input"
}

run_user_command "$@"
