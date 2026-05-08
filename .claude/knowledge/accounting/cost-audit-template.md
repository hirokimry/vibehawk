# コスト監査レポート雛形

`/audit-cost` による週次コスト監査の記録雛形。実施ごとに `audit-YYYY-MM-DD.md` としてコピーして使用する。

---

## 実施日

YYYY-MM-DD（実施者: CFO エージェント / スキル: `/audit-cost`）

## 監査範囲

- git commit range: `<base>..<head>`
- 対象期間: YYYY-MM-DD 〜 YYYY-MM-DD（直近7日間）

## 変更サマリ

- コミット数: N
- 変更ファイル数: N
- API 呼び出し箇所の増減: +N / -N
- ヘッドレス Claude 起動箇所（claude -p / npx / bunx）の増減: +N / -N

## 指摘事項

### Critical（即時対応）

- （該当なし / 詳細）

### Major（次回リリース前対応）

- （該当なし / 詳細）

### Minor（将来対応）

- （該当なし / 詳細）

## コスト影響評価

| 項目 | 変更前 | 変更後 | 影響度 |
|---|---|---|---|
| 想定月額 API コスト | $X | $Y | 増減 |
| 従量課金到達リスク | Low / Medium / High | Low / Medium / High | - |

## モデル指定監査

各エージェント定義（`templates/claude/agents/*.md` および `.claude/agents/*.md`）の `model:` 指定が役割に対して妥当かを審査する。判定は `docs/cost-analysis.md` の「モデル単価」表と「プリセット別の想定運用モード」を根拠とする。

### 走査対象

- 配布元: `templates/claude/agents/*.md`（N 件）
- 導入先: `.claude/agents/*.md`（N 件）

### 役割別判定

#### 判断品質が存在意義のロール（C-suite + 合議制の分析員 + プロセス管理）

対象: `cfo`, `cto`, `cpo`, `clo`, `ciso`, `accounting-analyst`, `legal-analyst`, `security-analyst`, `sm`

| エージェント | 現在のモデル | 判定 | 指摘区分 |
|---|---|---|---|
| （例）cfo | sonnet | 妥当 | - |
| （例）legal-analyst | haiku | 警告: 品質劣化リスク | Major |

#### 定型作業ロール（自動化エージェント）

対象: `branch`, `commit`, `pr`, `plan-architect`, `plan-cost`, `plan-dx`, `plan-legal`, `plan-performance`, `plan-security`, `plan-testing`

| エージェント | 現在のモデル | 判定 | 指摘区分 |
|---|---|---|---|
| （例）branch | sonnet | 妥当 | - |
| （例）commit | opus | 警告: 過剰指定 | Major |

#### モデル未指定（親から継承）

- （該当なし / エージェント名一覧）

### 直近7日間の Diff

`templates/claude/agents/*.md` および `.claude/agents/*.md` の `model:` 行に変更があれば記載する。

```text
（git log --since="7 days ago" -p -- 'templates/claude/agents/*.md' '.claude/agents/*.md' | grep -E '^[+-]model:|^diff --git' の出力）
```

### 警告サマリ

- Major: N 件
- Minor: N 件
- 妥当: N 件

警告対象は上の「指摘事項」節（Critical / Major / Minor）にも転記する。

## 推奨アクション

- （具体的な改善提案）

## 次回監査予定日

YYYY-MM-DD（週次: 毎週月曜）

## 関連

- `docs/cost-analysis.md`
- Phase 6 #291
