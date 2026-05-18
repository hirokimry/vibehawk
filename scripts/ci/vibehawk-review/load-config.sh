#!/usr/bin/env bash
# scripts/ci/vibehawk-review/load-config.sh
#
# vibehawk-review.yml の "vibehawk 設定読み込み（Issue #10 / #172 .vibehawk.yaml）"
# ステップ（旧 L187 インライン）の本体。
#
# `.vibehawk.yaml` を単独受付（Issue #172 で `.coderabbit.yaml` フォールバック撤廃）し、
# `language` / `reviews.size_limits.*` / `reviews.path_filters` / `reviews.path_instructions`
# を取り出す。さらに PR の変更ファイル数を閾値と照合して depth（full / focused /
# lightweight / summary_only）を段階的劣化型で決定する（docs/cost-analysis.md 仕様）。
#
# 入力 env:
#   FILES_COUNT   — PR の changed_files 数
#
# 出力 GITHUB_OUTPUT:
#   config_source=vibehawk|default
#   language=ja|en|<その他>
#   files_count=<整数>
#   depth=full|focused|lightweight|summary_only
#   path_filters=<jq -c 1行 JSON 配列>
#   path_instructions=<jq -c 1行 JSON 配列>

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

# 設定ファイル選択（.vibehawk.yaml 単独受付、Issue #10 / #172）
# Issue #172 で .coderabbit.yaml フォールバック分岐を撤廃。
# `.vibehawk.yaml` 不在時は下記のデフォルト値に倒れる。
config_file=""
source_label="default"
if [[ -f ".vibehawk.yaml" ]]; then
  config_file=".vibehawk.yaml"
  source_label="vibehawk"
fi

# デフォルト値（docs/cost-analysis.md 段階的劣化型、`.vibehawk.yaml` 不在時に適用）
language="en"
full_review_files=30
focused_review_files=80
skip_inline_files=3000
path_filters="[]"
path_instructions="[]"

# 非負整数判定（`.vibehawk.yaml` の数値設定が文字列や負数だった場合に
# set -e の `[[ "$fc" -ge "$skip_inline_files" ]]` で job を落とさず、警告 +
# デフォルト値フォールバックで吸収する）
is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

if [[ -n "$config_file" ]]; then
  # PyYAML 可用性確認（ubuntu-latest はプリインストール、念のため pip install フォールバック）
  python3 -c "import yaml" 2>/dev/null || pip install --user --quiet pyyaml

  # YAML → JSON 変換
  config_json="$(python3 -c "import yaml,json; print(json.dumps(yaml.safe_load(open('$config_file')) or {}))")"

  # キーマッピング（.vibehawk.yaml のスキーマ、Issue #10）
  language="$(echo "$config_json" | jq -r '.language // "en"')"
  raw_full="$(echo "$config_json" | jq -r '.reviews.size_limits.full_review_files // 30')"
  raw_focused="$(echo "$config_json" | jq -r '.reviews.size_limits.focused_review_files // 80')"
  raw_skip="$(echo "$config_json" | jq -r '.reviews.size_limits.skip_inline_files // 3000')"
  path_filters="$(echo "$config_json" | jq -c '.reviews.path_filters // []')"
  path_instructions="$(echo "$config_json" | jq -c '.reviews.path_instructions // []')"

  # 数値設定のバリデーション（誤設定時はデフォルトに倒す）
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

# depth 決定（PR 変更ファイル数 → 段階的劣化、docs/cost-analysis.md 仕様）
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
# 多行 JSON はそのままだと GITHUB_OUTPUT で破損するため、jq -c で 1 行化済
echo "path_filters=$path_filters" >> "$GITHUB_OUTPUT"
echo "path_instructions=$path_instructions" >> "$GITHUB_OUTPUT"
