#!/usr/bin/env bash
# scripts/ci/intent-checks/close-on-feature-merge.sh の単体テスト。
#
# 実際の GitHub API 呼び出しは行わない（CI で gh 認証情報を必須にしないため）。
# PATH に gh スタブを差し込み、PR_BODY のパースと Issue close 動作を検証する。

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

SCRIPT="${REPO_ROOT}/scripts/ci/intent-checks/close-on-feature-merge.sh"

echo "=== scripts/ci/intent-checks/close-on-feature-merge.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "スクリプトが存在する"
else
  fail "スクリプトが存在しない"
  exit 1
fi

# 必須環境変数の検証: REPO 不在
set +e
err_out="$(PR_NUMBER=1 bash "$SCRIPT" 2>&1)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -qF "REPO"; then
  pass "REPO 未指定で非 0 終了"
else
  fail "REPO バリデーション挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

# 必須環境変数の検証: PR_NUMBER 不在
set +e
err_out2="$(REPO=test/repo bash "$SCRIPT" 2>&1)"
err_code2=$?
set -e
if [[ $err_code2 -ne 0 ]] && echo "$err_out2" | grep -qF "PR_NUMBER"; then
  pass "PR_NUMBER 未指定で非 0 終了"
else
  fail "PR_NUMBER バリデーション挙動が想定と異なる: exit=$err_code2, out='$err_out2'"
fi

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

# シナリオ 1: PR_BODY に close キーワードなし → notice + exit 0
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
echo "GH_CALLED: $*" >&2
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out="$(PATH="$STUB_DIR:$PATH" REPO=test/repo PR_NUMBER=10 PR_BODY="Refs #123" bash "$SCRIPT" 2>&1)"
code=$?
set -e
if [[ $code -eq 0 ]] && echo "$out" | grep -qF "::notice::"; then
  pass "Refs キーワードのみ（close 対象外）で notice 出力 + exit 0"
else
  fail "Refs のみ分岐の挙動が想定と異なる: exit=$code, out='$out'"
fi

# シナリオ 2: PR_BODY に Closes #N あり、Issue が OPEN → close される
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  issue)
    case "\$2" in
      view)
        # state=OPEN を返す
        echo "OPEN"
        exit 0
        ;;
      close)
        # close コマンドを記録
        echo "GH_ISSUE_CLOSE_CALLED: \$*" >> "$STUB_DIR/calls.log"
        exit 0
        ;;
    esac
    ;;
esac
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out2="$(PATH="$STUB_DIR:$PATH" REPO=test/repo PR_NUMBER=10 PR_BODY="Closes #123" bash "$SCRIPT" 2>&1)"
code2=$?
set -e
if [[ $code2 -eq 0 ]]; then
  pass "Closes #N + OPEN で exit 0"
else
  fail "Closes #N + OPEN の exit code が 0 ではない: exit=$code2, out='$out2'"
fi

if [[ -f "$STUB_DIR/calls.log" ]] && grep -qF "GH_ISSUE_CLOSE_CALLED" "$STUB_DIR/calls.log"; then
  pass "Closes #N + OPEN で gh issue close が呼ばれる"
else
  fail "gh issue close が呼ばれていない"
fi

# シナリオ 3: Issue が既に CLOSED → スキップ（close されない）
rm -f "$STUB_DIR/calls.log"
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  issue)
    case "\$2" in
      view)
        echo "CLOSED"
        exit 0
        ;;
      close)
        echo "GH_ISSUE_CLOSE_CALLED: \$*" >> "$STUB_DIR/calls.log"
        exit 0
        ;;
    esac
    ;;
esac
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out3="$(PATH="$STUB_DIR:$PATH" REPO=test/repo PR_NUMBER=10 PR_BODY="Closes #456" bash "$SCRIPT" 2>&1)"
code3=$?
set -e
if [[ $code3 -eq 0 ]] && echo "$out3" | grep -qF "既に close 済み"; then
  pass "既に CLOSED の Issue はスキップメッセージ出力"
else
  fail "CLOSED スキップ分岐の挙動が想定と異なる: exit=$code3, out='$out3'"
fi

if [[ ! -f "$STUB_DIR/calls.log" ]]; then
  pass "CLOSED の Issue で gh issue close が呼ばれない（冪等性）"
else
  fail "CLOSED の Issue で gh issue close が呼ばれた: $(cat "$STUB_DIR/calls.log")"
fi

# シナリオ 4: Refs キーワードは対象外（暴発防止）— Closes と混在しても Refs 側は close されない
rm -f "$STUB_DIR/calls.log"
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  issue)
    case "\$2" in
      view)
        echo "OPEN"
        exit 0
        ;;
      close)
        echo "GH_ISSUE_CLOSE_CALLED: \$*" >> "$STUB_DIR/calls.log"
        exit 0
        ;;
    esac
    ;;
esac
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
PATH="$STUB_DIR:$PATH" REPO=test/repo PR_NUMBER=10 PR_BODY="Closes #100
Refs #200" bash "$SCRIPT" >/dev/null 2>&1
set -e

# calls.log には #100 のみが含まれ、#200 は含まれない
if [[ -f "$STUB_DIR/calls.log" ]] && grep -qF "100" "$STUB_DIR/calls.log" && ! grep -qF "200" "$STUB_DIR/calls.log"; then
  pass "Refs キーワードは close 対象外（Closes のみ close）"
else
  fail "Refs/Closes の判定が想定と異なる: log=$(cat "$STUB_DIR/calls.log" 2>/dev/null || echo NONE)"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
