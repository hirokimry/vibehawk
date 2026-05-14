# Issue #121 C-1: vibehawk を required status check 化する実装計画

## 概要

Issue #121 の最新コメント（C-1 採用: status check 追加で merge gating する設計）に従い、vibehawk のレビュー結果を `POST /repos/X/Y/check-runs` で **check run** として post する。利用者は branch protection の required status checks に "vibehawk" を追加することで merge gating を確実に動作させられる。

## 背景

PR #122 で bundled review API への移行は完了済み。しかし GitHub の構造仕様により bot review は branch protection の required reviewers に count されないことが確定（Issue #121 コメント「検証完了報告」）。そのため CodeRabbit が既に行っている方式（review API + check-runs API 並列発行）に倣い、check-runs API で status check を post して merge gating を担保する。

## 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `templates/.github/workflows/vibehawk-review.yml` | claude prompt に check-runs POST 指示を追加 |
| `.github/workflows/vibehawk-review.yml` | templates と完全一致のコピー（dogfooding） |
| `tests/test_workflow_yaml.sh` | check-runs POST 指示の grep 検証 + conclusion 導出表の存在検証 |
| `README.md` | setup ガイドに「branch protection で vibehawk を required status check に追加」手順を追記 |
| `docs/specification.md` | status check 仕様（name=vibehawk / conclusion 表）追記 |

## Phase 1: workflow prompt 修正（templates / dogfooding 両方）

1. `templates/.github/workflows/vibehawk-review.yml` の claude prompt に以下を追記:
   - bundled review POST の **直後** に check-runs API を post する手順
   - conclusion 導出ロジック（APPROVE → success / REQUEST_CHANGES → failure / 新規 Minor 以下のみ → neutral / API 失敗 → skip）
   - prompt 内のサンプルコードに `gh api -X POST "repos/$REPO/check-runs"` を埋め込む
2. `.github/workflows/vibehawk-review.yml` を templates と完全一致でコピー
3. `claude_args` の `allowedTools` は既に `Bash(gh api:*)` を含むため修正不要

## Phase 2: テスト追加

`tests/test_workflow_yaml.sh` に Issue #121-C1 セクションを追加し、以下を検証:

1. prompt に `check-runs` POST 指示が含まれる
2. prompt に `head_sha` 受け渡し指示が含まれる
3. prompt に `conclusion` 4 種（success / failure / neutral / skip）が言及される
4. prompt に check run の `name` として "vibehawk"（固定文字列）が含まれる

## Phase 3: ドキュメント追記

1. `README.md`: setup ステップ 6 の直後に新セクション「branch protection で vibehawk を required status check に追加」を追加
2. `docs/specification.md`:
   - コア機能表に status check 投稿を追加
   - 新セクション `### status check 仕様（Issue #121-C1）` を追加

## Phase 4: コミット + PR + マージ

1. `/vibecorp:commit` でコミット
2. `/vibecorp:review-loop` でレビュー
3. `/vibecorp:pr --close` で PR 作成
4. `/vibecorp:pr-fix-loop` でマージ待機

## 懸念事項

### a. App 権限 `checks: write` の必要性

`gh api -X POST repos/X/Y/check-runs` には App の `checks: write` 権限が必要。`vibehawk-for-<owner>` App のマニフェストで `checks: write` が無い場合、API は 403 となる。本 PR では prompt 内 `|| echo "::warning::check-runs POST 失敗"` で graceful degradation し、利用者が App の権限を追加できるよう warning に手順案内を含める。App manifest 側の権限追加は別 Issue（再 install / 既存 App への権限追加が必要なため範囲を切る）。

### b. workflow YAML の permissions ブロック

`autonomous-restrictions.md` §6 で workflow の permissions 変更は不可領域。本 PR では workflow `permissions:` は触れず、App Installation Token の権限に依存する。

### c. check run name の固定性

"vibehawk" 固定。命名統制 `vibehawk-for-<owner>` とは別軸（check run は status 表示の name であり bot login とは独立）。利用者は branch protection で "vibehawk" を required に登録するだけで OK。

## 完了条件

- [ ] templates / dogfooding 両 workflow に check-runs POST 指示が含まれる
- [ ] conclusion 導出表（4 種）が prompt 内に明記される
- [ ] `tests/test_workflow_yaml.sh` 全パス
- [ ] README に branch protection 追加手順が記載される
- [ ] docs/specification.md に status check 仕様セクションが追加される
- [ ] PR 作成 + auto-merge 設定済み
