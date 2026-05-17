#!/usr/bin/env bash
# scripts/ci/release/run-tests.sh
#
# release workflow（`.github/workflows/release.yml`）のテスト実行ステップ。
# tests/test_*.sh を全件実行し、いずれかが失敗したら終了コード 1 で終わる。
#
# 切り出し元: release.yml の "テスト実行" ステップ（Issue #179）。
# 同等のロジックは test.yml の "全テスト実行" にもあるが、各 workflow の
# 責務を分離するため scripts/ci/release/ と scripts/ci/test/ に二重配置する
# （ファイルは短く、divergence の余地を残す方針）。
#
# 使用例（workflow から）:
#   - name: テスト実行
#     run: bash scripts/ci/release/run-tests.sh
#
# 入力: なし（カレントディレクトリがリポジトリルートである前提）
# 出力: stdout に各テストの実行ログ。終了コードでテスト全体の成否を返す。

set -euo pipefail

shopt -s nullglob
files=(tests/test_*.sh)
if [ ${#files[@]} -eq 0 ]; then
  echo "テストファイルが見つかりません"
  exit 1
fi

failed=0
for f in "${files[@]}"; do
  echo "=== $f ==="
  bash "$f" || failed=1
done
exit "$failed"
