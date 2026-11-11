#!/bin/bash
# 在 GitHub 上创建好空仓库后，用这个脚本一键推送完整本地历史。
# 用法：./scripts/push-to-github.sh [owner/repo]，默认 ASAzhangyongchao/ycGitGlass
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPO="${1:-ASAzhangyongchao/ycGitGlass}"
URL="https://github.com/${REPO}.git"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前目录不是 git 仓库" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "工作区有未提交改动，请先提交" >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$URL"
else
  git remote add origin "$URL"
fi

if ! git ls-remote origin >/dev/null 2>&1; then
  echo "无法访问 ${REPO}。请先在 GitHub 网页创建一个空仓库（不要勾选 README / .gitignore / License），" >&2
  echo "或检查本机 git 凭据（HTTPS 需要 GitHub 用户名 + Personal Access Token）。" >&2
  exit 1
fi

echo "==> 推送到 $URL"
if ! git push -u origin main; then
  echo "" >&2
  echo "推送失败：本机 git 还没有 GitHub 写凭据（GitHub 已不支持账号密码）。" >&2
  echo "一次性配置：" >&2
  echo "  1. 打开 https://github.com/settings/tokens 生成 classic PAT，勾选 repo" >&2
  echo "  2. 重新运行本脚本，用户名填 GitHub 账号，密码粘贴 PAT" >&2
  echo "  3. osxkeychain 会记住，之后可直接 git push / 打 tag 发版" >&2
  exit 1
fi
echo "完成：https://github.com/${REPO}"
echo "推送 v1.2.0 tag 可触发自动 Release：git tag -a v1.2.0 -m 'Release v1.2.0' && git push origin v1.2.0"
