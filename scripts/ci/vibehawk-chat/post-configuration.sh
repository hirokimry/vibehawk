#!/usr/bin/env bash
# 用途: `@vibehawk configuration` コマンドで現在適用中の vibehawk 設定を返す（Issue #294、epic #289 子5）。
#       表示のみ・書き換えなし・LLM 不要。GitHub 内テキストのみで構成し外部 URL を埋めない。
#
# カレントの .vibehawk.yaml を読み取り、不在 / 不正 YAML の場合は default 値を表示する。
# .vibehawk.yaml は language / size_limits / path 設定のみで secrets を含まない設計のため、
# 表示しても機密情報は漏れない（VIBEHAWK_APP_ID 等は GitHub Secrets 管理で .vibehawk.yaml に非記載）。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER must be set}"

# default 値（docs/cost-analysis.md / load-config.sh と整合）
language="en"
full_review_files="30"
focused_review_files="80"
skip_inline_files="3000"
path_filters_count="0"
path_instructions_count="0"
source_label="default（.vibehawk.yaml なし）"

if [[ -f ".vibehawk.yaml" ]]; then
  # load-config.sh と同じ python→json 解析。pyyaml 不在なら導入を試みる（best-effort、失敗しても落とさない）。
  # 不正 YAML / python 不在 / 導入失敗時は default 表示にフォールバックする。
  config_json=""
  if ! python3 -c "import yaml" 2>/dev/null; then
    pip install --user --quiet pyyaml 2>/dev/null || true
  fi
  if python3 -c "import yaml" 2>/dev/null; then
    config_json="$(python3 -c "import yaml,json; print(json.dumps(yaml.safe_load(open('.vibehawk.yaml')) or {}))" 2>/dev/null || printf '')"
  fi
  if [[ -n "$config_json" ]]; then
    source_label=".vibehawk.yaml"
    language="$(printf '%s' "$config_json" | jq -r '.language // "en"')"
    full_review_files="$(printf '%s' "$config_json" | jq -r '.size_limits.full_review_files // 30')"
    focused_review_files="$(printf '%s' "$config_json" | jq -r '.size_limits.focused_review_files // 80')"
    skip_inline_files="$(printf '%s' "$config_json" | jq -r '.size_limits.skip_inline_files // 3000')"
    path_filters_count="$(printf '%s' "$config_json" | jq -r '(.path_filters // []) | length')"
    path_instructions_count="$(printf '%s' "$config_json" | jq -r '(.path_instructions // []) | length')"
  else
    source_label="default（.vibehawk.yaml の解析に失敗）"
  fi
fi

body="$(cat <<EOF
🦅 vibehawk: 現在の設定（ソース: ${source_label}）

\`\`\`yaml
language: ${language}
size_limits:
  full_review_files: ${full_review_files}
  focused_review_files: ${focused_review_files}
  skip_inline_files: ${skip_inline_files}
path_filters: ${path_filters_count} 件
path_instructions: ${path_instructions_count} 件
\`\`\`
EOF
)"

gh issue comment "$ISSUE_NUMBER" --body "$body"
