#!/usr/bin/env bash
# 用途: vibehawk Recent review info セクション用のデータ取得（Issue #226）
#
# 入力（環境変数）:
#   REPO               owner/repo（必須）
#   PR_NUMBER          PR 番号（必須）
#   PATH_FILTERS_JSON  .vibehawk.yaml の reviews.path_filters（JSON 配列、空配列許容）
#                      include / exclude glob のみサポート（`!pattern` で除外）。
#                      複雑な構文拡張は YAGNI（必要になった時点で別 Issue）。
#   GITHUB_OUTPUT      GitHub Actions が用意する step output ファイルパス（必須）
#
# 出力（GITHUB_OUTPUT に書き込み）:
#   commits_json         PR commits の 1 行 JSON（`gh api .../commits` の生出力を jq -c 1 行化）
#   files_selected_json  処理対象ファイル一覧（path_filters 適用後）の 1 行 JSON 配列
#   files_ignored_json   除外ファイル一覧（path_filters マッチ）の 1 行 JSON 配列
#
# 責務:
#   - gh からのデータ取得 + シンプル include/exclude glob によるファイル分類のみ。
#   - GITHUB_OUTPUT 書き込みは load-config.sh と同じ `key=value`（jq -c で 1 行化）パターン。

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
PATH_FILTERS_JSON="${PATH_FILTERS_JSON:-[]}"

# 機能: PR の commits 配列を取得して 1 行 JSON 化する。
# `gh api --paginate` はページごとに別 JSON 配列を出力する場合があるため、`jq -s 'add'` で
# 全ページを 1 配列に集約してから 1 行 JSON 化する（複数行混入で GITHUB_OUTPUT を壊さない）。
commits_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/commits" --paginate \
  | jq -s -c '(add // []) | if type == "array" then map({sha}) else [] end')"

# 機能: PR の変更ファイル一覧を取得して 1 行 JSON 配列にする
files_all_json="$(gh pr diff "$PR_NUMBER" --repo "$REPO" --name-only \
  | jq -R -s -c 'split("\n") | map(select(length > 0))')"

# 機能: path_filters を include / exclude に分割する
# `!pattern` → exclude、それ以外 → include。
# include 空なら「全件 include」扱い。
include_patterns="$(printf '%s' "$PATH_FILTERS_JSON" | jq -c 'map(select(startswith("!") | not))')"
# 要素単位で `!` で始まる要素だけ残してから先頭の `!` を除去する（map の中で select + 変換を行う）
exclude_patterns="$(printf '%s' "$PATH_FILTERS_JSON" | jq -c 'map(select(startswith("!")) | .[1:])')"

# 機能: 1 ファイルが パターンリストのいずれかにマッチするか判定する
# POSIX `case` 文を使用（bash `[[ ]]` の glob 評価は Windows Git Bash で
# path separator を超えないという挙動差があるため、全環境で一貫する `case` を採用）。
# パターン中の `**` は事前に `*` に置換する（POSIX glob で `**` は `*` と等価だが、
# 入力側の表記揺れを吸収する）。
# **Windows Git Bash 対応**: process substitution `< <(...)` は Windows で一部の組み合わせで
# 動かないことがあるため、一時ファイル経由で while ループに食わせる（test_fetch_recent_review_info.sh
# の Case 2 が Windows でのみ落ちていた PR #235 fix）。
glob_match() {
  local path="$1"
  local patterns_json="$2"
  local pat tmp
  tmp="$(mktemp)"
  printf '%s' "$patterns_json" | jq -r '.[]?' > "$tmp"
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    pat="${pat//\*\*/*}"
    case "$path" in
      $pat) rm -f "$tmp"; return 0 ;;
    esac
  done < "$tmp"
  rm -f "$tmp"
  return 1
}

# 機能: 1 ファイルが include / exclude のどちらに該当するかを判定する
# 採用判定: 1) exclude にマッチ → 除外、2) include 空 or マッチ → 採用、3) include 非空でマッチなし → 除外
classify_files() {
  local files_json="$1"
  local include_json="$2"
  local exclude_json="$3"
  local files_count include_count
  files_count="$(printf '%s' "$files_json" | jq -r 'length')"
  include_count="$(printf '%s' "$include_json" | jq -r 'length')"

  local selected=()
  local ignored=()
  local i path

  for ((i = 0; i < files_count; i++)); do
    path="$(printf '%s' "$files_json" | jq -r --argjson i "$i" '.[$i]')"

    # exclude にマッチすれば除外
    if glob_match "$path" "$exclude_json"; then
      ignored+=("$path")
      continue
    fi

    # include 空なら全件採用
    if [ "$include_count" -eq 0 ]; then
      selected+=("$path")
      continue
    fi

    # include にマッチすれば採用、しなければ除外
    if glob_match "$path" "$include_json"; then
      selected+=("$path")
    else
      ignored+=("$path")
    fi
  done

  # bash 配列を JSON 配列にする（jq の --args + $ARGS.positional で安全に encode）
  printf '%s\n' "$(jq -n -c --args '$ARGS.positional' "${selected[@]+"${selected[@]}"}")"
  printf '%s\n' "$(jq -n -c --args '$ARGS.positional' "${ignored[@]+"${ignored[@]}"}")"
}

# 機能: classify_files の 2 行出力を読み取る
classify_output="$(classify_files "$files_all_json" "$include_patterns" "$exclude_patterns")"
files_selected_json="$(printf '%s' "$classify_output" | sed -n '1p')"
files_ignored_json="$(printf '%s' "$classify_output" | sed -n '2p')"

# GITHUB_OUTPUT に書き込み（load-config.sh と同じ key=value 形式、jq -c 1 行化済み）
{
  printf 'commits_json=%s\n' "$commits_json"
  printf 'files_selected_json=%s\n' "$files_selected_json"
  printf 'files_ignored_json=%s\n' "$files_ignored_json"
} >> "$GITHUB_OUTPUT"
