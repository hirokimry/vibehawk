# vibehawk

> 鷹のように観察し、追加課金ゼロで PR レビューを届ける OSS プロダクト

## 概要

vibehawk は **追加課金ゼロの PR 自動レビュー OSS プロダクト** です。利用者が既に契約している LLM サブスクリプション枠（Claude Pro / Max 等）の **内側だけ** で動作し、AI レビュー専用 SaaS の月額や LLM API の従量課金を発生させません。

vibe シリーズ（vibecorp / vibemux / vibehawk）の一員として、CodeRabbit の「うさぎ（速さ・量）」に対し「鷹（精度・観察力・全体俯瞰）」のメタファーで対置します。

詳細は `MVV.md` / `docs/specification.md` / `docs/POLICY.md` を参照。

## 「追加課金ゼロ」の適用範囲

vibehawk が訴求する「追加課金ゼロ」は以下の条件下で成立します。vibehawk 開発者は GitHub Actions / Anthropic 双方の料金体系を制御できないため、対象外ケースの追加課金について責任を負いません（詳細は [`docs/POLICY.md`](docs/POLICY.md) 免責条項参照）。

### 対象（追加課金ゼロが成立）

| 条件 | 内容 |
|------|------|
| ✅ リポジトリ種別 | **Public リポジトリ** |
| ✅ Anthropic 契約 | **Claude Pro / Max（既存サブスクリプション枠内）** |
| ✅ GitHub Actions | **Public リポは無制限の無料枠** |

### 対象外（追加課金が発生する可能性）

| ケース | 発生する追加コスト |
|------|----------------|
| Private リポジトリでの利用 | GitHub Actions minutes が従量課金（個人プラン: 月 2,000 分まで無料、超過時 GitHub の公式料金表に従って課金） |
| Anthropic API Key（従量制）での利用 | vibehawk は運用ポリシーとして OAuth 経路（Claude Pro / Max）のみをサポート対象としており、API Key 経路はサポート対象外（claude-code-action 自体の仕様ではなく vibehawk 側の設計判断） |
| Pro/Max サブスクの解約・値上げ | Anthropic 契約内容に従う |

GitHub / Anthropic の課金体系変更（料金プラン改定・無料枠縮小・有料化等）により利用者に追加課金が発生した場合、vibehawk 開発者は責任を負いません。

## 利用者の導入手順

vibehawk は **利用者ごとに独立した GitHub App（`vibehawk-for-<owner>`）** を利用者本人が作成・運用する構造です。投稿者は `vibehawk-for-<owner>[bot]` 名義になります（命名統制 Issue #25）。

利用者リポジトリに登録する secrets は **3 つすべて利用者が GitHub Settings UI で手動登録** します（CEO 判断 Issue #72、CLI は secret を書き込みません。判断根拠は [`docs/secrets-handling.md`](docs/secrets-handling.md) 参照）。

> **対応 OS**: macOS / Linux / Windows（PowerShell / CMD / Git Bash）。Windows では `cmd /c start` でブラウザを起動します。CI で windows-latest runner で全テスト通過を保証しています。

### `npx vibehawk setup` 1 コマンドで導入する（推奨、Issue #91）

対話型ウィザードが全 6 ステップ（App 作成 → リポジトリインストール → 3 secrets 登録 → workflow PR）を 1 コマンドに集約します:

```bash
npx vibehawk setup --owner <your-github-username> --repo <owner>/<repo>
```

各ステップで「指示表示 → ブラウザで操作 → Enter → CLI が `gh api` 検証 → OK で次 / NG なら原因表示してリトライ・スキップ・中止」の Enter ゲートで進行します。失敗時は原因を画面に明示します（Secret 名のミスマッチ / App 未インストール / リポジトリ admin 権限不足 等）。

App ID / OAuth Token は **OS ネイティブのクリップボードに stdin 経由でコピー**（Cmd+V / Ctrl+V で貼付可能）。OAuth Token の値はクリップボードコピー失敗時でも stdout に出しません（CISO Critical: `docs/SECURITY.md` §setup-token「トークン本体は表示しない」既存条件と整合）。

ウィザード途中で中止する場合は `Ctrl+C`（メモリ上の token / App ID 参照は即座に `null` 化されます）。`--dry-run` を付けると実行計画だけ表示します:

```bash
npx vibehawk setup --owner alice --repo alice/my-app --dry-run
```

### CLI 自体は Anthropic に通信しません（重要）

本 CLI は localhost のみで完結し、vibehawk 運営側サーバー・Anthropic API のいずれにも通信しません。**ただし配置される workflow（`.github/workflows/vibehawk-review.yml` / `vibehawk-chat.yml`）は実行時に PR diff・コメントを `claude-code-action` 経由で Anthropic API に送信します**。送信内容・利用契約は利用者の Anthropic 契約（Claude Pro / Max OAuth）に基づきます（詳細: [`docs/POLICY.md`](docs/POLICY.md) データ取扱い方針）。

### CLI が secret を書き込まない設計（Issue #72）

vibehawk CLI（`setup` / `install` / `setup-token` のいずれも）は `gh secret set` を呼び出さず、利用者リポジトリの GitHub Secrets を直接書き換えません。CLI は登録手順の画面誘導 + 任意のクリップボードコピー + 読み取り専用 `gh api` での検証までを担当し、実際の secret 登録は利用者が GitHub Settings UI で実施します。判断根拠（メジャーサービス比較 / GitHub 公式ガイドライン / CodeRabbit 事件の教訓 / MVV 整合）は [`docs/secrets-handling.md`](docs/secrets-handling.md) を参照。

### 個別実行（後方互換、`setup` を使わずステップごとに実行する場合）

`setup` ウィザードを使わず各ステップを個別実行する従来の手順も引き続き利用可能です。`install` / `setup-token` サブコマンドは後方互換のため残しています。

#### 1. App 作成 — `npx vibehawk install`

```bash
npx vibehawk install --owner <your-github-username>
```

ローカルに一時 HTTP サーバー（127.0.0.1:8765）を起動し、ブラウザで GitHub App Manifest Flow を開始します。利用者が GitHub UI で「Create」を押すと `vibehawk-for-<owner>` 名の App が作成されます。CLI は完了後 App ID と Settings URL を画面表示します（Private Key は画面に印字せず破棄、CISO Critical 条件）。

vibehawk 運営側のサーバーには一切通信しません（localhost のみで完結）。

#### 2. App ID を Secrets に登録（GitHub UI）

CLI が表示する URL（対象リポジトリの `Settings → Secrets and variables → Actions → New repository secret`）を開き、以下を登録します:

| Secret 名 | 値 |
|---|---|
| `VIBEHAWK_APP_ID` | CLI 画面に表示された App ID（数値） |

#### 3. Private Key を Secrets に登録（GitHub UI）

App Settings ページ（`https://github.com/settings/apps/vibehawk-for-<owner>`）で「Generate a private key」を押して `.pem` ファイルをダウンロードします。続けて対象リポジトリの Secrets 画面で以下を登録します:

| Secret 名 | 値 |
|---|---|
| `VIBEHAWK_PRIVATE_KEY` | ダウンロードした `.pem` ファイルの **内容全文**（`-----BEGIN ... -----END` を含む） |

#### 4. OAuth Token を Secrets に登録 — `npx vibehawk setup-token`

```bash
npx vibehawk setup-token --repo <owner>/<repo>
```

CLI が `claude setup-token`（Anthropic 公式 CLI）の実行案内を表示します。別ターミナルで `claude setup-token` を実行してトークンを取得し、vibehawk CLI のプロンプトに貼り付けます。CLI は明示同意の上で OS ネイティブのクリップボードに stdin 経由でコピーし、対象リポジトリの GitHub Settings URL と登録手順を画面表示します。利用者がブラウザを開き以下を登録します:

| Secret 名 | 値 |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` で取得した OAuth Token |

CLI は受け取ったトークンをローカルファイルに保存せず、メモリ上のみで保持し、本プロセス終了と同時に消去します。

#### 5. workflow を配置

リポジトリに `.github/workflows/vibehawk-review.yml` を配置します。本リポジトリの同名ファイルをコピーして利用してください。workflow は以下の **最小権限** のみ要求します（詳細は [`docs/SECURITY.md`](docs/SECURITY.md)）:

- `pull_requests: write`
- `issues: write`
- `contents: read`

#### 6. PR を出す

PR を作成すると `vibehawk-review.yml` が起動し、`vibehawk-for-<owner>[bot]` 名義でレビューサマリコメントを投稿します。

#### `--dry-run` モード

実行内容を事前確認したい場合は `--dry-run` を付けてください。実際には何もせず、起動する HTTP サーバーのポート・通信先・書き込み範囲を表示するだけです:

```bash
npx vibehawk install --owner alice --dry-run
```

## なぜ経路 2（利用者ごと独立 App）を必須化するのか

vibehawk は OSS 利用者の標準導入経路として **経路 2（利用者ごとに独立した `vibehawk-for-<owner>` App + 3 secrets 手動登録）** のみを認め、経路 1（`secrets.GITHUB_TOKEN` + `github-actions[bot]` 投稿）を OSS 利用者の標準経路として認めません（CEO 判断、Issue #61 / #72 / #74 で確定）。

### Why 経路 2 必須化

| 観点 | 理由 |
|------|------|
| Private Key 漏洩影響の構造的限定 | 利用者ごと独立 App 設計のため、Private Key 漏洩の影響範囲は **利用者本人のリポジトリ群に限定**。集中 SaaS App（CodeRabbit 等）が抱える「1 鍵漏洩で全利用者波及」の構造リスクを回避する |
| Value 1「利用者の契約だけで、完結させる」純度 | 利用者本人の契約・本人の App・本人の手動登録で完結する。CEO のサーバー / Private Key / API キーが介在しない |
| 命名統制 #25 との一貫性 | `vibehawk-for-<owner>[bot]` 名義投稿により利用者リポジトリ上で「vibehawk が動いている」ことが視認できる。命名統制 #25 はこの経路でのみ機能する |
| ブランド統制 | 全 bot 名に `vibehawk` を必ず含むため、利用者・第三者から「これは vibehawk のレビューだ」と認識できる |

### 命名統制の非対称性（率直な開示）

`vibehawk-for-<owner>` 命名統制は **運営側ブランド都合の比重が大きく、利用者メリットが相対的に薄い** 構造です。利用者にとって直接的なメリットは「自分のリポで動いている bot を視認できる」程度で、運営側の「ブランド一貫性 + 商標保護 + 経路統合」の比重に比べると非対称です。

vibehawk はこの非対称性を隠さず、`npx vibehawk install` 実行時に「⚠️ 命名統制」を明示告知します（利用者は導入前にこの統制を認識した上で進める）。詳細は [`docs/design-philosophy.md`](docs/design-philosophy.md) 「命名統制」セクション参照。

## 法務・プライバシーに関する注意事項

vibehawk は以下の透明性開示・責任分界点を前提に提供されます。詳細は [`docs/POLICY.md`](docs/POLICY.md) および [`docs/external-dependency-audit.md`](docs/external-dependency-audit.md) を参照してください。

### claude-code-action 経由の Anthropic 送信

利用者リポジトリの workflow は `anthropics/claude-code-action`（MIT、Anthropic 提供）を呼び出します。これにより PR diff・PR コメント・Issue コメント・コミット作者情報・PR コントリビューター情報を含む文脈が Anthropic の処理基盤に送信されます。送信内容の処理は Anthropic の利用規約に従います。

### GDPR / 個人情報保護法対応は利用者の責務

| 役割 | 主体 |
|------|------|
| データ管理者（GDPR Controller） | 利用者 |
| データ処理者（GDPR Processor） | Anthropic |
| ツール提供者（処理者ではない） | vibehawk 開発者 |

- GDPR 適用圏（EU / EEA / UK 等）の利用者は、PR コントリビューター PII の処理者として Anthropic を指定する旨を自リポジトリの Privacy Policy / DPA に明示する責務を負います
- 個人情報保護法（日本）適用の利用者は、自リポジトリの Privacy Policy で「PR 内容が claude-code-action 経由で Anthropic に送信される」旨を開示する責務を負います
- vibehawk 開発者は PII を受信・保管・処理せず、GDPR Art. 28 に定める処理者の定義を満たしません

### vibehawk 自身は PII を保存・収集しません

vibehawk は MVV Value 1「利用者の契約だけで、完結させる」に従い、追加課金ゼロかつ vibehawk 開発側のサーバー・データ保存を一切持たない設計です。CLI（`npx vibehawk install` / `npx vibehawk setup-token`）も利用者環境のみで完結し、vibehawk 開発側に PII を送信しません。

## メンテナー向け運用ガイド

利用者がリポジトリのメンテナー（OWNER）として vibehawk を運用する場合、自身の PR ごとに claude-code-action が起動し、Claude Pro/Max 枠を消費する構造になります。OSS 開発が活発になるとメンテナー個人の契約枠がボトルネックとなる懸念があるため、`if:` 条件によるメンテナー PR 除外などの推奨設定を [`docs/maintainer-quota-policy.md`](docs/maintainer-quota-policy.md) に整理しています。

vibehawk リポジトリ自身も同ポリシーに沿って自リポジトリ向け workflow を運用します（実装は別 Issue）。

## ステータス

本リポジトリは **開発中**（Phase 1 基盤構築 + OSS 配布対応）です。Issue #7 で実行基盤を、Issue #22 で OSS 配布可能化を、Issue #24 で `npx vibehawk install` 基盤を、Issue #8 以降で詳細レビュー機能（サマリコメント・inline コメント・severity 5 段階・@mention チャット応答）を順次積み上げます。

## 免責事項

vibehawk は MIT ライセンスのもと OSS として **無保証** で提供されます。`npx vibehawk install` / `npx vibehawk setup-token` などの CLI 配布物の利用は **すべてご利用者の自己責任** でお願いします。要点は以下の通りです。

- **スクリプト誤動作**: vibehawk CLI が API 仕様変更追従漏れ・OS 依存バグ・依存ライブラリの脆弱性等により利用者の GitHub 環境を意図せず変更した場合、vibehawk 開発者は一切責任を負いません
- **GitHub App 作成失敗**: GitHub Manifest API の仕様変更・利用者環境の制約により `npx vibehawk install` の App 作成が失敗した場合、vibehawk 開発者は復旧義務を負いません
- **クリップボード経由のトークン受け渡し**: `npx vibehawk setup-token` で利用者の **明示同意（`[Y/n]` プロンプト）後** に OS ネイティブのクリップボードへ OAuth Token をコピーする操作について、利用者環境のクリップボード履歴 / 同居マルウェア / その他プロセスによるトークン取得リスクは利用者の運用責任です（vibehawk 開発者は責任を負いません）
- **secrets の登録・漏洩・上書き**: 利用者が GitHub Settings UI で登録する 3 secrets（`VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`）の登録の正確性・漏洩・誤登録・上書きは利用者の運用責任です（CLI は secrets を書き込まない設計のため、vibehawk 開発者は touch していません）
- **GitHub / Anthropic 側の障害**: 依存先サービス（GitHub Manifest API / `anthropics/claude-code-action` / Claude Pro / Max OAuth 等）の仕様変更・障害・課金影響は vibehawk の責任範囲外です

導入前に `--dry-run` モードで実行内容を確認し、本番リポジトリへの適用前に検証用リポジトリで動作を確認することを推奨します。

詳細な免責範囲・利用者の責務・claude-code-action の挙動に関する取扱いは [`docs/POLICY.md`](docs/POLICY.md) の「免責条項（Issue #32）」セクションを参照してください。
