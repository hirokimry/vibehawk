#!/usr/bin/env bash
# 用途: package.json version bump 漏れ警告コメントを PR に冪等投稿する（Issue #308）
#
# .github/workflows/version-bump-check.yml から version-bump-check.sh が failure を
# 返した場合に呼ばれる。HTML マーカーで既存コメントを検出し、二重投稿せず upsert する。
# 警告のみ・非ブロック（gh api 失敗時は warning ログで exit 0、merge gate を倒さない）。
#
# 必須 env:
#   GH_TOKEN   GitHub CLI 認証トークン（pull-requests: write 範疇）
#   REPO       owner/repo 形式のリポジトリ識別子
#   PR_NUMBER  対象 PR 番号
#   OWNER      owner（bot 名義フィルタ用）

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${REPO:?REPO が未設定です}"
: "${PR_NUMBER:?PR_NUMBER が未設定です}"
: "${OWNER:?OWNER が未設定です}"

# 冪等性の鍵。本文先頭に埋め込んだ HTML コメントで既存の同種コメントを一意に識別する。
MARKER="<!-- vibehawk:version-bump-check -->"

# 通知文本体は notification-prompt-extraction.md ルールに従い個別 .md に切り出して参照する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESSAGE_FILE="${SCRIPT_DIR}/../workflows/messages/notify-version-bump-missing.md"

if [[ ! -f "${MESSAGE_FILE}" ]]; then
  echo "::warning::version-bump-check: 通知文 ${MESSAGE_FILE} が見つかりません → skip"
  exit 0
fi

BODY="$(printf '%s\n\n%s' "${MARKER}" "$(cat "${MESSAGE_FILE}")")"

BOT_LOGIN_DEFAULT="github-actions[bot]"
BOT_LOGIN_APP="vibehawk-for-${OWNER}[bot]"

EXISTING=$(gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" --paginate) || {
  echo "::warning::version-bump-check: issues/comments 取得失敗 → skip"
  exit 0
}

MATCHES=$(printf '%s' "${EXISTING}" | jq -cs --arg bot1 "${BOT_LOGIN_DEFAULT}" --arg bot2 "${BOT_LOGIN_APP}" --arg marker "${MARKER}" '
  [ .[][]
    | select(.user.login == $bot1 or .user.login == $bot2)
    | select((.body // "") | startswith($marker))
  ]
  | sort_by(.created_at)
')

COUNT=$(printf '%s' "${MATCHES}" | jq 'length')

upsert_request() {
  local method="$1"
  local endpoint="$2"
  jq -nc --arg body "${BODY}" '{body: $body}' | gh api -X "${method}" "${endpoint}" --input -
}

case "${COUNT}" in
  0)
    echo "version-bump-check: 既存 0 件 → POST 新規"
    upsert_request POST "repos/${REPO}/issues/${PR_NUMBER}/comments" >/dev/null || {
      echo "::warning::version-bump-check: POST 失敗 → skip"
      exit 0
    }
    ;;
  1)
    ID=$(printf '%s' "${MATCHES}" | jq -r '.[0].id')
    echo "version-bump-check: 既存 1 件 (id=${ID}) → PATCH 更新"
    upsert_request PATCH "repos/${REPO}/issues/comments/${ID}" >/dev/null || {
      echo "::warning::version-bump-check: PATCH 失敗 → skip"
      exit 0
    }
    ;;
  *)
    LATEST_ID=$(printf '%s' "${MATCHES}" | jq -r '.[-1].id')
    OLDER_IDS=$(printf '%s' "${MATCHES}" | jq -r '.[:-1] | .[].id')
    echo "version-bump-check: 既存 ${COUNT} 件（race condition）→ 古い方 DELETE + 最新 (id=${LATEST_ID}) PATCH"
    while IFS= read -r OID; do
      [[ -z "${OID}" ]] && continue
      gh api -X DELETE "repos/${REPO}/issues/comments/${OID}" >/dev/null || \
        echo "::warning::version-bump-check: 重複コメント DELETE 失敗 (id=${OID})"
    done <<< "${OLDER_IDS}"
    upsert_request PATCH "repos/${REPO}/issues/comments/${LATEST_ID}" >/dev/null || {
      echo "::warning::version-bump-check: PATCH 失敗 → skip"
      exit 0
    }
    ;;
esac

echo "version-bump-check: 警告コメント投稿完了"
