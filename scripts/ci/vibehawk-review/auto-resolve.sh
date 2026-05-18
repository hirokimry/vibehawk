#!/usr/bin/env bash
# scripts/ci/vibehawk-review/auto-resolve.sh
#
# vibehawk-review.yml の "vibehawk auto_resolve（直った旧指摘を resolved 化、
# Issue #167）" ステップの本体。
#
# Issue #167: 旧設計（Issue #9）では Claude prompt 内で `gh api graphql
# resolveReviewThread` mutation を直接実行していた。これは Claude の確率的
# 応答に依存する最後の副作用であり、Issue #164（structured_output 経路の
# 確立）/ Issue #166（event 判定の workflow 移管）に続く責務分離の完成形
# として workflow step に移管する。Claude の責務は「解決対象 thread の
# node_id を `resolved_thread_ids` 配列に列挙する」だけになる。
#
# 設計:
#   1. STRUCTURED_OUTPUT から resolved_thread_ids を抽出（無ければ空配列扱い、jq | read
#      経由の Windows での \r 混入は ${var%$'\r'} でトリム）
#   2. 各 thread_id が GitHub node_id の許可文字（標準 Base64 `+/=` + URL-safe Base64
#      `-_` を網羅）のみで構成されていることを bash 内蔵 `case/esac` glob パターン
#      `*[!A-Za-z0-9+/=_-]*` で検証（GraphQL 入力サニタイズ、Claude 暴走防御、
#      OS 非依存）
#   3. GraphQL で全 reviewThread の {id, comments.nodes[0].author.login} を一括取得
#   4. 各 thread_id について author.login が `vibehawk-for-${OWNER}` 小文字正規化値
#      であることを二重防御として再検証してから resolveReviewThread mutation 実行
#   5. 他者・他 Bot の thread_id が混入していた場合は warning + skip（誤 resolve 防止）
#
# 大文字 OWNER の正規化: github.repository_owner は大文字保持（例: "MyOrg"）だが
# GitHub App login は小文字正規化（例: "vibehawk-for-myorg"）。比較前に両側を tr で
# 小文字化する（CodeRabbit PR #193 Major 指摘対応）。
#
# bot 表記差異の注意: GraphQL author.login は bot を `[bot]` サフィックスなしの
# app slug で返す（GitHub GraphQL 仕様、REST API とは異なる）。比較は
# 小文字正規化された `vibehawk-for-${OWNER}` 単独で行う。
#
# 入力 env:
#   GH_TOKEN            — App installation token（vibehawk-for-<owner>[bot] 名義）
#   REPO                — owner/repo
#   PR_NUMBER           — 対象 PR の番号
#   OWNER               — github.repository_owner、author 比較用
#   STRUCTURED_OUTPUT   — claude-code-action outputs.structured_output（JSON 文字列）
#   RUNNER_TEMP         — GitHub Actions runner の一時ディレクトリ
#
# 終了コード:
#   0 — 正常終了（個別 mutation 失敗は warning + skip で次に進む、step 全体は
#        止めない。post-bundled-review.sh と同じパターン）
#   非 0 — 必須 env 欠落 / 事前 GraphQL クエリ自体の失敗（根本的な API 障害）

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${OWNER:?OWNER must be set}"
: "${STRUCTURED_OUTPUT:?STRUCTURED_OUTPUT must be set}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"

CLAUDE_OUT="${RUNNER_TEMP}/vibehawk-claude-output.auto-resolve.json"
printf '%s' "$STRUCTURED_OUTPUT" > "$CLAUDE_OUT"

# 1. resolved_thread_ids を抽出（未定義/null/欠落でも空配列として吸収）。
# mapfile は bash 4+ 専用で macOS 標準 bash 3.x では動かないため、while read で配列に詰める
# （CI の ubuntu-latest は bash 4+ だが、開発者ローカルが macOS のケースもあるため互換性確保）。
# 末尾の `\r` をトリムする: git for Windows bash で jq | read 経由のテキスト処理に
# `\r` が混入し、後段の許可文字判定で正常な node_id まで skip される事象（PR #193）の防御。
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

# 2. 全 reviewThread の {id, 投稿者 login} を一括取得（first: 100 で typical PR は十分カバー、
# decide_event.sh と同じ上限。auto_resolve mutation 後の状態を decide_event が見るため
# 配置順は claude_review → auto_resolve → decide_event）。
#
# CodeRabbit PR #193 Major 指摘対応: github.repository_owner は GitHub Actions が大文字
# 表記をそのまま保持する（例: "MyOrg"）。一方、GitHub App のログイン名は GitHub 側で
# 小文字正規化される（例: "vibehawk-for-myorg"）。混在ケースで誤って有効 thread を
# skip しないよう、両側を小文字に正規化してから比較する。bash 3.2 互換のため `tr` を使う。
normalized_owner=$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')
EXPECTED_LOGIN="vibehawk-for-${normalized_owner}"
THREADS_JSON="${RUNNER_TEMP}/vibehawk-review-threads.json"
gh api graphql \
  -f query='query($owner: String!, $name: String!, $pr: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes { id comments(first: 1) { nodes { author { login } } } } } } } }' \
  -F owner="${REPO%%/*}" \
  -F name="${REPO##*/}" \
  -F pr="${PR_NUMBER}" > "$THREADS_JSON"

# GitHub node_id の許可文字（標準 Base64 + URL-safe Base64 を網羅）。
# 旧形式 node_id（例: `MDc6...`）は標準 Base64（`+`, `/`, `=`）を、新形式（例: `PRRT_xxx`）
# は URL-safe Base64（`-`, `_`）を使うため、両方を許可する必要がある。空白やシェルメタ
# 文字は含まれない。Claude が暴走して異常文字列を返した場合の GraphQL 入力サニタイズ
# （.claude/rules/shell.md「ユーザー入力値をファイルパスに組み込む前にサニタイズする」
# と同じ原則）。許可外文字を含む or 空文字なら warning + skip で次の thread へ。
#
# 判定は `case ... esac` の glob パターン（bash 内蔵、OS 間で一致挙動）で行う。
# `grep -E` や bash `=~` は MinGW / GNU / BSD で実装差があり、正常な node_id まで
# 弾かれる事象を PR #193 の Windows runner で確認した。bash glob は bash 本体実装の
# pattern matching で、ubuntu / macos / git for Windows bash すべてで同一挙動。
# 注: 文字クラス内のハイフン `-` は範囲指定子として解釈されないよう **必ず最後** に置く。

resolved_count=0
skipped_count=0
failed_count=0

for tid in "${thread_ids[@]}"; do
  # 入力サニタイズ: 空文字 or 許可外文字を含む thread id を弾く（bash glob, OS 非依存）。
  # `*[!A-Za-z0-9+/=_-]*` は「許可外文字を 1 つでも含む」glob パターン。
  case "$tid" in
    '' | *[!A-Za-z0-9+/=_-]* )
      echo "::warning::vibehawk: thread id が GitHub node_id 形式に一致しません（skip、誤入力 / Claude 暴走防御）"
      skipped_count=$((skipped_count + 1))
      continue
      ;;
  esac

  # 二重防御: GraphQL レスポンスから当該 thread の最初コメントの author.login を引く
  # 末尾 `\r` を念のためトリム（Windows での jq 出力経由の混入防御、PR #193）
  author=$(jq -r --arg id "$tid" \
    '.data.repository.pullRequest.reviewThreads.nodes[] | select(.id == $id) | (.comments.nodes[0].author.login // "")' \
    "$THREADS_JSON")
  author="${author%$'\r'}"

  if [[ -z "$author" ]]; then
    echo "::warning::vibehawk: thread $tid が reviewThreads に見つかりません（skip）"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  # author.login は GraphQL では通常小文字で返るが、念のため両側を小文字化して比較する
  # （github.repository_owner が大文字を含む場合の正規化と整合）。
  normalized_author=$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')
  if [[ "$normalized_author" != "$EXPECTED_LOGIN" ]]; then
    echo "::warning::vibehawk: thread $tid の投稿者は ${author}（${EXPECTED_LOGIN} ではない）、誤 resolve 防止のため skip"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  # resolveReviewThread mutation 実行。個別失敗は warning + skip で次へ進む（後続 step を止めない、
  # 既存 post-bundled-review.sh の「validation 失敗で exit 0」パターンと整合）。
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
