# 🦅 vibehawk

> 鷹のように観察し、追加課金ゼロで PR レビューを届ける OSS プロダクト

**vibehawk** は **branch protection の required status check として動く AI PR レビュアー** であり、**追加課金ゼロの OSS**。利用者は GitHub の branch protection で `vibehawk` を required status check に追加するだけで「AI レビューが OK を出さないと merge できない」merge gate を構築できる。利用者が既に契約している LLM サブスクリプション枠（Claude Pro / Max）の **内側だけ** で動作し、AI レビュー専用 SaaS の月額や LLM API の従量課金を発生させない。

vibe シリーズ（vibecorp / vibemux / vibehawk）の一員として、CodeRabbit の「うさぎ（速さ・量）」に対し「鷹（精度・観察力・全体俯瞰）」のメタファーで対置する。

## 30 秒サマリ

- 🦅 **CI required で gate**: branch protection の required status check として merge gate を構築（merge gate 主軸、Issue #138 / #121-C1）
- 🦅 **追加課金ゼロ**: 利用者の Claude Pro / Max OAuth トークン内で完結、運営側サーバー・専用 DB なし
- 🦅 **観察に徹する**: PR メタデータ（label / milestone 等）は書き換えず、レビュー & 修正提案のみを届ける
- 🦅 **公式の道だけ歩く**: 裏 API・スクレイピングなし、claude-code-action 経由の OAuth 経路のみサポート
- 🦅 **利用者ごと独立 App**: 集中 SaaS App の「1 鍵漏洩で全利用者波及」リスクを構造的に回避（経路 2 必須化）

Mission / Vision / Value は [`MVV.md`](MVV.md)、詳細仕様は [`docs/specification.md`](docs/specification.md)、プロダクト方針は [`docs/POLICY.md`](docs/POLICY.md) を参照。

## 🧭 設計思想: 人間 review 必須要件をバイパスしない

vibehawk は GitHub の `required_approving_review_count`（人間レビュー必須件数）を AI で満たす設計を **意図的に避ける**。AI が approve を発行できる設計だと「人間レビュー必須要件のバイパス」と見なされる構造的リスクがあり、業界 4 社（Copilot / Gemini / Claude Code Review / Cursor BugBot）の AI レビューも同じ理由で APPROVE 経路を回避している。

vibehawk は Anthropic が公式ドキュメントで案内している「自前 CI で gate する」設計思想（`claude-code-review` workflow）を OSS としてパッケージ化したもの（Anthropic 提携・公認製品ではない）。merge gate の **主軸は status check** であり、`approve` / `request_changes` は補助情報として post されるが merge gating には使わない（Issue #138 / #121-C1、詳細: [`docs/specification.md § status check 仕様`](docs/specification.md)）。

## ⚡ クイックスタート

vibehawk は **利用者ごとに独立した GitHub App（`vibehawk-for-<owner>`）** を利用者本人が作成・運用する構造（命名統制、詳細・非対称性の開示は [`docs/design-philosophy.md § 命名統制`](docs/design-philosophy.md) 参照）。投稿者は `vibehawk-for-<owner>[bot]` 名義になる。

> **対応 OS**: macOS / Linux / Windows（PowerShell / CMD / Git Bash）

### 使い方の全体像

**vibehawk を使う = リポジトリの branch protection に `vibehawk` を required status check として追加すること** がゴール。これにより「AI レビューの conclusion が `success` でない PR は merge できない」merge gate が成立する。

```text
[ステップ 1]                  [ステップ 2]                  [ステップ 3 ← ゴール]
App / secrets / workflow    →   初回 PR 発火で           →   branch protection に
を準備（前提準備）              `vibehawk` check 発火           `vibehawk` を required 登録
                                                              （vibehawk 利用の根幹）
```

GitHub の仕様上、`vibehawk` check が一度発火していないと branch protection の検索候補に出ないため、ステップ 3 は初回 PR 発火後に実施する手順順序になる。

### 1. App / secrets / workflow を準備（前提準備）

対話型ウィザード `npx vibehawk setup` が全 6 ステップ（App 作成 → リポジトリインストール → 3 secrets 登録 → workflow PR）を 1 コマンドに集約する（Issue #91）:

```bash
npx vibehawk setup --owner <your-github-username> --repo <owner>/<repo>
```

各ステップで「指示表示 → ブラウザで操作 → Enter → CLI が `gh api` 検証 → OK で次 / NG なら原因表示してリトライ」の Enter ゲートで進行。実行内容を事前確認したい場合は `--dry-run`:

```bash
npx vibehawk setup --owner alice --repo alice/my-app --dry-run
```

個別実行手順（`install` / `setup-token` サブコマンド、後方互換）は [`docs/specification.md § CLI 仕様 § CLI 利用フロー`](docs/specification.md) を参照（App 作成 → App ID / Private Key 登録 → `claude setup-token` → OAuth Token 登録 → workflow 配置 → PR 提出の 6 ステップ）。

App ID / OAuth Token は **OS ネイティブのクリップボードに stdin 経由でコピー**（Cmd+V / Ctrl+V で貼付可能）。OAuth Token の値はクリップボードコピー失敗時でも stdout に出さない（CISO Critical 条件、[`docs/SECURITY.md`](docs/SECURITY.md) 参照）。

### 2. 初回 PR で `vibehawk` check を発火

`.github/workflows/vibehawk-review.yml` 配置後、リポジトリに初回 PR を立てると workflow が起動し `vibehawk-for-<owner>[bot]` 名義でレビューを post する。同時に `check-runs` API で `vibehawk` という status check も post される（投稿者表示は `github-actions[bot]`、check の `name` は `vibehawk` 固定のため branch protection 設定上の識別性は維持される）。

### 3. branch protection に `vibehawk` を required status check 登録（vibehawk 利用の根幹）

**このステップが vibehawk 利用の根幹**。前のステップはこのステップを機能させるための前提準備にすぎない。本ステップを実施しないと vibehawk は補助情報（approve / request_changes）を post するのみで merge gate として機能しない。

vibehawk は `POST /repos/X/Y/check-runs` API で `vibehawk` という名前の status check を post する（**merge gate の主軸**）。これに加えて approve / request_changes を **補助情報** として post するが、GitHub の構造仕様により bot review は branch protection の `required_approving_review_count` に count されないため、merge gating を確実に効かせるには status check 側で required 指定が必須（CodeRabbit が `["CodeRabbit", "test"]` で行っているのと同じ仕組み、Issue #121-C1 / #138）。

設定手順は `Settings → Branches → Branch protection rules` から `Require status checks to pass before merging` を ON にし、検索ボックスに `vibehawk` を入力して required に追加する（詳細: [`docs/specification.md § status check 仕様`](docs/specification.md)）。

**この登録を行わない場合**、vibehawk は補助情報を post するのみで merge gate として機能しない（bot review は required reviewers に count されないため）。vibehawk を導入したら必ず本ステップまで完了させること。

導入時のトラブル（連番衝突 / ポート占有 / secret 登録ミス / Private Key 取扱）は [`docs/troubleshooting.md`](docs/troubleshooting.md) を参照。

## 💰 追加課金ゼロの条件

vibehawk 開発者は GitHub Actions / Anthropic 双方の料金体系を制御できない。「追加課金ゼロ」は以下の条件下で成立する。

### 対象（追加課金ゼロが成立）

| 条件 | 内容 |
|------|------|
| ✅ リポジトリ種別 | **Public リポジトリ** |
| ✅ Anthropic 契約 | **Claude Pro / Max（既存サブスクリプション枠内）** |
| ✅ GitHub Actions | **Public リポは無制限の無料枠** |

### 対象外

| ケース | 内容 |
|---|---|
| ⚠️ Private リポジトリ | GitHub Actions minutes が従量課金（個人プラン: 月 2,000 分まで無料、超過時 GitHub の公式料金表に従って課金） |
| ⚠️ Anthropic API Key（従量制）| vibehawk **側の運用ポリシー判断** として OAuth 経路（Claude Pro / Max）のみをサポート対象とし、API Key 経路は **サポート対象外**（claude-code-action 自体の仕様ではなく vibehawk 側の設計判断）|
| ⚠️ Pro/Max の解約・値上げ | Anthropic 契約内容に従う |

「追加課金が発生する」（Private リポ / Pro/Max 値上げ）と「サポート対象外」（API Key 経路）は区別する。料金体系変更時の免責詳細は [`docs/POLICY.md § 免責条項（Issue #32）`](docs/POLICY.md) を参照。

### 利用者ごと独立 App（経路 2 必須化）

vibehawk は経路 2（利用者ごとに独立した `vibehawk-for-<owner>` App + 3 secrets 手動登録）のみを OSS 利用者の標準導入経路として認める（Issue #61 / #72 / #74）。Private Key 漏洩影響を利用者本人のリポジトリ群に限定する構造で、集中 SaaS App の「1 鍵漏洩で全利用者波及」リスクを構造的に回避する。設計根拠と命名統制非対称性の率直開示は [`docs/design-philosophy.md § 認証経路の設計`](docs/design-philosophy.md) を参照。

### claude-code-action 経由の Anthropic 送信

利用者リポジトリの workflow は `anthropics/claude-code-action`（MIT、Anthropic 提供）を呼び出し、PR diff・コメント・コントリビューター情報を Anthropic の処理基盤に送信する。**CLI 自体は Anthropic に通信しない**（localhost のみで完結）。GDPR / 個人情報保護法対応の責任分界（利用者がデータ管理者、Anthropic がデータ処理者、vibehawk 開発者は処理者ではない）は [`docs/POLICY.md § PII 取扱い方針`](docs/POLICY.md) を参照。

## 🛠️ 機能概要

vibehawk は PR が作成・更新されるたびに以下を実行する:

- **required status check**: `vibehawk` 名で check run を post（**merge gate 主軸**、Issue #121-C1 / #138。投稿者: `github-actions[bot]`、認証: workflow デフォルト `GITHUB_TOKEN` + `permissions.checks: write`）
- **PR レビューサマリ**: PR 単位の総評コメントを review summary として `vibehawk-for-<owner>[bot]` 名義で投稿
- **インライン指摘**: 行レベルの severity 付きコメント（CodeRabbit 互換 5 段階: 🔴 Critical / 🟠 Major / 🟡 Minor / 🔵 Trivial / ⚪ Info）
- **approve / request_changes**: **補助情報** として post（merge gating には使わない、`required_approving_review_count` バイパス回避のため）
- **@mention チャット応答**: PR コメントで `@vibehawk-for-<owner>` メンションすると応答
- **メタデータ非操作**: PR の label / milestone / description / assignee 等は変更しない（MVV Value 2「観察する、書き換えない」）
- **指摘・強制しない設計**: severity を付けるが、直すか流すかの裁量は利用者に委ねる（MVV Value 3「指摘する、強制しない」）
- **CLI が secret を書き込まない設計**（Issue #72）: 利用者が GitHub Settings UI で 3 secrets（`VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`）を手動登録（判断根拠は [`docs/secrets-handling.md`](docs/secrets-handling.md) 参照）

機能仕様の詳細は [`docs/specification.md`](docs/specification.md)、PR レビュー設計の根拠と vibecorp との関係は [`docs/design-philosophy.md`](docs/design-philosophy.md) を参照。

### 再レビューを依頼する（Issue #135）

vibehawk が一度 `failure` を post すると、利用者が指摘に対応しても再レビュー無しに status check の conclusion を更新できないため、merge が永久にブロックされる UX 欠陥がある（Issue #135 / PR #133）。これを解消する正規導線として、以下 2 経路で vibehawk を再発火できる:

- **経路 1: "Re-request review" ボタン**: PR ページの Reviewers セクションから vibehawk-for-<owner> 横の 🔄 ボタンを押す → `pull_request: review_requested` トリガーで `vibehawk-review.yml` が再発火し、最新差分でレビュー＋status check を更新する
- **経路 2: `@vibehawk review` コメント**: PR コメントで `@vibehawk review` と書いて投稿 → `vibehawk-chat.yml` が `@vibehawk review` を検知し、bundled review POST と status check 更新を実行する

どちらの経路でも status check `vibehawk` の conclusion が最新差分に基づいて再評価される。空コミット push という workaround は不要。

> **利用者向けアップデート手順**: 既に vibehawk を導入済みのリポジトリは、`templates/.github/workflows/vibehawk-review.yml` および `templates/.github/workflows/vibehawk-chat.yml` の最新版を `.github/workflows/` に上書きコピーして PR を出すこと（再 install は不要、追加 secret 設定も不要）。

### メンテナー向け運用

利用者がリポジトリのメンテナー（OWNER）として vibehawk を運用する場合、自身の PR ごとに claude-code-action が起動して Claude Pro / Max 枠を消費する dogfooding 構造となる。OSS 開発活発化時に個人契約枠がボトルネック化する懸念に対する `if:` 条件による PR 除外等の推奨設定は [`docs/maintainer-quota-policy.md`](docs/maintainer-quota-policy.md) を参照。

## 📚 ドキュメント

| ドキュメント | 内容 |
|---|---|
| [`MVV.md`](MVV.md) | Mission / Vision / Value（編集禁止） |
| [`docs/specification.md`](docs/specification.md) | 機能仕様 / CLI 仕様 / アーキテクチャ / status check 仕様（Issue #121-C1） |
| [`docs/POLICY.md`](docs/POLICY.md) | プロダクト方針 / 法務・コンプライアンス / 免責条項（Issue #32）/ PII / 商標使用許諾（Issue #33） |
| [`docs/design-philosophy.md`](docs/design-philosophy.md) | 設計哲学 / 認証経路の設計（経路 2 必須化）/ 命名統制（Issue #25） |
| [`docs/SECURITY.md`](docs/SECURITY.md) | 認証・認可 / Private Key の CISO Critical 条件 / Manifest Flow セキュリティ対策（Issue #59） |
| [`docs/secrets-handling.md`](docs/secrets-handling.md) | 認証情報配布方式の判断履歴（CLI が secret を一切 touch しない設計、Issue #7 / #60 関連） |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | 命名統制衝突 / ポート占有 / secret 登録ミス / Private Key 取扱 |
| [`docs/maintainer-quota-policy.md`](docs/maintainer-quota-policy.md) | メンテナー個人契約枠の保護ポリシー |
| [`docs/cost-analysis.md`](docs/cost-analysis.md) | コスト設計 / PR サイズ段階的劣化 |
| [`docs/external-dependency-audit.md`](docs/external-dependency-audit.md) | 外部依存（claude-code-action 等）の規約整合監査 |

## 📜 ライセンス / ステータス / 免責

- **ライセンス**: MIT
- **ステータス**: 開発中（Phase 1 基盤構築 + OSS 配布対応）。Issue #7 で実行基盤、#22 で OSS 配布可能化、#24 で `npx vibehawk install` 基盤、#91 で `setup` ウィザード（1 コマンド導入）、#121-C1 で required status check、#138 で status check 主軸 positioning を順次積み上げ
- **免責**: vibehawk は MIT のもと **無保証** で提供。CLI 配布物（`npx vibehawk install` / `npx vibehawk setup-token`）の利用は **すべてご利用者の自己責任**。免責範囲（スクリプト誤動作 / GitHub App 作成失敗 / クリップボード経由のトークン受け渡し / secrets 登録運用 / GitHub・Anthropic 側の障害）の詳細は [`docs/POLICY.md § 免責条項（Issue #32）`](docs/POLICY.md) を参照
