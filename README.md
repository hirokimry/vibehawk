# 🦅 vibehawk

> 追加課金ゼロで動く、merge gate 型の AI PR レビュアー

branch protection の required status check として動き、「AI レビューが OK を出さないと merge できない」状態を作る OSS。
利用者が既に契約している Claude Pro / Max の枠内だけで動作する。

- 🛠️ **対象**: GitHub + Claude Pro / Max を利用する開発者・チーム
- 🎯 **解く課題**: レビュー SaaS の月額や LLM API の従量課金なしで merge gate を作りたい
- ⚡ **最短導入**: `npx vibehawk setup` の 1 コマンド

> [!IMPORTANT]
> このドキュメントは導入開発者向けの入口ガイド。
> 詳細は [`MVV.md`](MVV.md) / [`docs/specification.md`](docs/specification.md) / [`docs/POLICY.md`](docs/POLICY.md) を参照。

---

## ⚡ クイックスタート

> **対応 OS**: macOS / Linux / Windows（PowerShell / CMD / Git Bash）

ゴールは **branch protection に `vibehawk` を required status check として追加すること**。
`vibehawk` check は一度発火しないと branch protection の検索候補に出ないため、手順は次の 3 ステップになる。

### 1. App / secrets / workflow を準備

```bash
npx vibehawk setup --owner <your-github-username> --repo <owner>/<repo>
```

対話型ウィザードが App 作成 → リポジトリインストール → 3 secrets 登録 → workflow PR までを案内する（`--dry-run` で事前確認可）。
vibehawk は利用者ごとに独立した GitHub App（`vibehawk-for-<owner>`）を利用者本人が作成・運用する構造で、投稿者は `vibehawk-for-<owner>[bot]` 名義になる。

App ID / OAuth Token は OS のクリップボード経由で受け渡し、OAuth Token の値はクリップボードコピー失敗時でも stdout に出さない（CISO Critical 条件、[`docs/SECURITY.md`](docs/SECURITY.md) 参照）。
個別実行手順（`install` / `setup-token`）や bot アイコン差し替えは [`docs/specification.md § CLI 仕様`](docs/specification.md) を参照。

### 2. 初回 PR で `vibehawk` check を発火

workflow 配置後に PR を立てると、`vibehawk-for-<owner>[bot]` 名義のレビューと `vibehawk` status check が post される。

### 3. branch protection に `vibehawk` を required 登録

`Settings → Branches → Branch protection rules` で `Require status checks to pass before merging` を ON にし、`vibehawk` を required に追加する。

**この登録を行わない場合**、vibehawk は補助情報を post するのみで merge gate として機能しない（bot review は required reviewers に count されないため）。

導入時のトラブルは [`docs/troubleshooting.md`](docs/troubleshooting.md) を参照。

---

## 🎁 何ができる？

| できること | 動線 |
|------------|------|
| ✅ AI レビューが通らないと merge できない merge gate | branch protection に `vibehawk` を required 登録 |
| 💰 追加課金ゼロの AI PR レビュー | 利用者の Claude Pro / Max OAuth トークン内で完結 |
| 🖥️ push 前に手元で CI と同一基準のレビュー | `npx vibehawk review` |
| 🔄 指摘対応後の再レビュー | "Re-request review" ボタン or `@vibehawk review` コメント |
| 💬 PR コメントでの対話 | `@vibehawk-for-<owner>` メンション |

---

## ✨ 何がユニークか

- **merge gate の主軸は status check**: approve / request_changes は補助情報として post し、merge gating には使わない
- **人間 review 必須要件をバイパスしない**: `required_approving_review_count` を AI で満たす設計を意図的に避ける（主要な AI レビュー製品も同じ理由で APPROVE 経路を回避している）
- **観察に徹する**: PR の label / milestone 等のメタデータは書き換えない（MVV Value 2「観察する、書き換えない」）
- **利用者ごと独立 App**: 集中型 App の「1 鍵漏洩で全利用者波及」リスクを構造的に回避

Anthropic が公式に案内する「自前 CI で gate する」設計思想を OSS としてパッケージ化したもの（Anthropic 提携・公認製品ではない）。
詳細: [`docs/specification.md § status check 仕様`](docs/specification.md) / [`docs/design-philosophy.md`](docs/design-philosophy.md)。

---

## 🛡️ 安全と課金

### 💰 追加課金ゼロの条件

| 対象（成立する） | 対象外 |
|------|------|
| ✅ Public リポジトリ | ⚠️ Private リポジトリ（GitHub Actions minutes が従量課金） |
| ✅ Claude Pro / Max（既存サブスクリプション枠内） | ⚠️ Anthropic API Key 経路（**サポート対象外**、vibehawk 側の設計判断） |
| ✅ GitHub Actions（Public リポは無料枠無制限） | ⚠️ Pro/Max の解約・値上げ（Anthropic 契約内容に従う） |

「追加課金が発生する」（Private リポ / Pro/Max 値上げ）と「サポート対象外」（API Key 経路）は区別する。
免責の詳細は [`docs/POLICY.md § 免責条項`](docs/POLICY.md) を参照。

### 🔐 利用者ごと独立 App（経路 2 必須化）

経路 2（独立 App + 3 secrets 手動登録）のみを OSS 利用者の標準導入経路として認める。
Private Key 漏洩の影響を利用者本人のリポジトリ群に限定するための構造。設計根拠は [`docs/design-philosophy.md § 認証経路の設計`](docs/design-philosophy.md) を参照。

### 📡 Anthropic への送信

workflow は `anthropics/claude-code-action` を呼び出し、PR diff・コメント・コントリビューター情報を Anthropic の処理基盤に送信する。
セットアップ系 CLI（`install` / `setup` / `setup-token`）は Anthropic に通信しない。`npx vibehawk review` は手元の git diff を Anthropic に送信する。
GDPR / 個人情報保護法対応の責任分界（利用者がデータ管理者、Anthropic がデータ処理者、vibehawk 開発者は処理者ではない）は [`docs/POLICY.md § PII 取扱い方針`](docs/POLICY.md) を参照。

---

## 🛠️ 機能一覧

| 機能 | 何ができるか |
|------|------------|
| ✅ required status check | `vibehawk` 名で check run を post（**merge gate の主軸**） |
| 📝 PR レビューサマリ | PR 単位の総評を `vibehawk-for-<owner>[bot]` 名義で投稿 |
| 📌 sticky walkthrough | PR ごとに 1 個固定のサマリコメントを push のたびに更新 |
| 💬 インライン指摘 | 行レベルの severity 付きコメント（🔴 Critical / 🟠 Major / 🟡 Minor / 🔵 Trivial / ⚪ Info の 5 段階） |
| ℹ️ approve / request_changes | 補助情報として post（merge gating には使わない） |
| 🤖 @mention チャット応答 | PR コメントでのメンションに応答 |
| 🚫 メタデータ非操作 | label / milestone / description / assignee 等は変更しない |
| 🤝 指摘・強制しない | severity は付けるが、直すか流すかは利用者の裁量（MVV Value 3） |
| 🔐 CLI が secret を書き込まない | 3 secrets（`VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`）は利用者が GitHub Settings UI で手動登録（[`docs/secrets-handling.md`](docs/secrets-handling.md)） |

機能仕様の詳細は [`docs/specification.md`](docs/specification.md) を参照。

### 🔄 再レビューを依頼する

status check が `failure` のまま止まったら、以下のどちらかで最新差分の再レビューを発火できる（空コミット push は不要）。

| 経路 | 操作 |
|------|------|
| "Re-request review" ボタン | PR の Reviewers セクションで vibehawk-for-\<owner\> 横の 🔄 を押す |
| `@vibehawk review` コメント | PR コメントに `@vibehawk review` と書く |

> **利用者向けアップデート手順**: 導入済みリポジトリは `templates/.github/workflows/` 配下の最新 workflow を `.github/workflows/` に上書きコピーして PR を出す（再 install・追加 secret 不要）。

メンテナー自身の PR でも Claude Pro / Max 枠を消費するため、契約枠の保護設定は [`docs/maintainer-quota-policy.md`](docs/maintainer-quota-policy.md) を参照。

### 🖥️ push 前ローカルレビュー（`npx vibehawk review`）

push 前に手元の git diff を CI と同一基準でレビューできる。read-only（指摘のみ・自動修正なし）で、Claude Pro / Max 枠内で完結する。

```bash
npx vibehawk review                       # working tree をレビュー
npx vibehawk review --staged              # staged の変更だけ
npx vibehawk review --base main           # main からの差分
npx vibehawk review --output json         # JSON 出力
npx vibehawk review --fail-on major       # Major 以上で終了コード 1（pre-commit / CI 用）
```

| フラグ | 動作 |
|---|---|
| `--staged` | staged の変更だけをレビュー |
| `--base <ref>` | `<ref>...HEAD` の差分をレビュー |
| `--intent <label>` | 重視軸を指定（`feature` / `bugfix` / `security` 等 7 種） |
| `--output text\|json` | 出力形式（既定 `text`） |
| `--fail-on <severity>` | 該当 severity 以上で終了コード 1（既定は常に 0 = 止めない） |

初回のみ Claude Code のインストールと OAuth ログイン（`npx vibehawk setup-token` の案内に従う）が必要。

> [!NOTE]
> `ANTHROPIC_API_KEY` が設定されていると、追加課金（API 従量）を避けるため **review は実行を中止**する。
> `unset ANTHROPIC_API_KEY` で OAuth 経路に戻る（[`docs/troubleshooting.md`](docs/troubleshooting.md)）。

> [!IMPORTANT]
> `npx vibehawk review` は手元の git diff を Anthropic に送信する。
> 機密を含む場合は `--staged` や `.vibehawk.yaml` の `path_filters` で送信範囲を絞ること（[`docs/POLICY.md`](docs/POLICY.md)）。

---

## 📚 詳細ドキュメント

| 知りたいこと | 参照先 |
|------------|-------|
| 🌟 Mission / Vision / Value（編集禁止） | [`MVV.md`](MVV.md) |
| 🧩 機能仕様 / CLI 仕様 / status check 仕様 | [`docs/specification.md`](docs/specification.md) |
| 📜 プロダクト方針 / 免責 / PII / 商標 | [`docs/POLICY.md`](docs/POLICY.md) |
| 🎨 設計哲学 / 認証経路 / 命名統制 | [`docs/design-philosophy.md`](docs/design-philosophy.md) |
| 🔒 認証・認可 / Private Key の取扱 | [`docs/SECURITY.md`](docs/SECURITY.md) |
| 🔑 認証情報配布方式の判断履歴 | [`docs/secrets-handling.md`](docs/secrets-handling.md) |
| 🛟 トラブルシューティング | [`docs/troubleshooting.md`](docs/troubleshooting.md) |
| 👤 メンテナー契約枠の保護 | [`docs/maintainer-quota-policy.md`](docs/maintainer-quota-policy.md) |
| 💰 コスト設計 | [`docs/cost-analysis.md`](docs/cost-analysis.md) |
| 🔍 外部依存の規約整合監査 | [`docs/external-dependency-audit.md`](docs/external-dependency-audit.md) |
| 🤖 呼び出す Anthropic 公式 Action（MIT） | [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) |

---

## 🎨 設計思想

merge gate を status check に置く理由、AI approve を使わない理由、認証経路・命名統制の判断根拠は [`docs/design-philosophy.md`](docs/design-philosophy.md) にまとめている。

---

## 📜 ライセンス / ステータス / 免責

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

- **ライセンス**: [MIT](LICENSE)
- **ステータス**: 開発中。npm で [`vibehawk`](https://www.npmjs.com/package/vibehawk) として公開中（リリースは OIDC trusted publisher 経由で自動 publish）
- **免責**: MIT のもと **無保証** で提供。CLI 配布物の利用はすべてご利用者の自己責任。免責範囲の詳細は [`docs/POLICY.md § 免責条項`](docs/POLICY.md) を参照
