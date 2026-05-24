#!/usr/bin/env bash
# 用途: paths-ignore 全マッチ時に vibehawk required check を success で POST する（Issue #178）
#
# LLM レビューをスキップして API コスト 0 のまま merge gate を通過させる仕組み（Issue #65 / #157）。

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
