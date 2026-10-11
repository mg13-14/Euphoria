#!/bin/bash
# package-deb.sh —— TrollE-Installer deb 形态（eu-repo 源生态；B 线 2026-09-03）
# 用法：package-deb.sh <app_dir> <version>
# 布局：DEBIAN/{control,postinst} + Applications/TrollE-Installer.app（本体 .app 整体入包）
# 依赖：dpkg-deb（brew install dpkg）
set -euo pipefail

APP_DIR="$1"; VERSION="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d)"

[ -d "$APP_DIR" ] || { echo "❌ 缺 .app：$APP_DIR（先 make）"; exit 1; }
command -v dpkg-deb >/dev/null || { echo "❌ 缺 dpkg-deb（brew install dpkg）"; exit 1; }

# 版本号回写 control（保持单一事实源=命令行参数）
sed -i.bak "s/^Version: .*/Version: $VERSION/" "$ROOT/DEBIAN/control" && rm -f "$ROOT/DEBIAN/control.bak"

# 2026-09-07 C 修复（用户 19:47 截图+A 根因锁定）：载荷路径全量加 var/jb 前缀——
# rootless 越狱的 dpkg root=/，./Applications 落地系统只读卷（Read-only file system
# 实锤）；Procursus 对照组 69 包全带 var/jb 前缀。./var/jb/Applications → bind 后可写。
mkdir -p "$STAGE/var/jb/Applications"
cp -R "$APP_DIR" "$STAGE/var/jb/Applications/TrollE-Installer.app"
cp -R "$ROOT/DEBIAN" "$STAGE/DEBIAN"
# postinst 权限（dpkg 要求可执行）
chmod 755 "$STAGE/DEBIAN/postinst"

OUT="$ROOT/build/TrollE-Installer_${VERSION}_iphoneos-arm64.deb"
dpkg-deb --build -Zgzip "$STAGE" "$OUT"
rm -rf "$STAGE"
echo "✅ $OUT"
