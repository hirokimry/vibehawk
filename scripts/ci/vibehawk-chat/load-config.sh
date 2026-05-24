#!/usr/bin/env bash
# 用途: vibehawk-chat.yml の設定読み込みステップ本体（Issue #10 / #172 / #177）
#
# .vibehawk.yaml の language キーを読み取り GITHUB_OUTPUT に書き出す。
# Issue #172 で .coderabbit.yaml フォールバックを撤廃し、.vibehawk.yaml 単独受付に統一。

set -euo pipefail

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
