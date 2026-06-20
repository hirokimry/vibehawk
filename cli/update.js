'use strict';

// Issue #371: 導入済みリポジトリの workflow を最新版（最新タグの commit SHA）に更新する。
//
// 設計判断:
// - install.run() は --overwrite でも必ず Manifest Flow を実行し新しい App を作成するため、
//   更新には使えない（App 重複作成・命名衝突。#372 で判明）。
// - update は install.createWorkflowPr({ overwrite: true }) に委譲する。これは App 作成を伴わず、
//   最新タグ→commit SHA を解決して __VIBEHAWK_REF__ を置換し、workflow を上書きする更新 PR を出す。
// - secret 再登録は不要（workflow ファイルのみの更新）。

const install = require('./install');
const { parseRepoArg } = require('./oauth');

async function run({ argv = process.argv.slice(3) } = {}) {
  const repo = parseRepoArg(argv);
  if (!repo) {
    throw new Error(
      'vibehawk: --repo <owner>/<repo> を指定してください（例: npx vibehawk update --repo alice/my-app）'
    );
  }

  console.log(
    `vibehawk: ${repo} の workflow を最新版に更新します（App 作成は行いません、secret 再登録は不要）`
  );

  // App 作成（Manifest Flow）を伴わず workflow のみを上書き更新する（install.run は呼ばない）
  const result = await install.createWorkflowPr({ repo, overwrite: true });

  if (result && result.skipped) {
    const existing = (result.existingFiles || []).join(', ');
    console.log(
      `vibehawk: workflow 更新をスキップしました（${result.reason}）: ${existing}`
    );
    return result;
  }

  console.log(`✅ vibehawk: workflow 更新 PR を作成しました: ${result && result.url}`);
  console.log('   PR をマージすると workflow が最新版（commit SHA pin）に更新されます。');
  return result;
}

module.exports = { run };
