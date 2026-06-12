# CTO 技術判断記録インデックス

このファイルは目次。CTO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

- 2026-06-13 — Issue #346 / PR #348: 配布 workflow 自己完結化 — hashFiles guard + pin 付き runtime checkout + GITHUB_ENV 三項演算の標準パターン確定・スクリプト内参照は SCRIPT_DIR 基点（shell.md 追記）・完全一致 dogfooding は外部破綻を隠す
- 2026-06-12 — PR #345: README 大規模再構成 — 重要フレーズ grep 検証の標準化・内部リンク外部URL除外パターン・見出し順序機械検証を docs 再構成 PR の標準観点として確定
- 2026-06-07 — ローカルレビュー CLI 設計議論 — `claude -p` 呼び出し推奨（MVV整合）・プロンプト共通化先行が必須・CPO/CISO/CFO委任点3件特定
- 2026-05-24 — Issue #222 / PR #223: APPROVE 時レビュー抑制 — validation 通過後の後段 payload 上書きパターン採用・jq+mv の && 連結で payload 破損防止
- 2026-05-14 — PR #113: formatDuration 境界値処理と型チェックテスト — toFixed("60.0")繰り上げパターン・境界値3値必須・dry-run戻り値の型チェックアサーション追加
- 2026-05-08 — Issue #6 / PR #16: ship #6 知見 — specification.md(What)/design-philosophy.md(Why) 責務確定・ai-organization.md 配置は CEO 意図優先（技術的負債として負債記録）・shallow clone 対策は利用者側要件として specification に明示
- 2026-05-08 — PR #12: vibehawk MVV 制定 — `grep -F ... > /dev/null` で終了コード回避・状態管理はGitHubリソースのみ・固有セクションはvibecorp由来より前に配置

## 運用ルール

### エントリ書式

1 エントリ = 1 行:

```text
- YYYY-MM-DD — Issue #NNN または トピック名 — 結論の一行要約
```

### 四半期の命名

- 01-03 → Q1、04-06 → Q2、07-09 → Q3、10-12 → Q4
- 例: 2026-04-18 → `decisions/2026-Q2.md`

### 追記手順

1. `decisions/YYYY-QN.md` に詳細を追記（ファイルがなければ新規作成、`decisions/` ディレクトリ自動作成）
2. 本ファイルのエントリセクションに 1 行サマリを追記（新しい順で上に追加）

詳細仕様: `docs/migration-decisions-index.md`
