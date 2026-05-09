#!/usr/bin/env node
// vibehawk CLI entry
// usage: npx vibehawk <command>

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
  npx vibehawk install                      GitHub App Manifest Flow を起動して vibehawk App を作成
  npx vibehawk setup-token [--repo OWNER/REPO]   Claude OAuth Token を取得し GitHub Settings 登録手順を案内（CLI は secret を書き込まない）
  npx vibehawk help                         このヘルプを表示
  npx vibehawk version                      バージョンを表示

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
