# AI レビュー依存マップ

vibecorp の AI レビュー機構は **CodeRabbit** と **claude-code-action**（vibecorp ワークフロー枠）の 2 経路を並走させる設計。本ドキュメントは両者の責任分担、運用挙動、解約時の挙動を整理する。

## 4 契約 × ツール 責任分担表

vibecorp が利用者に提供する AI レビューの 4 契約を、各ツールがどう実現するか:

| 4 契約 | CodeRabbit | claude-code-action + vibecorp ワークフロー枠 |
|--------|----------|--------------------------------------|
| ① auto-review | ◎ ネイティブ（PR open / push で自動レビュー） | ◎ vibecorp 配布の `ai-review.yml` ワークフローが起動 |
| ② approve / request_changes 切替 | ◎ ネイティブ（`request_changes_workflow: true`、指摘ありで request_changes、resolve 後 approve） | ◎ vibecorp が `gh pr review --approve` / `--request-changes` 発行（#467 参照） |
| ③ auto-resolve（自身のコメント dismiss） | ◎ ネイティブ（`auto_resolve.enabled: true`、push 時に修正済みコメントを自動 resolve） | ◎ vibecorp が `gh api` で claude-action 自身のコメントを dismiss（#466 参照） |
| ④ 日本語レビュー | ◎ 設定（`language: ja-JP`） | ◎ `REVIEW.md` で指示（#465 参照） |

両ツールが同じ 4 契約を独立に履行する。利用者は片方だけ・両方どちらでも運用可能。

## 並走運用の挙動（approve 2 個の AND ゲート）

CodeRabbit と claude-action が両方有効な場合、GitHub のネイティブ挙動でマージ条件が決まる:

- 各レビュアーが独立して `approve` / `request_changes` を発行
- GitHub は **request_changes を優先**（厳しい方が勝つ AND ゲート的挙動）
- どちらか 1 つでも `request_changes` ならマージブロック
- 両者が `approve` なら `vibecorp.yml` の `branch_protection.required_approvals` に応じてマージ可（#463 参照）

これにより、片方が見逃した問題をもう片方が拾う多層防御が成立する。

### 重複指摘について

両ツールが同じ箇所を指摘することはあるが、利用者は両方を確認する必要はない:

- 修正対象が一致すれば 1 回の修正で両方のコメントが auto-resolve される
- 片方の解釈が分かれた場合は `.claude/rules/review-handling.md` の捌き基準（intent × severity）に従って判定する

並走時の挙動詳細・指摘ノイズの観測は #474（並走比較メトリクス）で実機検証する。

## ツール解約時の挙動

`vibecorp.yml` の `enabled` フラグで各ツールを個別に無効化できる:

| 設定 | CodeRabbit | claude-action |
|------|----------|--------------|
| `coderabbit.enabled: false` のみ | ❌ 無効 | ✅ 有効 |
| `claude_action.enabled: false` のみ | ✅ 有効 | ❌ 無効 |
| 両方 `false` | ❌ 無効 | ❌ 無効（人間レビューのみ） |
| 両方 `true`（デフォルト） | ✅ 有効 | ✅ 有効（並走） |

`install.sh` は各 `enabled` フラグを見て:
- `coderabbit.enabled: false` → `.coderabbit.yaml` を生成しない / 既存ファイルは触らない
- `claude_action.enabled: false` → `.github/workflows/ai-review.yml` と `REVIEW.md` を配布しない / 管理下の既存ファイルは削除（#468 参照）

両方無効化しても vibecorp の他機能（hooks、skills、CI 等）は動作する。AI レビューだけが止まる。

## vibecorp.yml の設定例

```yaml
# vibecorp.yml — プロジェクト設定の AI レビュー部分
coderabbit:
  enabled: true   # CodeRabbit Bot を使う

claude_action:
  enabled: true   # claude-code-action を使う
  skip_paths:     # AI レビュー対象から除外するパス（業界標準 7 件、CodeRabbit / claude-action 双方に反映）
    - "*.lock"
    - ".git/**"
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - ".cache/**"
    - "vendor/**"

branch_protection:
  required_approvals: 1   # マージに必要な approve 件数（人間 OR Bot どちらでも 1 件としてカウント）
```

`skip_paths` は単一の入力源として、`REVIEW.md` の skip rules セクションと `.coderabbit.yaml` の `path_filters` の両方に自動反映される（#465 参照）。

## CodeRabbit 設定値の根拠（参考）

CodeRabbit 側の `.coderabbit.yaml` の主要設定値:

| 設定 | 値 | 根拠 |
|------|---|------|
| `reviews.auto_review.enabled` | `true` | 4 契約 ① auto-review |
| `reviews.auto_review.drafts` | `false` | Draft PR ではコスト節約のためレビューしない |
| `reviews.auto_review.auto_incremental_review` | `true` | push 毎にインクリメンタルレビュー（4 契約 ③ の前提）|
| `reviews.path_filters` | `vibecorp.yml` の `claude_action.skip_paths` から自動生成（`!` プレフィックス）| 4 契約 各種 + skip 設定の単一ソース化 |
| `reviews.request_changes_workflow` | `true` | 4 契約 ② approve 切替 |
| `reviews.auto_resolve.enabled` | `true` | 4 契約 ③ auto-resolve |
| `language` | `ja-JP` | 4 契約 ④ 日本語レビュー、`vibecorp.yml` の `language` と連動 |
| `chat.auto_reply` | `true` | 却下スレッドの文脈完結 |

claude-code-action 側の挙動は `REVIEW.md`（vibecorp 配布のプロンプト）と `templates/.github/workflows/ai-review.yml`（ジョブ定義）で記述する。

## 関連

- 認証経路: `docs/ai-review-auth.md`
- 設定ファイル本体: `vibecorp.yml`（`coderabbit` / `claude_action` / `branch_protection` セクション）
- ワークフロー: `.github/workflows/ai-review.yml`
- claude-action プロンプト: `REVIEW.md`
- 捌き基準: `.claude/rules/review-handling.md`
- severity 定義: `.claude/rules/severity/coderabbit.md` / `.claude/rules/severity/claude-action.md`
- レビュー観点: `.claude/rules/review-observations.md`
- intent ラベル: `.claude/rules/intent-labels.md`

## 関連 Issue

- 親エピック: [#455](https://github.com/hirokimry/vibecorp/issues/455)
- 本 Issue: [#472](https://github.com/hirokimry/vibecorp/issues/472)
- 依存元: [#461](https://github.com/hirokimry/vibecorp/issues/461)（ワークフロー骨格）
- 依存元: [#465](https://github.com/hirokimry/vibecorp/issues/465)（REVIEW.md）
- 依存元: [#466](https://github.com/hirokimry/vibecorp/issues/466)（auto-resolve）
- 依存元: [#467](https://github.com/hirokimry/vibecorp/issues/467)（approve / request_changes 発行）
