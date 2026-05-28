#!/usr/bin/env bash
# 用途: vibehawk Pre-merge checks の Description check（Issue #229）
#
# 入力（環境変数）:
#   PR_BODY         PR 本文（必須）
#   GITHUB_OUTPUT   GitHub Actions step output ファイルパス（必須）
#
# 出力（GITHUB_OUTPUT に書き込み）:
#   description_check_status        passed / failed
#   description_check_explanation   判定理由（1 文）
#
# 判定基準:
#   PR 本文に以下のいずれかが含まれるかを grep で機械判定:
#   - Closes #N または Refs #N（関連 Issue 参照）
#   - ## 見出しが 1 つ以上（最低限の構造化）

set -euo pipefail

# PR_BODY は空文字を許容する（draft PR や本文未記入の PR を passed=failed で評価するため）。
# 旧 `: "${PR_BODY:?...}"` だと空文字でも fail し、step がエラー終了して
# 後続の pre_merge step に到達できない（CodeRabbit Major 指摘、PR #235）。
PR_BODY="${PR_BODY-}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

has_issue_ref=0
has_section=0
if printf '%s' "$PR_BODY" | grep -qiE '(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+#[0-9]+'; then
  has_issue_ref=1
fi
if printf '%s' "$PR_BODY" | grep -qE '^##[[:space:]]'; then
  has_section=1
fi

if [ "$has_issue_ref" -eq 1 ] && [ "$has_section" -eq 1 ]; then
  status="passed"
  explanation="PR 本文に Issue 参照 (Closes/Refs #N) と ## セクション見出しが含まれている"
elif [ "$has_issue_ref" -eq 0 ] && [ "$has_section" -eq 0 ]; then
  status="failed"
  explanation="PR 本文に Issue 参照 (Closes/Refs #N) も ## セクション見出しも含まれていない"
elif [ "$has_issue_ref" -eq 0 ]; then
  status="failed"
  explanation="PR 本文に Issue 参照 (Closes/Refs #N) が含まれていない"
else
  status="failed"
  explanation="PR 本文に ## セクション見出しが含まれていない"
fi

{
  printf 'description_check_status=%s\n' "$status"
  printf 'description_check_explanation=%s\n' "$explanation"
} >> "$GITHUB_OUTPUT"
