#!/bin/bash
# 构建可双击运行的 GitGlass.app（零第三方依赖，直接复用系统 SwiftUI / git / ssh）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "目标架构：$(uname -m)（编译为本机架构；换到不同架构的 Mac 请在本脚本重新构建）"
echo "==> 1/4 编译 release 版本"
# --disable-sandbox：部分受管环境不允许 SwiftPM 嵌套 sandbox-exec；普通 Xcode 环境去掉也无妨。
swift build -c release --disable-sandbox --product GitGlass

BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"
BIN="$BIN_DIR/GitGlass"
if [[ ! -x "$BIN" ]]; then
  echo "找不到可执行文件：$BIN" >&2
  exit 1
fi

APP="$ROOT/dist/GitGlass.app"
echo "==> 2/4 组装 .app bundle"
if pgrep -f "$APP/Contents/MacOS/GitGlass" >/dev/null 2>&1; then
  echo "    [注意] 检测到应用正在运行，覆盖后请退出并重新打开"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN" "$APP/Contents/MacOS/GitGlass"
cp -f "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "    图标缺失，自动生成本地图标"
  swift "$ROOT/scripts/make-icon.swift"
fi
cp -f "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/GitGlass"

echo "==> 3/4 本地签名（ad-hoc）"
if ! codesign --force --deep --sign - "$APP" 2>/dev/null; then
  echo "    codesign 不可用，已跳过（本机仍可直接运行）"
fi

echo "==> 4/4 完成"
echo "应用路径：$APP"
echo "体积：$(du -sh "$APP" | awk '{print $1}')"
echo "启动：open \"$APP\""
echo "换机安装：把整个项目拷到目标 Mac 后运行本脚本，或参见 docs/操作手册.md「安装与迁移」"
