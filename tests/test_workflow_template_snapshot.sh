#!/usr/bin/env bash
# vibehawk workflow テンプレートのスナップショット検証（Issue #29）
#
# 目的: `templates/.github/workflows/vibehawk-{review,chat}.yml`（npm 配布される
#      テンプレート本体）が `.claude/rules/autonomous-restrictions.md` §6 で
#      禁止された権限・トリガー・条件削除を含まないことを CI で機械検証する。
#
# `.github/workflows/vibehawk-{review,chat}.yml`（dogfooding 用デプロイコピー）は
# 存在する場合のみ追加検査する。dogfooding teardown（Issue #56）等で一時的に
# 削除されるケースを許容するため、不在は failure 扱いしない。
#
# CISO Major 条件: 自動化があってこそ permissions 固定の実効性が高い。
# CI 必須実行（required check）として位置づける。

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

# 必須検証対象（npm 配布されるテンプレート本体、review + chat 両方、Issue #11）
REQUIRED_TARGETS=(
  "templates/.github/workflows/vibehawk-review.yml"
  "templates/.github/workflows/vibehawk-chat.yml"
)

# 任意検証対象（dogfooding 用デプロイコピー、不在は許容、Issue #56 teardown 経路）
OPTIONAL_TARGETS=(
  ".github/workflows/vibehawk-review.yml"
  ".github/workflows/vibehawk-chat.yml"
)

TARGETS=("${REQUIRED_TARGETS[@]}")
for opt in "${OPTIONAL_TARGETS[@]}"; do
  if [[ -f "$opt" ]]; then
    TARGETS+=("$opt")
  fi
done

echo "=== vibehawk workflow テンプレート スナップショット検証 ==="

# 必須対象は不在で fail、任意対象（OPTIONAL_TARGETS）は事前に存在チェック済みで TARGETS に含まれる
for target in "${TARGETS[@]}"; do
  if [[ ! -f "$target" ]]; then
    fail "$target が存在しない（テンプレートとして必須）"
    continue
  fi
  pass "$target が存在する"

  # コメント行を除外（YAML として無効な状態でないことの軽い保護）
  body="$(awk '!/^[[:space:]]*#/' "$target")"

  # 禁止権限パターン（autonomous-restrictions.md §6）
  declare -a forbidden_perms=(
    "administration:[[:space:]]*write"
    "secrets:[[:space:]]*write"
    "workflows:[[:space:]]*write"
    "id-token:[[:space:]]*write"
  )
  declare -a forbidden_perm_labels=(
    "administration: write"
    "secrets: write"
    "workflows: write"
    "id-token: write"
  )

  for i in "${!forbidden_perms[@]}"; do
    pattern="${forbidden_perms[$i]}"
    label="${forbidden_perm_labels[$i]}"
    if echo "$body" | grep -E "$pattern" > /dev/null; then
      fail "$target に禁止権限 '$label' が混入"
    else
      pass "$target に禁止権限 '$label' が含まれない"
    fi
  done

  # 禁止トリガー: pull_request_target（Fork PR + secrets 参照は最大の攻撃経路）
  if echo "$body" | grep -E "^[[:space:]]*pull_request_target:" > /dev/null; then
    fail "$target に禁止トリガー 'pull_request_target' が混入"
  else
    pass "$target に禁止トリガー 'pull_request_target' が含まれない"
  fi

  # 経路 2 必須化（#59 / #61）: 利用者の 3 secrets が必ず参照される（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）
  declare -a required_secrets=(
    "VIBEHAWK_APP_ID"
    "VIBEHAWK_PRIVATE_KEY"
    "CLAUDE_CODE_OAUTH_TOKEN"
  )
  for sec in "${required_secrets[@]}"; do
    if echo "$body" | grep -F "$sec" > /dev/null; then
      pass "$target に必須 secret '$sec' が参照されている（経路 2）"
    else
      fail "$target に必須 secret '$sec' が参照されていない（経路 2 必須化、#59）"
    fi
  done

  # 経路 2 必須化（#59）: actions/create-github-app-token@v2 が必須
  if echo "$body" | grep -F "actions/create-github-app-token" > /dev/null; then
    pass "$target に actions/create-github-app-token が含まれる（経路 2 App Installation Token）"
  else
    fail "$target に actions/create-github-app-token が含まれない（経路 2 必須化、#59）"
  fi
done

# templates/ と .github/ のテンプレートが完全一致していることを検証（snapshot 等価性）
# dogfooding 用 workflow は配布用テンプレートと同一でなければならない（ドリフト防止）
declare -a SYNC_PAIRS=(
  "templates/.github/workflows/vibehawk-review.yml|.github/workflows/vibehawk-review.yml"
  "templates/.github/workflows/vibehawk-chat.yml|.github/workflows/vibehawk-chat.yml"
  "templates/.github/workflows/vibehawk-review-skip-mark.yml|.github/workflows/vibehawk-review-skip-mark.yml"
)

for pair in "${SYNC_PAIRS[@]}"; do
  src="${pair%|*}"
  dst="${pair#*|}"
  if [[ -f "$src" && -f "$dst" ]]; then
    if diff -u "$src" "$dst" > /dev/null; then
      pass "$src と $dst が完全一致"
    else
      fail "$src と $dst が乖離している（ドリフト検出）"
      echo "    差分:"
      # set -euo pipefail 下では diff の SIGPIPE が pipefail で拾われるため `|| true` で吸収
      # （CodeRabbit PR #87 指摘）
      diff -u "$src" "$dst" | head -20 | sed 's/^/      /' || true
    fi
  fi
done

# review workflow 限定の parity ガード（Issue #287）:
# resolve イベントで verdict を自動更新する pull_request_review_thread トリガーが
# 静かに落とされていないことを検証する（CodeRabbit request_changes_workflow 同等機能の退行防止）。
# chat workflow には本トリガーは無いため、review ファイルだけを対象にする（汎用ループの外）。
declare -a REVIEW_WORKFLOWS=(
  "templates/.github/workflows/vibehawk-review.yml"
  ".github/workflows/vibehawk-review.yml"
)
for rw in "${REVIEW_WORKFLOWS[@]}"; do
  if [[ -f "$rw" ]]; then
    if grep -q -e "pull_request_review_thread:" "$rw"; then
      pass "$rw に pull_request_review_thread トリガーが存在する（Issue #287 parity）"
    else
      fail "$rw に pull_request_review_thread トリガーが無い（Issue #287 parity 退行）"
    fi
  fi
done

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
