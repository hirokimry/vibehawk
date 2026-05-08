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

（応答時間、スループット等の要件を記載）

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
