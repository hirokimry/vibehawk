#!/usr/bin/env bash
# 用途: vibehawk-review.yml の auto_resolve ステップ本体（Issue #167）
#
# 旧設計（Issue #9）では Claude prompt 内で graphql mutation を直接実行していたが、
# Claude の確率的応答に依存する副作用を排除するため workflow step に移管した
# （Issue #164 structured_output 経路確立 / Issue #166 event 判定移管に続く責務分離の完成）。
# Claude の責務は resolved_thread_ids を列挙するだけ。実際の resolve は本スクリプトが行う。
#
# 二重防御の構造:
#   1. case/esac glob で node_id 許可文字（Base64 + URL-safe Base64）のみを通す（Claude 暴走防御）
#   2. GraphQL から author.login を取得し vibehawk bot であることを再確認してから mutation 実行
# 他者・他 Bot の thread_id が混入していた場合は warning + skip で誤 resolve を防ぐ。
#
# 大文字 OWNER の正規化: github.repository_owner は大文字保持（例: "MyOrg"）だが
# GitHub App login は小文字正規化（例: "vibehawk-for-myorg"）のため、両側を tr で
# 小文字化してから比較する（CodeRabbit PR #193 Major 指摘対応）。
# GraphQL author.login は [bot] サフィックスなしで返る（REST API とは異なる GitHub GraphQL 仕様）。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${OWNER:?OWNER must be set}"
: "${STRUCTURED_OUTPUT:?STRUCTURED_OUTPUT must be set}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"

CLAUDE_OUT="${RUNNER_TEMP}/vibehawk-claude-output.auto-resolve.json"
printf '%s' "$STRUCTURED_OUTPUT" > "$CLAUDE_OUT"

# mapfile は bash 4+ 限定で macOS (bash 3.2) で動かないため while read を使う。
# 末尾 \r をトリムするのは Windows (git bash) の jq 出力に \r が混入し
# 許可文字判定で正常な node_id が弾かれる事象（PR #193）への対策。
thread_ids=()
while IFS= read -r line; do
  line="${line%$'\r'}"
  [[ -n "$line" ]] && thread_ids+=("$line")
done < <(jq -r '(.resolved_thread_ids // []) | .[]' "$CLAUDE_OUT")

if [[ ${#thread_ids[@]} -eq 0 ]]; then
  echo "vibehawk: 解決対象スレッドなし（resolved_thread_ids が 0 件、skip）"
  exit 0
fi

echo "vibehawk: 解決対象スレッド ${#thread_ids[@]} 件を resolved 化します"

# 全 reviewThread の id と author.login を一括取得（first: 100 は typical PR で十分、decide_event と同じ上限）
# 配置順は claude_review → auto_resolve → decide_event（decide_event が resolve 後の状態を見るため）
normalized_owner=$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')
EXPECTED_LOGIN="vibehawk-for-${normalized_owner}"
THREADS_JSON="${RUNNER_TEMP}/vibehawk-review-threads.json"
gh api graphql \
  -f query='query($owner: String!, $name: String!, $pr: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes { id comments(first: 1) { nodes { author { login } } } } } } } }' \
  -F owner="${REPO%%/*}" \
  -F name="${REPO##*/}" \
  -F pr="${PR_NUMBER}" > "$THREADS_JSON"

# node_id の許可文字チェックは case/esac glob で行う（grep -E / bash =~ は OS 間で実装差があり
# Windows runner で正常な node_id まで弾かれた事象を PR #193 で確認、bash glob は OS 非依存）。
# 旧形式は標準 Base64（+/=）、新形式は URL-safe Base64（-_）を使うため両方を許可する。
# 文字クラス内のハイフンは末尾に置かないと範囲指定子として誤解釈される（例: A-Za-z0-9...-）。

resolved_count=0
skipped_count=0
failed_count=0

for tid in "${thread_ids[@]}"; do
  # 空文字 or 許可外文字を含む thread id は弾く（Claude 暴走防御、shell.md 入力サニタイズ原則）
  case "$tid" in
    '' | *[!A-Za-z0-9+/=_-]* )
      echo "::warning::vibehawk: thread id が GitHub node_id 形式に一致しません（skip、誤入力 / Claude 暴走防御）"
      skipped_count=$((skipped_count + 1))
      continue
      ;;
  esac

  # 二重防御: 当該 thread の author.login を GraphQL から引き、vibehawk bot であることを確認する
  # 末尾 \r は Windows での jq 出力経由の混入防御（PR #193）
  author=$(jq -r --arg id "$tid" \
    '.data.repository.pullRequest.reviewThreads.nodes[] | select(.id == $id) | (.comments.nodes[0].author.login // "")' \
    "$THREADS_JSON")
  author="${author%$'\r'}"

  if [[ -z "$author" ]]; then
    echo "::warning::vibehawk: thread $tid が reviewThreads に見つかりません（skip）"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  # GraphQL は通常小文字だが、OWNER が大文字を含むケースと整合するため両側を正規化する
  normalized_author=$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')
  if [[ "$normalized_author" != "$EXPECTED_LOGIN" ]]; then
    echo "::warning::vibehawk: thread $tid の投稿者は ${author}（${EXPECTED_LOGIN} ではない）、誤 resolve 防止のため skip"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  # 個別失敗は warning + skip で後続 step を止めない（post-bundled-review.sh と同じパターン）
  if gh api graphql \
       -f query='mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { isResolved } } }' \
       -F id="$tid" > /dev/null; then
    resolved_count=$((resolved_count + 1))
  else
    echo "::warning::vibehawk: thread $tid の resolveReviewThread mutation に失敗しました（次の thread に進みます）"
    failed_count=$((failed_count + 1))
  fi
done

echo "vibehawk: auto_resolve 完了（resolved=${resolved_count}, skipped=${skipped_count}, failed=${failed_count}）"
