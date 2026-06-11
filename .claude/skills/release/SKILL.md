---
name: release
description: "vibehawk のリリース PR を自動作成する版上げ係スキル。prepare-release.sh で Conventional Commits からバージョンを決定し、package.json + CHANGELOG.md を bump したリリース PR を作成して auto-merge を設定する。「/release」「リリースして」「リリース PR 作って」「版を上げて」と言った時に使用。"
---

# 🚀 リリース PR 自動作成スキル（版上げ係）

> [!IMPORTANT]
> このスキルは **vibehawk のリリース PR 作成（版上げ工程）の唯一の担当**（Issue #341）。
> bump の実体は `scripts/ci/release/prepare-release.sh` に完全委譲し、本スキルは呼び出し経路と PR 化のみを担う。
> マージ後の tag / GitHub Release / npm publish は既存の `release-tag.yml` → `release.yml` 連鎖が自動実行する（Issue #333 で e2e 実証済み）。
> **ローカル実行専用**。GHA workflow 化はしない（`GITHUB_TOKEN` が作る PR は required checks が発火せず永久にマージ不能になるため — Issue #341 設計判断）。

`/release` 一発で bump → リリース PR 作成 → auto-merge 設定までを実行する。マージは required checks（`test` / `vibehawk`）+ 承認を満たした時点で GitHub が自動実行する。

## 🛠️ 使用方法

```bash
/release
```

引数なし。リリース対象（feat / fix / perf / breaking）が直近 tag 以降に無ければ何も作らずに終了する。

## ✅ 前提条件

- 現在のブランチが main で working tree が clean であること。
- GitHub CLI（`gh`）が認証済みであること（`gh auth status`）。
- `node` / `npm` が利用可能であること（`prepare-release.sh` が依存）。
- vibecorp プラグインが有効化されていること（ステップ 11 の `/vibecorp:pr-fix-loop` 委譲に必要）。

## 🔄 ワークフロー

### 1. 前提確認

現在ブランチが main・working tree clean・`gh auth status` 通過を確認する。満たさなければ中断して CEO に報告する。

```bash
git branch --show-current
git status --short
gh auth status
```

### 2. Unreleased ガード

`CHANGELOG.md` に `## Unreleased` 見出しが存在する場合は中断し、CEO に手動統合を促す（介入ポイント）。

```bash
grep -q -e '^## Unreleased' CHANGELOG.md
```

現運用ではリリースノートを `cc-analyze.sh` が Conventional Commits から自動生成するため、`## Unreleased` セクションは使わない。本ガードは旧運用の残骸が紛れ込んだ場合の安全弁であり、版セクションへの切り出し自体は `prepare-release.sh` が担う。

### 3. ブランチ準備

既に `release/pending` が残存している場合は中断して CEO に報告する（前回中途終了の痕跡のため）。

```bash
git fetch origin main
git checkout -b release/pending origin/main
```

### 4. bump 実行

`prepare-release.sh` を実行し、stdout から新バージョンを取得する。

```bash
new_version="$(bash scripts/ci/release/prepare-release.sh)"
```

stdout が空（bump level 0 = リリース対象の変更なし）の場合は、一時ブランチを削除して main に戻り、「リリース対象の変更（feat / fix / perf / breaking）が無い」と CEO に報告して終了する。

```bash
git checkout main
git branch -D release/pending
```

### 5. ブランチ確定

`release/v<新バージョン>` にリネームする（PR #339 の実績 `release/v0.2.1` と同型の命名）。

```bash
git branch -m "release/v${new_version}"
```

### 6. 差分検証

変更ファイルが `package.json` / `package-lock.json` / `CHANGELOG.md` のみであることを確認する。想定外の差分があれば中断して CEO に報告する（介入ポイント）。

```bash
git status --short
```

### 7. コミット

決定的なメッセージで commit する。

```bash
git add package.json package-lock.json CHANGELOG.md
git commit -m "🚀 release: vibehawk を v${new_version} としてリリースする"
```

`/vibecorp:commit` に委譲しない理由: リリースコミットはメッセージが決定的であり、diff 解析による生成が不要なため。`release:` prefix は `cc-analyze.sh` で bump 対象外（「その他」）に落ちるため、リリースコミット自体が次回 bump を引き起こさない。

### 8. Refs 抽出

`CHANGELOG.md` の新バージョンセクション（`## v<新バージョン>` 見出しから次の `## v` 見出しまで）から `(#N)` 形式の番号を抽出し、重複排除して `Refs #N` 行のリストを作る。

- `pr-issue-link-check`（PR 本文に Issue 参照必須）を通すための必須要素。
- 抽出結果が 0 件の場合は中断して CEO に報告する（介入ポイント。squash マージ運用ではタイトル末尾に `(#N)` が付くため通常発生しない）。
- リリース用のダミー Issue は起票しない（intent ラベル 7 種にリリースが無くノイズになるため — Issue #341 設計判断）。

### 9. push + PR 作成

```bash
git push origin HEAD
```

`gh pr create` で以下の形式の PR を作成する。

- タイトル: `🚀 release: vibehawk を v<新バージョン> としてリリースする`（`release:` prefix は `check-pr-title.sh` で許可済み）
- 本文: CHANGELOG 新セクション（リリースノート）+ ステップ 8 の `Refs #N` 列挙

`/vibecorp:pr` に委譲しない理由: `/vibecorp:pr` は Issue 紐付き `dev/<番号>_*` ブランチ専用の本文生成を行うため。`release-epic` skill が自前で PR を作るのと同型。

### 10. auto-merge 設定

```bash
gh pr merge --squash --auto
```

required checks（`test` / `vibehawk`）+ 承認 1 件は branch protection が担保する。本スキルは branch protection を変更・迂回しない。

### 11. マージ見届け

`/vibecorp:pr-fix-loop` に委譲する（vibehawk レビュー対応 + CI パス確認）。

- 前提: vibecorp プラグインが有効化されていること。
- `/vibecorp:pr-fix-loop` が利用できない環境では、手動で CI 確認と `gh pr merge` を行う（fallback）。

### 12. 発火確認

マージ後、リリース連鎖の発火を確認して CEO に報告する。

```bash
gh run list --workflow=release-tag.yml --limit 3
gh run list --workflow=release.yml --limit 3
```

`release-tag.yml`（tag + GitHub Release 作成）→ `release.yml`（npm publish、OIDC trusted publisher 経由）の順に自動で流れる。

## 🚦 介入ポイント

以下の状況では CEO に報告して判断を委ねる（自動でスキップしない）。

| 状況 | タイミング |
|------|-----------|
| main 以外のブランチ / working tree が dirty | ステップ 1 |
| `CHANGELOG.md` に `## Unreleased` が存在する | ステップ 2 |
| `release/pending` ブランチが残存している | ステップ 3 |
| bump 差分に想定外のファイルが含まれる | ステップ 6 |
| `Refs #N` の抽出結果が 0 件 | ステップ 8 |
| `/vibecorp:pr-fix-loop` が利用できない | ステップ 11 |

## 🚧 制約

- `--force` / `--hard` / `--no-verify` は使用しない。
- `sed -i` は使用しない（`.claude/rules/shell.md` BSD/GNU 互換）。
- `scripts/ci/release/*.sh` は変更しない（呼び出すだけ）。
- 製品本体（`cli/` / `templates/`）には触れない（挙動不変）。
- 本スキルは自律改善ループ（`/vibecorp:diagnose` → `/vibecorp:autopilot`）から起動しない（CEO の明示実行専用）。

## 📤 結果報告

```text
## /release 完了

- バージョン: v{old} → v{new}
- PR: #{pr_number}（auto-merge 設定済み）
- ブランチ: release/v{new}
- Refs: {抽出した #N 一覧}
- マージ後連鎖: release-tag.yml → release.yml（発火確認結果）
```

リリース対象なしで終了した場合は「リリース対象の変更が無いため bump をスキップした」と報告する。

## 🔗 関連

| 種別 | 参照先 |
|------|--------|
| bump 実体 | `scripts/ci/release/prepare-release.sh` / `scripts/ci/release/cc-analyze.sh` |
| マージ後連鎖 | `.github/workflows/release-tag.yml` / `.github/workflows/release.yml` |
| リリース方針 | `docs/specification.md`「バージョニング・リリース方針」 |
| マージ見届け | `/vibecorp:pr-fix-loop` |
| シェル規約 | `.claude/rules/shell.md` |
| マークダウン規約 | `.claude/rules/markdown.md` |
