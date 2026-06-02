#!/usr/bin/env bash
# 用途: `@vibehawk help` コマンドで利用可能な @vibehawk コマンド一覧を返す（Issue #294、epic #289 子5）。
#       表示のみ・書き換えなし・LLM 不要。GitHub 内テキストのみで構成し外部 URL を埋めない。
#
# 本文中のコマンド例（`@vibehawk review` 等）はコード span で示すが、本コメントは
# vibehawk-for-<owner>[bot] 名義で投稿されるため、ジョブ if 条件 `!startsWith(login, 'vibehawk-for-')`
# が次回起動を弾く（無限ループ防止の既存ガード）。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER must be set}"

read -r -d '' body <<'EOF' || true
🦅 vibehawk: 利用可能なコマンド一覧

| コマンド | 説明 |
|---|---|
| `@vibehawk review` | 増分再レビュー（前回レビュー以降に差分が無ければ指摘の再チェックのみ） |
| `@vibehawk full review` | 過去指摘を無視した PR 全体の再レビュー |
| `@vibehawk resolve` | vibehawk 自身の指摘を一括 resolve |
| `@vibehawk summary` | sticky walkthrough を再生成 |
| `@vibehawk help` | このコマンド一覧を表示 |
| `@vibehawk configuration` | 現在の vibehawk 設定を表示 |
| `@vibehawk pause` | この PR の自動レビューを一時停止 |
| `@vibehawk resume` | 一時停止した自動レビューを再開 |
| `@vibehawk ignore` | この PR を自動レビュー対象外にする |

それ以外の `@vibehawk <メッセージ>` には通常のチャット応答を返します。
EOF

gh issue comment "$ISSUE_NUMBER" --body "$body"
