# vibehawk プロダクト仕様書

> このドキュメントはプロダクトの公式仕様を定義する Source of Truth です。

## 概要

vibehawk は **追加課金ゼロの PR 自動レビュー OSS プロダクト** である。利用者が既に支払っている LLM サブスクリプション枠（Claude Pro / ChatGPT Plus 等）の **内側だけ** で動作し、AI レビュー専用 SaaS の月額や LLM API の従量課金を発生させない。CodeRabbit Pro / Greptile / PR-Agent 等への対比優位は「**追加課金ゼロ**」という構造的差別化に立脚する。

### 対象ユーザー

- LLM サブスクリプション（Claude Pro / ChatGPT Plus 等）を既に契約している開発者
- PR レビューに AI を活用したいが、追加課金を発生させたくない個人 / 小〜中規模チーム
- 自前のサーバー運用・ベクタ DB 運用を避けたい OSS 利用者

### 提供価値

- **追加課金ゼロ**: 既存 LLM サブスク枠の内側で完結
- **公式準拠**: LLM プロバイダー公式の OAuth・Action だけを使う
- **GitHub に閉じる**: 専用 DB・専用サーバーを持たない
- **持続可能性**: 他社 SaaS の値上げ・廃止に左右されない構造

## ターゲット市場

vibehawk は以下の利用者層を主要ターゲットとする:

- **個人 OSS メンテナ**: 自身の Pro/Max サブスクリプション枠内で OSS リポジトリの PR レビューを行いたい
- **個人開発者・学習者**: GitHub 上で個人プロジェクトを運用し、追加課金なしで AI レビューを受けたい
- **小規模チーム（< 10 人）**: 共有 Pro/Max アカウントで運用するチーム

以下は構造的に対象外:

- **エンタープライズ顧客**: 通常 API Key 契約（従量制）で運用するため、OAuth 経路のみの vibehawk は使えない
- **コード送信を社外に許容しない組織**: 自社コードが Anthropic に送信されることを規約上許容しないケース
- **GitHub Organization の Admin 権限を持たない開発者**: `npx vibehawk install` 実行に Admin 権限が必要なリポジトリ

### MVV との整合

ターゲット市場の明示は Mission「レビューツールに追加課金が要らない世界をつくる」を **絞る** ものではなく、Mission の **適用範囲を明確化** するものである。エンタープライズ顧客が構造的に対象外となるのは、Pro/Max OAuth 経路に絞った Value 1「利用者の契約だけで、完結させる」の必然的な帰結であり、Mission との矛盾ではない。

## 機能仕様

### コア機能

| 機能 | 概要 |
|---|---|
| PR auto-review トリガー | PR が立ったら自動でレビューを始める（open / synchronize / ready_for_review） |
| PR 全体サマリコメント（walkthrough） | PR 冒頭に「変更概要 + 何を見たか」のサマリを 1 個投稿、push 毎に edit で最新化 |
| inline comment 投稿 | コードの行を指して指摘を書く。severity 絵文字付き、Suggestions 構文（` ```suggestion `）の生成も可 |
| approve 発行 | レビューが OK なら approve を発行する（sticky review state により request_changes と自動切替） |
| request_changes 発行 | 未解決指摘があれば request_changes を発行する（sticky review state により approve と自動切替） |
| インクリメンタルレビュー | 2 回目以降は前回見た範囲を覚えていて、新しい変更だけ見る |
| severity 5 段階の判定軸 | Critical / Major / Minor / Trivial / Info の付け方ルール（CodeRabbit 互換） |
| 日本語レビュー（locale 対応） | 日本語でコメントを書く（設定で切替可） |
| auto_resolve | 古い指摘を自動で resolved 化（Bot 自身の投稿のみ対象） |
| path_filters | レビュー対象から除外するパスを指定 |
| path_instructions | パス別のカスタムレビュー観点を Bot に注入 |
| @mention チャット応答 | 「@bot ここどうする？」に Bot が返事する（issue_comment トリガー） |
| 状態管理（GitHub をストアとして使う） | PR コメント・resolved 状態などを GitHub 上で直接読み書きする |

### 補助機能

| 機能 | 概要 | 状態 |
|---|---|---|
| profile（chill / assertive） | 口調の切替（優しめ / 厳しめ）。tone_instructions の切替 | 将来検討 |
| sequence diagram 自動生成 | 処理フローを図で表示 | 将来検討 |
| linked issue 評価 | PR が紐づく Issue の要件を満たしているか確認 | 将来検討 |

## アーキテクチャ

> 永続的状態は GitHub リポジトリ自体を状態ストアとして使う。内部 DB / ベクタ DB / 専用サーバーは持たない（5 大方針 4 / `docs/POLICY.md` 参照）。

### 状態管理（GitHub をストアとして使う）

CodeRabbit が DB で持つ状態を、vibehawk では GitHub 上のどこから読むか／どこに書くか:

| 状態の種類 | CodeRabbit | vibehawk |
|---|---|---|
| 前回レビュー時点のコミット SHA | 内部 DB | PR サマリコメント末尾 HTML コメント |
| PR 指摘の resolve 状態 | 内部 DB | GitHub の Resolved Conversation を直接読む |
| PR 全体の review status | 内部 DB | gh pr review で都度発行（永続化不要） |
| @mention チャット文脈 | 内部 DB | GitHub の comment スレッドを直接読む |
| PR 間の学習 | ベクタ DB | ❌ 持たない・実装しない |

### メタデータ仕様

サマリコメントに識別マーカーと SHA マーカーを HTML コメントとして埋め込む。Markdown レンダラーが描画しないため UI 上は不可視。

```markdown
## 📝 PR レビューサマリ
（本文）

<!-- vibehawk:summary -->
<!-- vibehawk:sha=abc123def456 -->
```

| マーカー | 役割 |
|---|---|
| `<!-- vibehawk:summary -->` | 種別マーカー（Bot の PR 全体サマリであることを示す） |
| `<!-- vibehawk:sha=<HEAD_SHA> -->` | 状態マーカー（前回どのコミットまで見たか） |

サマリコメントの一意特定: 投稿者 ID（`vibehawk-for-<owner>[bot]`）+ 種別マーカーの **二重チェック** で誤検知・なりすましを排除する。投稿者 ID だけでは同一リポジトリの他 GitHub Actions ジョブが投稿したコメントと混在するため、種別マーカー (`<!-- vibehawk:summary -->`) との AND 条件で識別する。`<owner>` は利用者本人の GitHub アカウント名であり、リポジトリの owner 名と一致する（命名統制 Issue #25）。

```bash
gh api repos/:owner/:repo/issues/:pr/comments --paginate \
  | jq --arg owner "<owner>" '[.[] | select(.user.login == "vibehawk-for-" + $owner + "[bot]") | select(.body | contains("<!-- vibehawk:summary -->"))]' \
  | jq 'sort_by(.created_at) | last'
```

> 投稿者 ID は **利用者ごとに独立した GitHub App `vibehawk-for-<owner>` の Installation Token** で発行される `vibehawk-for-<owner>[bot]` 名義（経路 2 必須化、Issue #61 で確定）。CEO の GitHub App Private Key を利用者に配布する設計（Issue #22 で却下された旧設計）とは異なり、利用者自身の App の Private Key を **利用者本人が GitHub Settings UI で手動登録** する。判断根拠は `docs/secrets-handling.md` 参照。

### マルチリポジトリ対応

利用者リポジトリへの **workflow ファイル配置 + 3 secrets 手動登録** によるリポジトリ単位の有効化方式（経路 2 必須化、Issue #61）。Org 配下の各リポジトリに `vibehawk-review.yml` をコピーし、各リポジトリの secrets に 3 つを登録する。

```text
利用者の Org / 個人（自身の vibehawk-for-<owner> App を 1 つ作成）
  ├─ repo-1: .github/workflows/vibehawk-review.yml + 3 secrets
  ├─ repo-2: .github/workflows/vibehawk-review.yml + 3 secrets
  └─ repo-N: ...

3 secrets:
  - VIBEHAWK_APP_ID         （利用者本人の App の ID）
  - VIBEHAWK_PRIVATE_KEY    （利用者本人の App の Private Key）
  - CLAUDE_CODE_OAUTH_TOKEN （利用者の Claude Pro / Max OAuth Token）
```

> Org-level secret として 3 つを設定すれば配下の全リポジトリで共有できる（個別設定不要）。Org 単位で 1 つの `vibehawk-for-<owner>` App を運用する形になる。

| 状態 | スコープ | 衝突リスク |
|---|---|---|
| サマリコメントの HTML メタデータ | PR 内（リポジトリ単位より狭い） | なし |
| @mention チャット文脈 | コメントスレッド内（さらに狭い） | なし |
| Cross-repository な状態 | 持たない（5 大方針 4） | 設計上発生しない |

### インクリメンタルレビュー実装パターン

サマリは **edit して 1 個に保つ**、inline は **append で履歴を残す**、解決済み指摘は **auto_resolve で resolved に倒す** の 3 段運用。

```text
[初回レビュー]
  ├─ PR 冒頭にサマリコメント投稿（種別マーカー + SHA 埋め込み付き）
  └─ 指摘箇所に inline comment 投稿

[2 回目以降（push 後）]
  ├─ サマリコメントを edit（更新）              ← コメント数は増えない
  ├─ 新しい inline 指摘は append（追加）        ← 履歴が残る
  └─ push で直った指摘は auto_resolve          ← Bot 自身の投稿のみ対象
```

**実装フロー**:

```text
[Step 1] PR の全コメントを gh api で取得
[Step 2] 投稿者 ID + 種別マーカー (<!-- vibehawk:summary -->) で
         自身の最新サマリコメントを一意に特定
[Step 3] サマリコメント末尾の HTML メタデータから前回 SHA を抽出
         <!-- vibehawk:sha=abc123def -->
[Step 4] 前回 SHA が現ブランチに含まれているかチェック
         ├─ 含まれている（通常 push）   → 前回 SHA から HEAD までの diff
         └─ 含まれていない（force push）→ base ブランチからの完全再レビュー
[Step 5] レビュー結果に応じて以下を発行:
         ├─ サマリコメント: edit（HEAD SHA を埋め込み直して内容更新）
         ├─ 新規指摘: 新しい inline comment を append
         └─ 旧指摘で差分が消えたもの: 該当 conversation を resolve
```

**force push / rebase 検出**:

```bash
prev_sha=$(extract_sha_from_summary)

# base ブランチは GitHub Actions 環境変数から動的取得（main 以外の default branch にも対応）
base_ref="${GITHUB_BASE_REF:-main}"

if git merge-base --is-ancestor "$prev_sha" HEAD; then
  range="$prev_sha..HEAD"
else
  base_sha=$(git merge-base "origin/${base_ref}" HEAD)
  range="$base_sha..HEAD"
fi
```

> 注 1: base ブランチは `GITHUB_BASE_REF` 環境変数から取得する（pull_request イベント時に GitHub Actions が自動設定）。`main` 以外（`master` / `trunk` 等）のデフォルトブランチを持つリポジトリでも動作させるため `origin/main` ハードコードは避ける。
>
> 注 2: GitHub Actions の shallow clone（`fetch-depth: 1` 等）では `$prev_sha` が履歴から欠落して `git merge-base --is-ancestor` が常に false を返し、意図せず force push 扱いになる場合がある。利用者の workflow では `actions/checkout` で `fetch-depth: 0` を指定するか、`git fetch --unshallow` でフォールバックすることを推奨する。

### sticky review state

未解決の指摘が残っていれば「直して」（request_changes）、全部解決していれば「OK」（approve）を毎回発行し直す。状態は GitHub 側にあるので Bot 側の永続化不要。

```text
[Step 1] gh api で PR の全 review thread を取得
[Step 2] resolved / unresolved の数をカウント
[Step 3] unresolved == 0 なら gh pr review --approve
[Step 4] unresolved >= 1 なら gh pr review --request-changes
```

### @mention チャット応答

応答のたびにスレッド全体を `gh api` で読み直して、全コメントを LLM コンテキストに渡す。会話状態は GitHub のスレッド自体が保持する。

```text
利用者が @vibehawk でメンション
  ↓
issue_comment イベントトリガーで workflow 起動
  ↓
gh api でスレッド全コメント取得
  ↓
全コメントを LLM コンテキストに含めて応答生成
  ↓
スレッドに新しいコメントとして応答を append
```

経路 2 必須化（Issue #61）に伴い、`issue_comment` トリガーの workflow も `vibehawk-review.yml` と同一の認証経路で動作する:

- 投稿主体: `vibehawk-for-<owner>[bot]` 名義（App Installation Token 認証）
- 起動条件: `@vibehawk` を含み、かつ投稿者が `vibehawk-for-` で始まる Bot 自身ではないこと（無限ループ防止）
- 必要 secrets: `VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`（レビュー workflow と同一）

将来的にスレッド超肥大化に備え、`.vibehawk.yaml` で `chat.max_thread_comments`（デフォルト未設定 = 無制限）を後付け可能な構造にしておく。

経路 2 必須化が本機能および Issue #8 / #9 / #10 / #11 の設計に与えた影響の詳細評価は `docs/route2-impact-analysis.md` を参照。

## やらない範囲（明示的除外）

vibehawk の責務範囲外として **実装しない** 機能、および vibecorp 側に残す機能を明示する。判断軸は `docs/POLICY.md` の「プロダクト方針（5 大方針）」を参照。

### やらない（実装しない）

| 機能 | 理由 |
|---|---|
| docstring / unit-test 生成 | コード生成しない方針（5 大方針 2） |
| apply suggestions / auto-fix（Bot 自身による commit） | 同上。Suggestions 構文の生成は OK だが Bot による commit は NG |
| PR ラベル / milestone / description 自動補完 | PR メタデータ操作しない（5 大方針 5） |
| 専用 DB（内部 DB）を持つ | 状態は GitHub に置く（5 大方針 4） |
| ベクタ DB を持つ | 同上 |
| knowledge_base / learnings | ベクタ DB に依存するため不可 |
| 利用者リポジトリ内の学習ファイル蓄積 | path_instructions で代替可（5 大方針 1） |
| web_search | サーバー必須。path_instructions で代替可 |
| 40+ linter 統合 | super-linter 等で利用者側に任せる |
| changelog 生成 | path_instructions で代替可 |
| issue triage / 要約 | 別 Action で実現可能 |
| pre-merge checks（タイトル形式・docstring 検証） | path_instructions で代替可 |

### vibecorp 側に残す

| 機能 | 残す理由 |
|---|---|
| intent × severity の捌き基準 | vibecorp 独自運用ルール（利用者側意思決定、5 大方針 3） |
| review-handling / review-observations | vibecorp 閉ループの一部 |
| review-harvest（PR 間学習） | vibecorp の knowledge/ 蓄積で代替 |
| intent-label-check CI | vibecorp 運用ルール |

## 非機能要件

### パフォーマンス

- **ジョブタイムアウト**: GitHub Actions 標準の **6 時間**。LLM レビューには十分な余裕がある（実運用では数分〜数十分のオーダーで完了する想定）。
- **並列実行制御**: 利用者の workflow ファイルで `concurrency:` を宣言する。新しい push が来たら古いレビューを中止する設計を推奨。

```yaml
concurrency:
  group: vibehawk-${{ github.event.pull_request.number }}
  cancel-in-progress: true
```

### セキュリティ

詳細は `docs/SECURITY.md` を参照。本仕様書では特記事項のみ記述する。

#### 投稿者表示（経路 2 必須化、Issue #61 で確定）

vibehawk が投稿するレビューコメントの投稿者は **`vibehawk-for-<owner>[bot]`** 名義に固定される（命名統制 Issue #25）。利用者ごとに独立した GitHub App `vibehawk-for-<owner>` の Installation Token（`actions/create-github-app-token@v2` 経由）で認証される。

CEO の GitHub App Private Key を利用者に配布する設計（Issue #22 の旧実装）と異なり、**利用者自身が GitHub App Manifest Flow で自前の App を作成** し、その App の Private Key を **利用者本人が GitHub Settings UI で対象リポジトリの Secrets に手動登録** する。Private Key の漏洩影響は利用者本人のリポジトリに限定される（独立 App の構造的利点、`docs/secrets-handling.md` § 7 参照）。

経路 2 必須化の判断根拠（業界比較 / GitHub 公式ガイドライン / CodeRabbit 事件の教訓 / MVV Value 1 整合）は `docs/secrets-handling.md` を参照。CLI による secret 自動書込はせず、3 secrets すべて利用者が GitHub Settings UI で手動登録する全手動方針（Issue #72 決定）を採用している。

### 可用性

（稼働率、障害復旧等の要件を記載）

## CLI 仕様

vibehawk は npm パッケージとして CLI を提供する。利用者は `npx vibehawk install` で GitHub App Manifest Flow を起動できる。

### 提供コマンド

| コマンド | 用途 |
|---|---|
| `npx vibehawk setup [--owner USER] [--repo OWNER/REPO] [--dry-run]` | 対話型ウィザード（推奨）。App 作成 → リポジトリインストール → 3 secrets 登録 → workflow 配置の全 6 ステップを 1 コマンドに集約。Enter ゲートで段階検証（CLI は Anthropic に通信しない、secret を書き込まない）（Issue #91） |
| `npx vibehawk install` | GitHub App Manifest Flow を起動して利用者の GitHub アカウントに `vibehawk-for-<owner>` App を作成（CLI は secret を書き込まない、利用者が GitHub Settings UI で App ID / Private Key を手動登録する） |
| `npx vibehawk setup-token` | Claude OAuth Token の取得を補助し GitHub Settings 登録手順を画面誘導（CLI は secret を書き込まない、明示同意の上でクリップボードにコピー、Issue #74） |
| `npx vibehawk help` | コマンド一覧を表示 |
| `npx vibehawk version` | バージョンを表示 |

### `install` コマンドの動作（Issue #24）

1. ローカル HTTP サーバー（127.0.0.1:8765）を起動
2. ブラウザで `http://localhost:8765/start` を自動オープン
3. ブラウザが GitHub App Manifest Flow（`POST https://github.com/settings/apps/new`）に遷移
4. 利用者が GitHub UI で「Create」ボタンを押下
5. GitHub が `http://localhost:8765/callback?code=<code>` にリダイレクト
6. CLI が `code` を `POST https://api.github.com/app-manifests/<code>/conversions` に渡し App credentials を取得
7. App ID / Slug / HTML URL を画面表示し、Private Key は **意図的に画面に印字せず破棄** する（メモリ上の参照を `[REDACTED]` で上書き）
8. 利用者は表示された URL から App をリポジトリにインストールする

### セキュリティ要件（CISO Critical）

- **localhost のみで完結**: vibehawk 運営側のサーバーには一切通信しない（`callback_urls` は localhost に固定）
- **Private Key 非配布**: GitHub Manifest API が返却する Private Key を CLI が画面に印字・ファイル保存しない（メモリ上の参照は `[REDACTED]` で上書き）
- **最小権限のみ要求**: `pull_requests: write` / `issues: write` / `contents: read`（`administration: write` / `secrets: write` / `workflows: write` / `id-token: write` は要求しない）
- **App は public**: OSS として配布するため `public: true`

### App 命名規則（Issue #25 採用）

`npx vibehawk install` で作成される GitHub App の名前は **`vibehawk-for-<owner>` 形式に固定** される（例: owner が `alice` なら App 名は `vibehawk-for-alice`、bot 表示は `vibehawk-for-alice[bot]`）。

| 観点 | 内容 |
|---|---|
| 形式 | `vibehawk-for-<owner>` |
| owner 制約 | GitHub user/org 命名規則（1-39 文字、英数字とハイフン、先頭末尾はハイフン不可、連続ハイフン不可） |
| カスタマイズ | 不可（CLI が引数 `--owner` または対話プロンプトで受け付け、命名は固定） |
| 同名衝突 | GitHub が自動連番付与する場合あり。CLI が `printResult` で警告表示 |
| 設計根拠 | `docs/design-philosophy.md`「命名統制」セクション参照 |

CLI 起動時に「⚠️ 命名統制」の旨を明示表示し、利用者がカスタマイズ不可であることを認識した上で進める運用とする。

### CLI 利用フロー（経路 2 必須化、Issue #61 で確定）

#### 推奨経路: `npx vibehawk setup` 1 コマンドで導入（Issue #91）

対話型ウィザードが全 6 ステップを 1 コマンドに集約する:

```bash
npx vibehawk setup --owner <your-github-username> --repo <owner>/<repo>
```

各ステップで「指示表示 → ブラウザで操作 → Enter → CLI が `gh api` 検証（読み取り専用）→ OK で次 / NG なら原因表示してリトライ・スキップ・中止」の Enter ゲートで進行する。CLI 自体は Anthropic に通信せず、secret を書き込まない。

#### 個別実行（後方互換）: `install` / `setup-token` を使う場合

`setup` ウィザードを使わず各ステップを個別実行する従来の手順も引き続き利用可能（`install` / `setup-token` サブコマンドは後方互換のため残す）:

| ステップ | コマンド / 操作 | 結果 |
|---|---|---|
| 1 | `npx vibehawk install --owner <name>` | `vibehawk-for-<owner>` App が作成される。CLI は App ID と Settings URL を画面表示する（Private Key は印字せず破棄、CISO Critical 条件） |
| 2 | GitHub Settings UI で `VIBEHAWK_APP_ID` を手動登録 | 利用者が CLI 表示の URL を開いてコピペ |
| 3 | GitHub App Settings で Private Key を `.pem` ダウンロード → Settings UI で `VIBEHAWK_PRIVATE_KEY` を手動登録 | 利用者が GitHub UI 内で完結（CLI 経由しない） |
| 4 | `npx vibehawk setup-token --repo <owner>/<repo>` → GitHub Settings UI で `CLAUDE_CODE_OAUTH_TOKEN` を手動登録 | CLI が `claude setup-token` 実行を案内 → 取得した token を明示同意の上クリップボードにコピー（stdin 経由） → 利用者が Settings UI で貼付 |
| 5 | `vibehawk-review.yml` を `.github/workflows/` に配置 | App Installation Token 認証で workflow が動作 |
| 6 | PR を作成 | `vibehawk-for-<owner>[bot]` 名義でレビューサマリ投稿 |

経路 1（`secrets.GITHUB_TOKEN` + `github-actions[bot]` 投稿）は Issue #22 修正時点の妥協経路だが、Issue #61 で OSS 利用者の標準経路として認めない方針に確定した（理由: ブランド統制 / 商標保護 / 利用者可視化）。

## 画面遷移・データフロー

（画面遷移図やデータフローの概要を記載）

## 用語集

| 用語 | 定義 |
|---|---|
| `vibehawk` | vibe + hawk（鷹）。CodeRabbit の「うさぎ（速さ・量）」に対し「鷹（精度・観察力・全体俯瞰）」のメタファーで対置。vibe シリーズ（vibecorp / vibemux / vibehawk）の一貫性 |
| severity 5 段階 | Critical (🔴) / Major (🟠) / Minor (🟡) / Trivial (🔵) / Info (⚪) の 5 段階で重大度を判定する。各レベルの定義は `.claude/rules/severity/claude-action.md`（vibecorp 実体版、CodeRabbit 公式仕様と完全一致）を参照 |
| インクリメンタルレビュー | 2 回目以降のレビューで前回見た範囲を記憶し、差分のみ見る挙動 |
| sticky review state | 未解決指摘ありなら request_changes、全解決なら approve に切り替わる仕組み |
