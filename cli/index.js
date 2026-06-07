#!/usr/bin/env node

'use strict';

const command = process.argv[2];

const commands = {
  install: () => require('./install').run().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  }),
  'setup-token': () => require('./oauth').setupToken().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  }),
  // Issue #91: 対話型ウィザードで全 6 ステップを 1 コマンドに集約
  setup: () => require('./setup').run().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  }),
  // Issue #331: push 前ローカルレビュー（read-only、claude -p の Pro/Max 枠）。run() は exit code を返す
  review: () => process.exit(require('./review').run()),
  help: () => printHelp(),
  '--help': () => printHelp(),
  '-h': () => printHelp(),
  version: () => printVersion(),
  '--version': () => printVersion(),
  '-v': () => printVersion(),
};

function printHelp() {
  console.log(`vibehawk CLI

usage:
  npx vibehawk setup [--owner USER] [--repo OWNER/REPO] [--dry-run]   対話型ウィザードで全 6 ステップ（App 作成 → インストール → 3 secrets 登録 → workflow PR）を 1 コマンドに集約（CLI は secret を書き込まない、推奨）
  npx vibehawk install [--repo OWNER/REPO] [--overwrite]              GitHub App Manifest Flow を起動して vibehawk App を作成（--repo 指定時は workflow ファイル PR も自動作成、既存ファイル衝突時は --overwrite で上書き、CLI は secret を書き込まない）
  npx vibehawk setup-token [--repo OWNER/REPO]                        Claude OAuth Token を取得し GitHub Settings 登録手順を案内（CLI は secret を書き込まない）
  npx vibehawk review [--staged] [--base <ref>] [--intent <label>] [--output text|json] [--fail-on <severity>]
                                                                      push 前に手元の diff を CI と同一基準でレビュー（read-only、claude -p の Pro/Max 枠、追加課金ゼロ）
  npx vibehawk help                                                   このヘルプを表示
  npx vibehawk version                                                バージョンを表示

詳細: https://github.com/hirokimry/vibehawk
`);
}

function printVersion() {
  const pkg = require('../package.json');
  console.log(pkg.version);
}

function main() {
  if (!command) {
    printHelp();
    process.exit(0);
  }
  const handler = commands[command];
  if (!handler) {
    console.error(`vibehawk: 未知のコマンド '${command}'`);
    console.error(`'npx vibehawk help' でヘルプを表示できます`);
    process.exit(1);
  }
  handler();
}

main();
