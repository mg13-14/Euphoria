#!/bin/bash
# package_ipa.sh —— 重打包入口（B 线新版，2026-09-03；旧 THEOS 版已废）
# 用途：不重编译，从 build/TrollE-Installer.app 重出双产物
#   TrollE-Installer.tipa（ldid -SEntitlements.plist：巨魔/TrollStore 通道，保留特权）
#   TrollE-Installer.ipa（侧载通道：AltStore/SideStore/Sideloadly 重签）
# 全新构建请直接 `make`（本脚本=make package 的纯打包子集）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/build/TrollE-Installer.app"
BUILD="$ROOT/build"

[ -d "$APP_DIR" ] || { echo "❌ 缺 build/TrollE-Installer.app（先 make）"; exit 1; }
command -v ldid >/dev/null || { echo "❌ 缺 ldid（brew install ldid）"; exit 1; }

xattr -rc "$APP_DIR" 2>/dev/null || true
# 主二进制：带 entitlements 签（ldid 无文件参数时保留既有 ents，故顺序重要）
ldid -S"$ROOT/Entitlements.plist" "$APP_DIR/TrollE-Installer"
# 递归 adhoc：frameworks + libjailbreak + libchoma
ldid -s "$APP_DIR"

rm -rf "$BUILD/Payload" "$BUILD/TrollE-Installer.tipa" "$BUILD/TrollE-Installer.ipa"
mkdir -p "$BUILD/Payload"
cp -R "$APP_DIR" "$BUILD/Payload/"
(cd "$BUILD" && zip -qry TrollE-Installer.tipa Payload)
cp "$BUILD/TrollE-Installer.tipa" "$BUILD/TrollE-Installer.ipa"

echo "✅ $BUILD/TrollE-Installer.tipa  ← 巨魔/TrollStore 通道（保留 entitlements）"
echo "✅ $BUILD/TrollE-Installer.ipa   ← 侧载通道（AltStore/SideStore/Sideloadly）"
