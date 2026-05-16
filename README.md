# 🦅 vibehawk

> 鷹のように観察し、追加課金ゼロで PR レビューを届ける OSS プロダクト

**vibehawk** は **追加課金ゼロの PR 自動レビュー OSS プロダクト**。利用者が既に契約している LLM サブスクリプション枠（Claude Pro / Max）の **内側だけ** で動作し、AI レビュー専用 SaaS の月額や LLM API の従量課金を発生させない。

vibe シリーズ（vibecorp / vibemux / vibehawk）の一員として、CodeRabbit の「うさぎ（速さ・量）」に対し「鷹（精度・観察力・全体俯瞰）」のメタファーで対置する。

### 30 秒サマリ

- 🦅 **追加課金ゼロ**: 利用者の Claude Pro / Max OAuth トークン内で完結、運営側サーバー・専用 DB なし
- 🦅 **観察に徹する**: PR メタデータ（label / milestone 等）は書き換えず、レビュー & 修正提案のみを届ける
- 🦅 **公式の道だけ歩く**: 裏 API・スクレイピングなし、claude-code-action 経由の OAuth 経路のみサポート
- 🦅 **利用者ごと独立 App**: 集中 SaaS App の「1 鍵漏洩で全利用者波及」リスクを構造的に回避（経路 2 必須化）

Mission / Vision / Value は [`MVV.md`](MVV.md)、詳細仕様は [`docs/specification.md`](docs/specification.md)、プロダクト方針は [`docs/POLICY.md`](docs/POLICY.md) を参照。

## ⚡ クイックスタート

vibehawk は **利用者ごとに独立した GitHub App（`vibehawk-for-<owner>`）** を利用者本人が作成・運用する構造（命名統制、詳細・非対称性の開示は [`docs/design-philosophy.md § 命名統制`](docs/design-philosophy.md) 参照）。投稿者は `vibehawk-for-<owner>[bot]` 名義になる。

> **対応 OS**: macOS / Linux / Windows（PowerShell / CMD / Git Bash）

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

### （推奨）branch protection に `vibehawk` を required status check 登録

vibehawk は bundled review API による approve / request_changes 投稿に加え、`POST /repos/X/Y/check-runs` で `vibehawk` という check run を post する。GitHub の構造仕様により bot review は branch protection の required reviewers に count されないため、merge gating には status check 側で required 指定が必須（CodeRabbit が `["CodeRabbit", "test"]` で行っているのと同じ仕組み）。設定手順は `Settings → Branches → Branch protection rules` から `Require status checks to pass before merging` を ON にし、検索ボックスに `vibehawk` を入力して required に追加する（Issue #121-C1、詳細: [`docs/specification.md § status check 仕様`](docs/specification.md)）。

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

vibehawk は PR が作成・更新されるたびに `vibehawk-for-<owner>[bot]` 名義で以下を実行する:

- **PR レビューサマリ**: PR 単位の総評コメントを review summary として投稿
- **インライン指摘**: 行レベルの severity 付きコメント（CodeRabbit 互換 5 段階: 🔴 Critical / 🟠 Major / 🟡 Minor / 🔵 Trivial / ⚪ Info）
- **@mention チャット応答**: PR コメントで `@vibehawk-for-<owner>` メンションすると応答
- **required status check**: `vibehawk` 名で check run を post（merge gating 対応、Issue #121-C1）
- **メタデータ非操作**: PR の label / milestone / description / assignee 等は変更しない（MVV Value 2「観察する、書き換えない」）
- **指摘・強制しない設計**: severity を付けるが、直すか流すかの裁量は利用者に委ねる（MVV Value 3「指摘する、強制しない」）
- **CLI が secret を書き込まない設計**（Issue #72）: 利用者が GitHub Settings UI で 3 secrets（`VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`）を手動登録（判断根拠は [`docs/secrets-handling.md`](docs/secrets-handling.md) 参照）

機能仕様の詳細は [`docs/specification.md`](docs/specification.md)、PR レビュー設計の根拠と vibecorp との関係は [`docs/design-philosophy.md`](docs/design-philosophy.md) を参照。

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
- **ステータス**: 開発中（Phase 1 基盤構築 + OSS 配布対応）。Issue #7 で実行基盤、#22 で OSS 配布可能化、#24 で `npx vibehawk install` 基盤、#91 で `setup` ウィザード（1 コマンド導入）、#121-C1 で required status check を順次積み上げ
- **免責**: vibehawk は MIT のもと **無保証** で提供。CLI 配布物（`npx vibehawk install` / `npx vibehawk setup-token`）の利用は **すべてご利用者の自己責任**。免責範囲（スクリプト誤動作 / GitHub App 作成失敗 / クリップボード経由のトークン受け渡し / secrets 登録運用 / GitHub・Anthropic 側の障害）の詳細は [`docs/POLICY.md § 免責条項（Issue #32）`](docs/POLICY.md) を参照
