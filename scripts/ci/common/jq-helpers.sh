#!/usr/bin/env bash
# scripts/ci/common/jq-helpers.sh
#
# jq の安全な使い方をまとめたヘルパー関数群。
#
# 重要な規約（`/vibecorp:ship` SKILL.md「制約」セクションより）:
#   jq では string interpolation `\(...)` を使わない。
#   Bash 上で `\` がエスケープ文字、`()` がサブシェルとして解釈され、
#   意図しない展開やパースエラーを引き起こすため。必ず `+` で結合する。
#
# 推奨パターン（外部入力を含む JSON 文字列構築）:
#   jq -n --arg prefix "件数: " --arg n "$count" '$prefix + $n'
#   # NOT: jq -n --arg n "$count" '"件数: \($n)"'
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

# 任意個数の文字列を `+` 結合で連結して 1 つの JSON 文字列値として stdout に出す。
#
# Usage: jq_concat <part1> [<part2> ...]
#
# 各 part は jq の `--arg` で渡されるため、Bash 側で特殊文字エスケープを意識する
# 必要はない。jq の string interpolation `\(...)` は使わず、`+` で連結する。
#
# 例:
#   jq_concat "件数: " "$count"
#   #=> "件数: 42"  （jq の出力は double-quote 付き文字列）
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

# 既存 JSON オブジェクトに「文字列値」のキーを追加する（jq の `+` でマージ）。
#
# Usage: jq_obj_set_str <json_object> <key> <string_value>
#
# - <json_object>: 例 `{"a":1}` または `{}`
# - <key>: 例 `b`
# - <string_value>: 例 `value`（任意の文字列、jq の `--arg` で安全に渡される）
#
# stdout に拡張済み JSON を流す。
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
