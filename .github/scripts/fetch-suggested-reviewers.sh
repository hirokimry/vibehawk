#!/usr/bin/env bash
# 用途: vibehawk Suggested reviewers セクション用のデータ取得（Issue #228）
#
# 入力（環境変数）:
#   REPO              owner/repo（必須）
#   PR_NUMBER         PR 番号（必須）
#   PR_AUTHOR         PR 作成者の login（必須、自己除外用）
#   GITHUB_OUTPUT     GitHub Actions step output ファイルパス（必須）
#
# 出力（GITHUB_OUTPUT に書き込み）:
#   suggested_reviewers_json   推奨レビュワーの 1 行 JSON 配列 ["login1","login2","login3"] 最大 3 名
#
# 責務:
#   - 1 段目: CODEOWNERS から該当ファイルの owner を抽出（簡易実装、glob は完全一致のみ）。
#   - 2 段目: CODEOWNERS 空 or 該当なしなら git log の上位コミッターから 3 名（自己除外）。
#   - 取得失敗時は空配列 [] で degrade。

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${PR_AUTHOR:?PR_AUTHOR must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

reviewers_json='[]'

# 機能: PR 変更ファイル一覧を取得
changed_files="$(gh pr diff "$PR_NUMBER" --repo "$REPO" --name-only 2>/dev/null || printf '')"

# 機能: CODEOWNERS が存在すれば該当行から @login を抽出する
codeowners_file=""
for path in CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
  if [ -f "$path" ]; then
    codeowners_file="$path"
    break
  fi
done

owners=()
if [ -n "$codeowners_file" ] && [ -n "$changed_files" ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    # 各 CODEOWNERS 行をチェック: 「pattern @owner1 @owner2」形式
    while IFS= read -r line; do
      # コメント / 空行を skip
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [ -z "${line// /}" ] && continue
      pattern=$(printf '%s' "$line" | awk '{print $1}')
      # シンプル glob 一致（`*.sh` / `docs/**/*.md` / `tests/**` 等の bash glob で評価）
      # shellcheck disable=SC2053
      if [[ "$file" == $pattern ]]; then
        # @login 形式を抽出（@team 形式は skip、個人ユーザーのみ）
        for token in $(printf '%s' "$line" | awk '{for(i=2;i<=NF;i++) print $i}'); do
          if [[ "$token" =~ ^@[a-zA-Z0-9_-]+$ ]] && [[ ! "$token" =~ / ]]; then
            owner="${token#@}"
            if [ "$owner" != "$PR_AUTHOR" ]; then
              owners+=("$owner")
            fi
          fi
        done
      fi
    done < "$codeowners_file"
  done <<< "$changed_files"
fi

# 機能: CODEOWNERS で見つからなければ git log 上位コミッターを取得
if [ "${#owners[@]}" -eq 0 ]; then
  # 直近 50 commit から author 一意を頻度順
  while IFS= read -r commiter; do
    [ -z "$commiter" ] && continue
    # GitHub login を email から取れないので、git log の email ローカルパートを fallback として使う
    login="${commiter%@*}"
    # noreply 系は skip（例: 123456+user@users.noreply.github.com → user 抽出）
    if [[ "$login" =~ ^[0-9]+\+(.+)$ ]]; then
      login="${BASH_REMATCH[1]}"
    fi
    if [ -n "$login" ] && [ "$login" != "$PR_AUTHOR" ]; then
      owners+=("$login")
    fi
  done < <(git log --format='%ae' -n 50 2>/dev/null | sort | uniq -c | sort -rn | awk '{print $2}' | head -10)
fi

# 機能: 一意化 + 上位 3 名に絞る
if [ "${#owners[@]}" -gt 0 ]; then
  # 配列の一意化（順序保持）
  unique=()
  for o in "${owners[@]}"; do
    skip=0
    for u in "${unique[@]+"${unique[@]}"}"; do
      if [ "$u" = "$o" ]; then
        skip=1
        break
      fi
    done
    [ "$skip" -eq 0 ] && unique+=("$o")
  done
  # 上位 3 名のみ
  top3=("${unique[@]:0:3}")
  reviewers_json="$(jq -n -c --args '$ARGS.positional' "${top3[@]+"${top3[@]}"}")"
fi

printf 'suggested_reviewers_json=%s\n' "$reviewers_json" >> "$GITHUB_OUTPUT"
