# vibehawk コスト分析

> [!IMPORTANT]
> このドキュメントはプロジェクトのコスト構造・予算管理を定義する Source of Truth。

## 初期投資（Fixed Costs）

初年度に必要な固定費の一覧。
実数値が未決定の項目は「TBD」と明記し、決定次第追記する。

| 項目 | 金額 | 支払先 | 期限・更新頻度 | 備考 |
|------|------|------|-------------|------|
| 商標登録（vibehawk） | TBD（数万〜30 万円） | 特許庁 + 弁理士 | 1 回（出願時） | Issue #38、出願料 ≈ 12,000 円（電子出願 1 区分）+ 弁理士費用 5〜20 万円 |
| GitHub Organization（vibehawk） | 0 円 / 月（Free プラン） | GitHub | 月額 | Issue #39、Free プランで開始（Team プラン: $4 / user / 月 は将来検討） |
| 独自ドメイン | TBD | TBD | TBD（年額想定） | 取得有無は未決定 |
| npm Organization | 0 円 / 月 | npm | TBD（Org 化未定） | 既存 hirokimry 個人アカウントで運用、Org 化未定 |

## 変動費

（ユーザーあたり・処理あたりの変動費構造を記載）

### API 利用コスト

vibehawk 開発側は LLM API キーを保有・配布しない。
利用者の Claude Pro / Max OAuth トークン（`CLAUDE_CODE_OAUTH_TOKEN`）を GitHub Actions Secrets 経由で利用する設計のため、LLM 呼び出しコストは全て利用者負担となり、vibehawk 開発側の月額見積には計上しない。

| サービス | 単価 | 想定月間量 | 月額見積 | 備考 |
|----------|------|-----------|----------|------|
| Claude API（claude-code-action） | 利用者負担 | 利用者の PR 数依存 | $0（vibehawk 開発側） | 利用者が既契約の Claude Pro / Max 枠内で完結。Value 1「利用者の契約だけで、完結させる」と整合 |

### インフラコスト

（スケーラブルなインフラ費用の構造を記載）

## スケール時のコスト予測

（Phase 別のコスト見積もりを記載）

| Phase | ユーザー数 | 月間処理量 | 月額コスト | 備考 |
|-------|-----------|-----------|-----------|------|
| Phase 1 | （想定数） | （想定量） | （見積額） | （備考） |
| Phase 2 | （想定数） | （想定量） | （見積額） | （備考） |
| Phase 3 | （想定数） | （想定量） | （見積額） | （備考） |

## vibehawk コスト設計原則（MVV 由来）

vibehawk の Mission「レビューツールに追加課金が要らない世界をつくる」および Value 1「利用者の契約だけで、完結させる」は、コスト設計の根幹を規定する。

> [!NOTE]
> 根拠: `MVV.md` — Mission「レビューツールに追加課金が要らない世界をつくる」、Value 1「利用者の契約だけで、完結させる」（2026-05-08 MVV 制定）

### 利用者側コスト

| 原則 | 内容 |
|------|------|
| MUST NOT | 利用者に追加の SaaS 月額（CodeRabbit Pro 等）を要求する設計にしないこと |
| MUST NOT | 利用者に専用の LLM API キー（Anthropic / OpenAI 等）の発行を要求する設計にしないこと |
| MUST NOT | 利用者に自前サーバーの用意・費用を要求する設計にしないこと |
| MUST | 利用者が既に契約している LLM プロバイダー（Claude Pro / Max 等）の枠内で完結する設計にすること |
| MUST | 公式 OAuth 経由での認証を前提とし、非公式 API・スクレイピングによるコスト回避策を選ばないこと |

### vibehawk 開発側コスト

| 原則 | 内容 |
|------|------|
| MUST NOT | 利用者数増加に伴い vibehawk 運営側の従量コストが線形に増加するアーキテクチャを採用しないこと |
| MUST | 新規アーキテクチャ採用時は「利用者側コスト増加ゼロ」を維持できるか CFO レビューを通すこと |

## コスト管理ポリシー

### 予算アラート

- MUST: 月間予算の 80 % 到達時にアラートを発火すること
- MUST: 月間予算の 100 % 到達時に自動停止または承認フローを発動すること

### キャッシュ制御

- MUST: API レスポンスは可能な限りキャッシュし、不要な再呼び出しを防止すること
- MUST NOT: キャッシュ未設定のまま高頻度 API を本番投入しないこと

### 無料枠の活用

（各サービスの無料枠・割引プランの活用方針を記載）

### コストレビュー

- MUST: 月次でコストレビューを実施し、予実差異を分析すること
- MUST: 新規サービス導入時はコスト試算を事前に行うこと

## vibehawk コスト制御（PR サイズ段階的劣化）

CodeRabbit と同じ「段階的劣化（graceful degradation）」型を採用する。
PR サイズに応じてレビュー深度を自動で下げる。
利用者は `.vibehawk.yaml` で閾値をオーバーライドできる。

### デフォルト閾値（CodeRabbit 互換）

| PR サイズ | デフォルトの挙動 |
|---|---|
| ~30 ファイル | フル品質レビュー（全ファイル深く見る） |
| 30〜80 ファイル | 主要ファイル優先（差分が大きいファイルから順にレビュー）、サマリ軽量化 |
| 80 ファイル超 | 各ファイル軽量レビュー（depth を下げる、主要観点のみ抽出） |
| 3000 ファイル超 | サマリのみ投稿、inline はスキップ（安全弁） |

### `.vibehawk.yaml` でのオーバーライド

```yaml
reviews:
  size_limits:
    full_review_files: 30        # フル品質レビューの上限
    focused_review_files: 80     # 主要ファイル優先モードの上限
    skip_inline_files: 3000      # inline スキップ閾値
```

### rate limit 制御の置き場所

| リスク | 制御の置き場所 |
|---|---|
| 並列実行（同時 PR 数） | 利用者の workflow `concurrency:` で宣言 |
| LLM rate limit（429） | claude-code-action のリトライ機構を流用 |
| GitHub API rate limit | `gh api` のバックオフ機構に任せる |

ツール側が持つのは「PR サイズ閾値」のみ。残りは外部委譲する。

### PR ごとの追加トークン消費（Issue #228: review_effort 追加）

Issue #228 で Claude prompt schema に `review_effort: {difficulty, minutes}` を必須フィールドとして追加した。出力側のトークン増分は **約 20〜30 トークン / PR**（小規模オブジェクト 1 個）で軽微。Possibly related PRs と Suggested reviewers は workflow step 取得（gh api + git log）のため Claude API への影響はゼロ。

### PR ごとの追加トークン消費（Issue #227）

Issue #227 で Claude prompt の schema に `walkthrough_narrative` + `changes_table[]` を必須フィールドとして追加した。利用者の Claude Max OAuth 個人クォータ（または ANTHROPIC_API_KEY 従量課金）への影響として、PR ごとに以下の追加トークン消費が発生する。

| 経路 | 推定追加トークン / PR | 備考 |
|---|---|---|
| 出力側: `walkthrough_narrative` | 約 100〜400 トークン | 200〜800 文字、日本語 0.5 文字 = 1 トークン換算 |
| 出力側: `changes_table[]`（5〜10 layer 想定） | 約 250〜500 トークン | layer あたり約 50 トークン |
| 入力側: prompt 内の指示文追加 | 約 100 トークン | walkthrough_narrative / changes_table の生成指示 2 ブロック |
| **合計** | **約 450〜1000 トークン / PR** | 平均 700 トークン想定 |

### 月間試算（上限ケース）

利用者リポジトリで 1 日 10 PR を上限とした場合の月間追加トークン消費:

| シナリオ | 1 日の PR 数 | 月間追加トークン | 影響 |
|---|---|---|---|
| 平均ケース | 5 PR / day | 5 × 700 × 30 = 105k トークン / 月 | Claude Max クォータに対して軽微 |
| 上限ケース | 10 PR / day | 10 × 1000 × 30 = 300k トークン / 月 | Max 5x プランの月間出力 1M-1.5M トークンに対し 20〜30% を占有 |

Claude Pro / Max 個人クォータ枯渇リスクへの影響度は中程度。利用者が大量 PR を出すリポジトリでは Max 20x プランへのアップグレード or `.vibehawk.yaml` の `size_limits` 厳格化（PR サイズ閾値を下げて段階的劣化を早めに発火）で抑制可能。

### 5 大方針との整合

5 大方針の本体定義は `docs/POLICY.md` の「## プロダクト方針（5 大方針）」を参照。

- 大方針 1（カスタムは外から注入）: `.vibehawk.yaml` で利用者がオーバーライド可能 → 整合
- 大方針 3（severity はツール / 捌き方は利用者）: コスト制御は本来「捌き方」寄りだが、初心者保護のための最低限の安全弁としてツール側に持つ

## 🔗 関連

- `MVV.md` — コスト設計原則の根拠（Mission / Value 1）
- `docs/POLICY.md` — プロダクト方針 5 大方針
- `docs/maintainer-quota-policy.md` — メンテナー枠消費対策ポリシー（起動抑制層）
