#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/load-config.sh
#
# vibehawk-chat.yml の `vibehawk 設定読み込み（locale 等）` step を切り出した
# スクリプト（Issue #10 / Issue #172 / Issue #177）。`.vibehawk.yaml` の
# `language` キーを読み取り、GITHUB_OUTPUT に `language=<value>` を書き出す。
#
# 仕様（Issue #172 で .coderabbit.yaml フォールバック撤廃）:
#   - `.vibehawk.yaml` 存在時: yaml の `language` キー（未指定なら "en"）を採用
#   - `.vibehawk.yaml` 不在時: "en" にフォールバック
#
# 入力（環境変数）:
#   GITHUB_OUTPUT  -- GitHub Actions が自動付与する step output ファイルパス
#
# 出力:
#   GITHUB_OUTPUT: language=<value>

set -euo pipefail

# 設定ファイル選択（.vibehawk.yaml 単独受付、Issue #10 / #172）
# Issue #172 で .coderabbit.yaml フォールバック分岐を撤廃。
# `.vibehawk.yaml` 不在時は下記の default language ('en') に倒れる。
config_file=""
if [[ -f ".vibehawk.yaml" ]]; then
  config_file=".vibehawk.yaml"
fi

language="en"
if [[ -n "$config_file" ]]; then
  python3 -c "import yaml" 2>/dev/null || pip install --user --quiet pyyaml
  config_json="$(python3 -c "import yaml,json; print(json.dumps(yaml.safe_load(open('$config_file')) or {}))")"
  language="$(echo "$config_json" | jq -r '.language // "en"')"
fi

echo "language=$language" >> "$GITHUB_OUTPUT"
