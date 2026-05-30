#!/usr/bin/env bash
# scripts/ci/intent-checks/pr-intent-inherit.sh の単体テスト。
#
# 実際の GitHub API 呼び出しは行わない（CI で gh 認証情報を必須にしないため）。
# PATH に gh / jq スタブを差し込み、スクリプトが想定通りの引数で gh を呼ぶか、
# 期待する分岐を通るかを検証する。

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

SCRIPT="${REPO_ROOT}/scripts/ci/intent-checks/pr-intent-inherit.sh"

echo "=== scripts/ci/intent-checks/pr-intent-inherit.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "スクリプトが存在する"
else
  fail "スクリプトが存在しない"
  exit 1
fi

# 必須環境変数の検証: PR_NUMBER 不在で fail
set +e
err_out="$(REPO=hirokimry/vibehawk bash "$SCRIPT" 2>&1)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -qF "PR_NUMBER"; then
  pass "PR_NUMBER 未指定で非 0 終了"
else
  fail "PR_NUMBER バリデーション挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

# 必須環境変数の検証: REPO 不在で fail
set +e
err_out2="$(PR_NUMBER=1 bash "$SCRIPT" 2>&1)"
err_code2=$?
set -e
if [[ $err_code2 -ne 0 ]] && echo "$err_out2" | grep -qF "REPO"; then
  pass "REPO 未指定で非 0 終了"
else
  fail "REPO バリデーション挙動が想定と異なる: exit=$err_code2, out='$err_out2'"
fi

# 統合シナリオ: gh / jq スタブで「Issue 参照なし」分岐を検証する
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

# gh スタブ: pr view body を返す（Issue 参照なし）
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# 引数を判定して body / labels / api を分岐する
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  # PR body を返す（Issue 参照キーワードなし）
  echo "This is a PR without any issue reference"
  exit 0
fi
# 想定外呼び出しを検出するためログに出力
echo "gh stub called with: $*" >&2
exit 0
EOF
chmod +x "$STUB_DIR/gh"

out="$(PATH="$STUB_DIR:$PATH" PR_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
if echo "$out" | grep -qF "対応 Issue が PR 本文から検出できませんでした"; then
  pass "Issue 参照なしの PR 本文で「継承スキップ」分岐に入る"
else
  fail "Issue 参照なし分岐の出力が想定と異なる: '$out'"
fi

# 統合シナリオ: Issue 参照ありで Issue 側に intent ラベルがあるケース
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# 第1引数で挙動を分岐
case "$1" in
  pr)
    case "$2" in
      view)
        # PR body / comments を返す
        if printf '%s\n' "$@" | grep -qF body; then
          echo "Closes #123"
        elif printf '%s\n' "$@" | grep -qF comments; then
          echo "0"
        fi
        exit 0
        ;;
      edit)
        # ラベル追加コマンドが呼ばれたことを記録
        echo "GH_PR_EDIT_CALLED: $*" >> "$STUB_DIR/calls.log"
        exit 0
        ;;
    esac
    ;;
  api)
    # /repos/.../issues/<n>/labels を返す
    if printf '%s\n' "$@" | grep -qF "issues/123/labels"; then
      echo '[{"name":"intent/bugfix"},{"name":"area/ci"}]'
    elif printf '%s\n' "$@" | grep -qF "issues/999/labels"; then
      # PR 自体の既存ラベル（intent/ なし）
      echo ""
    else
      echo "[]"
    fi
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$STUB_DIR/gh"

# STUB_DIR を gh スタブが書き込めるよう export
export STUB_DIR
out2="$(PATH="$STUB_DIR:$PATH" PR_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
if echo "$out2" | grep -qF "intent/bugfix"; then
  pass "Issue 側 intent ラベルが検出されると PR への継承メッセージに含まれる"
else
  fail "intent ラベル継承挙動が想定と異なる: '$out2'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
