#!/bin/bash
# ⚠️ レビューパイプラインのライブ動作検証用テストスクリプト
#
# 目的:
#   vibehawk-review.yml と CodeRabbit が non-trivial severity の指摘を
#   実際に post できる状態にあるかを、確実に違反を含むコードで検証する。
#
# 重要:
#   本ファイルは意図的に shell.md 違反を含む。merge しない前提。
#   レビューで指摘が出たら検証成功 → PR クローズ → ブランチ削除する。

set -euo pipefail

target="/tmp/vibehawk-review-trigger-${RANDOM}.txt"
echo "before" > "$target"

# 違反 1: sed -i は shell.md で禁止（BSD/GNU 引数形式が異なり移植性なし）
sed -i 's/before/after/' "$target"

# 違反 2: grep に -e / -- 終端なしで - 始まりパターンを渡す（shell.md 違反）
pattern="-x"
grep -q "$pattern" "$target" || true

# 違反 3: basename | tr に printf '%s' での newline 剥がしを入れていない（shell.md 違反）
id="$(basename "$target" | tr -cs 'A-Za-z0-9._-' '_')"

echo "id=${id}"

rm -f "$target"
