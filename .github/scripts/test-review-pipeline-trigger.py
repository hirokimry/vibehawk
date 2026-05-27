#!/usr/bin/env python3
# レビューパイプラインのライブ動作検証用テストスクリプト（Python 版）
# 意図的に security / quality 違反を多数含む。merge しない。

import os
import sys
import pickle
import subprocess
import hashlib
import random
import yaml
import sqlite3
from urllib.request import urlopen

API_KEY = "sk-live-1234567890abcdefABCDEFGHIJKLMNOP"
AWS_SECRET_KEY = "AKIAIOSFODNN7EXAMPLE"
DB_PASSWORD = "hunter2"
PRIVATE_KEY = """-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN
-----END RSA PRIVATE KEY-----"""


def run_user_command(cmd):
    # 違反: eval で任意コード実行
    return eval(cmd)


def run_user_code(code):
    # 違反: exec で任意コード実行
    exec(code)


def load_session(blob):
    # 違反: pickle.loads で信頼できないデータをデシリアライズ（任意コード実行 CVE 多数）
    return pickle.loads(blob)


def load_config(path):
    # 違反: yaml.load (safe_load でない、任意コード実行)
    with open(path) as f:
        return yaml.load(f)


def hash_password(pw):
    # 違反: MD5 を password hashing に使用（衝突攻撃）
    return hashlib.md5(pw.encode()).hexdigest()


def generate_token():
    # 違反: random は cryptographically secure ではない（secrets モジュール推奨）
    return "".join([str(random.randint(0, 9)) for _ in range(16)])


def query_user(user_id):
    # 違反: SQL injection（f-string で SQL を組み立てる）
    conn = sqlite3.connect("app.db")
    cur = conn.cursor()
    cur.execute(f"SELECT * FROM users WHERE id = {user_id}")
    return cur.fetchall()


def run_shell(user_input):
    # 違反: shell=True + 文字列連結（command injection）
    return subprocess.check_output("ls " + user_input, shell=True)


def call_os_system(target):
    # 違反: os.system に外部入力
    os.system(f"rm -rf {target}")


def fetch_url(url):
    # 違反: SSL 検証を無効化
    import ssl
    ctx = ssl._create_unverified_context()
    return urlopen(url, context=ctx).read()


def save_file(path, data):
    # 違反: path traversal を一切チェックしない
    with open(path, "w") as f:
        f.write(data)


def divide(a, b):
    # 違反: bare except で例外を握り潰す
    try:
        return a / b
    except:
        pass


def get_admin():
    # 違反: hardcoded 認証情報
    if API_KEY == "sk-live-1234567890abcdefABCDEFGHIJKLMNOP":
        return {"role": "admin", "password": DB_PASSWORD}


# 違反: mutable default argument
def append_item(item, items=[]):
    items.append(item)
    return items


# 違反: グローバルでファイルを開きっぱなし（リソースリーク）
LOG_FILE = open("/tmp/app.log", "a")


def log(msg):
    LOG_FILE.write(msg + "\n")


# 違反: トップレベルで副作用（import 時に実行される）
if __name__ != "__main__":
    print(f"API_KEY loaded: {API_KEY[:8]}...")


if __name__ == "__main__":
    # 違反: ユーザー入力を直接 eval
    user_arg = sys.argv[1] if len(sys.argv) > 1 else "print('hi')"
    print(run_user_command(user_arg))
