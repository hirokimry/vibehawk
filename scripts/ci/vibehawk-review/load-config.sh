#!/usr/bin/env bash
# 用途: vibehawk-review.yml の設定読み込みステップ本体（Issue #10 / #172）
#
# .vibehawk.yaml 単独受付（Issue #172 で .coderabbit.yaml フォールバック撤廃）。
# 変更ファイル数を閾値と照合して depth を段階的劣化型で決定する（docs/cost-analysis.md）。

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

config_file=""
source_label="default"
if [[ -f ".vibehawk.yaml" ]]; then
  config_file=".vibehawk.yaml"
  source_label="vibehawk"
fi

# デフォルト値（docs/cost-analysis.md 段階的劣化型）
language="en"
full_review_files=30
focused_review_files=80
skip_inline_files=3000
path_filters="[]"
path_instructions="[]"

# 非負整数でない値は警告 + デフォルトにフォールバックして job を落とさない
is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

if [[ -n "$config_file" ]]; then
  # ubuntu-latest には PyYAML がプリインストール済みだが念のため pip install フォールバックを入れる
  python3 -c "import yaml" 2>/dev/null || pip install --user --quiet pyyaml

  config_json="$(python3 -c "import yaml,json; print(json.dumps(yaml.safe_load(open('$config_file')) or {}))")"

  # .vibehawk.yaml のスキーマ（Issue #10）
  language="$(echo "$config_json" | jq -r '.language // "en"')"
  raw_full="$(echo "$config_json" | jq -r '.reviews.size_limits.full_review_files // 30')"
  raw_focused="$(echo "$config_json" | jq -r '.reviews.size_limits.focused_review_files // 80')"
  raw_skip="$(echo "$config_json" | jq -r '.reviews.size_limits.skip_inline_files // 3000')"
  path_filters="$(echo "$config_json" | jq -c '.reviews.path_filters // []')"
  path_instructions="$(echo "$config_json" | jq -c '.reviews.path_instructions // []')"

  if is_uint "$raw_full"; then full_review_files="$raw_full"; else
    echo "::warning::vibehawk: reviews.size_limits.full_review_files が非負整数ではない（'$raw_full'）。デフォルト 30 にフォールバック。"
  fi
  if is_uint "$raw_focused"; then focused_review_files="$raw_focused"; else
    echo "::warning::vibehawk: reviews.size_limits.focused_review_files が非負整数ではない（'$raw_focused'）。デフォルト 80 にフォールバック。"
  fi
  if is_uint "$raw_skip"; then skip_inline_files="$raw_skip"; else
    echo "::warning::vibehawk: reviews.size_limits.skip_inline_files が非負整数ではない（'$raw_skip'）。デフォルト 3000 にフォールバック。"
  fi
fi

# PR 変更ファイル数と閾値を照合して depth を段階的劣化型で決定する（docs/cost-analysis.md）
fc="${FILES_COUNT:-0}"
if [[ "$fc" -ge "$skip_inline_files" ]]; then
  depth="summary_only"
elif [[ "$fc" -ge "$focused_review_files" ]]; then
  depth="lightweight"
elif [[ "$fc" -ge "$full_review_files" ]]; then
  depth="focused"
else
  depth="full"
fi

echo "vibehawk: 設定ソース=${source_label}, 言語=${language}, ファイル数=${fc}, depth=${depth}"

echo "config_source=$source_label" >> "$GITHUB_OUTPUT"
echo "language=$language" >> "$GITHUB_OUTPUT"
echo "files_count=$fc" >> "$GITHUB_OUTPUT"
echo "depth=$depth" >> "$GITHUB_OUTPUT"
# 多行 JSON は GITHUB_OUTPUT で破損するため jq -c で 1 行化している
echo "path_filters=$path_filters" >> "$GITHUB_OUTPUT"
echo "path_instructions=$path_instructions" >> "$GITHUB_OUTPUT"
