#!/usr/bin/env bash
# 用途: レビュー state 遷移のデモ用ターゲット（#282 検証、マージしない）
set -euo pipefail

# Round 2: 脆弱性なし。受け取った 2 つの整数を加算して出力する正しい実装。
add_two_numbers() {
  local a="$1"
  local b="$2"
  local tmp
  tmp=$(( a + b ))
  echo "${tmp}"
}

add_two_numbers "$@"
