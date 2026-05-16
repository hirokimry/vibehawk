# トラブルシューティング

vibehawk CLI（`npx vibehawk setup` / `install` / `setup-token`）実行時に遭遇しやすいエラーと復旧手順をまとめる。各項目には Source of Truth となる関連ドキュメントへの cross-reference を付与しているので、詳細な設計判断や法務効果はリンク先を参照すること。

## 命名統制衝突（連番付与）が検出された場合

`npx vibehawk install` 実行時に以下のようなエラーで処理が中断される場合がある（Issue #60 / CEO 判断 B、2026-05-09）。

```text
vibehawk: 命名統制衝突を検出しました — 想定名「vibehawk-for-alice」に対し、
GitHub から返された実際の名前は「vibehawk-for-alice-2」です。
```

### 原因

GitHub Apps はグローバルで名前ユニーク制約があり、同名 App が既に存在する場合、GitHub が自動的に連番（例: `vibehawk-for-alice-2`）を付与する。これは `docs/POLICY.md § vibehawk-for-<owner> 命名の商標使用許諾（Issue #33）` の「命名は `vibehawk-for-<owner>` 形式に厳密に従うこと」MUST 条件に違反するため、vibehawk CLI は連番命名を検出した時点で処理を中断（exit 1）する。

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

CLI は連番命名を検出した時点で App credentials の Private Key を [REDACTED] 化してメモリから除去する（CISO Critical 条件、`docs/SECURITY.md` 参照）。利用者の手元・画面に Private Key が残存することはない。

連番付き App を放置すると `docs/POLICY.md` の MUST 違反状態が継続し、商標使用許諾の取消条件に該当する可能性がある。発見次第すみやかに削除すること。

### 関連ドキュメント

- `docs/POLICY.md § vibehawk-for-<owner> 命名の商標使用許諾（Issue #33）` — 商標使用許諾の MUST / MUST NOT 条件、取消条件
- `docs/design-philosophy.md § 命名統制（Issue #25 採用）` — 同名衝突時の挙動と設計根拠
- `docs/SECURITY.md` — Private Key [REDACTED] 化の CISO Critical 条件（Source of Truth）

## `127.0.0.1:8765` ポート占有エラー

`npx vibehawk install` 実行時に localhost のポート 8765 が既に使用されている場合、HTTP サーバ起動に失敗する。

### 原因

`npx vibehawk install` は GitHub App Manifest Flow のコールバック先として `127.0.0.1:8765` で一時 HTTP サーバを起動する。同ポートが先行プロセスで占有されていると CLI は起動できない。`127.0.0.1` への loopback bind 固定（外部到達不能）と `crypto.randomBytes(32)` で生成した `state` パラメータ + `crypto.timingSafeEqual` による CSRF 防止の多層防御を実装している。設計詳細は `docs/SECURITY.md § Manifest Flow のセキュリティ対策（Issue #59）` 参照。

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

### 関連ドキュメント

- `docs/SECURITY.md § Manifest Flow のセキュリティ対策（Issue #59）` — loopback bind / state パラメータの多層防御設計

## secret 登録ミス（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）

リポジトリの secrets 値が誤っていると workflow 実行時に App Installation Token 取得失敗・Claude OAuth 認証失敗が発生する。

### 原因

vibehawk CLI（`setup` / `install` / `setup-token` のいずれも）は **GitHub Secrets を一切 touch しない**（`docs/secrets-handling.md § 1`）。`gh secret set` を呼び出さず、メモリ・ファイル・環境変数にも secret を保持しない設計のため、3 secrets の登録の正確性は利用者本人が GitHub Settings UI で行う操作に依存する。

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

### 関連ドキュメント

- `docs/secrets-handling.md § 1 採用方針` — CLI が secret を一切 touch しない設計と判断根拠
- `docs/POLICY.md § 認証情報配布方式（Issue #72 決定、2026-05-09 / Issue #61 確定）` — 配布方式の MUST 条件
- `docs/SECURITY.md` — secrets 取扱の Critical 条件

## Private Key 取扱の CISO Critical 条件

`npx vibehawk install` / `npx vibehawk setup` 実行中に CLI 側で Private Key を一時取得する局面（GitHub App Manifest Flow 完了直後）の取扱を以下にまとめる。設計の Source of Truth は `docs/SECURITY.md` および `docs/secrets-handling.md § 1 採用方針` で、CLI は secret を一切 touch しない方針（メモリ・ファイル・環境変数のいずれにも保持しない）に従う。

### CISO Critical 条件

CLI は GitHub App 作成完了後 / 命名統制衝突検出時のいずれの場合も、App credentials の Private Key を **画面に印字せず**、Manifest Flow 完了直後に `redactCredentials()` で **`[REDACTED]` 上書き** してメモリから除去する。利用者の手元・画面に Private Key が残存することはない。具体的には:

- CLI は Private Key を **画面に印字しない**（CISO Critical 条件、`docs/SECURITY.md § install スクリプトの読み書き範囲（Issue #34）` 参照）
- CLI は Private Key を **ローカルファイルに保存しない**（メモリ・ファイル・環境変数のいずれにも書き込まない、`docs/secrets-handling.md § 1`）
- `redactCredentials()` を CLI run() return 直前に必ず呼び、`pem` / `client_secret` / `webhook_secret` を `[REDACTED]` で上書きする
- `npx vibehawk setup` ウィザード経由でも同条件が適用される。`SIGINT` / `SIGTERM` ハンドラで `clearState()` を呼び `oauthToken` / `appIdString` / `credentials` をすべて null 化する（`docs/SECURITY.md § npx vibehawk setup ウィザード経路の追加 Critical 条件（Issue #91）` 参照）

Private Key は GitHub の App Settings ページから `.pem` ファイルとして利用者本人がダウンロードする運用とする（`docs/secrets-handling.md § 1 採用方針`）。

### 関連ドキュメント

- `docs/SECURITY.md` — Private Key 取扱の CISO Critical 条件（Source of Truth）
- `docs/secrets-handling.md § 1 採用方針` — CLI が Private Key を保持しない設計判断
- `docs/specification.md § CLI 仕様 § セキュリティ要件（CISO Critical）` — 実装観点での Critical 条件
