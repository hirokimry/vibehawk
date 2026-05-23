# 🏷️ intent ラベル規約

> [!IMPORTANT]
> vibecorp の **Issue** には `intent/*` ラベルを **必ず 1 つだけ** 付与する。**PR には intent ラベルを付与しない**（Issue #575 確定: intent の SoT は Issue ラベル、PR は CC prefix が機械可読保険）。
> 判定の主従順は **intent ラベル（主）→ CC prefix（従）**。逆引きは行わない。
> 判定主体は **COO（メインセッション）** が Issue 本文を LLM 文脈理解で読み、7 種から 1 つを確定する。

レビュー判定（intent × severity）と PR スコープを狭く保つ運用のために、Issue ラベルを Source of Truth とする intent 体系を定める。

## 🪜 Issue 番号解決の 4 段フォールバック

レビュー判定（intent × severity）は `pr-fix` / `review-loop` が以下の **4 段フォールバック** で Issue 番号を解決し、`gh issue view --json labels` で intent を直接取得する。

1. `closingIssuesReferences`（GitHub 自動 close キーワード由来）
2. PR 本文 grep（`#N` 形式 + GitHub URL 形式、`pr-issue-link-check.yml` 互換）
3. ブランチ名（`dev/<num>_*` パターン）
4. 空（**severity-only fallback**: Critical / Major のみ修正対象、Minor 以下スキップ）

### ↩️ revert PR の扱い

`revert` は CC prefix としては独立しているが、intent ラベルとしては **Issue 側に `intent/bugfix` を付与する**（差し戻しの本質は「直前の commit が引き起こした問題を取り消す」= バグ修正の一形態）。

- Issue 側 `intent-label-issue-check.yml` ジョブは Issue 単位でラベル不在を fail させる
- revert PR で Issue が紐づかない hotfix 的 revert は、レビュー判定が **severity-only fallback**（Critical / Major のみ修正対象、Minor 以下はスキップ）に切り替わる

## 🎯 intent ラベル 7 種

| ラベル | 一言（何を重視するか） | カテゴリ |
|--------|----------------------|--------|
| `intent/feature` | 新機能を確実に動かす | 影響を与える系 |
| `intent/bugfix` | 既存バグを最小修正で直す | 影響を与える系 |
| `intent/performance` | 性能を測定可能な形で改善する | 影響を与える系 |
| `intent/security` | 脆弱性を塞ぐ | 影響を与える系 |
| `intent/refactor` | 構造の品質を高める（挙動不変） | 影響を与えない系 |
| `intent/infra` | 開発基盤の品質を底上げする（挙動不変） | 影響を与えない系 |
| `intent/docs` | ドキュメントの正確性を担保する（挙動不変） | 影響を与えない系 |

### 📂 大カテゴリ別の性質

| カテゴリ | 含まれるラベル | 性質 |
|---------|-------------|------|
| 影響を与える系 | feature / bugfix / performance / security | プロダクト挙動を変える |
| 影響を与えない系 | refactor / infra / docs | プロダクト挙動を変えない（挙動不変） |

### 🔍 「挙動不変性の確認」観点（影響を与えない系の必須チェック）

`intent/refactor` / `intent/infra` / `intent/docs` のラベルが付いた変更には、**挙動不変であることを必ず検証する**。

- リファクタ前後で観測可能な挙動が変わっていないか（公開 API、UI、ログ出力、副作用）
- インフラ変更でランタイム挙動に影響が出ていないか（ビルドフラグ、依存メジャー更新、CI 環境設定）
- ドキュメント変更が実コードの挙動を要求していないか（サンプルコードがコード本体に依存）

挙動が変わるものを「影響を与えない系」のラベルで通すと、レビュー観点が歪む（severity 判定で見逃し）。挙動が変わるなら必ず「影響を与える系」（feature / bugfix / performance / security）のラベルに付け替える。

## 🧭 主従関係（絶対条件）

| 役割 | 軸 |
|------|---|
| **主** | **intent ラベル**（vibecorp 独自要件、判定の起点） |
| **従** | **CC prefix**（業界標準、機械可読の保険） |

判定フロー: **intent → CC prefix の順で決める**。逆引き（CC prefix → intent）は行わない。

CC prefix の厳格定義と intent ラベル → CC prefix 対応表は `docs/conventional-commits.md` を参照。

## 🤖 判定主体: COO（FIX）

`/vibecorp:issue` で Issue 起票時、メインセッション（COO）が Issue 本文を読み、文脈判断で intent を確定する。

キーワード辞書ではなく LLM の文脈理解で判断する。

### 👥 役割分離

| 役職 | 主務 | intent 判定への関与 |
|------|------|-------------------|
| **COO**（メインセッション） | CEO 意図の解釈・委譲判断 | ✅ **intent 判定を直接行う**（本来役割） |
| CISO | 不可領域チェック | ❌ 触れない（ノイズなし） |
| CPO | MVV / 仕様整合チェック | ❌ 触れない（ノイズなし） |
| SM | 不可領域チェック | ❌ 触れない（ノイズなし） |
| CTO / CFO / CLO | 各専門領域 | ❌ 通常は呼ばれない |

「全体俯瞰して誰の領分か考える」のは COO 本来の役割（`.claude/rules/roles.md`）。スキル内で別途「全体俯瞰役」を召喚する必要なし。

### 🔄 判定フロー（既存 3 者承認ゲートと連携）

```text
/vibecorp:issue 起動
  │
  ├─ COO（メインセッション）が Issue 本文を読む
  │
  ├─ COO が intent を判定（7 種から 1 つ、絶対条件: 1 つだけ）
  │   - LLM の文脈理解で本文を読み、どの intent に該当するか確定
  │   - キーワード辞書ではなく柔軟な文脈判断
  │
  ├─ COO が intent に対応する CC prefix を選択
  │   - intent → prefix の主従順（絶対条件）
  │   - 同じ intent に対応する CC prefix が複数ある場合は内容に応じて選ぶ
  │
  ├─ COO がタイトルを CC prefix 付き形式（絵文字 + prefix + 動作主語）で整形
  │
  ├─ 既存 3 者承認ゲート（CISO + CPO + SM）を並列実行
  │   ├─ CISO: 不可領域チェック（主務）
  │   ├─ CPO: MVV / 仕様整合チェック（主務）
  │   └─ SM: 不可領域チェック（主務）
  │
  └─ 全 3 者 OK → gh issue create で起票（intent ラベル + 既存ラベル）
```

### ✨ この設計の特徴

| 観点 | 達成 |
|------|------|
| 主従順（intent → prefix） | ✅ COO が intent を先に決め、対応 prefix を選ぶ |
| 完全自動マッピング（手動論外） | ✅ COO が文脈判断で確定 |
| 「主務役職にノイズを追加しない」 | ✅ 既存 3 者ゲートはそのまま、COO が新規役割を担う |
| 追加コスト | ゼロ（メインセッション内で処理、追加の Agent 呼び出しなし） |
| キーワード辞書による誤判定リスク | ✅ ない（LLM 文脈判断） |
| LLM 呼び出しのレイテンシー / コスト | ✅ 既にメインセッションが動いているので追加コストゼロ |

### 🗑️ 旧 type 14 種は廃止

過去の `/vibecorp:issue` には独自 type 14 種（`design` / `agent` / `integrate` / `release` / `template` 等）のキーワード判定表が存在したが、Issue #469 議論結論「既存のキーワード判定表（独自 type 14 種）を廃止し、COO の文脈判断で intent を確定する形に書き換え」に従い廃止する。

intent ラベル 7 種への 1:N マッピング表は **意図的に作らない**（主従関係を狂わせないため、COO の文脈判定で都度確定する）。

`/vibecorp:issue` スキルの実装書き換え（旧 type 廃止 + COO 文脈判定への移行）は別 Issue で対応する（本ルールは判定基準の宣言のみ）。

## 1️⃣ 1 Issue / 1 intent 厳守

- 1 つの Issue には intent ラベルを **1 つだけ** 付与する（PR には付与しない、CC prefix が PR の機械可読保険）
- 複数 intent にまたがる変更は Issue を分割する
- Issue 側 `intent-label-issue-check.yml` CI ジョブが intent 数（0 個 / 2 個以上）を機械的に検知して fail コメントを投稿する

## 🔗 関連ルール

- CC prefix 厳格定義: `docs/conventional-commits.md`
- communication 規約: `.claude/rules/communication.md`
- 役割定義: `.claude/rules/roles.md`
