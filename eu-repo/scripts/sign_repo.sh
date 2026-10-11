#!/bin/sh
# EU 源签名器 —— T18-e 实建
# 用法：./sign_repo.sh <GPG密钥ID或邮箱>
# 产出：InRelease（clearsign 内嵌）+ Release.gpg（分离签名）
# Sileo/Zebra 验签：InRelease 优先，回退 Release+Release.gpg（A_T18 情报底座 §二.3）
set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "$1" ]; then
  echo "用法: $0 <GPG密钥ID>"
  echo "首建密钥: gpg --quick-gen-key 'Euphoria Repo <repo@euphoria-jb.dev>' ed25519 sign never"
  exit 1
fi
KEY="$1"

[ -f Release ] || { echo "[E] 先运行 build_repo.py"; exit 1; }

rm -f InRelease Release.gpg
gpg --default-key "$KEY" --batch --yes --clearsign -o InRelease Release
gpg --default-key "$KEY" --batch --yes -abs -o Release.gpg Release
echo "[OK] 签名完成：InRelease + Release.gpg"
echo "导出公钥（随源分发，PM 端导入 keyring）:"
echo "  gpg --export --armor $KEY > euphoria-repo.pub.asc"
