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
# Issue #178（エピック #174）でインライン shell が `scripts/ci/vibehawk-review-skip-mark/`
# 配下に切り出された。yml 側は env: と `bash scripts/ci/.../<step>.sh` のラッパー呼び出しのみ
# になっているため、シェル内容の検証は対応する .sh ファイルで行う。
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
SCRIPTS_DIR="${REPO_ROOT}/scripts/ci/vibehawk-review-skip-mark"
LIST_SH="${SCRIPTS_DIR}/list-changed-files.sh"
CLASSIFY_SH="${SCRIPTS_DIR}/classify-paths-ignore.sh"
POST_SH="${SCRIPTS_DIR}/post-skip-check-run.sh"

echo "=== templates/.github/workflows/vibehawk-review-skip-mark.yml 検証 ==="

if [[ -f "$WORKFLOW" ]]; then
  pass "templates/.github/workflows/vibehawk-review-skip-mark.yml が存在する"
else
  fail "templates/.github/workflows/vibehawk-review-skip-mark.yml が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# 切り出し先 3 シェルが存在する（Issue #178）
for sh in "$LIST_SH" "$CLASSIFY_SH" "$POST_SH"; do
  if [[ -f "$sh" ]]; then
    pass "$(basename "$sh") が scripts/ci/vibehawk-review-skip-mark/ 配下に存在する"
  else
    fail "$(basename "$sh") が scripts/ci/vibehawk-review-skip-mark/ 配下に存在しない"
  fi
done

WORKFLOW_BODY="$(awk '!/^[[:space:]]*#/' "$WORKFLOW")"

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

if echo "$WORKFLOW_BODY" | grep -E "^concurrency:" > /dev/null; then
  pass "concurrency が設定されている"
else
  fail "concurrency が設定されていない"
fi

if echo "$WORKFLOW_BODY" | grep -E "cancel-in-progress:[[:space:]]*true" > /dev/null; then
  pass "cancel-in-progress: true が設定されている"
else
  fail "cancel-in-progress が true でない"
fi

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

if echo "$WORKFLOW_BODY" | grep -E "^[[:space:]]*pull_request_target:" > /dev/null; then
  fail "禁止トリガー 'pull_request_target' が設定されている"
else
  pass "禁止トリガー 'pull_request_target' が設定されていない"
fi

if echo "$WORKFLOW_BODY" | grep -F "github.event.pull_request.head.repo.full_name == github.repository" > /dev/null; then
  pass "Fork PR 除外条件が設定されている"
else
  fail "Fork PR 除外条件 (head.repo.full_name == github.repository) が設定されていない"
fi

if echo "$WORKFLOW_BODY" | grep -F "draft == false" > /dev/null; then
  pass "draft skip ロジックが設定されている"
else
  fail "draft skip ロジック (draft == false) が設定されていない"
fi

# Issue #178: yml 側の run: ブロックがラッパー呼び出しのみ（5 行以下）
# 各 step の `run:` 行が `bash scripts/ci/vibehawk-review-skip-mark/<name>.sh` 形式であることを確認
declare -a wrapper_calls=(
  "bash scripts/ci/vibehawk-review-skip-mark/list-changed-files.sh"
  "bash scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh"
  "bash scripts/ci/vibehawk-review-skip-mark/post-skip-check-run.sh"
)
for call in "${wrapper_calls[@]}"; do
  # ${call} を明示することで、後続の日本語ブラケット「」を bash 3.2 が識別子の
  # 一部と誤解しないようにする
  if grep -F "${call}" "$WORKFLOW" > /dev/null; then
    pass "yml がラッパー呼び出ししている: ${call}"
  else
    fail "yml がラッパー呼び出ししていない: ${call}"
  fi
done

# yml の 'run: |' ブロック（複数行インラインシェル）が残っていないこと
# Issue #178 の完了条件「全 3 ブロックの run: | が 5 行以下のラッパー呼び出しのみになっている」
# 注: pass/fail メッセージ内で backtick を使うと command substitution が走るため
#     シングルクォート相当の表現に統一する
if grep -E "^[[:space:]]+run:[[:space:]]*\|[[:space:]]*$" "$WORKFLOW" > /dev/null; then
  fail "yml に 'run: |' 複数行インラインシェルが残っている（Issue #178 で全廃すべき）"
else
  pass "yml に 'run: |' 複数行インラインシェルが残っていない"
fi

# 全 run: 行がラッパー呼び出し (bash scripts/ci/vibehawk-review-skip-mark/) であること
# 'run: |' 不在チェックだけだと 'run: echo ...' のような単行 inline shell が混入しても
# 通ってしまうので、run: 行総数とラッパー呼び出し行数の一致を担保する
total_runs=$(grep -cE "^[[:space:]]+run:[[:space:]]" "$WORKFLOW" || true)
wrapper_runs=$(grep -cE "^[[:space:]]+run:[[:space:]]+bash[[:space:]]+scripts/ci/vibehawk-review-skip-mark/" "$WORKFLOW" || true)
if [[ "$total_runs" -eq "$wrapper_runs" ]] && [[ "$total_runs" -gt 0 ]]; then
  pass "全 run: ($total_runs 件) がラッパー呼び出し (bash scripts/ci/vibehawk-review-skip-mark/) のみ"
else
  fail "run: 行の総数 ($total_runs) とラッパー呼び出し行数 ($wrapper_runs) が一致しない（単行 inline shell が混入の疑い）"
fi

declare -a required_case_patterns=(
  '.github/dependabot.yml)'
  'package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb)'
)
for pattern in "${required_case_patterns[@]}"; do
  if grep -F "$pattern" "$CLASSIFY_SH" > /dev/null; then
    pass "classify-paths-ignore.sh の case 文に paths-ignore パターン '$pattern' が含まれる（Issue #65 と同期）"
  else
    fail "classify-paths-ignore.sh の case 文に paths-ignore パターン '$pattern' が含まれない（Issue #65 同期失敗）"
  fi
done

VIBEHAWK_REVIEW_YML="${REPO_ROOT}/templates/.github/workflows/vibehawk-review.yml"
if [[ -f "$VIBEHAWK_REVIEW_YML" ]]; then
  paths_ignore_count=$(awk '
    /^[[:space:]]+paths-ignore:/ { in_block = 1; next }
    in_block && /^[[:space:]]+[a-z_-]+:/ { exit }
    in_block && /^[[:space:]]+-[[:space:]]/ { count++ }
    END { print count }
  ' "$VIBEHAWK_REVIEW_YML")

  case_branch_count=$(awk '
    /case[[:space:]]+"\$file"[[:space:]]+in/ { in_case = 1; next }
    in_case && /^[[:space:]]+esac/ { exit }
    in_case && /\)[[:space:]]+;;/ && !/^[[:space:]]+\*\)/ { count++ }
    END { print count }
  ' "$CLASSIFY_SH")

  case_pattern_total=$(awk '
    /case[[:space:]]+"\$file"[[:space:]]+in/ { in_case = 1; next }
    in_case && /^[[:space:]]+esac/ { exit }
    in_case && /\)[[:space:]]+;;/ && !/^[[:space:]]+\*\)/ {
      line = $0
      sub(/\)[[:space:]]+;;.*/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      n = split(line, parts, "|")
      count += n
    }
    END { print count }
  ' "$CLASSIFY_SH")

  echo "  [info] vibehawk-review.yml paths-ignore: ${paths_ignore_count} 件 / classify-paths-ignore.sh case 文: ${case_branch_count} branch (${case_pattern_total} pattern)"

  if [[ "$paths_ignore_count" -eq "$case_pattern_total" ]]; then
    pass "paths-ignore 件数 (${paths_ignore_count}) と case 文パターン総数 (${case_pattern_total}) が一致（同期検証）"
  else
    fail "paths-ignore 件数 (${paths_ignore_count}) と case 文パターン総数 (${case_pattern_total}) が不一致（同期失敗）"
  fi
else
  fail "vibehawk-review.yml (${VIBEHAWK_REVIEW_YML}) が存在しないため同期検証不可"
fi

if grep -F "name=vibehawk" "$POST_SH" > /dev/null; then
  pass "post-skip-check-run.sh で name=vibehawk が固定指定されている（branch protection 一致）"
else
  fail "post-skip-check-run.sh で name=vibehawk が固定指定されていない"
fi

if grep -F "status=completed" "$POST_SH" > /dev/null; then
  pass "post-skip-check-run.sh で status=completed が固定指定されている"
else
  fail "post-skip-check-run.sh で status=completed が固定指定されていない"
fi

if grep -F "conclusion=success" "$POST_SH" > /dev/null; then
  pass "post-skip-check-run.sh で conclusion=success が固定指定されている"
else
  fail "post-skip-check-run.sh で conclusion=success が固定指定されていない"
fi

if grep -F "gh api -X POST" "$POST_SH" | grep -F "/check-runs" > /dev/null; then
  pass "post-skip-check-run.sh に check-runs API への POST が含まれる"
else
  fail "post-skip-check-run.sh に check-runs API への POST が含まれない"
fi

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

if grep -E 'GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*secrets\.GITHUB_TOKEN[[:space:]]*\}\}' "$WORKFLOW" > /dev/null; then
  pass "GH_TOKEN に secrets.GITHUB_TOKEN を使用している（App Installation Token 不要）"
else
  fail "GH_TOKEN に secrets.GITHUB_TOKEN を使用していない"
fi

if grep -F "actions/create-github-app-token" "$WORKFLOW" > /dev/null; then
  fail "App Installation Token (actions/create-github-app-token) を参照している（skip-mark は GITHUB_TOKEN のみで動作すべき）"
else
  pass "App Installation Token を参照していない（GITHUB_TOKEN のみ使用、最小権限）"
fi

# actions/checkout@v4 が含まれている（Issue #178: 切り出し先 .sh を runner に展開するため必要）
if grep -F "actions/checkout@v4" "$WORKFLOW" > /dev/null; then
  pass "actions/checkout@v4 が含まれる（scripts/ci/ を runner に展開するため、Issue #178）"
else
  fail "actions/checkout@v4 が含まれない（切り出し先 .sh が runner で見つからない）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
