# vibehawk プロダクト仕様書

> このドキュメントはプロダクトの公式仕様を定義する Source of Truth です。

## 概要

vibehawk は **追加課金ゼロの PR 自動レビュー OSS プロダクト** である。利用者が既に支払っている LLM サブスクリプション枠（Claude Pro / ChatGPT Plus 等）の **内側だけ** で動作し、AI レビュー専用 SaaS の月額や LLM API の従量課金を発生させない。CodeRabbit Pro / Greptile / PR-Agent 等への対比優位は「**追加課金ゼロ**」という構造的差別化に立脚する。

### 対象ユーザー

- LLM サブスクリプション（Claude Pro / ChatGPT Plus 等）を既に契約している開発者
- PR レビューに AI を活用したいが、追加課金を発生させたくない個人 / 小〜中規模チーム
- 自前のサーバー運用・ベクタ DB 運用を避けたい OSS 利用者

### 提供価値

- **追加課金ゼロ**: 既存 LLM サブスク枠の内側で完結
- **公式準拠**: LLM プロバイダー公式の OAuth・Action だけを使う
- **GitHub に閉じる**: 専用 DB・専用サーバーを持たない
- **持続可能性**: 他社 SaaS の値上げ・廃止に左右されない構造

## 機能仕様

### コア機能

| 機能 | 概要 |
|---|---|
| PR auto-review トリガー | PR が立ったら自動でレビューを始める（open / synchronize / ready_for_review） |
| PR 全体サマリコメント（walkthrough） | PR 冒頭に「変更概要 + 何を見たか」のサマリを 1 個投稿、push 毎に edit で最新化 |
| inline comment 投稿 | コードの行を指して指摘を書く。severity 絵文字付き、Suggestions 構文（` ```suggestion `）の生成も可 |
| approve 発行 | レビューが OK なら approve を発行する（sticky review state により request_changes と自動切替） |
| request_changes 発行 | 未解決指摘があれば request_changes を発行する（sticky review state により approve と自動切替） |
| インクリメンタルレビュー | 2 回目以降は前回見た範囲を覚えていて、新しい変更だけ見る |
| severity 5 段階の判定軸 | Critical / Major / Minor / Trivial / Info の付け方ルール（CodeRabbit 互換） |
| 日本語レビュー（locale 対応） | 日本語でコメントを書く（設定で切替可） |
| auto_resolve | 古い指摘を自動で resolved 化（Bot 自身の投稿のみ対象） |
| path_filters | レビュー対象から除外するパスを指定 |
| path_instructions | パス別のカスタムレビュー観点を Bot に注入 |
| @mention チャット応答 | 「@bot ここどうする？」に Bot が返事する（issue_comment トリガー） |
| 状態管理（GitHub をストアとして使う） | PR コメント・resolved 状態などを GitHub 上で直接読み書きする |

### 補助機能

| 機能 | 概要 | 状態 |
|---|---|---|
| profile（chill / assertive） | 口調の切替（優しめ / 厳しめ）。tone_instructions の切替 | 将来検討 |
| sequence diagram 自動生成 | 処理フローを図で表示 | 将来検討 |
| linked issue 評価 | PR が紐づく Issue の要件を満たしているか確認 | 将来検討 |

## アーキテクチャ

> 永続的状態は GitHub リポジトリ自体を状態ストアとして使う。内部 DB / ベクタ DB / 専用サーバーは持たない（5 大方針 4 / `docs/POLICY.md` 参照）。

### 状態管理（GitHub をストアとして使う）

CodeRabbit が DB で持つ状態を、vibehawk では GitHub 上のどこから読むか／どこに書くか:

| 状態の種類 | CodeRabbit | vibehawk |
|---|---|---|
| 前回レビュー時点のコミット SHA | 内部 DB | PR サマリコメント末尾 HTML コメント |
| PR 指摘の resolve 状態 | 内部 DB | GitHub の Resolved Conversation を直接読む |
| PR 全体の review status | 内部 DB | gh pr review で都度発行（永続化不要） |
| @mention チャット文脈 | 内部 DB | GitHub の comment スレッドを直接読む |
| PR 間の学習 | ベクタ DB | ❌ 持たない・実装しない |

### メタデータ仕様

サマリコメントに識別マーカーと SHA マーカーを HTML コメントとして埋め込む。Markdown レンダラーが描画しないため UI 上は不可視。

```markdown
## 📝 PR レビューサマリ
（本文）

<!-- vibehawk:summary -->
<!-- vibehawk:sha=abc123def456 -->
```

| マーカー | 役割 |
|---|---|
| `<!-- vibehawk:summary -->` | 種別マーカー（Bot の PR 全体サマリであることを示す） |
| `<!-- vibehawk:sha=<HEAD_SHA> -->` | 状態マーカー（前回どのコミットまで見たか） |

サマリコメントの一意特定: 投稿者 ID（`vibehawk[bot]`）+ 種別マーカーの **二重チェック** で誤検知・なりすましを排除する。

```bash
gh api repos/:owner/:repo/issues/:pr/comments --paginate \
  | jq '[.[] | select(.user.login == "vibehawk[bot]") | select(.body | contains("<!-- vibehawk:summary -->"))]' \
  | jq 'sort_by(.created_at) | last'
```

### マルチリポジトリ対応

GitHub App `vibehawk[bot]` を 1 つだけ作って公開し、利用者は Org / 個人にインストールすれば配下の任意リポジトリで使える。

```text
vibehawk GitHub App（1 つだけ公開）
  ├─ Org A にインストール
  │    ├─ repo-1 で稼働
  │    └─ repo-2 で稼働
  ├─ User B にインストール
  │    └─ repo-3 で稼働
  └─ Org C にインストール
       └─ repo-4, repo-5, ...
```

| 状態 | スコープ | 衝突リスク |
|---|---|---|
| サマリコメントの HTML メタデータ | PR 内（リポジトリ単位より狭い） | なし |
| @mention チャット文脈 | コメントスレッド内（さらに狭い） | なし |
| Cross-repository な状態 | 持たない（5 大方針 4） | 設計上発生しない |

### インクリメンタルレビュー実装パターン

サマリは **edit して 1 個に保つ**、inline は **append で履歴を残す**、解決済み指摘は **auto_resolve で resolved に倒す** の 3 段運用。

```text
[初回レビュー]
  ├─ PR 冒頭にサマリコメント投稿（種別マーカー + SHA 埋め込み付き）
  └─ 指摘箇所に inline comment 投稿

[2 回目以降（push 後）]
  ├─ サマリコメントを edit（更新）              ← コメント数は増えない
  ├─ 新しい inline 指摘は append（追加）        ← 履歴が残る
  └─ push で直った指摘は auto_resolve          ← Bot 自身の投稿のみ対象
```

**実装フロー**:

```text
[Step 1] PR の全コメントを gh api で取得
[Step 2] 投稿者 ID + 種別マーカー (<!-- vibehawk:summary -->) で
         自身の最新サマリコメントを一意に特定
[Step 3] サマリコメント末尾の HTML メタデータから前回 SHA を抽出
         <!-- vibehawk:sha=abc123def -->
[Step 4] 前回 SHA が現ブランチに含まれているかチェック
         ├─ 含まれている（通常 push）   → 前回 SHA から HEAD までの diff
         └─ 含まれていない（force push）→ base ブランチからの完全再レビュー
[Step 5] レビュー結果に応じて以下を発行:
         ├─ サマリコメント: edit（HEAD SHA を埋め込み直して内容更新）
         ├─ 新規指摘: 新しい inline comment を append
         └─ 旧指摘で差分が消えたもの: 該当 conversation を resolve
```

**force push / rebase 検出**:

```bash
prev_sha=$(extract_sha_from_summary)

if git merge-base --is-ancestor "$prev_sha" HEAD; then
  range="$prev_sha..HEAD"
else
  base_sha=$(git merge-base origin/main HEAD)
  range="$base_sha..HEAD"
fi
```

> 注: GitHub Actions の shallow clone（`fetch-depth: 1` 等）では `$prev_sha` が履歴から欠落して `git merge-base --is-ancestor` が常に false を返し、意図せず force push 扱いになる場合がある。利用者の workflow では `actions/checkout` で `fetch-depth: 0` を指定するか、`git fetch --unshallow` でフォールバックすることを推奨する。

### sticky review state

未解決の指摘が残っていれば「直して」（request_changes）、全部解決していれば「OK」（approve）を毎回発行し直す。状態は GitHub 側にあるので Bot 側の永続化不要。

```text
[Step 1] gh api で PR の全 review thread を取得
[Step 2] resolved / unresolved の数をカウント
[Step 3] unresolved == 0 なら gh pr review --approve
[Step 4] unresolved >= 1 なら gh pr review --request-changes
```

### @mention チャット応答

応答のたびにスレッド全体を `gh api` で読み直して、全コメントを LLM コンテキストに渡す。会話状態は GitHub のスレッド自体が保持する。

```text
利用者が @vibehawk でメンション
  ↓
issue_comment イベントトリガーで workflow 起動
  ↓
gh api でスレッド全コメント取得
  ↓
全コメントを LLM コンテキストに含めて応答生成
  ↓
スレッドに新しいコメントとして応答を append
```

将来的にスレッド超肥大化に備え、`.vibehawk.yaml` で `chat.max_thread_comments`（デフォルト未設定 = 無制限）を後付け可能な構造にしておく。

## やらない範囲（明示的除外）

vibehawk の責務範囲外として **実装しない** 機能、および vibecorp 側に残す機能を明示する。判断軸は `docs/POLICY.md` の「プロダクト方針（5 大方針）」を参照。

### やらない（実装しない）

| 機能 | 理由 |
|---|---|
| docstring / unit-test 生成 | コード生成しない方針（5 大方針 2） |
| apply suggestions / auto-fix（Bot 自身による commit） | 同上。Suggestions 構文の生成は OK だが Bot による commit は NG |
| PR ラベル / milestone / description 自動補完 | PR メタデータ操作しない（5 大方針 5） |
| 専用 DB（内部 DB）を持つ | 状態は GitHub に置く（5 大方針 4） |
| ベクタ DB を持つ | 同上 |
| knowledge_base / learnings | ベクタ DB に依存するため不可 |
| 利用者リポジトリ内の学習ファイル蓄積 | path_instructions で代替可（5 大方針 1） |
| web_search | サーバー必須。path_instructions で代替可 |
| 40+ linter 統合 | super-linter 等で利用者側に任せる |
| changelog 生成 | path_instructions で代替可 |
| issue triage / 要約 | 別 Action で実現可能 |
| pre-merge checks（タイトル形式・docstring 検証） | path_instructions で代替可 |

### vibecorp 側に残す

| 機能 | 残す理由 |
|---|---|
| intent × severity の捌き基準 | vibecorp 独自運用ルール（利用者側意思決定、5 大方針 3） |
| review-handling / review-observations | vibecorp 閉ループの一部 |
| review-harvest（PR 間学習） | vibecorp の knowledge/ 蓄積で代替 |
| intent-label-check CI | vibecorp 運用ルール |

## 非機能要件

### パフォーマンス

- **ジョブタイムアウト**: GitHub Actions 標準の **6 時間**。LLM レビューには十分な余裕がある（実運用では数分〜数十分のオーダーで完了する想定）。
- **並列実行制御**: 利用者の workflow ファイルで `concurrency:` を宣言する。新しい push が来たら古いレビューを中止する設計を推奨。

```yaml
concurrency:
  group: vibehawk-${{ github.event.pull_request.number }}
  cancel-in-progress: true
```

### セキュリティ

（認証・認可・データ保護等の要件を記載。詳細は SECURITY.md を参照）

### 可用性

（稼働率、障害復旧等の要件を記載）

## 画面遷移・データフロー

（画面遷移図やデータフローの概要を記載）

## 用語集

| 用語 | 定義 |
|---|---|
| `vibehawk` | vibe + hawk（鷹）。CodeRabbit の「うさぎ（速さ・量）」に対し「鷹（精度・観察力・全体俯瞰）」のメタファーで対置。vibe シリーズ（vibecorp / vibemux / vibehawk）の一貫性 |
| severity 5 段階 | Critical (🔴) / Major (🟠) / Minor (🟡) / Trivial (🔵) / Info (⚪) の 5 段階で重大度を判定する。各レベルの定義は `.claude/rules/severity/claude-action.md`（vibecorp 実体版、CodeRabbit 公式仕様と完全一致）を参照 |
| インクリメンタルレビュー | 2 回目以降のレビューで前回見た範囲を記憶し、差分のみ見る挙動 |
| sticky review state | 未解決指摘ありなら request_changes、全解決なら approve に切り替わる仕組み |
