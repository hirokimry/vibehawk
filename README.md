# vibehawk

> 鷹のように観察し、追加課金ゼロで PR レビューを届ける OSS プロダクト

## 概要

vibehawk は **追加課金ゼロの PR 自動レビュー OSS プロダクト** です。利用者が既に契約している LLM サブスクリプション枠（Claude Pro / Max 等）の **内側だけ** で動作し、AI レビュー専用 SaaS の月額や LLM API の従量課金を発生させません。

vibe シリーズ（vibecorp / vibemux / vibehawk）の一員として、CodeRabbit の「うさぎ（速さ・量）」に対し「鷹（精度・観察力・全体俯瞰）」のメタファーで対置します。

詳細は `MVV.md` / `docs/specification.md` / `docs/POLICY.md` を参照。

## 利用者の導入手順

vibehawk は **利用者ごとに独立した GitHub App（`vibehawk-for-<owner>`）** を利用者本人が作成・運用する構造です。投稿者は `vibehawk-for-<owner>[bot]` 名義になります（命名統制 Issue #25）。

利用者リポジトリに登録する secrets は **3 つすべて利用者が GitHub Settings UI で手動登録** します（CEO 判断 Issue #72、CLI は secret を書き込みません。判断根拠は [`docs/secrets-handling.md`](docs/secrets-handling.md) 参照）。

> **対応 OS**: macOS / Linux / Windows（PowerShell / CMD / Git Bash）。Windows では `cmd /c start` でブラウザを起動します。CI で windows-latest runner で全テスト通過を保証しています。

### 1. App 作成 — `npx vibehawk install`

```bash
npx vibehawk install --owner <your-github-username>
```

ローカルに一時 HTTP サーバー（127.0.0.1:8765）を起動し、ブラウザで GitHub App Manifest Flow を開始します。利用者が GitHub UI で「Create」を押すと `vibehawk-for-<owner>` 名の App が作成されます。CLI は完了後 App ID と Settings URL を画面表示します（Private Key は画面に印字せず破棄、CISO Critical 条件）。

vibehawk 運営側のサーバーには一切通信しません（localhost のみで完結）。

### 2. App ID を Secrets に登録（GitHub UI）

CLI が表示する URL（対象リポジトリの `Settings → Secrets and variables → Actions → New repository secret`）を開き、以下を登録します:

| Secret 名 | 値 |
|---|---|
| `VIBEHAWK_APP_ID` | CLI 画面に表示された App ID（数値） |

### 3. Private Key を Secrets に登録（GitHub UI）

App Settings ページ（`https://github.com/settings/apps/vibehawk-for-<owner>`）で「Generate a private key」を押して `.pem` ファイルをダウンロードします。続けて対象リポジトリの Secrets 画面で以下を登録します:

| Secret 名 | 値 |
|---|---|
| `VIBEHAWK_PRIVATE_KEY` | ダウンロードした `.pem` ファイルの **内容全文**（`-----BEGIN ... -----END` を含む） |

### 4. OAuth Token を Secrets に登録 — `npx vibehawk setup-token`

```bash
npx vibehawk setup-token --repo <owner>/<repo>
```

CLI が `claude setup-token`（Anthropic 公式 CLI）の実行案内を表示します。別ターミナルで `claude setup-token` を実行してトークンを取得し、vibehawk CLI のプロンプトに貼り付けます。CLI は明示同意の上で OS ネイティブのクリップボードに stdin 経由でコピーし、対象リポジトリの GitHub Settings URL と登録手順を画面表示します。利用者がブラウザを開き以下を登録します:

| Secret 名 | 値 |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` で取得した OAuth Token |

CLI は受け取ったトークンをローカルファイルに保存せず、メモリ上のみで保持し、本プロセス終了と同時に消去します。

### 5. workflow を配置

リポジトリに `.github/workflows/vibehawk-review.yml` を配置します。本リポジトリの同名ファイルをコピーして利用してください。workflow は以下の **最小権限** のみ要求します（詳細は [`docs/SECURITY.md`](docs/SECURITY.md)）:

- `pull_requests: write`
- `issues: write`
- `contents: read`

### 6. PR を出す

PR を作成すると `vibehawk-review.yml` が起動し、`vibehawk-for-<owner>[bot]` 名義でレビューサマリコメントを投稿します。

### `--dry-run` モード

実行内容を事前確認したい場合は `--dry-run` を付けてください。実際には何もせず、起動する HTTP サーバーのポート・通信先・書き込み範囲を表示するだけです:

```bash
npx vibehawk install --owner alice --dry-run
```

### CLI が secret を書き込まない設計（Issue #72）

vibehawk CLI は `gh secret set` を呼び出さず、利用者リポジトリの GitHub Secrets を直接書き換えません。CLI は登録手順の画面誘導と任意のクリップボードコピーまでを担当し、実際の secret 登録は利用者が GitHub Settings UI で実施します。判断根拠（メジャーサービス比較 / GitHub 公式ガイドライン / CodeRabbit 事件の教訓 / MVV 整合）は [`docs/secrets-handling.md`](docs/secrets-handling.md) を参照。

## ステータス

本リポジトリは **開発中**（Phase 1 基盤構築 + OSS 配布対応）です。Issue #7 で実行基盤を、Issue #22 で OSS 配布可能化を、Issue #24 で `npx vibehawk install` 基盤を、Issue #8 以降で詳細レビュー機能（サマリコメント・inline コメント・severity 5 段階・@mention チャット応答）を順次積み上げます。

## 免責事項

vibehawk は MIT ライセンスのもと OSS として **無保証** で提供されます。`npx vibehawk install` / `npx vibehawk setup-token` などの CLI 配布物の利用は **すべてご利用者の自己責任** でお願いします。要点は以下の通りです。

- **スクリプト誤動作**: vibehawk CLI が API 仕様変更追従漏れ・OS 依存バグ・依存ライブラリの脆弱性等により利用者の GitHub 環境を意図せず変更した場合、vibehawk 開発者は一切責任を負いません
- **secrets の登録・漏洩・上書き**: 利用者が GitHub Settings UI で登録する 3 secrets（`VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`）の登録の正確性・漏洩・誤登録・上書きは利用者の運用責任です（CLI は secrets を書き込まない設計のため、vibehawk 開発者は touch していません）
- **GitHub / Anthropic 側の障害**: 依存先サービス（GitHub Manifest API / `anthropics/claude-code-action` / Claude Pro / Max OAuth 等）の仕様変更・障害・課金影響は vibehawk の責任範囲外です

導入前に `--dry-run` モードで実行内容を確認し、本番リポジトリへの適用前に検証用リポジトリで動作を確認することを推奨します。

詳細な免責範囲・利用者の責務・claude-code-action の挙動に関する取扱いは [`docs/POLICY.md`](docs/POLICY.md) の「免責条項（Issue #32）」セクションを参照してください。
