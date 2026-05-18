#!/usr/bin/env bash
# scripts/ci/vibehawk-review-skip-mark/post-skip-check-run.sh
#
# vibehawk-review-skip-mark.yml の step
# 「vibehawk status check を success で post（paths-ignore 全マッチ時のみ）」相当。
# `vibehawk` required status check を success として GitHub に POST する。
#
# 入力（環境変数）:
#   GH_TOKEN       — gh CLI 認証用（gh CLI が直接読む）
#   HEAD_SHA       — PR の head SHA（check-run の対象）
#   REPO           — owner/repo 形式（例: hirokimry/vibehawk）
#
# 副作用:
#   - `gh api -X POST /repos/${REPO}/check-runs` を呼び `vibehawk` check-run を作成する
#
# 固定パラメータ:
#   name=vibehawk                  — branch protection の required check 名と一致
#   status=completed               — Issue #157 で確定
#   conclusion=success             — paths-ignore 全マッチで API コスト 0 のまま merge gate 通過
#   output[title]/output[summary]  — Issue #65 経緯を残す説明文
#
# Issue #178（エピック #174）で vibehawk-review-skip-mark.yml から切り出された。

set -euo pipefail

: "${HEAD_SHA:?HEAD_SHA が必須です}"
: "${REPO:?REPO が必須です}"

gh api -X POST "/repos/${REPO}/check-runs" \
  -f name=vibehawk \
  -f head_sha="${HEAD_SHA}" \
  -f status=completed \
  -f conclusion=success \
  -f 'output[title]=vibehawk-review skipped (paths-ignore matched)' \
  -f 'output[summary]=All changed files matched vibehawk-review.yml paths-ignore patterns (Issue #65). LLM review skipped to keep API cost at zero. Posted by vibehawk-review-skip-mark.yml (Issue #157).'
