## inline 指摘の severity 5 段階分類（CodeRabbit 公式仕様、`.claude/rules/severity/coderabbit.md` 準拠）

| Marker | severity | 定義 |
|--------|---------|---------|
| 🔴 | Critical | システム障害、セキュリティ侵害、データ損失を引き起こす重大な問題 |
| 🟠 | Major | 機能・パフォーマンスに大きく影響する重要な問題 |
| 🟡 | Minor | 対応すべきだがシステムに致命的な影響はない問題 |
| 🔵 | Trivial | コード品質を高めるための軽微な提案 |
| ⚪ | Info | 情報提供のみ、対応不要 |

`comments[]` の各要素は **構造化フィールド** で出力する（Issue #263）。本文（`body`）の組み立ては workflow 側の `scripts/ci/vibehawk-review/assemble-inline-bodies.sh` が決定論的に行うため、Claude は以下のフィールドに値を入れるだけでよい。3 軸ラベル・折り畳み・フッタ等の **固定書式は組み立て側が付与する**（Claude が書式を二重に書かないこと）。

### フィールド定義

| フィールド | 必須 | 値 |
|---|---|---|
| `category` | ✅ | `⚠️ Potential issue`（潜在バグ・不具合）/ `🛠️ Refactor suggestion`（構造改善提案）/ `🧹 Nitpick`（軽微な磨き込み提案、ブロッカーではない） |
| `severity` | actionable のみ | `🔴 Critical` / `🟠 Major` / `🟡 Minor` / `🔵 Trivial` / `⚪ Info`（上の 5 段階定義に厳格に従う）。**`🧹 Nitpick` には付けない**（severity は actionable 専用の直交ラベル、Issue #270） |
| `effort` | ✅ | `⚡ Quick win`（短時間で直せる）または `🏗️ Heavy lift`（大きめの対応が必要） |
| `title` | ✅ | 太字 1 行タイトル（指摘の要約を 1 文で。`**` は付けない、組み立て側が太字化する） |
| `description` | ✅ | 説明段落（なぜ問題か・どう直すかを日本語で） |
| `suggestion` | 任意 | 修正提案コードのみ。フェンスや `suggestion` ラベルは付けない（組み立て側が ` ```suggestion ` でラップする）。修正提案が無ければ省略する |
| `ai_prompt` | ✅ | AI エージェントが修正に着手できる指示（対象ファイル + 行範囲 + 日本語の具体手順） |

`category` / `effort` は全指摘に必ず付与する。`severity` は **actionable（`⚠️ Potential issue` / `🛠️ Refactor suggestion`）にのみ付与**し、`🧹 Nitpick` には付けない。

### actionable / nitpick の判定基準（Issue #270、CodeRabbit 互換）

各指摘を、severity を付ける前に **まず actionable か nitpick かで分類** する（severity を先に決めてから振り分けるのではない）。

| 分類 | category | severity | 判断軸 |
|------|----------|----------|--------|
| **actionable** | `⚠️ Potential issue` / `🛠️ Refactor suggestion` | 付ける（5 段階） | バグ・不具合・設計上の問題など、レビュアーが対応を検討すべき指摘 |
| **nitpick** | `🧹 Nitpick` | 付けない | 動作に影響しない軽微な磨き込み（命名の好み・軽微な体裁・任意の代替案など）。直さなくても支障がない |

- 判断は **内容で行う**（「Minor だから nitpick」のような severity 起点の機械振り分けはしない）。actionable なら軽微でも severity を付けて actionable のまま残す。
- 迷ったら actionable に倒す（nitpick は「直さなくても支障がない」と断言できるものに限る）。
- 本数を増やしすぎない。`🧹 Nitpick` は本当に軽微なものだけにする。

### 組み立て後のレンダリング（組み立て側が生成。Claude は書式を書かない）

`assemble-inline-bodies.sh` が各フィールドから以下の `body` を決定論的に生成する。Claude はこの書式を出力しないこと（フィールド値のみ出力する）。

1. **先頭行を CodeRabbit 互換の 3 軸ラベル** にする（Issue #252）。フォーマットは `_<category>_ | _<severity>_ | _<effort>_`（イタリック・パイプ区切り）。例: `_⚠️ Potential issue_ | _🟠 Major_ | _⚡ Quick win_`
2. **太字タイトル + 説明段落の 2 部構成**（Issue #253）: `**<title>**` → 空行 → `<description>`。太字 1 行タイトルの後に説明段落が続く。
3. `suggestion` がある場合のみ **CodeRabbit 互換の Committable suggestion 折り畳み**（Issue #255）でラップする。`<!-- suggestion_start -->` と `<!-- suggestion_end -->` で挟み、`<details><summary>📝 Committable suggestion</summary>` 内に `> [!IMPORTANT]` 注意書きと ` ```suggestion ` ブロックを置く。`suggestion` が無い指摘では折り畳みを出さない。
4. **🤖 AI 向け修正指示** の `<details>` 折り畳み（Issue #254）: `<details><summary>🤖 AI 向け修正指示</summary>` 内に `ai_prompt`（AI エージェントが修正に着手できる指示）を畳む。CodeRabbit の英語定型文（"Prompt for AI Agents"）の literal コピーはしない。枠は再現・中身は日本語の vibehawk 文面にする。
5. **vibehawk 識別フッタ**（Issue #256）: `body` の最終行に `<!-- vibehawk:inline -->` を付ける。CodeRabbit の文言（"This is an auto-generated comment by CodeRabbit"）の literal コピーは出所を偽るため禁止。既存の sticky マーカー（`<!-- vibehawk:summary -->` / `<!-- vibehawk:sha=... -->`）と同じ `vibehawk:` 名前空間に揃える。

severity は `severity` フィールドに保持されるため、後続の event 判定（件数主軸、Issue #171）も従来どおり機能する。

### 例（Claude が返す構造化フィールド）

```json
{
  "path": "src/foo.ts",
  "line": 42,
  "side": "RIGHT",
  "category": "⚠️ Potential issue",
  "severity": "🟠 Major",
  "effort": "⚡ Quick win",
  "title": "set -euo pipefail 下で grep 無マッチ時に即死する",
  "description": "grep がマッチしないと exit code 1 になり、set -e でスクリプトが落ちる。|| true でガードする。",
  "suggestion": "if grep -q foo bar || true; then",
  "ai_prompt": "src/foo.ts の 42 行目付近で grep の呼び出しを || true でガードし、無マッチ時の即死を防ぐ"
}
```

`🧹 Nitpick` の例（`severity` を付けない、Issue #270）:

```json
{
  "path": "src/foo.ts",
  "line": 88,
  "side": "RIGHT",
  "category": "🧹 Nitpick",
  "effort": "⚡ Quick win",
  "title": "変数名 tmp はより意図が伝わる名前にできる",
  "description": "動作には影響しないが、tmp より parsed_config 等の方が読み手に意図が伝わる。任意。",
  "ai_prompt": "src/foo.ts の 88 行目の変数 tmp を、用途が伝わる名前（例: parsed_config）に変えることを検討する"
}
```

複数行範囲指摘なら `start_line` / `start_side` を追加する。**Bot 自身は commit しない**（5 大方針 2 の例外として「`suggestion` フィールドの生成」は明示的に許可、Bot 自身が PR に commit を作る行為は禁止）。
