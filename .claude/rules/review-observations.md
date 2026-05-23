# 🔍 レビュー観点（intent 別）

> [!IMPORTANT]
> 各 intent の重視軸に対応するレビュー観点（observation_points）を定義する。
> `.coderabbit.yaml` と `REVIEW.md`（claude-code-action のプロンプト）の両方が本ファイルを Source of Truth として参照する。
> `intent/refactor` / `intent/infra` / `intent/docs` は **挙動不変性の確認** を必ず行う。

本ルールは PR レビュー時の観点リストを intent 別に提供する。

## 🎯 役割

本ルールは CodeRabbit / claude-code-action による PR レビューの観点定義を担う。

- 適用対象: CodeRabbit / claude-code-action による PR レビュー。
- 参照経路: `.coderabbit.yaml` と `REVIEW.md`（claude-code-action のプロンプト）の両方が本ファイルを Source of Truth として参照する。
- 関連: `.claude/rules/review-handling.md`（捌き基準、intent × severity の掛け合わせ）。

## 📋 intent 別レビュー観点

### 🆕 `intent/feature` — 新機能を確実に動かす

- **仕様逸脱**: Issue 本文・PR 説明と実装が一致しているか。
- **エッジケース**: 境界値、null / 空、巨大入力、並行アクセス。
- **新規 API 設計**: 命名、引数の妥当性、エラー設計、戻り値、後方互換。
- **テストカバレッジ**: 主要パスの自動テストがあるか。

### 🐛 `intent/bugfix` — 既存バグを最小修正で直す

- **修正範囲の妥当性**: 必要最小限か、無関係な変更が混じっていないか。
- **回帰テスト**: バグを再現するテストが追加されているか。
- **根本原因の修正**: 症状だけ直して原因を放置していないか。
- **副作用**: 修正によって他箇所が壊れていないか。

### ⚡ `intent/performance` — 性能を測定可能な形で改善する

- **ベンチマーク**: 改善が定量的に示されているか。
- **メモリリーク**: GC されないオブジェクト保持、循環参照。
- **N+1 問題**: ループ内 DB / API 呼び出し。
- **計算量**: アルゴリズムの O 記法、不要なソート / コピー。
- **観測可能性**: 性能メトリクス（latency / throughput）が出ているか。

### 🔒 `intent/security` — 脆弱性を塞ぐ

- **脆弱性パターン**: SQL injection / XSS / CSRF / SSRF / Path traversal / Deserialization。
- **認証・認可**: 認証スキップ可能経路、権限昇格、Session fixation。
- **入力検証**: 信頼境界での validation、型チェック、サニタイズ。
- **機密情報**: secrets ログ出力、エラーレスポンスへの混入、平文保存。
- **依存パッケージ**: 既知 CVE、メジャーバージョン更新の影響。

### 🔄 `intent/refactor` — 構造の品質を高める（挙動不変）

- **命名**: 変数 / 関数 / クラス名が意図を表しているか。
- **責務分離**: 関数 / クラスの責務が単一か（SRP）。
- **抽象化**: 過不足ない抽象（過剰抽象 / 重複コード）。
- **凝集度**: 関連処理が同じモジュールに集約されているか。
- **🔍 挙動不変性の確認（必須）**: リファクタ前後で観測可能な挙動が変わっていないか（公開 API、UI、ログ出力、副作用）。

### 🧱 `intent/infra` — 開発基盤の品質を底上げする（挙動不変）

- **CI 整合**: 既存 CI ジョブとの整合性、required check への影響。
- **テスト整合**: テスト基盤の変更がテスト挙動を変えていないか。
- **後方互換**: 設定ファイル / 環境変数の変更が既存利用者を壊していないか。
- **依存互換**: 依存パッケージのバージョン上げで API が変わっていないか。
- **🔍 挙動不変性の確認（必須）**: ランタイム挙動に影響が出ていないか（ビルドフラグ、依存メジャー更新、CI 環境設定）。

### 📖 `intent/docs` — ドキュメントの正確性を担保する（挙動不変）

- **用語**: 用語が一貫しているか、最新の用語に揃っているか。
- **リンク**: 内部リンク / 外部リンクが切れていないか。
- **内容**: 実装と整合しているか、過去の仕様が混入していないか。
- **サンプルコード動作**: 掲載コードが実際に動くか。
- **🔍 挙動不変性の確認（必須）**: ドキュメント変更が実コードの挙動を要求していないか（サンプルコードがコード本体に依存）。

## 🛡️ 「挙動不変性の確認」観点（影響を与えない系の必須チェック）

`intent/refactor` / `intent/infra` / `intent/docs` のラベルが付いた変更には **挙動不変であることを必ず検証する**。

- 挙動が変わるものを「影響を与えない系」のラベルで通すと、レビュー観点が歪む（severity 判定で見逃し）。
- 挙動が変わるなら必ず「影響を与える系」（`intent/feature` / `intent/bugfix` / `intent/performance` / `intent/security`）のラベルに付け替える。

## 🔗 関連ルール

- intent ラベル定義: `.claude/rules/intent-labels.md`
- severity 公式定義: `.claude/rules/severity/coderabbit.md`
- severity 実体版: `.claude/rules/severity/claude-action.md`
- 捌き基準（intent × severity）: `.claude/rules/review-handling.md`
- プロンプト作成基準: `.claude/rules/prompt-writing.md`
- マークダウン規約: `.claude/rules/markdown.md`
