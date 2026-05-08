# 自律実行不可領域

`/vibecorp:diagnose` → `/vibecorp:autopilot` → `/vibecorp:ship-parallel` の自律改善ループにおいて、**人間の明示的な承認が必須**で自動実行対象から除外しなければならない領域を定義する。

SM エージェントがこのルールに基づき `/vibecorp:diagnose` の候補をフィルタリングする（`/vibecorp:diagnose` ステップ6b）。

## 不可領域の定義

以下のいずれかに該当する改善候補は、SM が「除外」と判定しなければならない。

### 1. 認証

認証・認可の挙動を変更する候補。誤った変更は本体セキュリティを直接毀損する。

- `templates/claude/hooks/*auth*.sh`, `templates/claude/hooks/*permission*.sh`
- `settings.json` / `.claude/settings.local.json` の `permissions` セクション
- `gh auth`, `ANTHROPIC_API_KEY` の扱いを変更する候補

### 2. 暗号

暗号化・認証情報の永続化を扱う候補。誤った変更は情報漏洩につながる。

- `encrypt`, `decrypt`, `secret`, `credential`, `token` を扱うコード
- 認証情報のファイル保存パス・権限変更

### 3. 課金構造

コスト発生構造を変える候補。誤った変更は予算超過を招く。

- `docs/cost-analysis.md`
- `ANTHROPIC_API_KEY` を使う箇所、ヘッドレス Claude 起動方式
- `max_issues_per_day`, `max_issues_per_run` 等のコスト関連上限
- `claude -p`, `npx`, `bunx` で LLM を呼ぶ箇所

### 4. ガードレール

自律実行を制御するガードレール自体の変更。ここを緩めると他の不可領域に到達できてしまう。

- `templates/claude/hooks/protect-files.sh`
- `templates/claude/hooks/diagnose-guard.sh`
- `/vibecorp:diagnose` の `forbidden_targets` デフォルト値
- `~/.cache/vibecorp/state/<repo-id>/diagnose-active` スタンプの制御ロジック

### 5. MVV

プロダクトの根幹方針の変更。

- `MVV.md` 自体の変更

### 6. CI エージェント（GitHub Actions）

claude-code-action 等の CI 上 Claude エージェントに与える権限の変更。誤った変更は Fork PR 経由の secrets 漏洩・ガードレール迂回につながる。

- `.github/workflows/claude*.{yml,yaml}` / `.github/workflows/ai-review.{yml,yaml}` の `permissions` / `secrets` 参照変更（`.yml` / `.yaml` 両方の拡張子を対象）
- トリガーを `pull_request_target` に変更する候補（Fork PR + secrets 参照は最大の攻撃経路）
- `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` の参照方式変更
- Fork PR 除外条件（`if: github.event.pull_request.head.repo.full_name == github.repository`）の削除・緩和
- GitHub App に与える権限スコープの変更（特に `administration: write` / `secrets: write` / `workflows: write` の追加）

#### 例外: claude-code-action の動作要件として CISO 承認済の permissions

以下の permissions は claude-code-action の動作に必須と公式に要求されており、CISO レビューを経て **例外的に許可**されている。これら以外の permissions 変更は依然として不可領域。

- `id-token: write`: GitHub OIDC token を介して GitHub App identity を証明するために必須（Issue #505 で CISO 承認）。token 発行のみのスコープで、リポジトリの読み書き権限は付与しない。Fork PR では OIDC token は発行されないため攻撃経路にならない。`administration: write` / `secrets: write` / `workflows: write` 等の禁止権限とは性質が異なる

## 判定手順

SM エージェントは改善候補ごとに以下を判定する:

1. 候補の対象ファイル・変更内容を読み取る
2. 上記1〜6の不可領域に該当するかチェック
3. 該当する場合は「除外」と判定（理由として該当領域名を付記）
4. 該当しない場合は「通過」

## 人間承認ルート

不可領域の候補は自動起票対象から除外されるが、ユーザーが手動で Issue を起票して `/vibecorp:ship` で実装することは可能。Phase 5 の狙いは **自律実行を制限する** ことであり、人間による実装までは禁止しない。

## 関連

- Issue #284 Phase 5（#290）
- `/vibecorp:diagnose` ステップ6b
- `/vibecorp:autopilot` 前提条件
