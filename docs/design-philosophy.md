# 設計思想

> [!NOTE]
> 本ドキュメントは vibehawk に導入された vibecorp プラグインの設計思想を引き継ぐ。
> vibehawk 固有のカスタマイズはこのファイルへ追記する。

## 状態管理ポリシー（vibehawk 固有）

vibehawk は専用データストアを持たない。
状態はすべて GitHub の既存リソース（Issue / PR / Comment / Label / Workflow 状態）に置く。

### 根拠

- Mission「レビューツールに追加課金が要らない世界をつくる」の構造的根拠。
  専用 DB を持てば運用費が発生し、Value 1「利用者の契約だけで、完結させる」を裏切る。
- 利用者は既に GitHub に支払い済み。
  vibehawk が別の場所に状態を置いた瞬間、経済構造が崩れる。

### 含意

- セッション間で保持したい情報は Issue/PR コメントまたはラベルに書く。
- 集計が必要な場合は GitHub API で都度取得する（キャッシュ層を独自に持たない）。
- 「DB を入れれば速い / 楽」という誘惑が来たら、Mission への裏切りになっていないかを問い直す。

## vibehawk 固有の設計判断

### 価値の源流: 追加課金ゼロ

開発者は AI に対して 3 つの支払い経路を持つ。

1. AI レビュー専用 SaaS の月額（CodeRabbit Pro / Greptile 等）
2. LLM API の従量課金（PR-Agent BYOK 等）
3. LLM サブスクリプションの月額（Claude Pro / ChatGPT Plus 等、業務で既に日常利用）

3 を既に払っている開発者にとって、1 と 2 は「同じ AI 機能に二重で金を払う」状態。
vibehawk は 3 の枠内で完結し、1 と 2 をゼロ化する。

### 実現条件 4 つ（既に揃っている）

| # | 条件 | 状態 |
|:-:|------|:----:|
| 1 | LLM プロバイダー公式 Action がサブスクリプション OAuth に対応 | 公式リリース済み |
| 2 | 公式ドキュメントが CI 自動利用を案内 | 規約・実装ともに OK |
| 3 | レビュー機能が `workflow + プロンプト` だけで成立する技術スタック | 90%+ の機能が実装可能 |
| 4 | 同等品質のレビュー実装が本番運用で実証済み | vibecorp 内で運用中 |

### 競合不能構造

| 競合タイプ | 真似できない理由 |
|---|---|
| LLM SaaS 競合 | 自社 LLM コスト丸かぶり → 赤字確定で無料化できない |
| BYOK OSS 競合 | LLM プロバイダー公式 OAuth Action がないとサブスク枠で実行不可 → API 従量課金しか使えない |

必須 3 点セット:

1. LLM プロバイダー公式 Action
2. サブスクリプション OAuth
3. 同等品質のレビュープロンプト

この 3 点が揃って OSS 配布されたものは現時点で市場に存在しない。

## 認証経路の設計（経路 2 必須化、Issue #61 で確定）

vibehawk は以下の 2 系統 + 3 secrets 構成を採用する。

- 利用者ごとに独立した GitHub App `vibehawk-for-<owner>` の Installation Token
- Claude OAuth Token

配布方式の判断根拠は [`docs/secrets-handling.md`](secrets-handling.md) を参照（メジャーサービス比較 / GitHub 公式ガイドライン / CodeRabbit 事件教訓を網羅）。

| 系統 | secret 名 | 役割 | 当事者 | 設定方法 |
|---|---|---|---|---|
| GitHub App ID | `VIBEHAWK_APP_ID` | App Installation Token 取得用 | 利用者本人の `vibehawk-for-<owner>` App | **利用者が GitHub Settings UI で手動登録** |
| GitHub Private Key | `VIBEHAWK_PRIVATE_KEY` | App Installation Token 取得用 | 利用者本人の `vibehawk-for-<owner>` App | **利用者が GitHub Settings UI で手動登録** |
| LLM 認証 | `CLAUDE_CODE_OAUTH_TOKEN` | claude-code-action 経由の LLM 呼び出し | 利用者の Claude Pro / Max 契約 | **利用者が GitHub Settings UI で手動登録** |

**設計判断（Why 経路 2 + 全手動）**

- **利用者ごと独立 App**: 集中 SaaS App（CodeRabbit 等）が抱える「1 鍵漏洩で全利用者波及」の構造リスクを構造的に回避する。
  Private Key 漏洩の影響範囲は利用者本人のリポジトリ群に限定される。
- **CLI が secret を一切 touch しない**: GitHub 公式ガイドライン（"native client must never ship private key"）に完全準拠する。
  npm サプライチェーン攻撃 / typosquatting / gh CLI 権限借用といった Critical 攻撃面を設計レベルで消滅させる。
- **Value 1 整合**: 利用者本人の契約・本人の App・本人の手動登録で完結する。
  CEO のサーバー / Private Key / API キーが介在しない。

**Issue #22 認識見直しの経緯**

Issue #22（2026-05-08）では「CEO の GitHub App Private Key を利用者に配布する設計」が OSS 配布不可能と判定され、`secrets.GITHUB_TOKEN` 1 系統経路（経路 1）に妥協した。
ただし当時の判定は「集中 1 個の App Private Key を全利用者に配布」と「利用者ごとに独立した App を利用者本人が作成・運用」を区別していなかった。
後者では Private Key 漏洩の影響範囲が利用者本人に限定されるため、Value 1 と整合する。

2026-05-09 の C*O 統合議論で本認識見直しが共有され、CEO 判断により経路 2 必須化が確定した（Issue #72）。
経路 1（`secrets.GITHUB_TOKEN` + `github-actions[bot]` 投稿）は OSS 利用者の標準経路として認めない。
CLI による secret 自動書込はせず利用者が GitHub Settings UI で 3 secrets を手動登録する全手動方針を採用する（Issue #74 で `cli/oauth.js` の `gh secret set` 撤去済）。

**v2 以降の拡張検討（参考）**

将来 dogfooding / CEO 自動運用フローを拡張する場合も、本セクションの原則（CLI が secret を一切 touch しない / 利用者ごと独立 App / 利用者本人が GitHub Settings UI で手動登録）は維持する。
Anthropic 公式 `claude` App の仕組み調査と業界動向追従は `docs/secrets-handling.md` § 9 関連 Issue で継続する。

## localhost callback 採用根拠（Issue #37 追記）

> [!NOTE]
> **CTO sign-off**: 本セクションの設計根拠（POLICY.md 大方針 4 / GitHub App Manifest Flow 仕様 / Value 1 整合の 3 点）は CTO レビュー (Issue #37 / PR #96) で承認済み。
> 命名統制理由は本セクション後半の「技術選定理由（Issue #37 追記）」に記載。

`npx vibehawk install` は GitHub App Manifest Flow のコールバック先として、利用者ローカルの一時 HTTP サーバー（`127.0.0.1:8765`）を使う。
vibehawk 運営側は webhook 受信サーバーを持たない。
CLI 実装は `cli/manifest.js` に閉じ、`callback_urls` / `redirect_url` は localhost に固定される。

### 設計根拠

1. **POLICY.md 大方針 4「専用 DB を持たない」と整合する唯一の選択肢**:
   webhook 受信サーバーを vibehawk 側で立てれば、callback の到着を保持・突合する状態管理が不可避になる。
   複数利用者が同時に install した場合、どの一時 code が誰のものかを区別する必要が出る。
   それは「内部 DB / ベクタ DB / 専用サーバーを一切持たない」という大方針 4 を構造的に破る。
   localhost callback なら状態は利用者本人のローカルプロセス内に閉じ、運用側はサーバーもストレージも持たずに済む（`docs/POLICY.md` § 大方針 4 参照）。

2. **GitHub App Manifest Flow の仕様で十分**:
   GitHub App Manifest Flow は `redirect_url` を任意の URL で指定でき、HTTPS 化された公開エンドポイントは要求されない。
   一時 `code` を `POST https://api.github.com/app-manifests/<code>/conversions` に渡す処理さえできれば App credentials が取得できる。
   `127.0.0.1:8765` の素朴な HTTP サーバーで十分要件を満たす（公式仕様: `docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest`）。

3. **Value 1「利用者の契約だけで、完結させる」整合**:
   localhost callback は利用者本人のマシン内で完結し、vibehawk 運営側は通信経路にも一時 code にも一切関与しない。
   webhook サーバーを持つ瞬間、vibehawk が「利用者の install 行為を観測できる立場」になり、個人情報・利用統計を扱う運用者責任が発生する。
   localhost callback はその責任そのものを構造的に回避する。

### claude-code-action `/install-github-app` との比較

claude-code-action は対話形式の `/install-github-app` コマンドで Anthropic 側が運用するエンドポイントを介して App 設置を案内する。
vibehawk はこのアプローチを採用しない。

| 観点 | claude-code-action `/install-github-app` | vibehawk localhost callback |
|---|---|---|
| 運用側サーバー | Anthropic 側のインフラが flow を仲介する | 運用側サーバーなし、利用者ローカルで完結 |
| 障害時の影響範囲 | Anthropic 側の障害が全利用者に波及し得る | 利用者本人のローカルプロセスに閉じる |
| Value 1 整合性 | サブスク契約と独立した運用者責任が発生 | 利用者の契約のみで完結 |

claude-code-action は Anthropic サブスクリプションの一部として運用コストを集中管理できる立場だが、vibehawk は「運用者として課金される側に回らない」設計を Mission と直結させているため、同じ手法を採れない。

### 含意

- `127.0.0.1:8765` は利用者環境で一時占有される。
  同一ポートが先行プロセスで使われている場合、CLI は失敗する（`docs/SECURITY.md` のポート占有記述参照）。
- callback URL を localhost に固定する仕様は「自宅サーバー化」を防ぐ構造的保証も担う。
  運用側が将来 vibehawk のために webhook サーバーを立てたとしても、CLI が `callback_urls` を localhost で発行している限り利用者の callback は運用側に届かない。
- ブラウザ自動オープンとローカル listen の組合せは vibehawk CLI のセキュリティ要件として `docs/specification.md` § CLI 仕様にも記述する。
  本セクションは「なぜそう作ったか」の根拠を保持し、実装手順は仕様書側に置く責務分離とする。

## 命名統制（Issue #25 採用）

`npx vibehawk install` で作成される GitHub App の名前は `vibehawk-for-<owner>` 形式に固定する。
利用者は名前を自由にカスタマイズできない。

### 設計根拠

1. **GitHub Apps の名前ユニーク制約への対応**:
   GitHub Apps はプラットフォーム全体で名前ユニークが要求される。
   `vibehawk` 単独だと先着 1 名しか作成できない（公式仕様: `docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app`）。
   `<owner>` 部分で名前空間を分離することで、すべての利用者がブランド `vibehawk` を含む App 名を持てる。

2. **ブランド統制**:
   全 bot 名に `vibehawk` を必ず含むことで、利用者リポジトリ上で「vibehawk が動いている」ことが視認できる。
   命名カスタマイズを許容するとブランドが分散して特定不能になる。

3. **Value 3「強制しない」との競合の透明化**:
   命名固定は本来 Value 3 と緊張する。
   これを `npx vibehawk install` 実行時に明示的に告知し、隠蔽せず利用者の選択肢として提示する（CPO 修正提案）。

### 技術選定理由（Issue #37 追記）

`vibehawk-for-<owner>` の固定形式は、GitHub Apps プラットフォームの命名制約とブランド要件のトレードオフを最適化した結果である。
各構成要素は単独でなく、同時に満たさなければならない要請の集合として理解する。

| 構成要素 | 内容 | 何の制約に応じているか |
|---|---|---|
| GitHub Apps 名前ユニーク制約 | GitHub Apps はプラットフォーム全体で名前ユニークが要求される。`vibehawk` 単独では先着 1 名のみ作成可能となる | GitHub プラットフォーム側の不可動制約（`docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app`） |
| `<owner>` プレフィックスでユニーク性を回避 | `<owner>` は GitHub user/org 命名規則（1-39 文字、英数字とハイフン）でプラットフォーム内ユニーク。`vibehawk-for-<owner>` の組合せも自動的にユニークになる | 上記制約を回避しつつ全利用者に共通形式を提供する設計判断 |
| ブランド統制と利用者識別性の両立 | `vibehawk-` プレフィックスで「vibehawk が動いている」をブランド可視化、`-for-<owner>` サフィックスで「どの利用者の bot か」を識別可能。両者を 1 つの App 名文字列で同時に満たす | vibehawk の運用要件（bot コメント一覧で「vibehawk 由来」を grep 可能にする） |

CodeRabbit の `coderabbitai[bot]` のような単一名空間アプローチとは設計の出発点が異なる。
CodeRabbit は集中 SaaS App で 1 つの App を全利用者で共有するため、bot 名はブランド統制に最適化できる。
vibehawk は利用者ごと独立 App（経路 2 必須化、Issue #61）を採用しているため、`<owner>` 部分による識別性が App 名に組み込まれる必要があり、この命名形式が必然となる。

### Value 3 との関係

vibehawk Value 3「強制しない」はエンドユーザー体験（生成コード形式・レビュー方針・口調等）に関する原則であり、本命名規則は vibehawk ブランド側の統制要件として位置づける。
経路 2 必須化（Issue #61）により `npx vibehawk install` は OSS 利用者の標準導入経路となっており、命名規則は全利用者に一貫して適用される。
利用者は導入時にこの命名統制を明示的に告知される（`npx vibehawk install` 実行時の同意プロンプト経由）。

### 同名衝突時の挙動

`vibehawk-for-<owner>` 名で同名 App が既に存在する場合、GitHub は自動的に連番を付与（`vibehawk-for-<owner>-2` 等）する場合がある。
この際 CLI は `printResult` で「想定名と実際の名前が異なる」旨を警告表示する。
利用者は既存の App を確認してから再実行することを推奨する。

## vibecorp とは

vibecorp は「AIエージェントを組織化してプロダクト開発を回す」仕組みをプラグインとして提供する。
バイブコーディング時代の AI企業キット。どのリポジトリにも導入できる。

## 3層アーキテクチャ

```text
MVV.md（最上位方針・ファウンダーのみ編集）
  ↓ 全エージェント・スキルの判断基準
docs/（Source of Truth・仕様書群）
  ↓ エージェントが参照・更新する設計情報
.claude/（実行層）
  ├── agents/    ← Role Agents のみ（判断 + knowledge蓄積する者）
  ├── skills/    ← ワークフロー定義（内部でAgent起動しモデル/ツール制御）
  ├── hooks/     ← ゲート制御（ファイル保護 + ワークフロー強制）
  ├── knowledge/ ← 役割別の判断基準・判断記録（運用中に蓄積）
  ├── rules/     ← 全エージェント共通のコーディング規約
  └── settings.json ← フック設定
```

## agents vs skills の設計原則

### agents に定義するもの（Role Agents）

持続的アイデンティティ + 自律判断 + knowledge蓄積を持つエンティティ:

- **C-suite + SM**: CTO, CPO, CFO, CLO, CISO, SM -- MVVに基づいて判断する専門家
- **チーム分析員**: accounting, legal, security -- 3回独立実行し、C-suiteがレビュー

特徴:
- 持続的なアイデンティティがある（「私はCTOです」）
- 自律的に判断し、`knowledge/{role}/decisions.md` に蓄積する
- 他エージェントと権限境界がある（管轄ファイルが異なる）

### skills 内のステップにするもの

アイデンティティや持続的な知識蓄積が不要なタスク実行:

- **CLI実行型**: CodeRabbit CLI、カスタムレビューコマンド等
- **タスク実行型**: 計画に基づくコード修正
- **判断するがアイデンティティ不要**: レビュー妥当性判定、修正計画策定（共通基準は `.claude/rules/severity/coderabbit.md` / `severity/claude-action.md` / `review-handling.md` / `review-observations.md` に定義）

いずれもスキル内のステップとして直接実行する。

### 判断フローチャート

```text
そのエンティティは...

1. 持続的なアイデンティティがある？（「私はCTOです」）
   → No → スキル内のステップ
   → Yes ↓

2. 自律的に判断し、knowledge に蓄積する？
   → No → スキル内のステップ（Agent起動時に model/tools を指定）
   → Yes ↓

3. 他エージェントと権限境界がある？
   → Yes → agents/ に定義する
```

## プラグイン配布方式: Claude Code 規約パスへの直接配置

```text
導入先リポジトリ:
├── .claude/
│   ├── hooks/           ← フック（ファイル保護等）
│   ├── skills/          ← スキル（Claude Code の /コマンド）
│   ├── rules/           ← コーディング規約
│   ├── vibecorp.yml     ← プロジェクト設定
│   ├── vibecorp.lock    ← バージョン固定 + マニフェスト
│   ├── settings.json    ← フック設定（マージ管理）
│   └── CLAUDE.md        ← プロジェクト指示
├── .github/
│   └── workflows/
│       └── test.yml     ← CI ワークフロー
├── .coderabbit.yaml     ← CodeRabbit 設定
└── MVV.md               ← 最上位方針
```

設計上の重要な判断:

- **独自名前空間を持たない**:
  `.claude/vibecorp/` のような独自ディレクトリは作らない。
  全ファイルを Claude Code の規約パス（`.claude/hooks/`, `.claude/skills/`, `.claude/rules/`）に直接配置する。
  Claude Code が認識しないパスにファイルを置くことは、プラグインとして意味がない。

- **lock をマニフェストとして使う**:
  `vibecorp.lock` に vibecorp が管理するファイルの一覧を記録する。
  lock に載っている = vibecorp 管理、載っていない = ユーザー作成。
  更新時は lock を参照して vibecorp 管理ファイルのみ差し替える。

- **.gitignore の判断はユーザーに委ねる**:
  vibecorp は `.gitignore` を操作しない。`.claude` を gitignore するか git 管理するかは導入先プロジェクトの判断。
  生成物を一括 gitignore する案（node_modules パターン）は却下した。
  vibecorp の生成物は rules, skills, CLAUDE.md 等のチームがレビュー・カスタマイズする人間可読な設定であり、node_modules のような第三者コードとは性質が異なる。
  PR でのレビューを可能にするため、git 管理を推奨する。

- **settings.json はマージ管理**:
  vibecorp 由来フック（パスに `.claude/hooks/` を含む）のみ操作し、ユーザー独自フックは保持する。

- **Public 前提**:
  vibecorp リポジトリ自体はテンプレートのみで実データを含まない公開前提の設計。

### 生成物をフックで保護しない理由

vibecorp が生成した skills, rules, hooks を protect-files フックで保護する案は却下した。

- **生成物はユーザーのもの**:
  プラグインが生成したファイルであっても、ユーザーが自由に編集できるべき。
  npm が `node_modules/` を保護しないのと同じ原則。
- **復元は再実行で可能**:
  ユーザーが誤って壊しても `install.sh` を再実行すれば元に戻る。
- **保護はビジネスルールに限定**:
  protect-files が守るのは MVV.md のような「ファウンダーの方針」であり、「vibecorp が生成したから」という理由でファイルを保護するのはプラグインの越権行為。

## 3つの組織規模プリセット

| プリセット | agents | hooks | ユースケース |
|---|---|---|---|
| **minimal** | なし | protect-files, protect-branch | 個人〜小規模 |
| **standard** | CTO, CPO | + review-to-rules-gate, sync-gate, session-harvest-gate, review-gate | チーム開発 |
| **full** | C-suite全員 + 分析員 | + role-gate | AI企業・コンプライアンス重視 |

各プリセットに含まれるスキル:

- **minimal**: /vibecorp:review, /vibecorp:review-loop, /vibecorp:pr-fix, /vibecorp:pr-fix-loop, /vibecorp:pr, /vibecorp:commit, /vibecorp:issue, /vibecorp:ship, /vibecorp:plan, /vibecorp:branch, /vibecorp:plan-review-loop
- **standard**: 上記 + /vibecorp:review-to-rules, /vibecorp:sync-check, /vibecorp:sync-edit, /vibecorp:session-harvest, /vibecorp:harvest-all
- **full**: 上記 + /vibecorp:diagnose, /vibecorp:ship-parallel, /vibecorp:autopilot, /vibecorp:spike-loop

## フック設計パターン

### ファイル保護型

- **protect-files.sh**: 保護ファイルの編集をブロック（`protected_files` で設定可能）
- **protect-branch.sh**: メインブランチ（`base_branch`）での Edit/Write/git commit をブロック
- **role-gate.sh**: エージェントの役割に応じたファイル編集権限制御（full のみ）

### ワークフローゲート型

- **review-to-rules-gate.sh**: `gh pr merge` 前に `/vibecorp:review-to-rules` 完了を強制
- **sync-gate.sh**: `git push` 前に `/vibecorp:sync-check` 完了を強制（standard 以上）
- **session-harvest-gate.sh**: `gh pr merge` 前に `/vibecorp:session-harvest` 完了を強制（standard 以上）
- **review-gate.sh**: `gh pr create` 前に `/vibecorp:review` または `/vibecorp:review-loop` 完了を強制（standard 以上）

いずれも `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state/<repo-id>/{gate名}-ok` 形式のステートファイルで状態管理する（後述「ゲートスタンプの保存先」セクション参照）。
ステートは確認後に自動削除される（ワンタイム）。
`<repo-id>` は worktree の絶対パスから生成されるため、ブランチ単位で自然に分離される。

### API バイパス防止型

- **block-api-bypass.sh**: `gh api` による直接マージ（`pulls/{number}/merge`）と `@coderabbitai approve` の投稿をブロック。
  auto-merge 環境ではこれらがレビュープロセスの迂回手段になるため、エージェントの利用を禁止する。

### コマンドログ型

- **command-log.sh**: 全 Bash コマンドをログファイル（`$CLAUDE_PROJECT_DIR/.claude/state/command-log`）に記録する。
  判定は返さない（ログ記録のみ）。
  `/vibecorp:approve-audit` スキルと組み合わせて `settings.local.json` の allow リスト最適化に使用する。

## スキル設計原則

### プリセット自己完結の原則

各プリセットに含まれるスキルは、そのプリセット内で完結しなければならない。
スキルが参照するコマンド・スキルは、同じプリセットに必ず存在すること。

- NG: minimal の `/vibecorp:pr-fix-loop` が standard にしかない `/vibecorp:review-to-rules` を呼ぶ
- OK: minimal の `/vibecorp:pr-fix-loop` が minimal の `/vibecorp:pr-fix` を呼ぶ

### preset 条件分岐型エージェントゲート

プリセット自己完結の原則の例外として、スキル内で preset を確認し、上位プリセットでのみエージェントを呼び出すパターンを許容する。

- `/vibecorp:issue` は minimal プリセットに含まれるが、内部で `vibecorp.yml` の preset を確認する。
- `standard` または `full` の場合のみ CPO エージェントをゲートとして呼び出す（プロダクト整合チェック）。
- `minimal`、vibecorp.yml が存在しない、または preset キーが未定義の場合はゲートをスキップして動作する。

この設計により、スキル自体は minimal に配置しつつ、上位プリセットでは追加のガードレールが有効になる。
デフォルト（minimal）でも完全に動作するため、プリセット自己完結の原則には反しない。

### 拡張ポイントの設計

ユーザー設定（vibecorp.yml）による拡張は許容するが、デフォルトで動作することが前提。
拡張ポイントはデフォルト空で、ユーザーが意図的に追加した場合にのみ動作する。

- `review.custom_commands`: デフォルト空。ユーザーが追加すれば `/vibecorp:review` 内で並列実行される
- スキルは `custom_commands` が空でも CodeRabbit CLI のみで正常に動作する

### スキル・フックのトグル設定

プリセットで配置された skills / hooks は、`vibecorp.yml` の `skills:` / `hooks:` セクションで個別に有効/無効を切り替えられる。

```yaml
skills:
  commit: true
  review-to-rules: false
hooks:
  protect-files: true
  sync-gate: false
```

設計原則:

- **opt-out 方式**: キーを省略した場合は有効扱い。明示的に `false` を指定した場合のみ無効化される。
- **プリセット削除が先**: プリセットによるファイル選択が先に適用され、その後トグルでさらに絞る。
- **インストール時に反映**: `install.sh` 実行時（初回・`--update` 両方）にトグル設定を評価し、無効化されたファイルはコピー対象から除外・削除される。
- **settings.json にも反映**: 無効化された hooks は `settings.json` の hooks エントリからも除外される。

## リポジトリインフラ設定

vibecorp は Claude Code の実行層だけでなく、開発ワークフロー全体を支えるリポジトリインフラ設定もテンプレートとして提供する。
スキルやフックが正しく機能するには、CI・レビュー・ブランチ保護が連動している必要があるため、これらをセットで提供する。

### CI ワークフロー（`.github/workflows/test.yml`）

- `tests/test_*.sh` を自動実行する CI ワークフローを提供する
- matrix ジョブ（macOS / Ubuntu）の結果を `test` ジョブに集約し、Branch Protection の required check として機能させる
- `push` + `pull_request` の両方でトリガーし、`concurrency` グループで同一ブランチの重複実行を防止する

### CodeRabbit 設定（`.coderabbit.yaml`）

- `/vibecorp:pr-fix-loop` が前提とする CodeRabbit の挙動を設定する。
- `request_changes_workflow: true` — 指摘0件なら approve、指摘ありなら request changes、全コメント resolve 後に approve に切り替える。
  Branch Protection の「Require approvals」と連動して auto-merge を実現する。
- `auto_resolve.enabled: true` — push 時に修正済みのレビューコメントを自動 resolve する。
  `/vibecorp:pr-fix-loop` の「修正した指摘は返信不要」方針の前提。
- `language: ja-JP` — レビューコメントを日本語で出力（`vibecorp.yml` の `language` と連動）。
- 各設定値と `/vibecorp:pr-fix-loop` のステップとの対応は `docs/ai-review-dependency.md` の「CodeRabbit 設定値の根拠（参考）」セクションを参照。

### Branch Protection（GitHub 設定）

GitHub API でしか設定できないため、`install.sh` から `gh api` で自動適用する（権限不足時はフォールバックとして推奨設定を表示）。

- **Require a pull request before merging** — 直接 push を防止。
- **Require approvals** (1以上) — CodeRabbit の approve を必須化。
- **Dismiss stale pull request approvals when new commits are pushed** — push 後に approve をリセットし、再レビューを強制する。
  auto-merge との組み合わせで、未レビューのコードがマージされることを防止。
- **Required status checks**: `test` — CI 集約ジョブの通過を必須化。

### マージ戦略（GitHub 設定）

- **Allow squash merging のみ有効化** — ブランチ単位で1コミットにまとまり、履歴がクリーンに保たれる。
- **Allow auto-merge 有効化** — required checks パス + approve 後に自動マージ。
  `/vibecorp:pr` が `gh pr merge --auto --squash` で設定し、条件達成時に GitHub が自動マージする。
  `/vibecorp:pr-fix-loop` はレビュー修正に特化し、マージは auto-merge に委ねる。

### 設計判断

- **セットで提供する理由**: CI・CodeRabbit・Branch Protection は相互依存している。
  CI の集約ジョブ名が Branch Protection の required check と一致しなければ永遠に pending になり、CodeRabbit の `request_changes_workflow` が無効なら approve が出ずマージできない。
  個別に手動設定させると不整合が起きるため、vibecorp がセットで提供する。
- **テンプレートとして配布**: `.github/workflows/test.yml` と `.coderabbit.yaml` は `install.sh` でテンプレートから配置する。
  ユーザーがカスタマイズ可能（skills/hooks と同じ原則）。
  `.coderabbit.yaml` の配置は `vibecorp.yml` の `coderabbit.enabled`（デフォルト: `true`）で制御され、`false` 時は生成されない。
- **GitHub API 設定はベストエフォート**: Branch Protection とマージ戦略は `gh api` で設定するが、権限不足の場合は推奨設定を表示してユーザーに手動設定を促す。

## --update モードの設計判断

`install.sh --update` は「vibecorp 管理ファイルの差し替え」と「ユーザー作成ファイルの保護」を両立する。

### ファイル削除の非対称性

- **hooks / skills / agents**: lock 記載の管理ファイルを削除し、テンプレートから再配置する。
- **knowledge**: 運用中にユーザー（エージェント）が蓄積したデータのため、`--update` でも削除しない。
- **rules**: `--update` 時はテンプレート由来の rules を上書きする。
  ユーザーが独自に追加した rules（テンプレートに存在しないファイル名）は影響しない。
- **docs**: ユーザーが内容をカスタマイズ済みの前提で、既存ファイルはスキップする。

### Branch Protection の既存設定との共存

`install.sh` は Branch Protection の required status checks を設定する際、既存の checks を破壊しない:

1. 既存の required status checks を GitHub API で取得する
2. vibecorp が必要とする checks（`test`, 任意で `CodeRabbit`）と UNION をとる
3. 重複を排除してソートした結果を PUT する
4. 既存の checks 取得に失敗した場合（権限不足等）は上書きリスクを避けるため自動設定をスキップし、手動設定のガイダンスを表示する

### vibecorp.lock のセクション構造

lock はインストール時に配置されたファイルの完全なマニフェストを記録する:

```yaml
files:
  hooks:       # テンプレート由来かつ配置先に存在するもの
  skills:      # 同上
  agents:      # 同上
  rules:       # コピー時に実際にコピーされたもの（既存スキップ分は含まない）
  issue_templates:  # 同上
  docs:        # 同上
  knowledge:   # 同上
```

「テンプレートに存在し、かつプリセット削除後も配置先に残っているもの」のみ記録される。
これにより `--update` 時に vibecorp 管理ファイルだけを正確に差し替えできる。

## スキル実行時のエラーハンドリング方針

### コマンドリダイレクト・フォールバックの禁止

スキル（SKILL.md）内で Bash コマンドを実行する際、以下のパターンを禁止する:

- `2>/dev/null` — 標準エラー出力のリダイレクト
- `|| echo ""` — エラー時のフォールバック出力
- `; echo ""` — 無条件の後続出力
- `|| true` — 終了コードの握りつぶし

### 根拠

Claude Code のスキル実行アーキテクチャでは、コマンドの終了コードと標準エラー出力がエラー検知の唯一の手段である。
リダイレクトやフォールバックを付加すると以下の問題が発生する。

1. **エラーの隠蔽**: `2>/dev/null` はコマンドが失敗した理由を消し去る。
   Claude Code はエラー出力を読んで次のアクションを判断するため、エラー情報の欠落は誤った判断に直結する。
2. **終了コードの偽装**: `|| echo ""` や `|| true` はコマンド失敗を成功に見せかける。
   スキルのフロー制御がエラーを検知できなくなり、後続ステップが不正な前提で実行される。
3. **デバッグの困難化**: エラーが抑制されると、スキルが期待通りに動かない場合に原因特定が著しく困難になる。
   エラーメッセージが残っていれば即座に特定できる問題が、沈黙した出力からは判断できない。
4. **フック・ゲートの無力化**: `sync-gate.sh` 等のワークフローゲートはコマンドの終了コードで通過/拒否を判断する。
   終了コードを握りつぶすとゲートが素通りになり、ワークフローの強制が機能しなくなる。

### 正しい対処

コマンドがエラーを返した場合、リダイレクトで隠すのではなく:

- エラー出力をそのまま Claude Code に返し、スキルのフロー内で適切に処理する
- 想定されるエラー（ファイルが存在しない等）は事前チェックで回避する
- 回復不能なエラーはスキルを中断してユーザーに報告する

## プロセス隔離（Phase 1 PoC）

### PATH シム方式

vibecorp は Claude Code 本体を書き換えず、ユーザーの PATH 先頭に薄いラッパー（`templates/claude/bin/claude`）を配置することでサンドボックスを挟み込む。
本体ファイルの侵食がなく、UX や他のコマンドライフサイクルへの影響を最小限に留める。

### opt-in 設計

デフォルトは passthrough。
`VIBECORP_ISOLATION=1` を明示した場合のみ sandbox 経由で起動する。
Phase 1 PoC 段階のため、意図しない環境で隔離が有効になることを防ぐ。

### 二重サンドボックス防止

`VIBECORP_SANDBOXED=1` 環境変数と PPID チェーン検証の AND 条件で passthrough を判断する。
環境変数単独では外部注入によるバイパスが可能なため、祖先プロセスに `sandbox-exec` が存在することをあわせて確認する。

### OS ディスパッチャの抽象化

OS 判定を `vibecorp-sandbox` に閉じ込め、Phase 1 では Darwin（macOS の sandbox-exec）のみ実装する。
Linux 向けの bwrap 対応は Phase 2 以降の拡張余地として確保する。

### 境界パラメータの symlink 解決と 2 段階検証

`WORKTREE` / `HOME` 等の境界パラメータは raw バリデート（絶対パス確認）の後、`(cd "$p" && pwd -P)` で symlink を解決してから再度バリデートする 2 段階検証を行う。
macOS の `$TMPDIR` は `/var/folders/...` で `/private/var/...` の symlink であるため、解決前後の混在比較を行うと包含判定が崩れる。

### WORKTREE が HOME を包含する設定の拒否

`WORKTREE=/Users` のような設定は sandbox-exec の `(subpath (param "WORKTREE"))` 経由で `~/.ssh` / `~/.aws` を書込み対象に含めてしまう。
canonicalize 後に `case "${HOME_VALUE}/" in "${WORKTREE_VALUE}/"*)` で WORKTREE が HOME を包含するケースを入口で拒否する。

### 境界定義の正典

macOS sandbox-exec プロファイルの許可・拒否境界（書込許可パス・読取許可パス・ioctl 許可デバイス、`literal` / `subpath` の使い分け、network/process 制約等）の詳細は `.claude/sandbox/claude.sb` の全体（ヘッダコメント + SBPL ルール本文）を正として参照すること。
本セクションは設計思想の記述であり、個々のパス・ルールを逐次列挙するスコープではない。

## ゲートスタンプの保存先

### `.claude/` 外への切り出し

`/vibecorp:sync-check`、`/vibecorp:session-harvest`、`/vibecorp:review-to-rules`、`/vibecorp:review-loop` が発行するゲートスタンプは XDG Base Directory 仕様に準拠し `${XDG_CACHE_HOME:-$HOME/.cache}/vibecorp/state/<repo-id>/` 配下に配置する。
`.claude/` 配下への書込みは Claude Code の `--dangerously-skip-permissions` でも確認プロンプトが発生するため、スタンプ発行が連続するスキルワークフロー（PR 作成からマージまで最大 4 回）の UX を阻害する。

### `<repo-id>` 構成

`<sanitized-basename>-<sha8>` 形式。
basename は `git rev-parse --show-toplevel` の basename を `tr -cs 'A-Za-z0-9._-' '_'` でサニタイズ、sha8 は同 toplevel パスの SHA-256 先頭 8 文字。
multi-repo 共存時の衝突を回避する。

### sandbox-exec 内動作（VIBECORP_ISOLATION=1）

`~/.cache/vibecorp/` は claude.sb の writable subpath に追加されており、隔離レイヤ内でも gate hook がスタンプを書き込める。
親ディレクトリ `~/.cache/` の作成は sandbox 内で拒否されるため、install.sh が起動時に `~/.cache/vibecorp/state/` を pre-create する（`chmod 700` 適用）。

### 脅威モデル

スタンプは存在チェックのみで内容検証を行わない。
同一ユーザー内の任意プロセスからの偽造は本設計のスコープ外（信頼境界 = ユーザーアカウント）。
ディレクトリは `chmod 700` で他ユーザーからの偽造のみブロックする。
HMAC や PID 埋め込みは v1 では採用しない。

### デバッグ手順

スタンプの実体パスを確認するには:

```bash
source .claude/lib/common.sh
vibecorp_stamp_dir
# → /Users/me/.cache/vibecorp/state/vibecorp-a1b2c3d4
```

gate hook 失敗時はこのディレクトリ内の `<name>-ok` ファイル有無で原因を切り分けられる。

## @vibehawk コマンド体系の設計（epic #289 で確定）

> [!IMPORTANT]
> resolve イベントへの自動反応は GitHub Actions では構造的に実現できない。
> だから vibehawk は `@vibehawk` **コマンド駆動**（`issue_comment` トリガー）で CodeRabbit のコマンド群を再現する。
> parity の対象は **観察・通知系のみ**。書き換え系は MVV Value 2 により恒久対象外とする。

CodeRabbit には「PR のコメントを全て resolve すると自動で approve に切り替わる」挙動がある。
vibehawk で同じ「resolve したら自動で再判定」を **resolve イベント起点では実装しない** と決めた。
代わりに利用者が `@vibehawk` コマンドを投稿したときに再判定する方式を採る。

### 決定の一言要約

| 項目 | 内容 |
|------|------|
| 採用 | `@vibehawk` コマンド駆動（`issue_comment` トリガー、`vibehawk-chat.yml` 基盤） |
| 却下 | resolve イベント自動反応（`pull_request_review_thread` トリガー） |
| parity 範囲 | 観察・通知系コマンドのみ |
| 恒久対象外 | コード・ファイルを書き換える系コマンド（MVV Value 2） |

### 根拠 1: resolve 自動反応は Actions で startup_failure になる

`pull_request_review_thread`（resolved / unresolved）は GitHub の **webhook イベント** としては存在する。
しかし GitHub Actions の `on:` トリガーとしては **使えない**。
`on:` に書いた workflow は **startup_failure** で起動せず、`vibehawk` required status check が永久に post されない。
その結果 PR が恒久ブロックされる。

- 📍 実証: Issue #287 / PR #288 はこの方式を試し、startup_failure を再現して close 済み。
- この事実は「推測」ではなく実際の Actions 実行ログで確認した外部仕様。

### 根拠 2: CodeRabbit が resolve に反応できるのはアーキ差（劣後ではない）

| 観点 | CodeRabbit | vibehawk |
|------|-----------|----------|
| 実行基盤 | webhook サーバを持つ GitHub App | GitHub Actions |
| resolve webhook の受信 | 自前サーバが直接受信できる | Actions の `on:` では受信不可 |
| resolve 起点の自動 approve | 可能 | 不可（基盤の制約） |

vibehawk が resolve に自動反応「しない」のは品質の劣後ではない。
サーバを持たない（MVV Value 1）という構造選択の必然的な帰結である。

### 根拠 3: コマンド駆動なら同じ価値を公式の道で再現できる

`issue_comment` は Actions の正規トリガーである。
利用者が `@vibehawk review` 等を投稿した時点で workflow が起動し、最新差分で再判定できる。
これは「resolve したら更新される」価値を、利用者の明示操作に置き換えて再現するものである。
Value 4「公式の道を、迂回せず歩く」とも整合する。

### parity の線引き（MVV Value 2「観察する、書き換えない」）

再現するのは **観察し、伝えるだけ** のコマンドに限る。
コードや PR メタデータを **書き換える** コマンドは恒久的に実装しない。

| 区分 | コマンド | 方針 |
|------|---------|------|
| ✅ 再現（観察・通知系） | review / full review / resolve / summary / help / configuration / pause / resume / ignore | epic #289 で実装 |
| ❌ 恒久対象外（書き換え系） | autofix / generate docstrings / generate unit tests / generate configuration | MVV Value 2 違反のため実装しない |

書き換え系を実装しないのは CodeRabbit に劣るからではない。
「観察し、伝えるところで止まる」という vibehawk の核を守る **意図的な差別化** である。
この恒久対象外は新規制約ではなく、`docs/POLICY.md` 大方針 2（コード生成系を実装しない）の追認にあたる。

### 関連

- MVV: `MVV.md` Value 2「観察する、書き換えない」 / Value 4「公式の道を、迂回せず歩く」
- やらない範囲（書き換え系の WHAT 記録）: `docs/specification.md`「やらない範囲（明示的除外）」
- 各コマンドの個別仕様: `docs/specification.md`（実装に伴い各 PR で更新）

## ガードレール

- **Public Ready**: セキュリティ情報・特定プロダクト名・ローカルパス依存の混入禁止。
- **品質基準**: 参照元の実装を全網羅し、品質・汎用性・堅牢性で上回る。
- **テスト必須**: hooks / install.sh は自動テスト付き。テストなしで push しない。

## 🔗 関連

- プロダクト仕様書: `docs/specification.md`
- ファイル配置ポリシー: `docs/file-placement.md`
- セキュリティポリシー: `docs/SECURITY.md`
- 秘密情報配布方式の判断根拠: `docs/secrets-handling.md`
- 認証経路影響評価: `docs/route2-impact-analysis.md`
- AI レビュー依存マップ: `docs/ai-review-dependency.md`
