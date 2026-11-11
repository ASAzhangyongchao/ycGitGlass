#!/bin/bash
# 一键推送完整本地历史。绝不静默等待凭据输入：缺认证时快速失败并给出明确下一步。
#
# 用法：
#   ./scripts/push-to-github.sh                  # HTTPS（已配置凭据时）
#   ./scripts/push-to-github.sh --auth          # 交互式把 PAT 存入 osxkeychain 后推送
#   ./scripts/push-to-github.sh --ssh           # 走 SSH（需先把公钥加到 GitHub）
#   ./scripts/push-to-github.sh owner/repo      # 指定其它仓库
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="https"
REPO="ASAzhangyongchao/ycGitGlass"
case "${1:-}" in
  --ssh)  MODE="ssh";  REPO="${2:-$REPO}" ;;
  --auth) MODE="auth"; REPO="${2:-$REPO}" ;;
  "")     ;;
  *)      REPO="$1" ;;
esac

# 关键：禁止 git 弹出交互提示（否则在没有凭据的终端里会一直挂起）
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/echo
# 网络低速/无响应 15 秒就断开，不会「半天没反应」
GIT_NET_OPTS=(-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=15 -c credential.interactive=never)

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前目录不是 git 仓库" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "工作区有未提交改动，请先提交" >&2
  exit 1
fi

if [[ "$MODE" == "ssh" ]]; then
  URL="git@github.com:${REPO}.git"
  echo "==> 检查 SSH 认证"
  SSH_OUT="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
             -T git@github.com 2>&1 || true)"
  if ! grep -qi "successfully authenticated\|Hi .*You've successfully" <<<"$SSH_OUT"; then
    echo "SSH 认证未通过：$SSH_OUT" >&2
    echo "请先把本机公钥加到 https://github.com/settings/keys" >&2
    echo "公钥：$(cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || echo '未找到 ~/.ssh/id_ed25519.pub')" >&2
    exit 1
  fi
  echo "    SSH 认证通过"
else
  URL="https://github.com/${REPO}.git"
fi

if [[ "$MODE" == "auth" ]]; then
  echo "==> 配置一次性凭据"
  read -r -p "GitHub 用户名 [ASAzhangyongchao]: " GH_USER
  GH_USER="${GH_USER:-ASAzhangyongchao}"
  read -r -s -p "粘贴 GitHub PAT（输入不回显，不会写入历史或日志）: " GH_PAT
  echo
  if [[ -z "$GH_PAT" ]]; then
    echo "PAT 为空，已取消" >&2
    exit 1
  fi
  printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' \
    "$GH_USER" "$GH_PAT" | git credential-osxkeychain store
  unset GH_PAT
  echo "    凭据已存入 osxkeychain，以后无需重复输入"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$URL"
else
  git remote add origin "$URL"
fi

if ! git "${GIT_NET_OPTS[@]}" ls-remote origin >/dev/null 2>&1; then
  echo "无法访问 ${REPO}（网络不通、仓库不存在或没有读权限）。" >&2
  echo "提示：私有仓库需要凭据，可先运行 ./scripts/push-to-github.sh --auth" >&2
  exit 1
fi

echo "==> 推送到 $URL"
if ! git "${GIT_NET_OPTS[@]}" push -u origin main; then
  echo "" >&2
  echo "推送失败：本机 git 没有 GitHub 写凭据，已快速失败（不会卡住）。" >&2
  echo "任选一条：" >&2
  echo "  A. ./scripts/push-to-github.sh --auth    # 生成 PAT 后粘贴一次，自动存 Keychain" >&2
  echo "  B. 把公钥加到 https://github.com/settings/keys，再运行 ./scripts/push-to-github.sh --ssh" >&2
  echo "     公钥：$(cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || echo '未找到')" >&2
  exit 1
fi

echo "完成：https://github.com/${REPO}"
echo "推送 tag 可触发自动 Release：git tag -a v1.2.0 -m 'Release v1.2.0' && git push origin v1.2.0"
