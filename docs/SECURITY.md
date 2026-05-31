# vibehawk セキュリティポリシー

> [!IMPORTANT]
> 本ドキュメントはプロジェクトのセキュリティ方針を定義する Source of Truth。
> 守る対象: 利用者リポジトリの認証情報・GitHub Secrets・PR メタデータ。
> 想定攻撃経路: npm サプライチェーン攻撃 / CSRF / Port hijacking / Fork PR secrets 漏洩。
> 残存リスク: CLI 実行環境の侵害時の揮発情報（永続ストレージは非保有）。

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

状態を GitHub に置く設計により、利用者のリポジトリ・組織に設定された GitHub のアクセス制御がそのまま vibehawk の操作にも適用される。

- 適用される制御: Branch Protection / CODEOWNERS / Organization ポリシー等
- vibehawk が独自のアクセス制御レイヤーを持つ必要はない

## 脆弱性報告

（脆弱性を発見した場合の報告フロー・連絡先を記載）

## 認証・認可

### 認証方式

vibehawk は GitHub の公式 OAuth アプリケーション認証のみを使用する（Value 4「公式の道を、迂回せず歩く」）。

- GitHub OAuth App または GitHub App（GitHub Actions OIDC）経由でのみ認証を行う
- 非公式な手段（クッキー流用・セッショントークン抽出等）によるアクセスは禁止
- `claude-code-action` が利用する `CLAUDE_CODE_OAUTH_TOKEN`（Claude Pro / Max OAuth）は GitHub Actions の Secrets 経由で注入する。
  - リポジトリへの直書き・ログ出力は禁止
  - vibehawk は OAuth 経路のみをサポート対象とし、`ANTHROPIC_API_KEY` 経路（従量課金）はサポートしない
  - 📍 根拠: README.md「追加課金ゼロの適用範囲」と整合

### 認可モデル

vibehawk 独自の認可レイヤーは持たない。GitHub のリポジトリ権限・Organization 権限に完全委譲する。

- vibehawk が実行できる操作は、実行時の GitHub トークンに紐づく権限スコープに限定される
- 権限の昇格・スコープ外アクセスを試みるコードはセキュリティ違反として即ブロック対象

### CI エージェントの権限管理

GitHub Actions 上で動作する claude-code-action には最小限の権限のみ付与する。
Fork PR からの secrets 漏洩を防ぐため以下を遵守する。
📍 根拠: `.claude/rules/autonomous-restrictions.md`

- Fork PR で `pull_request_target` トリガーを使用しない
- `administration: write` / `secrets: write` / `workflows: write` / `id-token: write` は付与しない（Issue #22 修正後、`id-token: write` も禁止権限に追加）

### 認証経路の設計（経路 2 必須化、Issue #61 で確定）

vibehawk は **利用者ごとに独立した GitHub App `vibehawk-for-<owner>`** の認証を採用する。

- 構成: Installation Token + Claude OAuth Token の 2 系統 + 3 secrets
- 配布方式の判断根拠: [`docs/secrets-handling.md`](secrets-handling.md) を参照

```text
利用者リポジトリの GitHub Actions
   ├─ ① GitHub 認証（PR コメント / review 投稿）
   │    └─ App Installation Token（vibehawk-for-<owner>）
   │       └─ VIBEHAWK_APP_ID + VIBEHAWK_PRIVATE_KEY（利用者本人の App）
   │       → 投稿者: vibehawk-for-<owner>[bot]
   │
   ├─ ① ' status check 投稿経路（merge gate 主軸、Issue #121-C1）
   │    └─ workflow デフォルトの GITHUB_TOKEN（workflow.permissions に checks: write 付与）
   │       → 投稿者: github-actions[bot]、check name は `vibehawk` 固定
   │       （App permission の後付け追加が利用者の再 install を要求するのを避けるため、
   │         App Installation Token ではなくデフォルト GITHUB_TOKEN 経路を採用）
   │
   └─ ② Anthropic 認証（LLM 呼び出し）
        └─ CLAUDE_CODE_OAUTH_TOKEN（利用者の Claude Pro / Max 枠）
```

経路 ① と ① ' は投稿者表示が異なる。
branch protection は status check の `name`（`vibehawk` 固定）で識別するため、利用者の merge gate 設定上の識別性は維持される。
📍 詳細設計根拠: `docs/specification.md` §「check run の投稿者と認証経路（Issue #121-C1 fix）」

| 系統 | secret 名 | 役割 | 当事者 | 設定方法 |
|---|---|---|---|---|
| GitHub App ID | `VIBEHAWK_APP_ID` | App Installation Token 取得用 | 利用者本人の `vibehawk-for-<owner>` App | **利用者が GitHub Settings UI で手動登録** |
| GitHub Private Key | `VIBEHAWK_PRIVATE_KEY` | App Installation Token 取得用 | 利用者本人の `vibehawk-for-<owner>` App | **利用者が GitHub Settings UI で手動登録** |
| LLM 認証 | `CLAUDE_CODE_OAUTH_TOKEN` | claude-code-action 経由の LLM 呼び出し | 利用者の Claude Pro / Max 契約 | **利用者が GitHub Settings UI で手動登録** |

**設計判断**:

- 利用者ごとに独立 App を採用することで、Private Key 漏洩時の影響範囲が **利用者本人のリポジトリ群に限定** される。
- CodeRabbit 型の集中 SaaS App では 1 鍵漏洩で全利用者へ波及するが、vibehawk はその構造を回避。
- CLI による secret 自動書込はせず、利用者が GitHub Settings UI で 3 secrets を手動登録する。
- CLI プロセスが secret を touch しない攻撃面ゼロの設計を実現する。
- 📍 根拠: Issue #72 決定

#### 推奨経路（`npx vibehawk setup` ウィザード、Issue #91）

Issue #91 で実装された対話型ウィザードを使うと、以下 6 ステップを 1 コマンドで集約できる。
既存の CISO Critical 条件（CLI が secret を書き込まない方針 Issue #72 / #74）は完全に遵守される。

```text
npx vibehawk setup --owner <name> --repo <owner>/<repo>
```

| ステップ | 内容 | 操作主体 |
|---|---|---|
| 1/6 | GitHub App を作成（`vibehawk-for-<owner>`） | CLI が自動実行 |
| 2/6 | App を対象リポジトリにインストール | 利用者がブラウザで操作 |
| 3/6 | `VIBEHAWK_APP_ID` を Secrets に登録 | 利用者が GitHub Settings で操作 |
| 4/6 | `VIBEHAWK_PRIVATE_KEY` を生成・登録 | 利用者が GitHub Settings で操作 |
| 5/6 | `CLAUDE_CODE_OAUTH_TOKEN` を取得・登録 | 利用者が GitHub Settings で操作 |
| 6/6 | workflow ファイル PR を作成 | CLI が自動実行 |

ウィザードのセキュリティ特性（CISO Critical 条件遵守）の詳細は後述「`npx vibehawk setup` ウィザード経路の追加 Critical 条件（Issue #91）」を参照。

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

Issue #22（2026-05-08）では「CEO の GitHub App Private Key を利用者に配布する設計」が OSS 配布不可能と判定された。
その結果、`secrets.GITHUB_TOKEN` 1 系統経路（経路 1）に妥協した。

2026-05-09 の C*O 統合議論で、当時の判定が以下 2 つを区別していなかったことが判明した。

- 「集中 1 個の App Private Key を全利用者に配布」する設計
- 「利用者ごとに独立した App を利用者本人が作成・運用」する設計

後者では Private Key 漏洩の影響範囲が利用者本人に限定されるため、Value 1「利用者の契約だけで、完結させる」と整合する。

CEO 判断（2026-05-09）により、経路 2（利用者ごと独立 App + 3 secrets 手動登録）が必須化された。
Issue #22 の経路 1 妥協は撤回され、経路 1（`secrets.GITHUB_TOKEN` + `github-actions[bot]` 投稿）は OSS 利用者の標準経路として認めない方針に確定した。

#### Manifest Flow のセキュリティ対策（Issue #59）

`npx vibehawk install` の GitHub App Manifest Flow は、利用者のローカルマシンで localhost HTTP サーバを起動して GitHub からの callback を待ち受ける構造を持つ。
CSRF / port hijacking 攻撃面を最小化するための多層防御を実装している。

| 対策 | 実装箇所 | 目的 |
|---|---|---|
| loopback bind (`127.0.0.1`) | `cli/install.js` `server.listen(port, '127.0.0.1', ...)` | 外部ネットワークから vibehawk localhost サーバに到達不能にする（port hijacking 防止） |
| cryptographically secure な `state` パラメータ | `cli/install.js` `crypto.randomBytes(32).toString('hex')` で生成し manifest フォーム POST の hidden input に埋め込み | 同一ホスト上の別プロセスが偽の `/callback` リクエストを送って認可コードを横取りする CSRF 攻撃を防止 |
| `crypto.timingSafeEqual` による state 照合 | `cli/install.js` `/callback` ハンドラ | timing attack による state 推測を防止 |
| state 不一致時のサーバ即時停止 + reject | `cli/install.js` `/callback` ハンドラ | CSRF 試行検知時の保守的挙動。利用者は `npx vibehawk install` を再実行する（新たな state が生成される） |

設計意図:

- loopback bind 単独でも同一ホスト外からの攻撃は防げる。
- 同一ホスト上の別プロセス（マルウェア等）からの偽 callback を防ぐため state パラメータを追加で実装。
- GitHub App Manifest Flow の `state` フィールドは GitHub 公式仕様で利用者の callback URL にクエリパラメータとして戻る。
- 📍 根拠: [GitHub Docs](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)

#### Fork PR の扱い

- Fork PR からの起動時、`pull_request_target` は使用しない（`.claude/rules/autonomous-restrictions.md` §6 不可領域）
- `pull_request`・`pull_request_review`・`pull_request_review_thread` の各トリガーは **Fork PR では secrets が注入されない**。`pull_request` と同等の secrets 分離モデルが `pull_request_review_thread` にも適用される
- App Installation Token は base リポジトリのコンテキストで発行されるため Fork PR でも投稿は技術的に可能だが、Fork PR からの secrets 漏洩リスク回避を優先し、本シナリオを **対象外** として扱う
- 同一リポジトリ内の通常 PR では正常に動作する

#### Installation Token 権限スコープ（CISO 再承認 #62 / #81 で文書化）

`vibehawk-for-<owner>` App の Installation Token は、`actions/create-github-app-token@v2` 経由で `cli/manifest.js` が App 作成時に要求した最小権限のみで発行される。

| 権限 | スコープ | 用途 |
|---|---|---|
| `pull-requests` | `write` | PR コメント投稿、PR メタデータ読取 |
| `issues` | `write` | issue_comment 投稿（`@mention` 応答 #11 等） |
| `contents` | `read` | PR diff 取得、レビュー対象コードの読取 |

**`vibehawk-for-<owner>` App が要求しない権限**（GitHub App permissions、`.claude/rules/autonomous-restrictions.md` §6 連動の禁止権限と一致）:

- `administration: write` — リポジトリ設定変更権限を持たない（自律実行不可領域）
- `secrets: write` — GitHub Secrets 書込権限を持たない（CLI が touch しない方針 Issue #72 / #74 と整合）
- `workflows: write` — workflow ファイル書換権限を持たない（PR 経由配置のみ Issue #58）

**`vibehawk-review.yml` workflow が要求する権限**（GitHub Actions workflow/job permissions、上記 App permissions とは別の制約軸）:

- トリガー: `pull_request` / `pull_request_review` / `pull_request_review_thread: [resolved, unresolved]`
- `pull-requests: write` — review event / inline comment 投稿（App Installation Token 経路と重複付与、`pull_request` イベントで `secrets.GITHUB_TOKEN` 経路の動作担保）
- `issues: write` — issue_comment 投稿
- `contents: read` — チェックアウト・差分取得
- `checks: write` — **status check post（Issue #121-C1、merge gate 主軸）**。
  - `check-runs` API で `vibehawk` という固定 name の check を発火するためにデフォルト `GITHUB_TOKEN` に付与する。
  - App Installation Token の `checks: write` 経路（PR #125 初版が依存していた）は採用しない。
  - App permission を後付け追加すると既存利用者が App を再 install しないと反映されないため、利用者影響を回避する設計判断。

**`vibehawk-reverdict` ジョブ（Issue #287 追加）**:

- トリガー: `pull_request_review_thread: [resolved, unresolved]`
- 役割: スレッドの手動 resolve / unresolve を検知し、LLM を呼び出さずに verdict（check run）を再評価する。
  - resolve 状態に応じて `vibehawk` check run の pass / fail を自動更新する。
  - CodeRabbit の `request_changes_workflow` 相当の動作を提供する。
- **LLM 非呼び出し**: `claude-code-action` を起動しない。プロンプトインジェクション攻撃面はゼロ。
- **既存 secrets 再利用**: `VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` の 3 secrets を再利用する。新規 secret を追加しない。
- **check-secrets ガード**: 未注入時は `ready!=true` により後続ステップが自動 skip される（既存機構と同一）。
- **追加 permissions なし**: `vibehawk-review.yml` の既存 workflow/job permissions の変更・追加は一切行わない。

**`vibehawk-review.yml` workflow が要求しない権限**:

- `id-token: write` — Actions OIDC token 発行権限を付与しない。
  - `actions/create-github-app-token@v2` は App Private Key からローカル JWT 生成 → API exchange で動作するため OIDC 不要

**設計意図**:

- PR レビュー投稿に必要な最小権限のみを App に持たせる。
- Private Key 漏洩時の被害範囲を「PR コメント投稿 + Issue コメント投稿 + 読取」に限定する。
- リポジトリ設定変更・secrets 流出・workflow 改ざんは構造的に不可能。
- Installation Token の寿命は GitHub 仕様により最大 1 時間。

#### App permissions 更新時の利用者通知運用フロー（Issue #61 で追加）

vibehawk は中央 SaaS App ではなく **利用者ごと独立 App** 設計のため、`vibehawk-for-<owner>` App の permissions を変更する必要が生じた場合、運営側 1 箇所の変更では伝播しない。

- 伝播に必要な手順: `cli/manifest.js` の更新 → `npx vibehawk install` 再実行 → 利用者個別の App 再作成または manual 設定変更
- CodeRabbit 型の集中 SaaS App では運営側で permissions を更新すれば全利用者に即時伝播するが、vibehawk はその構造を持たない。

| ステップ | 操作主体 | 内容 |
|---|---|---|
| 1 | vibehawk 開発者 | CHANGELOG / GitHub Releases に「App permissions 変更あり」を明示（変更前→変更後の権限を併記、影響範囲を CISO レビューで確認した上で記載） |
| 2 | vibehawk 開発者 | 変更後の `cli/manifest.js` で新しい permissions の App を作成できるよう更新する（manifest.js の `default_permissions` を変更） |
| 3 | 利用者 | 既存利用者は GitHub の標準フローで App Settings → Permissions & events で新権限を手動承認する（または `vibehawk-for-<owner>` App を一旦削除 → `npx vibehawk install` 再実行で新 manifest から再作成する） |
| 4 | 利用者 | permissions 拡大（追加）の場合、承認前は workflow が「権限不足」エラーで動作しない可能性があるため、CHANGELOG に明示し利用者の早期認知を促す |

- 縮小（剥奪）の場合: 利用者影響なし（利用者が手動承認しなくても workflow は動作する）。
- 拡大（追加）の場合: テンポラリで動作不能になる可能性がある。CHANGELOG での明示告知とリリースノートでのアナウンスを必須とする。

CISO レビュー観点（permissions 変更時の必須チェック）:

- 追加する permissions が `.claude/rules/autonomous-restrictions.md` §6 の禁止権限（`administration: write` / `secrets: write` / `workflows: write` / `id-token: write`）に該当しないこと
- 縮小する permissions が既存機能を破壊しないこと（特に `pull-requests: write` / `issues: write` / `contents: read` の core 3 権限）

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
- 漏洩疑いの場合は、rotation 完了後 **最大 1 時間で旧 token も自動失効** し、無害化が完了する。
  - GitHub Installation Token 寿命に依存するため、即時ではない点に注意

##### 5. 漏洩検証（推奨）

- GitHub App Settings の `Recent deliveries` で異常な API 呼出が記録されていないか確認
- 対象リポジトリの `Settings → Audit log` で想定外の操作が記録されていないか確認
- 必要に応じて `gh api repos/<owner>/<repo>/issues/comments` で `vibehawk-for-<owner>[bot]` 名義の予期しないコメント投稿がないか確認

##### 漏洩時の影響範囲（参考）

vibehawk は **利用者ごとに独立 App** 設計のため、Private Key 漏洩の影響は **利用者本人のリポジトリ群に限定** される。

- CodeRabbit 型の集中 SaaS App では 1 鍵漏洩で全利用者へ波及するが、vibehawk はその構造を回避。
- 攻撃者ができるのは上記「Installation Token 権限スコープ」の範囲内のみ。
- 📍 参照: [`docs/secrets-handling.md`](secrets-handling.md) § 5

### Claude OAuth Token の取得・登録（Issue #26 → Issue #74 で全手動化）

`npx vibehawk setup-token` は利用者の `CLAUDE_CODE_OAUTH_TOKEN` の取得を補助し、**GitHub Settings UI への登録手順を画面誘導する**。
CLI は GitHub Secrets に直接書き込まない。
📍 根拠: Issue #72 決定、Issue #74 で実装撤去 / [`docs/secrets-handling.md`](secrets-handling.md) 参照

#### 設計判断

- vibehawk は Anthropic OAuth client_id を保有しない（Value 4「公式の道を、迂回せず歩く」）
- 公式 `claude setup-token` フロー（Anthropic 公式の Claude Code CLI が提供）に委譲
- 利用者は別ターミナルで `claude setup-token` を実行してトークンを取得し、vibehawk CLI のプロンプトに貼り付ける
- vibehawk CLI は受け取ったトークンを **GitHub Secrets に書き込まない**（Issue #74、`gh secret set` 撤去）
- 利用者の明示同意を得て OS ネイティブのクリップボードに **stdin 経由** で渡す。
  - プロセス引数・環境変数には出さない
  - 対象リポジトリの GitHub Settings URL と登録手順を画面表示する
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

#### `npx vibehawk setup` ウィザード経路の追加 Critical 条件（Issue #91）

Issue #91 で実装された `cli/setup.js` は、`npx vibehawk setup-token` の設計方針（Issue #74）を踏襲しつつ、6 ステップを 1 コマンドに集約する。
以下の CISO Critical 条件を遵守する。

| 条件 | 実装 |
|---|---|
| `gh secret set` 不在 | `cli/setup.js` / `cli/verify.js` に書込系 `gh secret set` を含まない（grep 機械検証） |
| 書込系 `gh api` 不在 | `cli/verify.js` は読み取り専用 API のみ呼ぶ（`--method PUT/POST/DELETE` を含まない、grep 機械検証） |
| OAuth Token stdout 漏洩防止 | `STEPS` の `isSensitive: true` フラグで分岐し、クリップボードフォールバック時でも OAuth Token を標準出力に出力しない（`cli/setup.js` `showClipboardFallback`） |
| 中断時のメモリ null 化 | SIGINT/SIGTERM ハンドラで `clearState()` を呼び `oauthToken` / `appIdString` / `credentials` をすべて null 化 |
| `redactCredentials()` 強制実行 | `cli/install.js` の `run()` return 直前に `redactCredentials()` を必ず呼び、pem / client_secret / webhook_secret を `[REDACTED]` で上書き |
| 事前認証検証 | ウィザード開始前に `gh auth status` を実行し、未認証なら早期終了（全ステップが 401 で失敗する前に止める） |
| `appId` 型サニタイズ | `verifyAppInstallation` は `Number.isInteger(appId)` で検証し、非整数を `TypeError` で拒否 |
| `repository_selection: 'selected'` 実検証 | 楽観判定を廃止し `/user/installations/<id>/repositories` で対象リポジトリの包含を実検証 |

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

vibehawk は専用 DB を持たない設計により、個人情報を自前のストレージに蓄積しない。
振る舞いとして観察した PR メタデータ・コメント等は GitHub リポジトリ上に存在するものであり、vibehawk がそれらを外部に転送・保存することはない。
📍 根拠: `docs/design-philosophy.md` 状態管理ポリシー

例外なく以下を遵守する:

- 利用者の GitHub アクセストークン・メールアドレス・個人識別情報を vibehawk の実行ログ外に書き出さない
- API レスポンスに含まれる個人情報をキャッシュ・永続化しない（キャッシュ層非保有の原則）

## 依存関係管理

（依存パッケージの更新方針・脆弱性スキャンの運用を記載）

## npm 配布のセキュリティ（Issue #30）

vibehawk CLI は npm registry 経由で配布される。
npm 侵害は世界中の利用者に偽物 vibehawk が配布される最大のサプライチェーン攻撃面のため、以下の **CISO Critical 条件** を遵守する。

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

### 経路 2 必須化による npm 侵害時の影響範囲拡大シナリオ（Issue #61 で追加）

経路 2 必須化（Issue #61 / #72 / #74 確定）により、利用者ごとに `vibehawk-for-<owner>` App が `npx vibehawk install` 経由で作成される構造となった。
経路 1 時代（`secrets.GITHUB_TOKEN` のみ）と比べて、CLI が触る対象として **GitHub Manifest API レスポンス（Private Key を含む）** が新規に追加されている。

#### 想定攻撃シナリオ

1. 攻撃者が npm registry 上の vibehawk パッケージを侵害（typosquatting / 公式パッケージの改ざん版 publish 等）。
2. 改ざん版 CLI は、現実装の `[REDACTED]` メモリ上書き処理（CISO Critical 条件）を **スキップした上で**、Private Key を運営側サーバーに POST 送信する亜種に書き換えられる。
3. 利用者が改ざん版を `npx vibehawk install` 経由で実行 → 利用者本人の `vibehawk-for-<owner>` App の Private Key が攻撃者側に漏洩する。

#### 影響範囲（独立 App 設計の構造的利点）

vibehawk は **利用者ごと独立 App** 設計のため、上記攻撃が成功した場合でも影響範囲は **改ざん版を実行した利用者本人のリポジトリ群に限定** される。
集中 SaaS App（CodeRabbit 型）では 1 鍵漏洩で全利用者に波及するが、vibehawk はその構造を回避している。
📍 参照: [`docs/secrets-handling.md`](secrets-handling.md) § 7

ただし「利用者本人のリポジトリ群への影響」自体は経路 1 時代より拡大している事実を利用者に開示する。

- 経路 1 時代: `secrets.GITHUB_TOKEN` の利用範囲はリポジトリ単位 + workflow 実行時のみ
- 経路 2: Private Key 漏洩経由で **App Installation Token の発行が攻撃者側に渡る**。
  Installation Token 寿命（最大 1 時間）の間は権限スコープ全体が利用される可能性がある。

#### 軽減策（一次防御 + 二次防御）

| 層 | 対策 | 担当 |
|---|---|---|
| 一次防御（vibehawk 側） | npm publish アカウントの 2FA 必須 / GitHub Actions OIDC 経由の publish のみ許可 / npm provenance 署名（CISO Critical 条件 3 点、上記 §「CISO Critical 条件 3 点」） | vibehawk 開発者 |
| 二次防御（利用者側） | npm install 時の provenance 検証（`npm install --foreground-scripts=false` 推奨、`npm audit signatures` で署名検証）、`--dry-run` 実行による予行演習で外部 POST が含まれないか確認、`npm view vibehawk` で公式パッケージの `repository.url` / publisher を事前確認 | 利用者 |
| 三次防御（漏洩検知） | 万が一漏洩を疑った場合は SECURITY.md 「Private Key rotation 手順」に従い `vibehawk-for-<owner>` App の Private Key を rotation する（既存ガイダンス再掲） | 利用者 |

経路 2 必須化は Private Key 漏洩影響を **利用者本人のリポジトリ群に限定** する構造的利点を持つ。
ただし一次/二次防御の重要性は経路 1 時代と比べて高まっている。

- CEO は npm publish 経路を OIDC + provenance に固定しているため、改ざん版が公式 npm registry に流通するリスクは限定的。
- 利用者は二次防御として `npm audit signatures` 等の検証を推奨する。

### install スクリプトの読み書き範囲（Issue #34）

`npx vibehawk install` および `npx vibehawk setup-token` の読み書き範囲は CISO レビューで承認された以下の範囲に限定される。
範囲外の操作は実装してはならない。

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

## 🔗 関連

- [`docs/secrets-handling.md`](secrets-handling.md): 認証情報配布方式の設計判断（全手動採用の根拠）
- [`docs/external-dependency-audit.md`](external-dependency-audit.md): 外部依存サービス規約整合監査
- [`docs/sha-update-policy.md`](sha-update-policy.md): claude-code-action SHA 更新ポリシー
- [`docs/sha-update-history.md`](sha-update-history.md): SHA 更新履歴
- [`docs/design-philosophy.md`](design-philosophy.md): 状態管理ポリシー（自前 DB 非保有原則）
- `.claude/rules/autonomous-restrictions.md`: CI エージェント権限の不可領域定義
- `MVV.md`: セキュリティ方針の設計起点（Value 1 / Value 4）
