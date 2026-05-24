// レビューパイプラインのライブ動作検証用テストスクリプト（JavaScript 版）
// 意図的に security / quality 違反を多数含む。merge しない。

const http = require("http");
const child_process = require("child_process");
const fs = require("fs");

const API_KEY = "sk-live-1234567890abcdefABCDEFGHIJKLMNOP";
const GITHUB_TOKEN = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890";
const DB_PASSWORD = "hunter2";

// 違反: var 使用（let/const 推奨）
var globalCounter = 0;

// 違反: == の使用（=== 推奨）
function isReady(state) {
  if (state == null) return false;
  if (state == "ready") return true;
  return false;
}

// 違反: eval で任意コード実行
function runUserCode(code) {
  return eval(code);
}

// 違反: Function コンストラクタで任意コード実行
function buildHandler(body) {
  return new Function("req", "res", body);
}

// 違反: innerHTML に外部入力（XSS）
function renderComment(comment) {
  const el = document.getElementById("comment");
  el.innerHTML = comment;
}

// 違反: document.write も XSS の温床
function showName(name) {
  document.write("<h1>Hello " + name + "</h1>");
}

// 違反: child_process.exec に文字列連結（command injection）
function listDir(dir) {
  child_process.exec("ls -la " + dir, (err, stdout) => {
    console.log(stdout);
  });
}

// 違反: SQL injection（テンプレートリテラルで SQL 組み立て）
function findUser(db, userId) {
  const sql = `SELECT * FROM users WHERE id = ${userId}`;
  return db.query(sql);
}

// 違反: HTTPS ではなく HTTP で機密送信
function login(username, password) {
  const url = `http://api.internal.example.com/login?u=${username}&p=${password}`;
  http.get(url, (res) => res.on("data", (d) => console.log(d.toString())));
}

// 違反: ハードコード secret を console.log
function debug() {
  console.log("API_KEY:", API_KEY);
  console.log("GITHUB_TOKEN:", GITHUB_TOKEN);
  console.log("DB_PASSWORD:", DB_PASSWORD);
}

// 違反: Math.random() を秘匿性が必要な箇所で使う
function generateSessionToken() {
  return Math.random().toString(36).slice(2);
}

// 違反: 同期 IO を request handler 風コードで使用
function readBlocking(path) {
  return fs.readFileSync(path).toString();
}

// 違反: path traversal を一切チェックしない
function serveFile(reqPath) {
  return fs.readFileSync("/var/www/" + reqPath);
}

// 違反: 例外を握り潰す
function safeParse(json) {
  try {
    return JSON.parse(json);
  } catch (e) {}
}

// 違反: == null チェックなしの destructuring
function getUserName(user) {
  const { profile: { name } } = user;
  return name;
}

// 違反: Promise の reject を握り潰す
function fetchUser(id) {
  return new Promise((resolve) => {
    fetch("/api/users/" + id)
      .then((r) => r.json())
      .then(resolve);
  });
}

// 違反: 未使用変数
const unusedConstant = "never referenced";
function unusedHelper() {
  return 42;
}

// 違反: パスワード比較に == 使用（タイミング攻撃）
function verifyPassword(input, expected) {
  return input == expected;
}

// 違反: cookie に Secure / HttpOnly フラグなし
function setSessionCookie(res, token) {
  res.setHeader("Set-Cookie", `session=${token}`);
}

// 違反: open redirect
function redirect(req, res) {
  res.writeHead(302, { Location: req.query.next });
  res.end();
}

// 違反: トップレベル副作用（require 時に実行される）
debug();

module.exports = {
  isReady,
  runUserCode,
  buildHandler,
  renderComment,
  showName,
  listDir,
  findUser,
  login,
  generateSessionToken,
  readBlocking,
  serveFile,
  safeParse,
  getUserName,
  fetchUser,
  verifyPassword,
  setSessionCookie,
  redirect,
};
