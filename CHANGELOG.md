# CHANGELOG

vibehawk のリリース履歴。各バージョンの主要変更点を記録する。

## Unreleased

### 💥 BREAKING CHANGES

- 💥 **#172 fix: `.coderabbit.yaml` フォールバック読み込みを撤廃**: vibehawk-review.yml / vibehawk-chat.yml の `vibehawk_config` step が読み込む設定ソースを `.vibehawk.yaml` 単独受付に絞った。`source_label` の値域も `vibehawk` / `default` の 2 値に縮退（旧 `coderabbit` 値は撤廃）
  - **影響**: `.coderabbit.yaml` だけを持つ利用者は、本変更後は default 挙動（`language=en` / `full_review_files=30` / `focused_review_files=80` / `skip_inline_files=3000` / `path_filters=[]` / `path_instructions=[]`）に倒れる
  - **移行**: 同スキーマで `.vibehawk.yaml` を新規作成すれば従前同等の設定を引き継げる
  - **背景**: v0.1.0（Issue #10）で実装した CodeRabbit 互換読み込みは CEO 確定方針（2026-05-18）「互換機能は不要、削除すべき」に基づき撤廃。CodeRabbit と vibehawk は別プロダクトであり、vibehawk を利用するなら `.vibehawk.yaml` を配置するのが筋

## v0.1.0 - 2026-05-10

### 🚀 vibehawk が AI エージェントによる PR 自動レビューを実行できるようになった (Epic #1)

vibehawk MVP リリース。利用者の Claude Pro / Max サブスクリプション枠の内側で完結し、追加課金ゼロで CodeRabbit 同等のレビュー体験を提供する OSS。

#### 機能カタログ

- ✨ **PR 全体サマリ + インクリメンタルレビュー** (#8): push のたびにサマリコメントが edit で最新化され、コメントが増殖しない。force push / rebase 検出で完全再レビューに自動切替
- ✨ **severity 5 段階付き inline comment + auto_resolve + sticky review state** (#9): 🔴 Critical / 🟠 Major / 🟡 Minor / 🔵 Trivial / ⚪ Info の絵文字付き inline 指摘。push で直った旧指摘は自身投稿のみ resolved 化、未解決数で都度 approve / request_changes 発行
- ✨ **`.vibehawk.yaml` 設定 + CodeRabbit 互換** (#10): `path_filters` / `path_instructions` / `size_limits`（段階的劣化）/ `language` (ja/en) を制御。`.coderabbit.yaml` 互換読み込みで既存利用者がそのまま移行可能
- ✨ **`@mention` チャット応答** (#11): PR / Issue で `@vibehawk` メンションするとスレッド全体を読んで多ターン会話。状態は GitHub のスレッド自体が保持し、専用 DB を持たない（5 大方針 4）

#### 利用者導入

経路 2 必須化により、以下の流れで導入する（CLI は GitHub Secrets を一切 touch しない、利用者が GitHub Settings UI で手動登録、Issue #72 / #74 確定）:

1. `npx vibehawk install --owner <name> --repo <owner>/<repo>` で `vibehawk-for-<owner>` App 作成 + 2 つの workflow ファイル（review + chat）の配置 PR 自動作成 (#58)
2. GitHub Settings UI で 3 secrets 手動登録: `VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`
3. workflow 配置 PR をマージ → PR を作成すると `vibehawk-for-<owner>[bot]` 名義でレビューサマリが投稿される

#### セキュリティ

- 🔒 **CISO Critical 条件全充足** (#54 / #62): npm publish 2FA + GitHub Actions OIDC publish + npm provenance 署名 + CLI が secrets を touch しない設計 + クリップボード stdin 経由
- 🔒 **CodeRabbit 事件 (2025-08) の構造的回避**: 利用者ごとに独立 App `vibehawk-for-<owner>`、Private Key 漏洩の影響範囲は利用者本人のリポジトリ群に限定（集中 SaaS App とは構造的に異なる）
- 🔒 **GitHub 公式ガイドライン完全準拠**: "native client must never ship private key" — CLI は Private Key を一切 touch しない

詳細は [`docs/secrets-handling.md`](docs/secrets-handling.md) を参照。

#### MVV 整合

- **Mission**: レビューツールに追加課金が要らない世界をつくる
- **Vision**: 一度の支払いが、つくるすべてに届く世界
- **Values 1**: 利用者の契約だけで、完結させる（自前サーバー / 専用 DB / 追加 API キーを持たない）
- **Values 2**: 観察する、書き換えない（コード生成しない、PR メタデータ操作しない）
- **Values 3**: 指摘する、強制しない（severity 判定はツール、捌き方は利用者）
- **Values 4**: 公式の道を、迂回せず歩く（GitHub / Anthropic 公式 API のみ）

#### 含まれる子 Issue（Epic #1）

- 🎯 #4 docs: vibehawk の MVV を制定する
- 📚 #5 docs: vibehawk のプロダクト仕様・5 大方針・機能カタログ・命名を既存テンプレに反映する
- 🏗 #6 docs: アーキテクチャ設計 8 セクションと実装パターンを既存テンプレに反映する
- 🔐 #7 feat: vibehawk GitHub App と PR auto-review トリガー基盤を構築する
- 📝 #8 feat: PR 全体サマリコメントとインクリメンタルレビュー判定を実装する
- 💬 #9 feat: severity 5 段階付き inline comment と sticky review state を実装する
- ⚙️ #10 feat: .vibehawk.yaml 設定スキーマと CodeRabbit 互換読み込みを実装する
- 💬 #11 feat: @mention チャット応答（issue_comment トリガー）を実装する

#### 並行で完了した OSS リリース整備（Epic #23）

- ✨ #24 `npx vibehawk install` で GitHub App Manifest Flow 実装
- ✨ #25 bot 名 `vibehawk-for-<owner>[bot]` 命名統制
- ✨ #26 → 🔒 #74 OAuth Token 取得補助（自動登録 → 全手動誘導に転換、Issue #72 決定）
- ✨ #27 `--dry-run` モード
- ✨ #28 同意確認プロンプト（npm AUP 遵守）
- ✨ #29 workflow テンプレート禁止権限非出力 CI スナップショットテスト
- 🚀 #30 npm registry 公開のため 2FA + provenance + OIDC publish 環境
- ✨ #31 Windows 環境対応
- ✨ #57 サマリコメントに種別マーカー / SHA マーカー注入
- ✨ #58 workflow ファイル PR 自動配置（`--repo` フラグで 2 ファイル一括）
- ✨ #59 workflow が App Installation Token 認証で動作（`vibehawk-for-<owner>[bot]` 名義投稿）
- 📖 #61 docs を経路 2 必須化 + 全手動方針に揃えて全面改訂
- 📖 #70 claude-code-action SHA 更新ポリシー策定（CFO + CTO + CISO 3 名承認、月次評価）
- 📖 #73 認証情報配布方式の経緯と業界調査結果を `docs/secrets-handling.md` に永続化
- 🔒 #74 `cli/oauth.js` の OAuth Token 自動登録機能撤去 → 手動誘導に変更
- 📖 #81 CISO 再承認 (#62) で検出された Minor 3 件（Token スコープ / rotation 手順 / 旧コメント修正）反映

#### 認識見直し

- **Issue #22 妥協の撤回**: 「CEO の GitHub App Private Key を全利用者に配布する設計」と「利用者ごとに独立した App を利用者本人が作成・運用する設計」を区別していなかった当初判定を見直し、後者は Value 1 と整合することが判明。経路 1（`secrets.GITHUB_TOKEN` + `github-actions[bot]`）の妥協を撤回し、経路 2 必須化（CEO 判断 2026-05-09、Issue #72）

### CISO 承認

経路 2 必須化版で CISO 条件付き承認発行（Issue #62）。致命的脆弱性なし、新規発生リスク 6 件のうち 3 件「許容」、3 件「Minor 要対策」（Issue #81 で対応済）。

### 関連 Epic

- Epic #1: vibehawk が AI エージェントによる PR 自動レビューを実行できるようになる
- Epic #23: vibehawk OSS リリース完遂（Phase 2/3 + 5 C*O 必須条件全充足）
