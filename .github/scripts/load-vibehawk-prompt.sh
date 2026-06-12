#!/usr/bin/env bash
# 用途: vibehawk-review.yml の長文プロンプトを外部 .md から読み込み、envsubst で動的値を展開する
#
# 背景: vibehawk-review.yml の prompt: | block が GitHub Actions の expression length 21000 chars
# 制限を超えて startup_failure を起こしていた（PR #235）。長文プロンプトを外部
# .github/prompts/vibehawk-review.md に切り出し、ここで envsubst による動的値展開を行う。
#
# Issue #330: レビュー基準（severity 5 段階・inline フィールド定義等）を単一ソース
# templates/review-prompt.md に切り出し、CI とローカル CLI（子2 #331）で共有する。CI 側は
# expand-prompt-includes.sh で include マーカーを展開してから envsubst にパイプする
# （展開は envsubst の前段。whitelist 展開は不変で sensitive env は非展開を維持）。
#
# 入力（環境変数）: prompt 内で参照される値全て（REPO / PR_NUMBER / HEAD_SHA 等、14 種）
# 出力: GITHUB_OUTPUT に `content<<__VIBEHAWK_PROMPT_EOF__` 形式で展開済みプロンプトを書き出す

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# デフォルトは本スクリプトと同じリポジトリ内の prompts/ を指す（SCRIPT_DIR 相対）。
# 外部リポジトリでは runtime checkout（.vibehawk-runtime/）内の本スクリプトが実行されるため、
# CWD（対象リポジトリ root）相対だと prompt が見つからず破綻する（Issue #346）。
PROMPT_FILE="${PROMPT_FILE:-${SCRIPT_DIR}/../prompts/vibehawk-review.md}"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "::error::vibehawk: プロンプトファイルが見つかりません: $PROMPT_FILE" >&2
  exit 1
fi

# envsubst は全 env を展開する挙動だが、第 1 引数で展開対象 env を明示すれば
# それ以外の env (sensitive な ANTHROPIC_API_KEY 等) は展開されない安全運用。
EXPANDED_VARS='${REPO} ${PR_NUMBER} ${HEAD_SHA} ${BASE_REF} ${INCREMENTAL_MODE} ${EXISTING_COMMENT_ID} ${PREV_SHA} ${REVIEW_RANGE} ${CONFIG_SOURCE} ${LANGUAGE} ${FILES_COUNT} ${DEPTH} ${PATH_FILTERS_JSON} ${PATH_INSTRUCTIONS_JSON}'

# GitHub Actions の multi-line output は heredoc delimiter で囲む必要がある。
# プロンプト本文に偶然出現しない unique な delimiter を使う。
# include マーカー展開を envsubst の前段にパイプする（Issue #330）。pipefail 下で
# expand 失敗（include 先不在等）はそのまま非ゼロ終了し、CI を fail させる。
{
  echo 'content<<__VIBEHAWK_PROMPT_EOF__'
  "${SCRIPT_DIR}/expand-prompt-includes.sh" "$PROMPT_FILE" | envsubst "$EXPANDED_VARS"
  echo '__VIBEHAWK_PROMPT_EOF__'
} >> "$GITHUB_OUTPUT"
