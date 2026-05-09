#!/usr/bin/env bash
# Issue #8: vibehawk-review.yml の prev_summary ステップで使う
# 種別マーカー検出と SHA 抽出ロジックの単体テスト
#
# 検証対象（vibehawk-review.yml prev_summary ステップ内 inline bash と同等のロジック）:
# - body に `<!-- vibehawk:summary -->` を含むコメントの検出
# - body から `<!-- vibehawk:sha=<hex> -->` の SHA 抽出（grep -oE）
# - 投稿者 ID + 種別マーカーの二重チェック（jq 経由のシミュレーション）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

# 種別マーカー検出: body に <!-- vibehawk:summary --> を含む
echo "=== 種別マーカー検出（vibehawk:summary） ==="

body_with_marker='## vibehawk レビュー
変更内容のサマリ。

<!-- vibehawk:summary -->
<!-- vibehawk:sha=abc123def456 -->'

if echo "$body_with_marker" | grep -F '<!-- vibehawk:summary -->' > /dev/null; then
  pass "マーカー入り body が検出される"
else
  fail "マーカー入り body が検出されない"
fi

body_without_marker='## レビュー
マーカーなしのコメント'

if echo "$body_without_marker" | grep -F '<!-- vibehawk:summary -->' > /dev/null; then
  fail "マーカーなし body が誤検出される"
else
  pass "マーカーなし body は検出されない（正しい）"
fi

# SHA 抽出: <!-- vibehawk:sha=<hex> --> から hex 部分を抽出
echo "=== SHA 抽出（vibehawk:sha=<hex>） ==="

extract_sha() {
  # workflow yaml の prev_summary ステップと同等のロジック
  echo "$1" | grep -oE 'vibehawk:sha=[a-f0-9]+' | sed 's/vibehawk:sha=//' | head -1 || echo ""
}

# 通常ケース: 7 文字の短縮 SHA
sha_short="$(extract_sha 'body...
<!-- vibehawk:summary -->
<!-- vibehawk:sha=abc1234 -->')"
if [[ "$sha_short" == "abc1234" ]]; then
  pass "短縮 SHA (7 文字) を抽出"
else
  fail "短縮 SHA 抽出失敗: '$sha_short'"
fi

# 通常ケース: 40 文字フル SHA
sha_full="$(extract_sha 'body...
<!-- vibehawk:summary -->
<!-- vibehawk:sha=abc1234567890abcdef1234567890abcdef12345 -->')"
if [[ "$sha_full" == "abc1234567890abcdef1234567890abcdef12345" ]]; then
  pass "フル SHA (40 文字) を抽出"
else
  fail "フル SHA 抽出失敗: '$sha_full'"
fi

# マーカーが複数ある場合: 最初のものを採用
sha_first="$(extract_sha '<!-- vibehawk:sha=aaa1111 -->
<!-- vibehawk:sha=bbb2222 -->')"
if [[ "$sha_first" == "aaa1111" ]]; then
  pass "複数マーカー時に最初の SHA を抽出"
else
  fail "複数マーカー時の挙動が想定と異なる: '$sha_first'"
fi

# SHA がない場合: 空文字
sha_empty="$(extract_sha 'body without sha marker')"
if [[ -z "$sha_empty" ]]; then
  pass "SHA なしの body から空文字を返す"
else
  fail "SHA なし body から空でない値が返った: '$sha_empty'"
fi

# 不正な SHA（非 hex 文字）: 抽出されない
sha_invalid="$(extract_sha '<!-- vibehawk:sha=ZZZINVALID -->')"
if [[ -z "$sha_invalid" ]]; then
  pass "非 hex 文字を含む SHA マーカーは抽出されない"
else
  fail "非 hex 文字 SHA が誤抽出された: '$sha_invalid'"
fi

# 投稿者 ID + 種別マーカー二重チェック（jq シミュレーション）
echo "=== 投稿者 ID + 種別マーカーの二重チェック（jq） ==="

owner="alice"
bot_login="vibehawk-for-${owner}[bot]"

# テストデータ: 異なる投稿者 + 異なる body の混在
mock_comments='[
  {"user": {"login": "github-actions[bot]"}, "body": "<!-- vibehawk:summary -->", "created_at": "2026-01-01T00:00:00Z", "id": 1},
  {"user": {"login": "vibehawk-for-alice[bot]"}, "body": "old summary <!-- vibehawk:summary -->", "created_at": "2026-01-02T00:00:00Z", "id": 2},
  {"user": {"login": "vibehawk-for-alice[bot]"}, "body": "comment without marker", "created_at": "2026-01-03T00:00:00Z", "id": 3},
  {"user": {"login": "vibehawk-for-alice[bot]"}, "body": "latest summary <!-- vibehawk:summary -->", "created_at": "2026-01-04T00:00:00Z", "id": 4}
]'

# 二重チェック: 投稿者 == bot_login かつ body に マーカー含む → 4 のみ抽出
selected="$(echo "$mock_comments" | jq -r --arg bot "$bot_login" \
  '[.[] | select(.user.login == $bot) | select(.body | contains("<!-- vibehawk:summary -->"))] | sort_by(.created_at) | last | .id')"

if [[ "$selected" == "4" ]]; then
  pass "二重チェックで vibehawk-for-alice[bot] の最新サマリ (id=4) を選択"
else
  fail "二重チェック結果が想定と異なる: '$selected' (期待: 4)"
fi

# 投稿者違いを除外: github-actions[bot] のマーカー入り body は採用されない
github_actions_excluded="$(echo "$mock_comments" | jq -c --arg bot "$bot_login" \
  '[.[] | select(.user.login == $bot) | select(.body | contains("<!-- vibehawk:summary -->"))] | sort_by(.created_at) | map(.id)')"

if [[ "$github_actions_excluded" == "[2,4]" ]]; then
  pass "github-actions[bot] のサマリは投稿者チェックで除外される（[2,4] のみ採用）"
else
  fail "投稿者チェックの除外結果が想定と異なる: '$github_actions_excluded' (期待: [2,4])"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
