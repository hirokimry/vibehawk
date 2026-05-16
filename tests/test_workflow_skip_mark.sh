#!/usr/bin/env bash
# vibehawk-review-skip-mark.yml workflow テンプレートの仕様検証（Issue #157）
#
# 目的:
#   `templates/.github/workflows/vibehawk-review-skip-mark.yml` が以下を満たすことを検証する:
#     - paths-ignore 全マッチ判定の 5 パターン同期（Issue #160 で `**/*.md` / `CHANGELOG*` を撤回）
#     - required status check `vibehawk` の success post
#     - 最小権限 (checks: write のみ)、禁止権限不在、禁止トリガー不在
#     - Fork PR 除外 / draft skip
#     - 同期コメント（保守者向け）の存在
#
# `.github/workflows/vibehawk-review-skip-mark.yml`（dogfooding 用デプロイコピー）は
# `test_workflow_template_snapshot.sh` の SYNC_PAIRS で templates と完全一致が
# 検証されるため、本テストでは templates のみを検査する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

WORKFLOW="${REPO_ROOT}/templates/.github/workflows/vibehawk-review-skip-mark.yml"

echo "=== templates/.github/workflows/vibehawk-review-skip-mark.yml 検証 ==="

# ファイル存在（前提: 不在なら全後続テスト無意味）
if [[ -f "$WORKFLOW" ]]; then
  pass "templates/.github/workflows/vibehawk-review-skip-mark.yml が存在する"
else
  fail "templates/.github/workflows/vibehawk-review-skip-mark.yml が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# コメント行を除外したワークフロー本文（行頭 # を除外）
WORKFLOW_BODY="$(awk '!/^[[:space:]]*#/' "$WORKFLOW")"

# pull_request トリガー
if echo "$WORKFLOW_BODY" | grep -E "^[[:space:]]*pull_request:" > /dev/null; then
  pass "pull_request トリガーが設定されている"
else
  fail "pull_request トリガーが設定されていない"
fi

# 必須イベントタイプ 4 種（vibehawk-review.yml と揃える）
for evt in opened synchronize ready_for_review review_requested; do
  if echo "$WORKFLOW_BODY" | grep -F "$evt" > /dev/null; then
    pass "イベントタイプ $evt が設定されている"
  else
    fail "イベントタイプ $evt が設定されていない"
  fi
done

# concurrency
if echo "$WORKFLOW_BODY" | grep -E "^concurrency:" > /dev/null; then
  pass "concurrency が設定されている"
else
  fail "concurrency が設定されていない"
fi

# cancel-in-progress: true
if echo "$WORKFLOW_BODY" | grep -E "cancel-in-progress:[[:space:]]*true" > /dev/null; then
  pass "cancel-in-progress: true が設定されている"
else
  fail "cancel-in-progress が true でない"
fi

# 必須権限（最小）
declare -a required_perms=(
  "checks:[[:space:]]*write"
  "pull-requests:[[:space:]]*read"
  "contents:[[:space:]]*read"
)
declare -a required_perm_labels=(
  "checks: write"
  "pull-requests: read"
  "contents: read"
)
for i in "${!required_perms[@]}"; do
  pattern="${required_perms[$i]}"
  label="${required_perm_labels[$i]}"
  if echo "$WORKFLOW_BODY" | grep -E "$pattern" > /dev/null; then
    pass "permissions: $label が設定されている"
  else
    fail "permissions: $label が設定されていない"
  fi
done

# 禁止権限不在（autonomous-restrictions §6）
declare -a forbidden_perms=(
  "administration:[[:space:]]*write"
  "secrets:[[:space:]]*write"
  "workflows:[[:space:]]*write"
  "id-token:[[:space:]]*write"
)
declare -a forbidden_labels=(
  "administration: write"
  "secrets: write"
  "workflows: write"
  "id-token: write"
)
for i in "${!forbidden_perms[@]}"; do
  pattern="${forbidden_perms[$i]}"
  label="${forbidden_labels[$i]}"
  if echo "$WORKFLOW_BODY" | grep -E "$pattern" > /dev/null; then
    fail "禁止権限 $label が設定されている"
  else
    pass "禁止権限 $label が設定されていない"
  fi
done

# 禁止トリガー不在: pull_request_target
if echo "$WORKFLOW_BODY" | grep -E "^[[:space:]]*pull_request_target:" > /dev/null; then
  fail "禁止トリガー 'pull_request_target' が設定されている"
else
  pass "禁止トリガー 'pull_request_target' が設定されていない"
fi

# Fork PR 除外条件
if echo "$WORKFLOW_BODY" | grep -F "github.event.pull_request.head.repo.full_name == github.repository" > /dev/null; then
  pass "Fork PR 除外条件が設定されている"
else
  fail "Fork PR 除外条件 (head.repo.full_name == github.repository) が設定されていない"
fi

# draft skip
if echo "$WORKFLOW_BODY" | grep -F "draft == false" > /dev/null; then
  pass "draft skip ロジックが設定されている"
else
  fail "draft skip ロジック (draft == false) が設定されていない"
fi

# paths-ignore 全マッチ判定の 5 パターン同期検証（vibehawk-review.yml と完全一致が必須）
# case 文の各パターン存在チェック（Issue #160 で `*.md)` / `CHANGELOG*)` を撤回）
declare -a required_case_patterns=(
  '.github/dependabot.yml)'
  'package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb)'
)
for pattern in "${required_case_patterns[@]}"; do
  if grep -F "$pattern" "$WORKFLOW" > /dev/null; then
    pass "case 文に paths-ignore パターン '$pattern' が含まれる（Issue #65 と同期）"
  else
    fail "case 文に paths-ignore パターン '$pattern' が含まれない（Issue #65 同期失敗）"
  fi
done

# vibehawk-review.yml の paths-ignore リストと数を照合（同期検証）
# vibehawk-review.yml から paths-ignore リストを抽出
VIBEHAWK_REVIEW_YML="${REPO_ROOT}/templates/.github/workflows/vibehawk-review.yml"
if [[ -f "$VIBEHAWK_REVIEW_YML" ]]; then
  # paths-ignore: 以降、次のトップレベルキー or 空行までのパターン数をカウント
  paths_ignore_count=$(awk '
    /^[[:space:]]+paths-ignore:/ { in_block = 1; next }
    in_block && /^[[:space:]]+[a-z_-]+:/ { exit }
    in_block && /^[[:space:]]+-[[:space:]]/ { count++ }
    END { print count }
  ' "$VIBEHAWK_REVIEW_YML")

  # skip-mark の case 文パターン数（`) ;;` で終わる行）
  # default branch (`  *) all_match=false; break ;;`) のみ除外したいので、
  # 行頭空白の直後が `*)` のもの（= default branch）だけを除外する。
  # `CHANGELOG*)` などパターン末尾の `*)` は対象に含める。
  case_branch_count=$(awk '
    /case[[:space:]]+"\$file"[[:space:]]+in/ { in_case = 1; next }
    in_case && /^[[:space:]]+esac/ { exit }
    in_case && /\)[[:space:]]+;;/ && !/^[[:space:]]+\*\)/ { count++ }
    END { print count }
  ' "$WORKFLOW")

  # case branch 内に含まれる総パターン数（| 区切りで展開）
  case_pattern_total=$(awk '
    /case[[:space:]]+"\$file"[[:space:]]+in/ { in_case = 1; next }
    in_case && /^[[:space:]]+esac/ { exit }
    in_case && /\)[[:space:]]+;;/ && !/^[[:space:]]+\*\)/ {
      # `) ;;` の直前までを取り出して | で分割
      line = $0
      sub(/\)[[:space:]]+;;.*/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      n = split(line, parts, "|")
      count += n
    }
    END { print count }
  ' "$WORKFLOW")

  echo "  [info] vibehawk-review.yml paths-ignore: ${paths_ignore_count} 件 / skip-mark case 文: ${case_branch_count} branch (${case_pattern_total} pattern)"

  if [[ "$paths_ignore_count" -eq "$case_pattern_total" ]]; then
    pass "paths-ignore 件数 (${paths_ignore_count}) と case 文パターン総数 (${case_pattern_total}) が一致（同期検証）"
  else
    fail "paths-ignore 件数 (${paths_ignore_count}) と case 文パターン総数 (${case_pattern_total}) が不一致（同期失敗）"
  fi
else
  fail "vibehawk-review.yml (${VIBEHAWK_REVIEW_YML}) が存在しないため同期検証不可"
fi

# check-run post の固定パラメータ
if echo "$WORKFLOW_BODY" | grep -F "name=vibehawk" > /dev/null; then
  pass "check-run post に name=vibehawk が固定指定されている（branch protection 一致）"
else
  fail "check-run post に name=vibehawk が固定指定されていない"
fi

if echo "$WORKFLOW_BODY" | grep -F "status=completed" > /dev/null; then
  pass "check-run post に status=completed が固定指定されている"
else
  fail "check-run post に status=completed が固定指定されていない"
fi

if echo "$WORKFLOW_BODY" | grep -F "conclusion=success" > /dev/null; then
  pass "check-run post に conclusion=success が固定指定されている"
else
  fail "check-run post に conclusion=success が固定指定されていない"
fi

# check-runs エンドポイント
if echo "$WORKFLOW_BODY" | grep -F "gh api -X POST" | grep -F "/check-runs" > /dev/null; then
  pass "check-runs API への POST が含まれる"
else
  fail "check-runs API への POST が含まれない"
fi

# 同期コメント（保守者向け）— ファイル冒頭のハードコード同期コメント
if grep -F "同期" "$WORKFLOW" > /dev/null && grep -F "vibehawk-review.yml" "$WORKFLOW" > /dev/null; then
  pass "保守者向け同期コメント（vibehawk-review.yml との同期必須）が含まれる"
else
  fail "保守者向け同期コメント（vibehawk-review.yml との同期必須）が含まれない"
fi

if grep -F "Issue #157" "$WORKFLOW" > /dev/null; then
  pass "Issue #157 の出典コメントが含まれる"
else
  fail "Issue #157 の出典コメントが含まれない"
fi

# GITHUB_TOKEN のみ使用（App Installation Token 不要）
if grep -E 'GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*secrets\.GITHUB_TOKEN[[:space:]]*\}\}' "$WORKFLOW" > /dev/null; then
  pass "GH_TOKEN に secrets.GITHUB_TOKEN を使用している（App Installation Token 不要）"
else
  fail "GH_TOKEN に secrets.GITHUB_TOKEN を使用していない"
fi

# App Installation Token を参照していないこと（経路 2 不要、最小権限）
if grep -F "actions/create-github-app-token" "$WORKFLOW" > /dev/null; then
  fail "App Installation Token (actions/create-github-app-token) を参照している（skip-mark は GITHUB_TOKEN のみで動作すべき）"
else
  pass "App Installation Token を参照していない（GITHUB_TOKEN のみ使用、最小権限）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
