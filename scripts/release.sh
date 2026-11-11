#!/bin/bash
# 发布新版本：校验 -> 本地自检 -> 打 tag -> 推送，CI 会自动构建并发布 Release。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "用法：./scripts/release.sh v1.2.0" >&2
  exit 1
fi
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "版本号格式应为 vX.Y.Z，例如 v1.2.0" >&2
  exit 1
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前目录不是 git 仓库，请先从 GitHub clone" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "工作区有未提交改动，请先提交或储藏" >&2
  exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "tag $TAG 已存在" >&2
  exit 1
fi

PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
if [[ "$PLIST_VERSION" != "${TAG#v}" ]]; then
  echo "Info.plist 版本（$PLIST_VERSION）与 tag（${TAG#v}）不一致，请先更新" >&2
  exit 1
fi

echo "==> 本地自检"
swift run --disable-sandbox GitGlassSelfTest | tee /tmp/gitglass-release-selftest.log | tail -3
if ! grep -q "0 失败" /tmp/gitglass-release-selftest.log; then
  echo "自检未全通过，已中止发布" >&2
  exit 1
fi

echo "==> 创建并推送 tag：$TAG"
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"
echo "完成。GitHub Actions 的 Release 工作流会自动生成 .app 与分发 zip 并发布到 Releases 页面。"
