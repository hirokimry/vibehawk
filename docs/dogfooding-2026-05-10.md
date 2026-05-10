# Dogfooding 実施記録 — 2026-05-10

Issue: [#56 経路 2 必須化版で vibehawk 自身を一旦消して dogfooding を実施する（手動運用）](https://github.com/hirokimry/vibehawk/issues/56)

実施日: 2026-05-10
実施者: hirokimry（CEO）+ Claude（COO）

## 目的

CEO 方針確定（2026-05-09）により vibehawk は経路 2（`vibehawk-for-<owner>[bot]` 名義投稿）を必須化。本 dogfooding は **全実装完了後の最終動作確認** として、vibehawk 自身を一旦完全に teardown し、Issue #91 で導入された `npx vibehawk setup` ウィザードで再導入できるかを検証する。

別リポジトリではなく vibehawk 自身で実施するのは、Value 1「利用者の契約だけで、完結させる」の純度を最大化するため。

## Phase 別記録

### Phase 1: 完全 teardown

| サブ Phase | 操作 | PR / 操作主体 | 結果 |
|---|---|---|---|
| 1.1 | `.github/workflows/vibehawk-{review,chat}.yml` 削除 | [PR #102](https://github.com/hirokimry/vibehawk/pull/102) | ✅ マージ |
| 1.1 補完 | テスト 4 ファイルを「`templates/` 必須・`.github/` 配下不在許容」に修正 | PR #102 同梱 | ✅ teardown 中も CI 通過可能に |
| 1.2 | `gh secret delete CLAUDE_CODE_OAUTH_TOKEN --repo hirokimry/vibehawk` | CEO 手動 | ✅ secret 完全削除を確認 |
| 1.3 | `vibehawk-for-hirokimry` App を GitHub UI で削除 | CEO ブラウザ | ✅ |

### Phase 2: 経路 2 必須化版で 1 コマンド再導入

`node cli/index.js setup --owner hirokimry --repo hirokimry/vibehawk` を実行。**5 分以内完走** が Issue #91 の dogfooding 完了条件だったが、複数のウィザードバグにより **51 分かかった**（手動補完含む）。

| Step | 状態 | 補足 |
|---|---|---|
| 1/6 GitHub App 作成 | ✅ | App ID 3663653、`vibehawk-for-hirokimry` slug |
| 2/6 App インストール | ✅（手動補完） | ウィザード自動検証は `gh api /user/installations` 403 で fail、CEO がブラウザで手動インストール完了 |
| 3/6 `VIBEHAWK_APP_ID` 登録 | ✅ | CEO 手動登録 |
| 4/6 `VIBEHAWK_PRIVATE_KEY` 登録 | ✅ | CEO 手動登録（Private key 取得 URL 案内バグあり） |
| 5/6 `CLAUDE_CODE_OAUTH_TOKEN` 登録 | ✅（手動補完） | ウィザード異常終了、CEO が token 取得 → 手動登録 |
| 6/6 workflow PR 作成 | ✅（手動補完） | ウィザード未到達のため [PR #106](https://github.com/hirokimry/vibehawk/pull/106) を手動作成 |

dogfooding 中に発見された hotfix 必須バグ:

- ✅ **[Issue #103 / PR #105](https://github.com/hirokimry/vibehawk/pull/105)**: GitHub App manifest の `hook_attributes.url` が欠落して `Invalid GitHub App configuration` で停止。Phase 2 着手不能だったため即 hotfix
- ✅ [PR #106](https://github.com/hirokimry/vibehawk/pull/106) で発見された CodeRabbit Major × 2:
  - `vibehawk-chat.yml` の `--allowedTools` から `Bash(gh api:*)` / `Bash(jq:*)` 除外（issue_comment 経路の prompt 注入対策）
  - `vibehawk-review.yml` で `actions/checkout` の `ref` を `${{ github.event.pull_request.head.sha }}` 明示（synthetic merge commit ではなく PR HEAD SHA を check out、Issue #57 SHA マーカーと整合）

### Phase 3: 経路 2 動作確認

**本 PR がそのまま Phase 3 検証対象**。本 PR を作成した時点で `vibehawk-review.yml` workflow が起動し、以下を満たすかを実機検証する:

- [ ] `vibehawk-review.yml` workflow が起動する
- [ ] **`vibehawk-for-hirokimry[bot]` 名義** でレビューサマリコメントが投稿される
- [ ] 種別マーカー `<!-- vibehawk:summary -->` がコメントに含まれる
- [ ] SHA マーカー `<!-- vibehawk:sha=<HEAD_SHA> -->` がコメントに含まれる
- [ ] エラーなく完了する

検証コマンド（マージ後に PR 番号を `<本PR>` に置換して実行）:

```bash
gh api repos/hirokimry/vibehawk/issues/<本PR>/comments --paginate \
  --jq '.[] | select(.user.login | startswith("vibehawk-for-")) | {login: .user.login, has_summary: (.body | contains("<!-- vibehawk:summary -->")), has_sha: (.body | test("<!-- vibehawk:sha=[0-9a-f]+ -->"; "i"))}'
```

### Phase 4: 全手動方針の動作証跡（CISO Critical 条件）

#### 4-1. secret list 差分

| 時点 | secrets |
|---|---|
| Phase 1 開始時（teardown 前） | `CLAUDE_CODE_OAUTH_TOKEN`（2026-05-08T14:05:11Z 作成） |
| Phase 1.2 完了時（teardown 後） | （空、全 secret 削除確認） |
| Phase 2 完了時（再導入後） | `VIBEHAWK_APP_ID`（08:39:54Z）<br>`VIBEHAWK_PRIVATE_KEY`（08:42:29Z）<br>`CLAUDE_CODE_OAUTH_TOKEN`（08:49:25Z、新規取得） |

3 secrets すべて Phase 2 中に CEO が GitHub Settings UI で **手動登録**。`CLAUDE_CODE_OAUTH_TOKEN` のタイムスタンプも teardown 前 (`05-08T14:05:11Z`) から更新後 (`05-10T08:49:25Z`) に変わっており、別 token が登録されたことが確認できる。

#### 4-2. CLI が `gh secret set` を呼ばないことの grep 証跡

```bash
$ grep -rn "gh secret set" cli/ | grep -v "^[^:]*://" | grep -v "^[^:]*:[0-9]*://" | grep -vE "^[^:]+:[0-9]+:\s*//"
✅ コメント以外で gh secret set の呼び出しなし（CISO 条件遵守の証跡）
```

`cli/setup.js` および `cli/verify.js` の冒頭コメントには「CLI は secret を一切 touch しない」と明記されており、grep でも実呼び出し 0 件を確認。`docs/secrets-handling.md` 案 2「全手動方針」が dogfooding 実機検証で担保された。

## 成果

| 項目 | 結果 |
|---|---|
| Phase 1〜4 完走 | ✅ |
| 経路 2 secrets 3 種類 手動登録 | ✅ |
| `gh secret set` CLI 呼び出し不在 | ✅ grep で機械検証済 |
| `vibehawk-for-hirokimry[bot]` 名義投稿 | 本 PR で Phase 3 検証中 |
| 5 分以内完走 (Issue #91 完了条件) | ❌ 51 分（バグ群が原因） |
| ドキュメント `docs/secrets-handling.md` 案 2 動作前提の dogfooding 確認 | ✅ |

## 改善 backlog（dogfooding で発見、本 PR 後に別 Issue 化）

| 優先度 | 内容 | 起票 Issue |
|---|---|---|
| high | hook_attributes.url 必須化 | ✅ [#103](https://github.com/hirokimry/vibehawk/issues/103)（修正済 PR #105） |
| low | clack/prompts 枠線が日本語幅で崩れる | ✅ [#104](https://github.com/hirokimry/vibehawk/issues/104) |
| 高 | App インストール検証が `gh api /user/installations` で 403（個人 token では実行不能、検証経路を変える必要） | （本 PR 後に起票予定） |
| 中 | Private key 取得 URL 案内が `/apps/<slug>` 公開ページ（正しくは `/settings/apps/<slug>` 設定ページ） | （本 PR 後に起票予定） |
| 高 | OAuth token 取得失敗時にウィザードが異常終了し Step 6 に到達しない（リカバリ動線なし） | （本 PR 後に起票予定） |
| 高 | claude alias / vibecorp sandbox 干渉で `claude setup-token` が動かない（Step 5 案内文が不十分） | （本 PR 後に起票予定） |

## 関連

- Issue #56（本 dogfooding 親 Issue）
- Issue #91 / PR #101（setup ウィザード初版）
- Issue #59 / PR #78（経路 2 workflow App Token 認証）
- Issue #61 / PR #77（docs 全面改訂、経路 2 必須化）
- Issue #73 / PR #75（secrets-handling SoT）
- Issue #74 / PR #76（cli/oauth.js 自動登録撤去）
- Issue #57 / PR #80（種別マーカー注入）
- Issue #62（CISO 条件付き承認）
- Issue #25（命名統制）
