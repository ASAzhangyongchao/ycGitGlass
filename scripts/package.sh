#!/bin/bash
# 生成可迁移的完整分发包：现成 .app + 全源码 + 构建脚本 + 操作手册。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.3.0"
# 顶层目录与包名保持 ASCII，避免其它解压工具对中文条目名乱码
NAME="GitGlass-${VERSION}-macOS26"
OUT="$ROOT/dist/${NAME}.zip"

if [[ ! -d "$ROOT/dist/GitGlass.app" ]]; then
  echo "缺少 dist/GitGlass.app，请先执行：./scripts/build-app.sh" >&2
  exit 1
fi

STAGE_PARENT="$(mktemp -d)"
# 仅清理本脚本自己创建的临时目录
trap 'rm -rf "$STAGE_PARENT"' EXIT
STAGE="$STAGE_PARENT/$NAME"
mkdir -p "$STAGE"

cp -R "$ROOT/dist/GitGlass.app" "$STAGE/"
cp "$ROOT/Package.swift" "$STAGE/"
cp "$ROOT/README.md" "$STAGE/"
cp "$ROOT/CHANGELOG.md" "$STAGE/"
cp "$ROOT/CONTRIBUTING.md" "$STAGE/"
cp "$ROOT/LICENSE" "$STAGE/"
cp "$ROOT/.gitignore" "$STAGE/"
cp -R "$ROOT/Sources" "$STAGE/"
cp -R "$ROOT/Resources" "$STAGE/"
cp -R "$ROOT/scripts" "$STAGE/"
cp -R "$ROOT/docs" "$STAGE/"
cp -R "$ROOT/.github" "$STAGE/"
# 图标中间产物不进分发包
rm -rf "$STAGE/Resources/AppIcon.iconset"
# 同一份手册的 ASCII 文件名副本，方便在文件名编码异常时仍能打开
cp "$ROOT/docs/操作手册.md" "$STAGE/docs/UserGuide.md"
cp "$ROOT/docs/操作手册.html" "$STAGE/docs/UserGuide.html"

rm -f "$OUT"
# ditto 会保留 .app 的代码签名与扩展属性，比普通 zip 更适合 macOS 应用
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$OUT"

echo "分发包：$OUT"
echo "体积：$(du -sh "$OUT" | awk '{print $1}')"
echo "内容：应用 / 完整 Swift 源码 / Package.swift / Resources / scripts / docs / README"
echo "校验：unzip -l \"$OUT\" | head -20"
