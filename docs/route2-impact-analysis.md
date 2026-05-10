# 経路 2 必須化の影響評価レポート

経路 2（`vibehawk-for-<owner>[bot]` 名義投稿、App Installation Token 認証）必須化決定（Issue #61, #72）が、Issue #8 以降の機能追加に与える影響を retrospective に評価する。

## 対象範囲

評価対象は経路 2 必須化決定（2026-05-09）以前に起票された機能追加 Issue。本レポート作成時点（2026-05-10）で評価対象 Issue は全て CLOSED であり、経路 2 想定での実装が完了している。本レポートは「設計変更の理由を文書として永続化する」事後検証の記録である。

## 影響度の定義

| 影響度 | 意味 |
|---|---|
| **None** | 経路 2 必須化が機能設計に影響しない |
| **Low** | 文書記述の表現変更のみ（実装変更なし） |
| **Medium** | 認証経路 / bot 名義の切り替えに伴う実装変更が必要（後方互換維持で対応可能） |
| **High** | 機能の中核設計（状態特定ロジック等）が破綻する。後方互換のための追加実装が必要 |

## Issue 別評価

### Issue #8 — PR 全体サマリコメントとインクリメンタルレビュー判定

- **影響度**: **High**
- **影響内容**: サマリコメント特定ロジックが「投稿者 `vibehawk[bot]` + マーカー `<!-- vibehawk:summary -->` の二重チェック」を前提としていたが、経路 2 では投稿者が `vibehawk-for-<owner>[bot]`（owner ごとに変わる）に切り替わるため、固定 ID 一致による特定が機能しない。
- **必要な設計変更**:
  - 投稿者 ID 一致を「`vibehawk-for-` プレフィックスで始まる Bot」へ拡張（前方一致）
  - またはマーカー単独特定への移行（投稿者チェックを補助条件として残す）
- **実装結果**: 実装済み（Issue #8 CLOSED, b2b8268 ほか）。`templates/.github/workflows/vibehawk-chat.yml` 等で `startsWith(comment.user.login, 'vibehawk-for-')` パターンが採用され、無限ループ防止と種別マーカーの組み合わせで Bot 自身のコメント特定が機能している。
- **対応の優先度**: 完了済み

### Issue #9 — severity 5 段階付き inline comment と sticky review state

- **影響度**: **Medium**
- **影響内容**: inline コメント投稿には repo 書き込み権限を持つ token が必要。経路 1 の `secrets.GITHUB_TOKEN` ではなく、経路 2 の App Installation Token に切り替える必要がある。
- **必要な設計変更**:
  - workflow 内で App Installation Token を取得 → `gh` 認証コンテキストに注入
  - sticky review state（unresolved 数による approve / request_changes 切替）の投稿主体も同 Bot 名義に揃える
- **実装結果**: 実装済み（Issue #9 CLOSED, 683a561）。`templates/.github/workflows/vibehawk-review.yml` で `actions/create-github-app-token@v2` 相当の経路で Installation Token を取得する構成に移行済み。
- **対応の優先度**: 完了済み

### Issue #10 — `.vibehawk.yaml` 設定スキーマと CodeRabbit 互換読み込み

- **影響度**: **None**
- **影響内容**: 設定ファイル経由の挙動カスタマイズと、経路 2（認証経路の切り替え）は直交する。設定スキーマに認証関連キーを追加する設計上の必要性はない（secrets は GitHub Settings UI で管理する方針が確定済み、`docs/secrets-handling.md`）。
- **必要な設計変更**: なし
- **実装結果**: 実装済み（Issue #10 CLOSED, 90968f0）。`.vibehawk.yaml` は path_filters / chat / review_observations 等のレビュー挙動カスタマイズに集中しており、認証は workflow 側 secrets で完結する設計が維持された。
- **対応の優先度**: 完了済み

### Issue #11 — `@mention` チャット応答（`issue_comment` トリガー）

- **影響度**: **Medium**
- **影響内容**: `issue_comment` トリガーの workflow も経路 2 を前提とする必要がある。Bot 自身のコメント（`vibehawk-for-*[bot]`）を起動条件から除外しないと無限ループ（Bot 自身のメンションに反応）が発生する。
- **必要な設計変更**:
  - workflow の起動条件に `!startsWith(github.event.comment.user.login, 'vibehawk-for-')` を追加
  - Installation Token 取得ロジックを `vibehawk-review.yml` と共通化
  - スレッド読み出しと応答投稿の双方で App 認証を使う
- **実装結果**: 実装済み（Issue #11 CLOSED, b2b8268）。`templates/.github/workflows/vibehawk-chat.yml` で起動条件 `!startsWith(github.event.comment.user.login, 'vibehawk-for-')` と 3 secrets 検証（`VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`）が実装されている。
- **対応の優先度**: 完了済み

## specification.md §`@mention チャット応答` への反映

経路 2 必須化に伴い、specification.md `### @mention チャット応答` セクション（全面改訂は Issue #61 の管轄）に **bot 名義（`vibehawk-for-<owner>[bot]`）と Installation Token 認証** の最小注記を追加した。フロー図および `.vibehawk.yaml` 設定の記述は維持されている。

## 影響度サマリ

| Issue | タイトル | 影響度 | 状態 |
|---|---|---|---|
| #8 | PR 全体サマリコメント / インクリメンタルレビュー | High | 対応済み |
| #9 | severity 5 段階 inline comment / sticky review state | Medium | 対応済み |
| #10 | `.vibehawk.yaml` 設定スキーマ | None | 対応済み |
| #11 | `@mention` チャット応答 | Medium | 対応済み |

経路 2 必須化決定が機能追加 Issue の設計に与えた具体的影響は、**Bot 名義の動的化（`vibehawk-for-<owner>[bot]`）に伴う「投稿者 ID 固定値マッチ」の見直し** に集約される。本リポジトリの実装ではプレフィックス一致（`vibehawk-for-` start-with）と種別マーカー（`<!-- vibehawk:summary -->`）の組合せで対応済み。

## 関連

- 経路 2 必須化決定: Issue #61, #72
- 親エピック: Issue #23（CLOSED）
- 種別マーカー仕様: Issue #57
- secrets 取扱い方針: `docs/secrets-handling.md`
- App 命名規則: `docs/specification.md` § `App 命名規則`
