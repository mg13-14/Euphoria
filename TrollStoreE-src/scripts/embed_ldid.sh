#!/bin/bash
# TrollStoreE 构建期脚本：嵌入自带 ldid（iOS arm64, Procursus 2.1.5）
# 用法: 在 theos 构建产物 Payload/TrollStoreE.app 上执行（macOS 需 install_name_tool）
set -e
APP_DIR="$1"  # 传 Payload/TrollStoreE.app 路径
[ -z "$APP_DIR" ] && APP_DIR="$(ls -d .theos/obj/Payload/TrollStoreE.app 2>/dev/null || ls -d packages/Payload/TrollStoreE.app 2>/dev/null)"
KIT="TrollStore/Resources/ldid-ios-kit"

# 1) dylib 依赖 → Frameworks/
mkdir -p "$APP_DIR/Frameworks"
cp "$KIT"/lib/*.dylib "$APP_DIR/Frameworks/"

# 2) ldid 本体 → Resources（spawn 时用绝对路径调用）
cp "$KIT"/bin/ldid "$APP_DIR/Resources/ldid"

# 3) 改 LC_RPATH: /var/jb/usr/lib → @executable_path/Frameworks（install_name_tool，mac 构建机自带）
install_name_tool -rpath /var/jb/usr/lib @executable_path/Frameworks "$APP_DIR/Resources/ldid" 2>/dev/null || \
install_name_tool -add_rpath @executable_path/Frameworks "$APP_DIR/Resources/ldid"

# 4) 重签 ldid（构建管线自带 ldid/fastPathSign 时用）
echo "[embed_ldid] done → $APP_DIR/Resources/ldid + Frameworks/{libiosexec,libplist-2,libssl,libcrypto}.dylib"
