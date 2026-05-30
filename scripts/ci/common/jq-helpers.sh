#!/usr/bin/env bash
# 用途: jq の安全な文字列構築ヘルパー関数群
#
# jq の string interpolation `\(...)` は Bash 上で `\` と `()` が展開・解釈され
# 意図しないパースエラーを起こすため、`+` 結合に統一する（shell.md 準拠）。
#
# 使用例:
#   source "$(dirname "$0")/../common/jq-helpers.sh"
#   jq_concat "PR #" "$pr_number" " のレビューを開始します"
#   #=> "PR #175 のレビューを開始します"
#
#   jq_obj_set_str '{"a":1}' "b" "value"
#   #=> {"a":1,"b":"value"}

# 多重 source 防止
if [[ -n "${VIBEHAWK_CI_JQ_HELPERS_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
VIBEHAWK_CI_JQ_HELPERS_LOADED=1

# shellcheck source=./log.sh
. "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# 機能: 任意個数の文字列を jq の `+` 結合で連結し JSON 文字列として stdout に出す
# 各 part を --arg で渡すため、Bash 側の特殊文字エスケープは不要。
jq_concat() {
  if [[ $# -lt 1 ]]; then
    log_error "jq_concat: 少なくとも 1 つの引数が必要です"
    return 2
  fi

  local args=()
  local filter=""
  local i=0
  for part in "$@"; do
    args+=(--arg "p${i}" "$part")
    if [[ $i -eq 0 ]]; then
      filter="\$p${i}"
    else
      filter="${filter} + \$p${i}"
    fi
    i=$((i + 1))
  done

  jq -n "${args[@]}" "$filter"
}

# 機能: 既存 JSON オブジェクトに文字列値のキーを追加する（jq `+` でマージ）
jq_obj_set_str() {
  local base="${1:-}"
  local key="${2:-}"
  local value="${3:-}"

  if [[ -z "$base" || -z "$key" ]]; then
    log_error "jq_obj_set_str: base と key が必須です"
    return 2
  fi

  jq -n \
    --argjson base "$base" \
    --arg k "$key" \
    --arg v "$value" \
    '$base + {($k): $v}'
}
