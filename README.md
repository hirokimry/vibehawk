# 🦅 vibehawk

> 追加課金ゼロで動く、merge gate 型の AI PR レビュアー

branch protection の required status check として動く。
「AI レビューが OK を出さないと merge できない」状態を作る OSS。
利用者が既に契約している Claude Pro / Max の枠内だけで動作する。

- 🛠️ **対象**: GitHub + Claude Pro / Max を利用する開発者・チーム
- 🎯 **解く課題**: SaaS 月額も API 従量課金も払わずに merge gate を作る
- ⚡ **最短導入**: `npx vibehawk setup` の 1 コマンド

> [!IMPORTANT]
> このドキュメントは導入開発者向けの入口ガイド。
> 方針は [`MVV.md`](MVV.md) と [`docs/POLICY.md`](docs/POLICY.md) を参照。
> 仕様は [`docs/specification.md`](docs/specification.md) を参照。

---

## ⚡ クイックスタート

> **対応 OS**: macOS / Linux / Windows

ゴールは `vibehawk` check の required 登録。
check は一度発火しないと branch protection の検索候補に出ない。
そのため手順は次の 3 ステップになる。

### 1. App / secrets / workflow を準備

```bash
npx vibehawk setup --owner <your-github-username> --repo <owner>/<repo>
```

対話型ウィザードが App 作成・secrets 登録・workflow PR までを案内する。
実行内容は `--dry-run` で事前確認できる。

vibehawk は利用者ごとに独立した GitHub App を利用者本人が運用する構造。
App 名は `vibehawk-for-<owner>`。
レビューの投稿者は `vibehawk-for-<owner>[bot]` 名義になる。

App ID / OAuth Token は OS のクリップボード経由で受け渡す。
OAuth Token の値はクリップボードコピー失敗時でも stdout に出さない。
根拠は [`docs/SECURITY.md`](docs/SECURITY.md)（CISO Critical 条件）を参照。

個別実行手順は [`docs/specification.md § CLI 仕様`](docs/specification.md) を参照。
bot アイコンの差し替え手順も同セクションに記載。

### 2. 初回 PR で `vibehawk` check を発火

workflow 配置後に PR を立てると `vibehawk` check が post される。
レビューは `vibehawk-for-<owner>[bot]` 名義で投稿される。

### 3. branch protection に `vibehawk` を required 登録

1. `Settings → Branches` で Branch protection rule を開く
2. `Require status checks to pass before merging` を ON
3. 検索ボックスで `vibehawk` を required に追加

**この登録を行わない場合**、vibehawk は補助情報を post するだけになる。
bot review は required reviewers に count されないため。

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

- **merge gate の主軸は status check**
  - approve / request_changes は補助情報として post する。
  - merge gating には使わない。
- **人間 review 必須要件をバイパスしない**
  - `required_approving_review_count` を AI で満たす設計を避ける。
  - 主要な AI レビュー製品も同じ理由で APPROVE 経路を回避している。
- **観察に徹する**
  - PR の label / milestone 等のメタデータは書き換えない。
  - MVV Value 2「観察する、書き換えない」に基づく。
- **利用者ごと独立 App**
  - 集中型 App の「1 鍵漏洩で全利用者波及」リスクを構造的に回避する。

Anthropic 公式の「自前 CI で gate する」設計思想を OSS 化したもの。
Anthropic 提携・公認製品ではない。
設計判断の詳細は [`docs/design-philosophy.md`](docs/design-philosophy.md) を参照。

---

## 🛡️ 安全と課金

### 💰 追加課金ゼロの条件

| 対象（成立する） | 対象外 |
|------|------|
| ✅ Public リポジトリ | ⚠️ Private リポジトリ（GitHub Actions minutes が従量課金） |
| ✅ Claude Pro / Max（既存サブスクリプション枠内） | ⚠️ Anthropic API Key 経路（**サポート対象外**、vibehawk 側の設計判断） |
| ✅ GitHub Actions（Public リポは無料枠無制限） | ⚠️ Pro/Max の解約・値上げ（Anthropic 契約内容に従う） |

「追加課金が発生する」と「サポート対象外」は区別する。
前者は Private リポと Pro/Max 値上げ、後者は API Key 経路を指す。
免責の詳細は [`docs/POLICY.md § 免責条項`](docs/POLICY.md) を参照。

### 🔐 利用者ごと独立 App（経路 2 必須化）

経路 2 のみを OSS 利用者の標準導入経路として認める。
経路 2 = 独立 App + 3 secrets の手動登録。
Private Key 漏洩の影響を利用者本人のリポジトリ群に限定する。
設計根拠は [`docs/design-philosophy.md § 認証経路の設計`](docs/design-philosophy.md) を参照。

### 📡 Anthropic への送信

workflow は `anthropics/claude-code-action` を呼び出す。
PR diff・コメント・コントリビューター情報を Anthropic の処理基盤に送信する。
セットアップ系 CLI（`install` / `setup` / `setup-token`）は通信しない。
`npx vibehawk review` は手元の diff を Anthropic に送信する。

GDPR 等の責任分界は [`docs/POLICY.md § PII 取扱い方針`](docs/POLICY.md) を参照。
利用者がデータ管理者、Anthropic がデータ処理者、vibehawk 開発者は処理者ではない。

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

status check が `failure` のまま止まることがある。
以下のどちらかで最新差分の再レビューを発火できる。
空コミット push は不要。

| 経路 | 操作 |
|------|------|
| "Re-request review" ボタン | PR の Reviewers セクションで vibehawk-for-\<owner\> 横の 🔄 を押す |
| `@vibehawk review` コメント | PR コメントに `@vibehawk review` と書く |

> **利用者向けアップデート手順**: 最新の workflow を上書きコピーして PR を出す。
> コピー元は `templates/.github/workflows/`。
> コピー先は `.github/workflows/`。
> 再 install・追加 secret は不要。
>
> **v0.2.2 以前の既存導入**: v0.2.3 で `vibehawk-review-skip-mark.yml` が新規追加された。
> 上記の上書きコピーで取得できる。lockfile のみ変更の PR が required check で BLOCKED にならなくなる。

メンテナー自身の PR でも Claude Pro / Max 枠を消費する。
契約枠の保護設定は [`docs/maintainer-quota-policy.md`](docs/maintainer-quota-policy.md) を参照。

### 🖥️ push 前ローカルレビュー（`npx vibehawk review`）

push 前に手元の git diff を CI と同一基準でレビューできる。
read-only（指摘のみ・自動修正なし）で、Claude Pro / Max 枠内で完結する。

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

初回のみ Claude Code のインストールと OAuth ログインが必要。
手順は `npx vibehawk setup-token` の案内に従う。

> [!NOTE]
> `ANTHROPIC_API_KEY` が設定されていると **review は実行を中止**する。
> 追加課金（API 従量）を避けるための挙動。
> `unset ANTHROPIC_API_KEY` で OAuth 経路に戻る。
> 詳細は [`docs/troubleshooting.md`](docs/troubleshooting.md) を参照。

> [!IMPORTANT]
> `npx vibehawk review` は手元の diff を Anthropic に送信する。
> 機密を含む場合は送信範囲を絞ること。
> `--staged` や `.vibehawk.yaml` の `path_filters` が使える。
> 詳細は [`docs/POLICY.md`](docs/POLICY.md) を参照。

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

設計判断の根拠は [`docs/design-philosophy.md`](docs/design-philosophy.md) にまとめている。
対象は merge gate の置き方・AI approve 不使用の理由・認証経路・命名統制。

---

## 📜 ライセンス / ステータス / 免責

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

- **ライセンス**: [MIT](LICENSE)
- **ステータス**: 開発中。npm で [`vibehawk`](https://www.npmjs.com/package/vibehawk) として公開中。リリースは OIDC trusted publisher 経由で自動 publish される
- **免責**: MIT のもと **無保証** で提供。CLI 配布物の利用はすべてご利用者の自己責任。免責範囲の詳細は [`docs/POLICY.md § 免責条項`](docs/POLICY.md) を参照
