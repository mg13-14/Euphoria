#!/usr/bin/env python3
"""
EU 源索引构建器 —— T18-e 实建（roothide 模式：Flat 结构，零服务器）
用法：python3 build_repo.py [--repo-root ../]
产出：Packages / Packages.gz / Release（签名由 sign_repo.sh 完成）
依赖：dpkg-scanpackages（标准 dpkg-dev 组件，GitHub Actions ubuntu runner 自带）
设计：本地跑完把整个 eu-repo/ 推 GitHub Pages 仓库即可，无任何服务器依赖。
"""
import subprocess, sys, os, hashlib, gzip, datetime, argparse

REQUIRED_FIELDS = ["Architectures", "Components", "Description", "Origin", "Label", "Suite"]

def run(cmd, cwd):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"[E] {' '.join(cmd)} 失败:\n{r.stderr}")
    return r.stdout

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", default=os.path.join(os.path.dirname(__file__), ".."))
    ap.add_argument("--origin", default="Euphoria")
    ap.add_argument("--label", default="Euphoria Official Source")
    ap.add_argument("--suite", default="./")
    ap.add_argument("--arch", default="iphoneos-arm64")  # rootless 单架构（A_T18 情报底座 §一.2）
    ap.add_argument("--desc", default="Euphoria EU 官方源（Flat 结构）")
    args = ap.parse_args()

    root = os.path.abspath(args.repo_root)
    pool = os.path.join(root, "pool")
    if not os.path.isdir(pool):
        sys.exit(f"[E] 找不到 {pool}，请在 eu-repo/ 下运行")

    # 1. 扫描 pool 生成 Packages（flat 语义：Filename 相对 repo 根）
    print("[1/3] dpkg-scanpackages 扫描 pool/ ...")
    raw = run(["dpkg-scanpackages", "--multiversion", "pool"], cwd=root)

    # 2. 架构白名单过滤（防 all/any 双域可见坑：A_T18 情报底座 §一.4）
    print("[2/3] 架构过滤（仅 iphoneos-arm64，all 包显式放行需改 --arch）...")
    blocks, keep = raw.split("\n\n"), []
    for b in blocks:
        if not b.strip():
            continue
        arch = next((l.split(":", 1)[1].strip() for l in b.splitlines()
                     if l.startswith("Architecture:")), "")
        if arch == args.arch or arch == "all":  # all 包默认放行（本源目前无 all 包）
            keep.append(b)
        else:
            print(f"    [skip] 架构 {arch} 不匹配，已滤除")
    packages = "\n\n".join(keep) + "\n"

    with open(os.path.join(root, "Packages"), "w") as f:
        f.write(packages)
    with gzip.open(os.path.join(root, "Packages.gz"), "wb") as f:
        f.write(packages.encode())
    n = packages.count("Package:")
    print(f"    Packages 索引完成：{n} 个包")

    # 3. 生成 Release（含哈希清单；Date 用 UTC RFC1123）
    print("[3/3] 生成 Release ...")
    def sums(path):
        data = open(os.path.join(root, path), "rb").read()
        md5 = hashlib.md5(data).hexdigest(); sha = hashlib.sha256(data).hexdigest()
        return f" {md5} {sha} {len(data)} {path}"
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S UTC")
    release = (
        f"Origin: {args.origin}\nLabel: {args.label}\nSuite: {args.suite}\n"
        f"Version: 1.0\nCodename: {args.suite}\n"
        f"Architectures: {args.arch}\nComponents: main\n"
        f"Description: {args.desc}\nDate: {date}\n"
        f"MD5Sum:\n{sums('Packages')}\n{sums('Packages.gz')}\n"
        f"SHA256:\n{sums('Packages')}\n{sums('Packages.gz')}\n"
    )
    with open(os.path.join(root, "Release"), "w") as f:
        f.write(release)
    print("    Release 完成。下一步：./sign_repo.sh <GPG密钥ID> 生成 InRelease/Release.gpg")
    print("[OK] EU 源构建完成。部署：整个 eu-repo/ 推 GitHub Pages 仓库（见 README.md）")

if __name__ == "__main__":
    main()
