#!/bin/bash
# sync-from-euphoria.sh —— 从 Euphoria 主树重同步 vendor 与 src 引擎源（B 线 2026-09-03）
# 在 Euphoria 主树 checkout 根目录内执行（shared/Euphoria/）。
# 注意：src/ 的 EUStandalone* 是 C 线解耦版，勿用主树 EUTrollE.m 覆盖——
#       主树引擎演进后需人工比对移植（README §九 的同步记录处登记）。
set -euo pipefail

EUPHORIA_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TGT="$(cd "$(dirname "$0")/.." && pwd)"

echo "主树：$EUPHORIA_ROOT"
echo "独立工程：$TGT"

# ① exploit 源（全量镜像）
rsync -a --delete "$EUPHORIA_ROOT/Application/Euphoria/Exploits/" "$TGT/Exploits/"

# ② vendor 快照（不含构建产物）
rsync -a --delete \
    --exclude 'output' --exclude 'build' \
    --exclude 'tests' --exclude 'ChOma.xcodeproj' --exclude 'cert.p12' \
    "$EUPHORIA_ROOT/BaseBin/ChOma/" "$TGT/vendor/ChOma/"
rsync -a --delete "$EUPHORIA_ROOT/BaseBin/libjailbreak/src/" "$TGT/vendor/libjailbreak/src/"
rsync -a --delete "$EUPHORIA_ROOT/BaseBin/_external/include/" "$TGT/vendor/include/"
rsync -a --delete "$EUPHORIA_ROOT/BaseBin/_external/modules/litehook/" "$TGT/vendor/modules/litehook/"
rsync -a --delete "$EUPHORIA_ROOT/BaseBin/_external/frameworks/IOMobileFramebuffer.framework/" \
    "$TGT/vendor/frameworks/IOMobileFramebuffer.framework/"

echo "✅ 同步完成。构建产物已过期，请重跑 make（根目录）。"
echo "⚠️ src/EUStandaloneInstaller.m 未动——若主树引擎 B 有演进，人工比对移植并登记。"
