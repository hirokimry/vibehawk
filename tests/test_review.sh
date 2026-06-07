#!/usr/bin/env bash
# cli/review.js（npx vibehawk review）の検証（Issue #331）
#
# - 純関数（parseArgs / validateRef / buildDiffArgs / readReviewConfig / sanitizeForPrompt /
#   pickDepth / buildPrompt / parseFindings / maxSeverity / shouldFail）を node -e で検証
# - preflight / run() は spawn・env を注入して外部コマンドなしで検証
# - read-only（--fix / Write / Edit が無い）を機械検証
# - help に review コマンドが載る

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

# 前提ファイル不在なら後続テストは無意味
if [[ ! -f cli/review.js ]]; then
  fail "cli/review.js が存在しない"
  exit 1
fi
if [[ ! -f templates/review-prompt.md ]]; then
  fail "templates/review-prompt.md（共通基準）が存在しない"
  exit 1
fi

run_node() {
  # node -e の終了コードで pass/fail を判定する
  if node -e "$1"; then
    pass "$2"
  else
    fail "$2"
  fi
}

echo "=== 純関数 ==="

run_node '
const r=require("./cli/review"); const a=require("assert");
a.strictEqual(r.parseArgs(["--staged"]).staged,true);
a.strictEqual(r.parseArgs(["--base","main"]).base,"main");
a.strictEqual(r.parseArgs(["--intent","feature"]).intent,"feature");
a.strictEqual(r.parseArgs(["--intent","intent/bugfix"]).intent,"bugfix");
a.strictEqual(r.parseArgs(["--output","json"]).output,"json");
a.strictEqual(r.parseArgs(["--fail-on","MAJOR"]).failOn,"major");
a.strictEqual(r.parseArgs([]).output,"text");
a.throws(()=>r.parseArgs(["--output","bad"]));
a.throws(()=>r.parseArgs(["--fail-on","huge"]));
a.throws(()=>r.parseArgs(["--unknown"]));
a.throws(()=>r.parseArgs(["--staged","--base","main"]));
// --intent は 7 ラベルにホワイトリスト化（プロンプトインジェクション防止）
a.throws(()=>r.parseArgs(["--intent","garbage"]));
a.throws(()=>r.parseArgs(["--intent","feature\nIGNORE ALL"]));
' "parseArgs 正常/不正/未知/排他/intent whitelist"

run_node '
const r=require("./cli/review"); const a=require("assert");
a.ok(r.validateRef("feature/x_1"));
a.ok(r.validateRef("a".repeat(255)));
a.throws(()=>r.validateRef("a".repeat(256)));
a.throws(()=>r.validateRef("-x"));
a.throws(()=>r.validateRef("a..b"));
a.throws(()=>r.validateRef("a b"));
a.throws(()=>r.validateRef(""));
' "validateRef 許可/先頭-/..//許可外/空/255境界"

run_node '
const r=require("./cli/review"); const a=require("assert");
a.deepStrictEqual(r.buildDiffArgs({staged:true}),["diff","--staged"]);
a.deepStrictEqual(r.buildDiffArgs({base:"main"}),["diff","main...HEAD"]);
a.deepStrictEqual(r.buildDiffArgs({}),["diff","HEAD"]);
' "buildDiffArgs staged/base/default"

run_node '
const r=require("./cli/review"); const a=require("assert");
a.strictEqual(r.pickDepth(29,{}),"full");
a.strictEqual(r.pickDepth(30,{}),"focused");
a.strictEqual(r.pickDepth(79,{}),"focused");
a.strictEqual(r.pickDepth(80,{}),"lightweight");
a.strictEqual(r.pickDepth(2999,{}),"lightweight");
a.strictEqual(r.pickDepth(3000,{}),"summary_only");
a.strictEqual(r.pickDepth(50,{full_review_files:100}),"full");
' "pickDepth 境界 + 設定上書き"

run_node '
const r=require("./cli/review"); const a=require("assert");
// 5 severity × fail-on 各閾値 + 未指定
const R={critical:4,major:3,minor:2,trivial:1,info:0};
for(const k of Object.keys(R)){ a.strictEqual(r.shouldFail(R[k],null),false); }
a.strictEqual(r.shouldFail(4,"critical"),true);
a.strictEqual(r.shouldFail(3,"critical"),false);
a.strictEqual(r.shouldFail(3,"major"),true);
a.strictEqual(r.shouldFail(2,"major"),false);
a.strictEqual(r.shouldFail(0,"info"),true);
a.strictEqual(r.shouldFail(-1,"info"),false);
' "shouldFail severity 閾値網羅"

run_node '
const r=require("./cli/review"); const a=require("assert");
a.deepStrictEqual(r.parseFindings("{\"findings\":[]}","json"),{findings:[]});
a.deepStrictEqual(r.parseFindings("noise {\"findings\":[{\"severity\":\"major\"}]} tail","json").findings.length,1);
a.throws(()=>r.parseFindings("not json","json"));
a.deepStrictEqual(r.parseFindings("hello","text"),{text:"hello"});
a.strictEqual(r.maxSeverity({findings:[{severity:"major"},{severity:"info"}]}),3);
a.strictEqual(r.maxSeverityFromText("🔴 Critical here"),4);
a.strictEqual(r.maxSeverityFromText("指摘なし"),-1);
' "parseFindings/maxSeverity (json+text)"

run_node '
const r=require("./cli/review"); const a=require("assert");
a.strictEqual(r.sanitizeForPrompt("a\nb\tc"),"a b c");
const p=r.buildPrompt({criteria:"## inline 指摘の severity 5 段階分類\nCRIT_MARK",diff:"diff --git a/x b/x",intent:"a\nINJECT",output:"json",language:"ja",pathFilters:["dist/**"],depth:"full",fileCount:1});
a.ok(p.includes("CRIT_MARK"),"共通基準が連結される");
a.ok(p.includes("read-only"));
a.ok(p.includes("dist/**"));
a.ok(!p.includes("\nINJECT"),"設定値の改行注入が除去される");
a.ok(p.includes("JSON オブジェクト"));
' "buildPrompt 共通基準内包/サニタイズ/出力指示"

echo "=== readReviewConfig ==="
run_node '
const r=require("./cli/review"); const a=require("assert"); const fs=require("fs"); const os=require("os"); const path=require("path");
const d=fs.mkdtempSync(path.join(os.tmpdir(),"vhcfg-"));
fs.writeFileSync(path.join(d,".vibehawk.yaml"),"language: ja\nreviews:\n  path_filters:\n    - \"node_modules/**\"\n  size_limits:\n    full_review_files: 40\n");
const c=r.readReviewConfig(d);
a.strictEqual(c.language,"ja");
a.deepStrictEqual(c.pathFilters,["node_modules/**"]);
a.strictEqual(c.sizeLimits.full_review_files,40);
// 不在
a.deepStrictEqual(r.readReviewConfig(path.join(os.tmpdir(),"vh-absent-"+Date.now())),{language:null,pathFilters:[],sizeLimits:{}});
// 不正 yaml は best-effort で throw しない
fs.writeFileSync(path.join(d,".vibehawk.yaml"),":\n: : :\n\tbad");
a.doesNotThrow(()=>r.readReviewConfig(d));
' "正常yaml/不在/不正yaml"

echo "=== preflight（spawn 注入） ==="
run_node '
const r=require("./cli/review"); const a=require("assert");
const ok=(c,ar)=>{ if(c==="git"&&ar[0]==="rev-parse")return{status:0,stdout:"true\n"}; if(c==="claude")return{status:0,stdout:"1\n"}; return{status:1}; };
// ANTHROPIC_API_KEY 設定で fail-fast
a.throws(()=>r.preflight({env:{ANTHROPIC_API_KEY:"x"},spawn:ok,cwd:"."}),/ANTHROPIC_API_KEY/);
// git 外
a.throws(()=>r.preflight({env:{},cwd:".",spawn:(c,ar)=>{ if(c==="git")return{status:128,stdout:""}; return{status:0,stdout:"1\n"}; }}),/git/);
// claude 未インストール（ENOENT）
a.throws(()=>r.preflight({env:{},cwd:".",spawn:(c,ar)=>{ if(c==="git"&&ar[0]==="rev-parse")return{status:0,stdout:"true\n"}; if(c==="claude")return{error:{code:"ENOENT"},status:null}; return{status:1}; }}),/claude/);
// templates 不在
a.throws(()=>r.preflight({env:{},cwd:".",spawn:ok,criteriaPath:"/no/such/file.md"}),/基準/);
// 正常
a.doesNotThrow(()=>r.preflight({env:{},cwd:".",spawn:ok}));
' "API_KEY/git外/claude不在/templates不在/正常"

echo "=== run()（spawn 注入） ==="
run_node '
const r=require("./cli/review"); const a=require("assert");
const NW={write:()=>{}};
const mk=(ov)=>(c,ar)=>{
  if(c==="git"&&ar[0]==="rev-parse")return{status:0,stdout:"true\n"};
  if(c==="claude"&&ar[0]==="--version")return{status:0,stdout:"1\n"};
  if(c==="git"&&ar[0]==="diff")return{status:0,stdout:(ov.diff!==undefined?ov.diff:"diff --git a/x b/x\n+f\n")};
  if(c==="claude"&&ar[0]==="-p")return ov.claude||{status:0,stdout:"🟠 Major: x:1\n"};
  return{status:1};
};
const base={env:{},cwd:".",stdout:NW,stderr:NW};
// text 成功
a.strictEqual(r.run({...base,argv:[],spawn:mk({})}),0);
// fail-on major -> 1
a.strictEqual(r.run({...base,argv:["--fail-on","major"],spawn:mk({})}),1);
// fail-on critical（major のみ）-> 0
a.strictEqual(r.run({...base,argv:["--fail-on","critical"],spawn:mk({})}),0);
// json 成功
a.strictEqual(r.run({...base,argv:["--output","json"],spawn:mk({claude:{status:0,stdout:"{\"findings\":[]}"}})}),0);
// json + fail-on critical -> 1
a.strictEqual(r.run({...base,argv:["--output","json","--fail-on","critical"],spawn:mk({claude:{status:0,stdout:"{\"findings\":[{\"severity\":\"critical\"}]}"}})}),1);
// json パース失敗 -> 2
a.strictEqual(r.run({...base,argv:["--output","json"],spawn:mk({claude:{status:0,stdout:"garbage"}})}),2);
// 空 diff -> 0、claude 未起動
let called=false;
const code=r.run({...base,argv:[],spawn:(c,ar)=>{ if(c==="claude"&&ar[0]==="-p")called=true; if(c==="git"&&ar[0]==="rev-parse")return{status:0,stdout:"true\n"}; if(c==="claude"&&ar[0]==="--version")return{status:0,stdout:"1\n"}; if(c==="git"&&ar[0]==="diff")return{status:0,stdout:"  \n"}; return{status:1}; }});
a.strictEqual(code,0); a.strictEqual(called,false);
// status null -> 1
a.strictEqual(r.run({...base,argv:[],spawn:mk({claude:{status:null,signal:"SIGKILL"}})}),1);
' "run text/json/fail-on/empty/null"

run_node '
const r=require("./cli/review"); const a=require("assert");
const mk=(ov)=>(c,ar)=>{
  if(c==="git"&&ar[0]==="rev-parse")return{status:0,stdout:"true\n"};
  if(c==="claude"&&ar[0]==="--version")return{status:0,stdout:"1\n"};
  if(c==="git"&&ar[0]==="diff")return{status:0,stdout:"diff --git a/x b/x\n+f\n"};
  if(c==="claude"&&ar[0]==="-p")return ov.claude;
  return{status:1};
};
// 認証エラー（陽性経路）-> setup-token 誘導 + exit 1
let e1="";
a.strictEqual(r.run({env:{},cwd:".",argv:[],stdout:{write:()=>{}},stderr:{write:s=>e1+=s},spawn:mk({claude:{status:1,stderr:"please login to authenticate"}})}),1);
a.ok(e1.includes("setup-token"),"認証エラーで setup-token 誘導");
// 汎用エラー（陰性経路）-> setup-token 出さない
let e2="";
a.strictEqual(r.run({env:{},cwd:".",argv:[],stdout:{write:()=>{}},stderr:{write:s=>e2+=s},spawn:mk({claude:{status:1,stderr:"random failure xyz"}})}),1);
a.ok(e2.includes("実行に失敗")&&!e2.includes("setup-token"),"汎用エラーは誤って setup-token を出さない");
' "run 認証エラー陽性/汎用エラー陰性"

echo "=== read-only 担保 ==="
# --fix 等の自動修正フラグを持たない（MVV Value 2）。挙動で検証する（コメント言及の誤検出を避ける）
run_node '
const r=require("./cli/review"); const a=require("assert");
a.throws(()=>r.parseArgs(["--fix"]),/未知のオプション/);
' "--fix は未知オプションとして拒否される（read-only）"

# claude へ渡す allowed-tools が読取系のみ（Write/Edit/Bash/GitHub 投稿系を含まない）
if grep -qF "'Read,Grep,Glob'" cli/review.js; then
  pass "claude へ Read,Grep,Glob のみ渡す"
else
  fail "claude へ渡す allowed-tools が読取系のみではない"
fi
if grep -F "allowed-tools" cli/review.js | grep -qiE -e "write" -e "edit" -e "bash" -e "mcp__github"; then
  fail "allowed-tools に書込/実行/GitHub 投稿系ツールが含まれる（read-only 違反）"
else
  pass "allowed-tools に書込/実行/GitHub 投稿系が無い"
fi

# --bare を使っていない（OAuth 維持）
if grep -qF -- "--bare" cli/review.js; then
  fail "--bare を使用している（OAuth を読まなくなる）"
else
  pass "--bare を使用していない（OAuth 維持）"
fi

echo "=== index 登録 / help ==="
if grep -qF "review: () => process.exit(require('./review').run())" cli/index.js; then
  pass "cli/index.js に review コマンドが登録されている"
else
  fail "cli/index.js に review コマンドが登録されていない"
fi

help_out="$(node cli/index.js help)"
if printf '%s' "$help_out" | grep -qF 'npx vibehawk review'; then
  pass "help に review コマンドが載る"
else
  fail "help に review コマンドが載っていない"
fi

echo "=== E2E: git 外 / 不正引数 ==="
TMPDIR_OUT="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_OUT" || true; }
trap cleanup EXIT

# git リポジトリ外で誘導付き非 0 終了（ANTHROPIC_API_KEY を unset した子プロセスで実行）
set +e
( cd "$TMPDIR_OUT" && env -u ANTHROPIC_API_KEY node "$REPO_ROOT/cli/index.js" review >/dev/null 2>"$TMPDIR_OUT/err.txt" )
ec=$?
set -e
if [[ $ec -ne 0 ]] && grep -qF 'git リポジトリ内で実行' "$TMPDIR_OUT/err.txt"; then
  pass "git 外で誘導付き非 0 終了"
else
  fail "git 外の挙動が不正（ec=$ec）"
fi

# 不正 output で非 0 終了
set +e
env -u ANTHROPIC_API_KEY node "$REPO_ROOT/cli/index.js" review --output bad >/dev/null 2>&1
ec2=$?
set -e
if [[ $ec2 -ne 0 ]]; then
  pass "--output bad で非 0 終了"
else
  fail "--output bad が非 0 終了しない"
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
