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
  # PyYAML での解析を試みる。本番の chat workflow は ubuntu-latest で PyYAML がプリインストール
  # 済みのため解析できる。pyyaml 不在環境（一部 OS）や不正 YAML では default 表示にフォールバックする。
  # 実行時の pip install は行わない（テスト runner 等の環境を汚染しないため）。
  config_json=""
  if python3 -c "import yaml" 2>/dev/null; then
    config_json="$(python3 -c "import yaml,json; print(json.dumps(yaml.safe_load(open('.vibehawk.yaml')) or {}))" 2>/dev/null || printf '')"
  fi
  if [[ -n "$config_json" ]]; then
    source_label=".vibehawk.yaml"
    # `?` で型不正（例: size_limits: "oops" / path_filters: foo）でも jq を非 0 で落とさず、
    # 各キーは default にフォールバックする（schema 崩れでも configuration コマンドを落とさない）。
    language="$(printf '%s' "$config_json" | jq -r '.language? // "en"' 2>/dev/null || printf 'en')"
    full_review_files="$(printf '%s' "$config_json" | jq -r '.size_limits?.full_review_files? // 30' 2>/dev/null || printf '30')"
    focused_review_files="$(printf '%s' "$config_json" | jq -r '.size_limits?.focused_review_files? // 80' 2>/dev/null || printf '80')"
    skip_inline_files="$(printf '%s' "$config_json" | jq -r '.size_limits?.skip_inline_files? // 3000' 2>/dev/null || printf '3000')"
    path_filters_count="$(printf '%s' "$config_json" | jq -r '((.path_filters? | arrays) // []) | length' 2>/dev/null || printf '0')"
    path_instructions_count="$(printf '%s' "$config_json" | jq -r '((.path_instructions? | arrays) // []) | length' 2>/dev/null || printf '0')"
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
