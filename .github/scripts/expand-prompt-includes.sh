#!/usr/bin/env bash
# 用途: プロンプト .md 内の include マーカーを参照先ファイルの内容に展開して stdout に出す（Issue #330）
#
# 背景: CI レビュー基準（severity 5 段階・inline フィールド定義・actionable/nitpick 判定）を
# 単一ソース templates/review-prompt.md に切り出し、CI とローカル CLI（npx vibehawk review、子2 #331）が
# 同じファイルを参照してレビュー基準のブレを防ぐ。CI 側は本スクリプトでマーカーを展開してから
# load-vibehawk-prompt.sh が envsubst にパイプする（展開は envsubst の前段、whitelist は不変）。
#
# マーカー形式: 行全体が `<!-- vibehawk:include <path> -->`（path は repo root 相対）
# 展開は 1 段のみ（展開後の内容は再スキャンしない＝ネスト include 無限ループ防止）
#
# 入力: $1 = 展開対象ファイル
# 出力: stdout に展開済みテキスト（envsubst はしない）
# 異常: include 先不在・絶対パス・`..` traversal・許可外 charset は error + exit 1

set -euo pipefail

SRC="${1:?usage: expand-prompt-includes.sh <file>}"

if [[ ! -f "$SRC" ]]; then
  echo "::error::vibehawk: 展開対象ファイルが見つかりません: ${SRC}" >&2
  exit 1
fi

# include パスの解決基点は repo root に固定する（呼び出し元の cwd 依存を排除）。
# CI は checkout 直後 repo root が cwd だが、git で明示解決し、取得失敗時のみ PWD にフォールバックする。
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$PWD"
fi

# awk 一本でマーカー検出・パス検証・参照先読み出しを行う（shell.md: grep -e/sed -i を避ける、
# パス文字列を shell に渡さずインジェクション余地を排除）。BSD/GNU 両対応のため sub/getline/~ のみ使用。
awk -v base="$REPO_ROOT" -v src="$SRC" '
function fail(msg) {
  printf("::error::vibehawk: %s\n", msg) > "/dev/stderr"
  exit 1
}
{
  if ($0 ~ /^<!-- vibehawk:include .+ -->$/) {
    path = $0
    sub(/^<!-- vibehawk:include /, "", path)
    sub(/ -->$/, "", path)

    if (path ~ /^\//)                  fail("include パスに絶対パスは使えません: " path " (" src ":" NR ")")
    if (path ~ /(^|\/)\.\.(\/|$)/)     fail("include パスに .. は使えません: " path " (" src ":" NR ")")
    if (path !~ /^[A-Za-z0-9._\/-]+$/) fail("include パスに使用できない文字があります: " path " (" src ":" NR ")")

    full = base "/" path
    first = (getline line < full)
    if (first < 0) fail("include 先が見つかりません: " full " (" src ":" NR ")")
    printf("vibehawk: include 展開: %s\n", path) > "/dev/stderr"
    if (first > 0) {
      print line
      while ((getline line < full) > 0) print line
    }
    close(full)
  } else {
    print
  }
}
' "$SRC"
