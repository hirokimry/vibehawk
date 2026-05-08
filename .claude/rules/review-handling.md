レビュー指摘の捌き基準は **intent の重視軸 × severity の掛け合わせ** で決定すること。

## 設計原則

修正対象は **intent の重視軸 × severity の掛け合わせ** で決める。重視軸外の指摘は管轄外（その PR では扱わない、必要なら別 Issue を立てる）。

「後続 PR」という表記は使わない。重視軸外で重要なら severity を Major 以上に上げてもらう運用とする（Minor 以下で出した時点で「Major ではない」を認めている）。

## 各 intent の重視軸

| intent | 重視軸 | 重視軸に該当する指摘 | 管轄外（重視軸外） |
|--------|------|------------------|----------------|
| `intent/feature` | 新機能を確実に動かす | 仕様逸脱、エッジケース、新規 API 設計 | 構造改善、命名整理 |
| `intent/bugfix` | 最小修正で直す | 修正範囲の妥当性、回帰テスト、根本原因 | 修正範囲外の指摘 |
| `intent/performance` | 測定可能な性能改善 | ベンチマーク、メモリリーク、N+1、計算量 | 性能と無関係な指摘 |
| `intent/security` | 脆弱性を塞ぐ | 脆弱性パターン、認証・認可、入力検証、機密情報 | セキュリティと無関係な指摘 |
| `intent/refactor` | 構造の品質（挙動不変） | 命名、責務分離、抽象化、凝集度、挙動不変性 | 機能追加、バグ修正 |
| `intent/infra` | 基盤の品質（挙動不変） | CI 整合、テスト整合、後方互換、依存互換、挙動不変性 | 本番コードへの踏み込み |
| `intent/docs` | 正確性（挙動不変） | 用語、リンク、内容、サンプルコード動作、挙動不変性 | コード本体への影響 |

## severity 軸との掛け合わせ

| severity | 扱い |
|---------|------|
| 🔴 Critical | intent 問わず必ず対応 |
| 🟠 Major | intent 問わず必ず対応 |
| 🟡 Minor | 重視軸該当なら対応、外なら管轄外 |
| 🔵 Trivial | 重視軸該当なら対応、外なら管轄外 |
| ⚪ Info | 重視軸該当なら対応、外なら管轄外 |

severity の定義は `.claude/rules/severity/coderabbit.md`（CodeRabbit 公式仕様）と `.claude/rules/severity/claude-action.md`（vibecorp 実体版）を参照。

### Info の扱い（severity 定義は同じ、判定で拡張）

severity の **定義** は CodeRabbit と完全一致させる（`severity/coderabbit.md` / `severity/claude-action.md` 参照）。Info の定義もそのまま「情報提供のみ、対応不要」のまま変えない。

ただし **修正対象とするかどうかの判定** は本ドキュメント（`review-handling.md`）が vibecorp 独自運用として別途行う。Info も **判定の側で**「重視軸に該当する場合は対応する」に拡張する。

| 観点 | severity 定義 | 修正対象判定 |
|------|------|------|
| 役割 | 重大度の意味を CodeRabbit と完全一致させて記録 | vibecorp の運用要件で修正対象か否かを決める |
| ファイル | `severity/coderabbit.md` / `severity/claude-action.md` | 本ファイル（`review-handling.md`） |
| Info の扱い | CodeRabbit と同じ「情報提供のみ、対応不要」 | 重視軸該当なら対応、外なら管轄外（vibecorp 独自）|

なぜ判定で拡張するか:
- vibecorp の「intent 重視軸」は PR スコープを狭く保つための運用判定軸であり、その軸に該当する Info 指摘は **無視すると重視軸の品質が落ちる**
- CodeRabbit 公式の「Info = 対応不要」は CodeRabbit の汎用デフォルトであり、vibecorp 固有の運用要件を反映していない
- severity 定義そのものを書き換えるのではなく、**判定の側でだけ** vibecorp 独自運用を入れることで、CodeRabbit 公式仕様との完全一致を保ちつつ vibecorp 要件にも応える

## 設計の根拠

- **1 PR 1 intent 厳守**（`.claude/rules/intent-labels.md`）と整合。PR のスコープを狭く保つ
- **Critical / Major は実害がある**ので intent 問わず対応
- **Minor / Trivial / Info は「致命的影響なし」**なので intent の重視軸該当のみ対応
- **重視軸外で重要なら severity を Major 以上に上げてもらう運用**（Minor 以下で出した時点で「Major ではない」を認めている）

## 検証手順

1. 指摘された箇所の実コードを読んで文脈を確認する
2. severity を確認する（CodeRabbit 出力 or claude-action 出力）
3. PR の intent ラベルを確認する
4. 上記マトリクスに照らして「修正対象」「管轄外」を判定する
5. 判断に迷う場合は「修正対象」に分類する
6. 修正対象が 0 件の場合は「修正すべき指摘なし」と返す

## 関連

- intent ラベル定義: `.claude/rules/intent-labels.md`
- severity 公式定義: `.claude/rules/severity/coderabbit.md`
- severity 実体版: `.claude/rules/severity/claude-action.md`
- レビュー観点: `.claude/rules/review-observations.md`
