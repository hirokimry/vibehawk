# vibehawk セキュリティポリシー

> このドキュメントはプロジェクトのセキュリティ方針を定義する Source of Truth です。

## セキュリティ方針

vibehawk は MVV（特に Value 1・Value 4）を設計の起点とするセキュリティ方針を採用する。

### Value 4 に基づく公式経路限定原則

「公式の道を、迂回せず歩く」— 裏 API・スクレイピングを選ばず、公式に案内された経路だけで構築する。

この Value はセキュリティ方針と直接接続している:

- **認証は GitHub の公式 OAuth フローのみ使用する。** 非公式トークン取得・セッションハイジャック等の手段を選ばない
- **GitHub API は公式エンドポイント経由のみ使用する。** 非公式 GraphQL エンドポイント・レートリミット回避目的のスクレイピング等は禁止
- 公式 API の仕様外の挙動に依存したコードはセキュリティ上の問題と同等に扱い、差し戻しの対象とする

### Value 1 に基づく自前ストレージ非保有原則

「利用者の契約だけで、完結させる」— 専用 DB を持たず、状態は GitHub に置く（`docs/design-philosophy.md` 状態管理ポリシー参照）。

これはセキュリティ構造上の以下のリスクを根本的に排除する:

- **情報漏洩リスクの排除**: vibehawk 自身が機密データを蓄積・保管しないため、vibehawk サーバー側からの情報漏洩の攻撃面がない
- **認証情報管理リスクの排除**: 利用者の GitHub トークン等を vibehawk 側で保持しない。アクセス制御の責務は GitHub に完全委譲される
- **データ侵害スコープの限定**: 仮に vibehawk の実行環境が侵害されても、攻撃者が入手できるのは実行時の揮発情報のみ（永続ストレージがないため）

### 責務委譲によるアクセス制御

状態を GitHub に置く設計により、利用者のリポジトリ・組織に設定された GitHub のアクセス制御（Branch Protection / CODEOWNERS / Organization ポリシー等）がそのまま vibehawk の操作にも適用される。vibehawk が独自のアクセス制御レイヤーを持つ必要がない。

## 脆弱性報告

（脆弱性を発見した場合の報告フロー・連絡先を記載）

## 認証・認可

### 認証方式

vibehawk は GitHub の公式 OAuth アプリケーション認証のみを使用する（Value 4「公式の道を、迂回せず歩く」）。

- GitHub OAuth App または GitHub App（GitHub Actions OIDC）経由でのみ認証を行う
- 非公式な手段（クッキー流用・セッショントークン抽出等）によるアクセスは禁止
- `claude-code-action` が利用する `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` は GitHub Actions の Secrets 経由で注入する（リポジトリへの直書き・ログ出力禁止）

### 認可モデル

vibehawk 独自の認可レイヤーは持たない。GitHub のリポジトリ権限・Organization 権限に完全委譲する。

- vibehawk が実行できる操作は、実行時の GitHub トークンに紐づく権限スコープに限定される
- 権限の昇格・スコープ外アクセスを試みるコードはセキュリティ違反として即ブロック対象

### CI エージェントの権限管理

GitHub Actions 上で動作する claude-code-action には最小限の権限のみ付与する（`.claude/rules/autonomous-restrictions.md` 参照）。Fork PR からの secrets 漏洩を防ぐため以下を遵守する:

- Fork PR で `pull_request_target` トリガーを使用しない
- `administration: write` / `secrets: write` / `workflows: write` / `id-token: write` は付与しない（Issue #22 修正後、`id-token: write` も禁止権限に追加）

### 認証経路の設計（経路 2 必須化、Issue #61 で確定）

vibehawk は **利用者ごとに独立した GitHub App `vibehawk-for-<owner>` の Installation Token + Claude OAuth Token** の 2 系統 + 3 secrets 構成を採用する。配布方式（CLI 自動 vs 手動）の判断根拠は [`docs/secrets-handling.md`](secrets-handling.md) を参照。

```text
利用者リポジトリの GitHub Actions
   ├─ ① GitHub 認証（PR コメント投稿）
   │    └─ App Installation Token（vibehawk-for-<owner>）
   │       └─ VIBEHAWK_APP_ID + VIBEHAWK_PRIVATE_KEY（利用者本人の App）
   │       → 投稿者: vibehawk-for-<owner>[bot]
   │
   └─ ② Anthropic 認証（LLM 呼び出し）
        └─ CLAUDE_CODE_OAUTH_TOKEN（利用者の Claude Pro / Max 枠）
```

| 系統 | secret 名 | 役割 | 当事者 | 設定方法 |
|---|---|---|---|---|
| GitHub App ID | `VIBEHAWK_APP_ID` | App Installation Token 取得用 | 利用者本人の `vibehawk-for-<owner>` App | **利用者が GitHub Settings UI で手動登録** |
| GitHub Private Key | `VIBEHAWK_PRIVATE_KEY` | App Installation Token 取得用 | 利用者本人の `vibehawk-for-<owner>` App | **利用者が GitHub Settings UI で手動登録** |
| LLM 認証 | `CLAUDE_CODE_OAUTH_TOKEN` | claude-code-action 経由の LLM 呼び出し | 利用者の Claude Pro / Max 契約 | **利用者が GitHub Settings UI で手動登録** |

**設計判断**: 利用者ごとに独立 App を採用することで、Private Key 漏洩時の影響範囲が **利用者本人のリポジトリ群に限定** される（CodeRabbit 型の集中 SaaS App では 1 鍵漏洩で全利用者へ波及するが、vibehawk はその構造を回避）。CLI による secret 自動書込はせず利用者が GitHub Settings UI で 3 secrets を手動登録することで、CLI プロセスが secret を touch しない攻撃面ゼロの設計を実現する（Issue #72 決定）。

#### 利用者準備手順（3 secrets 手動登録）

| 手順 | 操作 | 結果 |
|---|---|---|
| 1 | `npx vibehawk install --owner <name>` | `vibehawk-for-<owner>` App 作成。CLI が App ID と Settings URL を画面表示（Private Key は印字せず破棄） |
| 2 | GitHub Settings UI で `VIBEHAWK_APP_ID` を手動登録 | CLI 表示の URL から登録 |
| 3 | GitHub App Settings ページで `.pem` ダウンロード → Settings UI で `VIBEHAWK_PRIVATE_KEY` を手動登録 | 利用者が GitHub UI 内で完結 |
| 4 | `npx vibehawk setup-token --repo <owner>/<repo>` → GitHub Settings UI で `CLAUDE_CODE_OAUTH_TOKEN` を手動登録 | CLI が登録手順を画面誘導、明示同意の上でクリップボードコピー（stdin 経由） |
| 5 | `.github/workflows/vibehawk-review.yml` を配置 | App Installation Token 認証で動作 |
| 6 | PR 作成 | `vibehawk-for-<owner>[bot]` 名義でレビューサマリ投稿 |

#### Issue #22 認識見直しの経緯記録

Issue #22（2026-05-08）では「CEO の GitHub App Private Key を利用者に配布する設計」が OSS 配布不可能と判定され、`secrets.GITHUB_TOKEN` 1 系統経路（経路 1）に妥協した。

しかし 2026-05-09 の C*O 統合議論で、当時の判定が「**集中 1 個の App Private Key を全利用者に配布**」と「**利用者ごとに独立した App を利用者本人が作成・運用**」を区別していなかったことが判明した。後者では Private Key 漏洩の影響範囲が利用者本人に限定されるため、Value 1「利用者の契約だけで、完結させる」と整合する。

CEO 判断（2026-05-09）により、経路 2（利用者ごと独立 App + 3 secrets 手動登録）が必須化された。Issue #22 の経路 1 妥協は撤回され、経路 1（`secrets.GITHUB_TOKEN` + `github-actions[bot]` 投稿）は OSS 利用者の標準経路として認めない方針に確定した。

#### Fork PR の扱い

- Fork PR からの起動時、`pull_request_target` は使用しない（`.claude/rules/autonomous-restrictions.md` §6 不可領域）
- App Installation Token は base リポジトリのコンテキストで発行されるため Fork PR でも投稿は技術的に可能だが、Fork PR からの secrets 漏洩リスク回避を優先し、本シナリオを **対象外** として扱う
- 同一リポジトリ内の通常 PR では正常に動作する

#### Installation Token 権限スコープ（CISO 再承認 #62 / #81 で文書化）

`vibehawk-for-<owner>` App の Installation Token は、`actions/create-github-app-token@v2` 経由で `cli/manifest.js` が App 作成時に要求した最小権限のみで発行される。

| 権限 | スコープ | 用途 |
|---|---|---|
| `pull-requests` | `write` | PR コメント投稿、PR メタデータ読取 |
| `issues` | `write` | issue_comment 投稿（`@mention` 応答 #11 等） |
| `contents` | `read` | PR diff 取得、レビュー対象コードの読取 |

**vibehawk が要求しない権限**（`.claude/rules/autonomous-restrictions.md` §6 連動の禁止権限と一致）:

- `administration: write` — リポジトリ設定変更権限を持たない（自律実行不可領域）
- `secrets: write` — GitHub Secrets 書込権限を持たない（CLI が touch しない方針 Issue #72 / #74 と整合）
- `workflows: write` — workflow ファイル書換権限を持たない（PR 経由配置のみ Issue #58）
- `id-token: write` — OIDC token 発行権限を持たない（`actions/create-github-app-token@v2` は OIDC 不要で動作）

**設計意図**: PR レビュー投稿に必要な最小権限のみを App に持たせることで、Private Key 漏洩時の被害範囲を「PR コメント投稿 + Issue コメント投稿 + 読取」に限定する（リポジトリ設定変更・secrets 流出・workflow 改ざんは構造的に不可能）。Installation Token の寿命は GitHub 仕様により最大 1 時間。

#### Private Key rotation 手順（CISO 再承認 #62 / #81 で文書化）

`VIBEHAWK_PRIVATE_KEY` の漏洩を疑った場合、または定期的なキーローテーション運用で Private Key を更新する手順:

##### 1. 旧 Private Key の無効化（GitHub UI）

1. ブラウザで `https://github.com/settings/apps/vibehawk-for-<owner>` を開く
2. ページ下部「Private keys」セクションで該当キーの **Delete private key** をクリック
3. GitHub が即座に該当キーを無効化（以降このキーで Installation Token は発行できなくなる）

##### 2. 新 Private Key の生成（GitHub UI）

1. 同じページで **Generate a private key** をクリック
2. 新しい `.pem` ファイルが自動ダウンロードされる
3. ダウンロードした `.pem` ファイルの **内容全文**（`-----BEGIN ... -----END` を含む）をコピー

##### 3. リポジトリ Secrets の更新（GitHub UI）

1. 対象リポジトリの `Settings → Secrets and variables → Actions` を開く
2. 既存の `VIBEHAWK_PRIVATE_KEY` の `Update secret` をクリック
3. 新 `.pem` ファイル全文を貼付して保存

##### 4. workflow 動作影響と過渡期の挙動

- 旧 Private Key で発行された Installation Token は最大 1 時間有効（GitHub 仕様）
- rotation 完了から 1 時間以内に発行された旧 token は引き続き動作する（PR コメント投稿等）
- 新 Secret 更新後の workflow 起動からは新 Private Key で Installation Token が発行される
- 漏洩疑いの場合は、rotation 完了から 1 時間後に旧 token も自動失効するため、「即時無害化」が達成される

##### 5. 漏洩検証（推奨）

- GitHub App Settings の `Recent deliveries` で異常な API 呼出が記録されていないか確認
- 対象リポジトリの `Settings → Audit log` で想定外の操作が記録されていないか確認
- 必要に応じて `gh api repos/<owner>/<repo>/issues/comments` で `vibehawk-for-<owner>[bot]` 名義の予期しないコメント投稿がないか確認

##### 漏洩時の影響範囲（参考）

vibehawk は **利用者ごとに独立 App** 設計のため、Private Key 漏洩の影響は **利用者本人のリポジトリ群に限定** される（CodeRabbit 型の集中 SaaS App では 1 鍵漏洩で全利用者へ波及するが、vibehawk はその構造を回避、[`docs/secrets-handling.md`](secrets-handling.md) § 5 参照）。攻撃者ができるのは上記「Installation Token 権限スコープ」の範囲内のみ。

### Claude OAuth Token の取得・登録（Issue #26 → Issue #74 で全手動化）

`npx vibehawk setup-token` は利用者の `CLAUDE_CODE_OAUTH_TOKEN` の取得を補助し、**GitHub Settings UI への登録手順を画面誘導する**。CLI は GitHub Secrets に直接書き込まない（Issue #72 決定、Issue #74 で実装撤去）。配布方式の判断根拠は [`docs/secrets-handling.md`](secrets-handling.md) 参照。

#### 設計判断

- vibehawk は Anthropic OAuth client_id を保有しない（Value 4「公式の道を、迂回せず歩く」）
- 公式 `claude setup-token` フロー（Anthropic 公式の Claude Code CLI が提供）に委譲
- 利用者は別ターミナルで `claude setup-token` を実行してトークンを取得し、vibehawk CLI のプロンプトに貼り付ける
- vibehawk CLI は受け取ったトークンを **GitHub Secrets に書き込まない**（Issue #74、`gh secret set` 撤去）
- 代わりに利用者の明示同意を得て OS ネイティブのクリップボードに **stdin 経由** で渡し（プロセス引数・環境変数には出さない）、対象リポジトリの GitHub Settings URL と登録手順を画面表示する
- 利用者がブラウザでその URL を開いて手動登録する

#### 読み書き範囲（Issue #74 更新版）

| リソース | 操作 | 経路 |
|---|---|---|
| 利用者の OAuth Token | 受領（メモリ上のみ） | CLI プロンプト経由（標準入力） |
| GitHub Secrets | **書き込み禁止**（Issue #74 で `gh secret set` 撤去） | （該当なし） |
| OS クリップボード | **明示同意後**にトークンを書き込み | macOS: `pbcopy` / Linux: `xclip` / `xsel` / `wl-copy` / Windows: `clip`（いずれも `spawnSync` の `input` オプション経由 = stdin） |
| 標準出力 | GitHub Settings URL と登録手順を表示（**トークン本体は表示しない**） | console.log |
| ローカルファイル | **書き込み禁止** | （該当なし） |
| vibehawk 運営側サーバー | **通信禁止** | （該当なし） |

#### クリップボード経由の取り扱い（Issue #74）

- クリップボードコピーは **利用者の明示同意（[Y/n] プロンプト）を取得してから実行**
- 同意拒否時は GitHub Settings URL の表示のみ行い、利用者が `claude setup-token` を再実行してトークンを再取得する経路を案内
- クリップボードコマンドへのトークン受け渡しは **stdin 経由のみ**（プロセス引数 / 環境変数には出さない、CISO Critical 条件）
- クリップボードツール検出失敗時はエラーメッセージを表示し、手動貼付を案内する

#### キャンセル時の挙動

- OAuth フローを途中で中断した場合（Ctrl+C 等）、トークンはクリップボードにも書き込まない
- ローカル状態は変更されない（部分セットアップ状態を残さない）

## データ保護

### 機密情報の取り扱い

- シークレット・APIキー・パスワードをリポジトリにコミットしない
- 環境変数またはシークレットマネージャーで管理する

### 個人情報

vibehawk は専用 DB を持たない設計（`docs/design-philosophy.md` 状態管理ポリシー）により、個人情報を自前のストレージに蓄積しない。振る舞いとして観察した PR メタデータ・コメント等は GitHub リポジトリ上に存在するものであり、vibehawk がそれらを外部に転送・保存することはない。

例外なく以下を遵守する:

- 利用者の GitHub アクセストークン・メールアドレス・個人識別情報を vibehawk の実行ログ外に書き出さない
- API レスポンスに含まれる個人情報をキャッシュ・永続化しない（キャッシュ層非保有の原則）

## 依存関係管理

（依存パッケージの更新方針・脆弱性スキャンの運用を記載）

## npm 配布のセキュリティ（Issue #30）

vibehawk CLI は npm registry 経由で配布される。npm 侵害は世界中の利用者に偽物 vibehawk が配布される最大のサプライチェーン攻撃面のため、以下の **CISO Critical 条件** を遵守する。

### CISO Critical 条件 3 点

| 要件 | 実装 |
|---|---|
| npm publish アカウントの 2FA 必須 | npmjs.com Settings 側で設定（CEO 手動）、authenticator app + recovery code |
| GitHub Actions OIDC 経由の publish のみ許可 | `.github/workflows/release.yml`、`permissions: id-token: write` で短寿命 token を発行 |
| npm provenance 署名 | `npm publish --provenance --access public` で改ざん検知。`package.json` の `publishConfig.provenance: true` で常時有効 |

### 手動 publish 禁止

- 開発者個人の npm token を使った `npm publish` は **運用上禁止** する
- リリースは GitHub Releases 作成 → `.github/workflows/release.yml` 自動起動の経路のみ
- 詳細は `CONTRIBUTING.md` の「リリースプロセス」を参照

### install スクリプトの読み書き範囲（Issue #34）

`npx vibehawk install` および `npx vibehawk setup-token` の読み書き範囲は CISO レビューで承認された以下の範囲に限定される。範囲外の操作は実装してはならない。

#### `npx vibehawk install` の読み書き範囲

| リソース | 操作 | 経路 |
|---|---|---|
| `localhost:8765` ポート | listen / accept | Node.js http モジュール、127.0.0.1 限定 |
| ブラウザ | 自動オープン | macOS: `open` / Linux: `xdg-open` / Windows: `cmd /c start` |
| GitHub API (`api.github.com/app-manifests/<code>/conversions`) | POST 呼出 | fetch（公式エンドポイント） |
| 標準出力 | App 名 / App ID / Slug / HTML URL を表示 | console.log |
| **Private Key** | **画面非表示・メモリ参照を `[REDACTED]` で上書き** | （CISO Critical 条件） |
| ローカルファイルシステム | **書き込み禁止** | （該当なし） |
| vibehawk 運営側サーバー | **通信禁止** | （該当なし） |

#### `npx vibehawk setup-token` の読み書き範囲

| リソース | 操作 | 経路 |
|---|---|---|
| 標準入力 | 利用者からトークン受領 | readline |
| GitHub Secrets | **書き込み禁止**（Issue #74 で `gh secret set` 撤去、Issue #72 全手動方針） | （該当なし、テストで機械検証） |
| OS クリップボード | **明示同意後**にトークンを書き込み | macOS: `pbcopy` / Linux: `xclip` / `xsel` / `wl-copy` / Windows: `clip`（いずれも `spawnSync` の `input` オプション = stdin 経由） |
| 標準出力 | GitHub Settings URL と登録手順を表示（**トークン本体は表示しない**） | console.log |
| ローカルファイル | **書き込み禁止** | （該当なし、テストで機械検証） |
| vibehawk 運営側サーバー | **通信禁止** | （該当なし、テストで機械検証） |

### npm 侵害時のインシデント対応（Issue #34）

万が一 vibehawk の npm パッケージが改ざんされた場合のインシデント対応手順:

#### 検知

- **検知ソース**: GitHub Security Advisory / npm Snyk / Socket.dev / 利用者からの報告
- **検知後の初動**: 1 時間以内に CEO + CISO へエスカレーション

#### 即時対応（検知から 24 時間以内）

1. **該当 version の unpublish 申請**: npm Support に通報し、改ざん version を npm registry から削除依頼
2. **GitHub Releases の警告追記**: 該当 tag に「⚠️ Compromised version, do not install」警告を表示
3. **GitHub Security Advisory 発行**: GHSA を発行して GitHub の依存関係グラフ経由で利用者に通知
4. **README に注意書き**: 該当 version 範囲を README に明記して新規利用者を保護

#### 中期対応（24-72 時間）

5. **改ざん経路の特定**: GitHub Actions OIDC token / npm publish アカウント 2FA / リポジトリ侵害のいずれかを CISO 主導で調査
6. **OIDC token rotation**: 必要に応じて GitHub Actions の権限・シークレットを再発行
7. **依存パッケージ全面監査**: vibehawk が依存する全パッケージのライセンス・脆弱性を再監査

#### 再発防止

8. **CISO レビュー後の対策実装**: 改ざん経路を塞ぐ追加対策（追加 2FA / SBOM 公開 / npm audit 自動化等）
9. **インシデントポストモーテムの公開**: 透明性確保のため経緯と対策を README / docs/SECURITY.md に追記

#### 利用者へのアナウンス窓口

- **GitHub Security Advisory**: 第一窓口（GitHub の依存関係グラフ経由で自動通知）
- **GitHub Releases の警告**: 既にインストール済みの利用者向け
- **README**: 新規利用者向け
- **CEO による twitter 等の SNS 周知**: 拡散用

## インシデント対応

（セキュリティインシデント発生時の対応手順を記載）
