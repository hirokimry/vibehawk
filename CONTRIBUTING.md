# Contributing to vibehawk

vibehawk は OSS プロダクトです。コントリビュータの参加を歓迎します。

## リリースプロセス

vibehawk のリリースは **GitHub Actions OIDC 経由の自動 publish のみ** を許可します。手動 publish は禁止です（CISO Critical 条件）。

### リリース手順

1. `package.json` の `version` を更新（semver に従う）
2. `main` ブランチに version bump コミットを push
3. GitHub Releases で対応する tag（例: `v0.2.0`）を作成して publish
4. `.github/workflows/release.yml` が自動起動し、以下を実行:
   - 全テスト（`tests/test_*.sh`）の実行
   - tag と `package.json` version の整合確認
   - `npm publish --provenance --access public`（OIDC token 経由で provenance 署名）
5. npm registry に provenance 付きで公開される

### 禁止事項

- **手動 `npm publish` 実行**: CISO Critical 条件違反。OIDC publish 以外は運用上禁止
- **`--no-provenance` での publish**: provenance 署名は必須
- **個人 npm token を CI に登録**: 個人 token は短寿命の OIDC token に置き換える方針

## セキュリティ要件

### npm アカウント

- npm publish アカウントは **2FA 必須**（CISO Critical 条件）
- 2FA は authenticator app + recovery code を組み合わせて運用

### npm 侵害時の対応

万が一 vibehawk の npm パッケージが改ざんされた場合の対応手順は `docs/SECURITY.md` の「npm 侵害時のインシデント対応」セクションを参照（Issue #34 で整備予定）。

## 開発

### テスト

```bash
bash tests/test_smoke.sh
bash tests/test_workflow_yaml.sh
bash tests/test_workflow_template_snapshot.sh
bash tests/test_cli.sh
```

または `npm test` で全テスト実行。

### Lint

シェルスクリプトは `shellcheck` で lint してください（CI では未統合、ローカル推奨）。

## Issue / PR

Issue 起票は `intent-labels.md` に従って `intent/*` ラベルを 1 つだけ付与してください（vibecorp プラグインが自動判定します）。

詳細は `.claude/rules/intent-labels.md` を参照。
