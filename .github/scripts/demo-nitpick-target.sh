#!/usr/bin/env bash
# 用途: nitpick-only レビューのデモ用ターゲット（#282 検証、マージしない）
set -euo pipefail

# 受け取った 2 つの整数を加算して出力する（脆弱性なし・正しい実装）。
add_two_numbers() {
  local a="$1"
  local b="$2"
  local tmp
  tmp=$(( a + b ))
  echo "${tmp}"
}

add_two_numbers "$@"
