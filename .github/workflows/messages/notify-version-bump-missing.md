⚠️ `package.json` の `version` bump 漏れを検知しました

## 🎯 検知内容

- 製品ソース（`cli/` / `templates/` / `package.json`）が変更されました
- `package.json` の `version` は据え置かれています
- このままでは npm に公開される版が更新されません

## 🛠️ 必要な対応

マージ前に `package.json` の `version` を bump してください。

| 操作 | 内容 |
|------|------|
| 編集 | `package.json` の `version` を SemVer で 1 段上げる |
| 再 push | 同一ブランチに通常 push すれば本チェックが再実行される |

## 📍 根拠

- 監視対象は `package.json`（vibehawk 製品版 SoT）と製品ソース（`cli/` / `templates/`）
- `.claude-plugin/plugin.json` は vendored 開発ツールのため監視対象外
- 本チェックの位置づけ: 警告のみ・非ブロック（マージ自体は阻害しません）
