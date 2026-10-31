#!/usr/bin/env python3
"""通过 GitHub REST contents API 推送文件更新（绕过被代理阻断的 git over https）。

背景：本机 git 走 HTTPS 代理连 github.com 会返回 502（CONNECT tunnel failed），
但 api.github.com 可正常访问。本脚本直接用 contents API 提交文件，
同样会生成 commit 并触发 GitHub Actions。

用法：
    GH_TOKEN=<pat> python3 scripts/gh_push_api.py "<commit message>" <file1> [file2 ...]
"""
import os
import sys
import json
import base64
import urllib.request
import urllib.error

TOKEN = os.environ["GH_TOKEN"]
OWNER = os.environ.get("GH_OWNER", "shierduan")
REPO = os.environ.get("GH_REPO", "ssh-ios-client")
BRANCH = os.environ.get("GH_BRANCH", "main")

HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}


def request(method, path, data=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(
        f"https://api.github.com{path}", data=body, method=method, headers=HEADERS
    )
    return json.loads(urllib.request.urlopen(req, timeout=60).read())


def sync_file(api_path, local_path, message):
    with open(local_path, "rb") as fh:
        content_b64 = base64.b64encode(fh.read()).decode()

    sha = None
    try:
        current = request("GET", f"/repos/{OWNER}/{REPO}/contents/{api_path}?ref={BRANCH}")
        sha = current.get("sha")
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise

    payload = {"message": message, "content": content_b64, "branch": BRANCH}
    if sha:
        payload["sha"] = sha

    result = request("PUT", f"/repos/{OWNER}/{REPO}/contents/{api_path}", payload)
    commit = result.get("commit", {}).get("sha", "?")
    print(f"  updated {api_path} -> commit {commit}")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    message = sys.argv[1]
    files = sys.argv[2:]
    print(f"Syncing {len(files)} file(s) to {OWNER}/{REPO}@{BRANCH} ...")
    for path in files:
        api_path = path.replace("\\", "/")
        # 只去掉一次前缀 "./"，不能用 lstrip("./") —— 那会把 ".github" 的点也吃掉
        if api_path.startswith("./"):
            api_path = api_path[2:]
        sync_file(api_path, path, message)
    print("Done. CI will be triggered on push to", BRANCH)


if __name__ == "__main__":
    main()
