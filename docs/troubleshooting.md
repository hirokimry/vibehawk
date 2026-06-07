# トラブルシューティング

> [!NOTE]
> 本ドキュメントは vibehawk CLI（`npx vibehawk setup` / `install` / `setup-token` / `review`）実行時に遭遇しやすいエラーと復旧手順をまとめる。
> 対象読者: vibehawk を導入する開発者。
> 各項目には Source of Truth となる関連ドキュメントへの cross-reference を付与している。詳細な設計判断や法務効果はリンク先を参照すること。

## 命名統制衝突（連番付与）が検出された場合

`npx vibehawk install` 実行時に以下のようなエラーで処理が中断される場合がある（Issue #60 / CEO 判断 B、2026-05-09）。

```text
vibehawk: 命名統制衝突を検出しました — 想定名「vibehawk-for-alice」に対し、
GitHub から返された実際の名前は「vibehawk-for-alice-2」です。
```

### 原因

GitHub Apps はグローバルで名前ユニーク制約があり、同名 App が既に存在する場合、GitHub が自動的に連番（例: `vibehawk-for-alice-2`）を付与する。
これは `POLICY.md § vibehawk-for-<owner> 命名の商標使用許諾（Issue #33）` の「命名は `vibehawk-for-<owner>` 形式に厳密に従うこと」MUST 条件に違反するため、vibehawk CLI は連番命名を検出した時点で処理を中断（exit 1）する。

連番付き App は商標使用許諾の範囲外（`vibehawk-` プレフィックスの未許可派生名）にあたるため、即時削除すべきである。

### 復旧手順

1. **連番付き App を削除**: 直前の実行で作成された連番付き App（例: `vibehawk-for-alice-2`）を GitHub UI から削除する。
   - エラーメッセージに表示された URL（例: `https://github.com/settings/apps/vibehawk-for-alice-2`）にアクセス
   - 該当 App の **Settings → Delete GitHub App** で削除

2. **既存の `vibehawk-for-<owner>` App を確認**: 同名 App が既に存在することが連番付与の原因である。
   - `https://github.com/settings/apps` にアクセスして既存 App 一覧を確認
   - 不要であれば既存 App を削除し、その後 `npx vibehawk install --owner <owner>` を再実行
   - 既存 App を残したい場合は、別 owner 名で再実行（例: `npx vibehawk install --owner <別の名前>`）

3. **再実行**: 上記いずれかの対応後、`npx vibehawk install` を再実行すると正しい命名（`vibehawk-for-<owner>` 形式）で App が作成される。

### 注意事項

CLI は連番命名を検出した時点で App credentials の Private Key を [REDACTED] 化してメモリから除去する（CISO Critical 条件、`SECURITY.md` 参照）。利用者の手元・画面に Private Key が残存することはない。

連番付き App を放置すると `POLICY.md` の MUST 違反状態が継続し、商標使用許諾の取消条件に該当する可能性がある。発見次第すみやかに削除すること。

### 関連ドキュメント

- `POLICY.md § vibehawk-for-<owner> 命名の商標使用許諾（Issue #33）` — 商標使用許諾の MUST / MUST NOT 条件、取消条件
- `design-philosophy.md § 命名統制（Issue #25 採用）` — 同名衝突時の挙動と設計根拠
- `SECURITY.md` — Private Key [REDACTED] 化の CISO Critical 条件（Source of Truth）

## `127.0.0.1:8765` ポート占有エラー

`npx vibehawk install` 実行時に localhost のポート 8765 が既に使用されている場合、HTTP サーバ起動に失敗する。

### 原因

`npx vibehawk install` は GitHub App Manifest Flow のコールバック先として `127.0.0.1:8765` で一時 HTTP サーバを起動する。
同ポートが先行プロセスで占有されていると CLI は起動できない。
`127.0.0.1` への loopback bind 固定（外部到達不能）と `crypto.randomBytes(32)` で生成した `state` パラメータ + `crypto.timingSafeEqual` による CSRF 防止の多層防御を実装している。
設計詳細は `SECURITY.md § Manifest Flow のセキュリティ対策（Issue #59）` 参照。

### 復旧手順

1. ポート 8765 を占有しているプロセスを特定する。

   macOS / Linux:

   ```bash
   lsof -i :8765
   ```

   Windows（PowerShell）:

   ```powershell
   Get-NetTCPConnection -LocalPort 8765
   ```

2. 占有プロセスが不要なら停止する。前回失敗した `vibehawk install` プロセスが残っている場合は kill する。
3. ポートが空いたことを確認してから `npx vibehawk install` を再実行する。

### 注意事項

ポート 8765 は vibehawk CLI 固定のため、ポート番号を変更して回避することはできない（loopback bind + `state` パラメータの多層防御が `127.0.0.1:8765` 固定前提で設計されている）。
占有プロセスを kill する際は当該プロセスが他の重要な役割を持たないことを確認すること（無関係なプロセスを誤って終了するリスクに注意）。

### 関連ドキュメント

- `SECURITY.md § Manifest Flow のセキュリティ対策（Issue #59）` — loopback bind / state パラメータの多層防御設計

## secret 登録ミス（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）

リポジトリの secrets 値が誤っていると workflow 実行時に App Installation Token 取得失敗・Claude OAuth 認証失敗が発生する。

### 原因

vibehawk CLI（`setup` / `install` / `setup-token` のいずれも）は GitHub Secrets を一切 touch しない（`secrets-handling.md § 1`）。
`gh secret set` を呼び出さず、メモリ・ファイル・環境変数にも secret を保持しない設計のため、3 secrets の登録の正確性は利用者本人が GitHub Settings UI で行う操作に依存する。

登録ミスのよくあるパターン:

- Secret 名のタイポ（例: `VIBEHAWK_APP_ID` を `VIBEHAWK_APPID` と誤入力）
- `VIBEHAWK_PRIVATE_KEY` に `.pem` ファイルの一部だけを貼り付けた（`-----BEGIN ... -----END` を含めていない）
- `CLAUDE_CODE_OAUTH_TOKEN` を別アカウントから発行したものに上書きしてしまった

### 復旧手順

1. 対象リポジトリの `Settings → Secrets and variables → Actions` を開く。
2. 該当 secret を **Update** し、正しい値で再登録する。
   - `VIBEHAWK_APP_ID`: 数値のみ（App Settings ページの `App ID` フィールド）
   - `VIBEHAWK_PRIVATE_KEY`: `.pem` ファイルの **内容全文**（`-----BEGIN ... -----END` を含む）
   - `CLAUDE_CODE_OAUTH_TOKEN`: 利用者本人の Claude Pro / Max OAuth トークン（`claude setup-token` で取得）
3. PR を再 push して workflow を再起動する。

### 注意事項

`VIBEHAWK_PRIVATE_KEY` 再登録時は `.pem` ファイル内容の改行を保持する（GitHub Secrets 入力フォームに貼り付ける際、エディタ間の改行コード差異で改行が削除されると Installation Token 取得が失敗する）。
漏洩懸念がある場合は GitHub App Settings ページで Private Key を revoke + regenerate し、利用者本人が再ダウンロードして secret を更新すること（vibehawk CLI は secret 値を保持しないため、利用者運用での rotation 主体は利用者本人）。
誤って漏洩した OAuth Token は `claude logout` 等で即時失効させる。

### 関連ドキュメント

- `secrets-handling.md § 1 採用方針` — CLI が secret を一切 touch しない設計と判断根拠
- `POLICY.md § 認証情報配布方式（Issue #72 決定、2026-05-09 / Issue #61 確定）` — 配布方式の MUST 条件
- `SECURITY.md` — secrets 取扱の Critical 条件

## Private Key 取扱の CISO Critical 条件

`npx vibehawk install` / `npx vibehawk setup` 実行中に CLI 側で Private Key を一時取得する局面（GitHub App Manifest Flow 完了直後）の取扱を以下にまとめる。設計の Source of Truth は `SECURITY.md` および `secrets-handling.md § 1 採用方針` で、CLI は secret を一切 touch しない方針（メモリ・ファイル・環境変数のいずれにも保持しない）に従う。

### CISO Critical 条件

CLI は GitHub App 作成完了後 / 命名統制衝突検出時のいずれの場合も、App credentials の Private Key を画面に印字せず、Manifest Flow 完了直後に `redactCredentials()` で `[REDACTED]` 上書きしてメモリから除去する。
利用者の手元・画面に Private Key が残存することはない。具体的には:

- CLI は Private Key を画面に印字しない（CISO Critical 条件、`SECURITY.md § install スクリプトの読み書き範囲（Issue #34）` 参照）。
- CLI は Private Key をローカルファイルに保存しない（メモリ・ファイル・環境変数のいずれにも書き込まない、`secrets-handling.md § 1`）。
- `redactCredentials()` を CLI run() return 直前に必ず呼び、`pem` / `client_secret` / `webhook_secret` を `[REDACTED]` で上書きする。
- `npx vibehawk setup` ウィザード経由でも同条件が適用される。`SIGINT` / `SIGTERM` ハンドラで `clearState()` を呼び `oauthToken` / `appIdString` / `credentials` をすべて null 化する（`SECURITY.md § npx vibehawk setup ウィザード経路の追加 Critical 条件（Issue #91）` 参照）。

Private Key は GitHub の App Settings ページから `.pem` ファイルとして利用者本人がダウンロードする運用とする（`secrets-handling.md § 1 採用方針`）。

### 関連ドキュメント

- `SECURITY.md` — Private Key 取扱の CISO Critical 条件（Source of Truth）
- `secrets-handling.md § 1 採用方針` — CLI が Private Key を保持しない設計判断
- `specification.md § CLI 仕様 § セキュリティ要件（CISO Critical）` — 実装観点での Critical 条件

## bot アイコンがデフォルトのままで vibehawk ロゴにならない

PR コメント・レビュー・ラベル付与など bot の露出箇所で、アイコンが GitHub のデフォルトのまま vibehawk ロゴ（🦅）にならない場合。

### 原因

GitHub App のロゴは **Web UI（Display information）でしか設定できない**。

- Manifest Flow にロゴ欄が無く、App 自動作成時に焼き込めない。
- 作成後にロゴを設定する REST / GraphQL API も存在しない。
- そのため `npx vibehawk setup` は手動アップロードを案内するのみで、自動設定はできない（GitHub 仕様）。

### 復旧手順

1. App 設定ページを開く: `https://github.com/settings/apps/<slug>`（`<slug>` は `vibehawk-for-<owner>`）
2. `Display information` の現在のロゴ（GitHub のデフォルトアイコン）をクリックする
3. 同梱の vibehawk ロゴ画像をドラッグ&ドロップしてアップロードする
   - 画像の場所: 配布物同梱の `assets/vibehawk-logo.png`（PNG / 512×512px / 1MB 未満）
   - npx 実行時はパッケージキャッシュ内に展開される。`npx vibehawk setup` の `bot アイコン（ロゴ）を差し替え` ステップが絶対パスを表示する
4. `Save changes` で保存する

### 注意事項

- ロゴ差し替えは **任意**。設定しなくても vibehawk の動作（レビュー・check post・merge gate）には影響しない。
- ロゴ設定は認証・認可・Private Key の取り扱いとは無関係（credential 経路に影響しない、Issue #249）。

### 関連ドキュメント

- `README.md § 1. App / secrets / workflow を準備` — setup ウィザードのステップ説明
- `specification.md § CLI 仕様` — setup ウィザードのステップ構成

## vibehawk が指摘を出しているのに merge できる（merge gate が機能しない）

`vibehawk` workflow がレビューを post して `request_changes` も出しているのに、PR が merge できてしまう場合。

### 原因

branch protection に `vibehawk` が **required status check として登録されていない**。vibehawk は `POST /repos/X/Y/check-runs` で `vibehawk` という名前の status check を post するが、利用者の repo の branch protection で required 指定がないと merge gate として機能しない（bot review は GitHub 構造仕様により `required_approving_review_count` に count されないため、status check 経路が merge gate の主軸）。

### 復旧手順

1. 対象リポジトリで初回 PR を作成して `vibehawk` check を一度発火させる（GitHub の仕様上、未発火の check 名は branch protection 設定の検索候補に出ない）
2. `Settings → Branches → Branch protection rules` を開く
   - 直リンク: `https://github.com/<owner>/<repo>/settings/branches`
3. main ブランチ（または保護対象ブランチ）のルールを編集
4. `Require status checks to pass before merging` を ON
5. 検索ボックスに `vibehawk` を入力して required に追加
6. 既存 PR を作り直すか空コミットを push して merge gate が効くことを確認

### 注意事項

- 検索ボックスに `vibehawk` が出てこない場合、まだ一度も check が発火していない（手順 1 の初回 PR が未実施）か、check 名が誤って別の値で post されている。`gh api repos/<owner>/<repo>/commits/<sha>/check-runs` で post された check 名を確認できる
- vibehawk 自身の dogfooding でも本ステップは手動で必要（GitHub App permissions に `administration: write` を持たせて CLI が自動書き換えする経路は `.claude/rules/autonomous-restrictions.md` の CI エージェント不可領域に該当するため、L1 + L2 の利用者誘導が現実解）

### 関連ドキュメント

- `README.md § 3. branch protection に vibehawk を required status check 登録（vibehawk 利用の根幹）` — 必須手順の説明
- `specification.md § status check 仕様` — `vibehawk` check の post 設計（Issue #138 / #121-C1）

## 全 PR で `vibehawk` check が永続 pending になり merge が完全停止する

branch protection に `vibehawk` を required 追加した後、新規 PR を立てると `vibehawk` check が永続 pending になり、どの PR も merge できない場合。

### 原因

`vibehawk` を required 指定したものの、3 secrets（`VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`）のいずれかが未登録 / 不正のため workflow が早期に失敗し、`check-runs` API への post まで到達できていない。required で登録されているのに post 自体が来ないため、GitHub は「未到達 = pending」と判定し続ける。

### 復旧手順

1. **branch protection の `vibehawk` required を一旦外す**（merge 完全停止の解除）
   - `https://github.com/<owner>/<repo>/settings/branches` から該当ルールを編集
2. Settings → Secrets and variables → Actions で 3 secrets を再確認
   - `VIBEHAWK_APP_ID`: 数値のみ（App ID）
   - `VIBEHAWK_PRIVATE_KEY`: `.pem` ファイルの **改行を保持** した全文
   - `CLAUDE_CODE_OAUTH_TOKEN`: `claude setup-token` で取得した OAuth Token
3. 任意の PR で workflow を再起動し、`vibehawk` check が `success` または `failure` で post されることを確認
4. 確認後、再度 branch protection で `vibehawk` を required 追加（順序強制）

### 注意事項

- 順序: **3 secrets 全完了 → 初回 PR で vibehawk check 発火確認 → branch protection 追加** の順を厳守する
- `npx vibehawk setup` ウィザードは 3 secrets 完了状態でのみ branch protection 案内を表示する（順序強制の UI 側実装、Issue #134）
- secret の改行が壊れているケースが最も多い。エディタ間で改行コード（CRLF / LF）が変換される / フォーム貼付時に削除されるなど。GitHub Secrets UI は値の visual feedback がないため、再登録時は `.pem` ファイルをそのままドラッグ&ドロップするか pbcopy / clip でクリップボード経由で貼付するのが安全

### 関連ドキュメント

- `secrets-handling.md` — secret 値の正規化と CLI 非保持の方針
- `README.md § 3. branch protection に vibehawk を required status check 登録（vibehawk 利用の根幹）`

## `npx vibehawk review` が前提不備で中止される

`npx vibehawk review`（push 前ローカルレビュー）の実行時、前提が満たされないと処理が中止される。代表的なエラーは以下の 4 種。

```text
vibehawk: claude コマンドが見つかりません。
vibehawk: claude の認証が必要です。'npx vibehawk setup-token' で OAuth トークンを設定してください。
vibehawk: ANTHROPIC_API_KEY が設定されています。
vibehawk: git リポジトリ内で実行してください。
```

### 原因

`npx vibehawk review` は利用者ローカルの **Claude Code（`claude`）を OAuth（Pro / Max 枠）で**呼び出す read-only CLI（追加課金ゼロを守るための設計）。前提が崩れると安全側に倒して中止する。

- **claude 未インストール**: `claude` コマンドが PATH に存在しない。
- **未ログイン**: `claude` はあるが OAuth ログインが済んでいない（認証エラー）。
- **`ANTHROPIC_API_KEY` 設定**: 非対話の `claude -p` は `ANTHROPIC_API_KEY` があると API 従量課金経路を優先するため、追加課金を避けて中止する（fail-fast）。
- **git リポジトリ外**: diff を取得できないため中止する。

### 復旧手順

1. **claude 未インストール**: `npm install -g @anthropic-ai/claude-code` で導入する。
2. **未ログイン**: `npx vibehawk setup-token` の案内に従って `claude setup-token` でログインし、**その後 `npx vibehawk review` を再実行**する。
3. **`ANTHROPIC_API_KEY` 設定**: `unset ANTHROPIC_API_KEY` で解除する。解除後は OAuth（Pro / Max 枠）経路に戻り、追加課金なしで実行できる。
4. **git リポジトリ外**: `cd` で対象リポジトリのルート（または作業ツリー内）へ移動してから再実行する。

### 注意事項

- `review` は **read-only**（指摘のみ・自動修正なし）。`--fix` 等の書き込みフラグは存在しない（MVV Value 2）。
- 既定の終了コードは **0**（指摘しても止めない、Value 3）。pre-commit / CI のゲートにする場合のみ `--fail-on <severity>` でオプトインする。
- `review` は手元の git diff を `claude -p` 経由で Anthropic に送信する。機密を含む場合は `--staged` や `.vibehawk.yaml` の `path_filters` で送信範囲を絞る。

### 関連ドキュメント

- `README.md § 🖥️ push 前ローカルレビュー（npx vibehawk review）`
- `POLICY.md § Anthropic への送信通知` — 送信内容と利用者の責任範囲
- `cost-analysis.md` — Pro / Max 枠のクォータ消費と段階的劣化
