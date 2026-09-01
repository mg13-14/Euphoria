# EU 官方源（eu-repo）——T18-e 实建交付

> 模式：roothide 同款 Flat 结构 + GitHub Pages 零服务器分发（A_T18 情报底座 §五方案 A）。
> 状态：**实体已建成**（索引构建器/签名器/首包巨魔E 安装器 deb 全通，测试密钥端到端验签通过）。
> 交付人：并行搜索员A，2026-08-28 凌晨（应汇总员 00:25:01 派件②）。

## 目录结构（=GitHub Pages 站点根，整目录推送即部署）

```
eu-repo/
├── Packages            ← 索引（Flat 直放根，Sileo/Zebra/apt 通用）
├── Packages.gz
├── Release             ← 元数据（Architectures: iphoneos-arm64 —— 从 Day1 就写对）
├── Release.gpg         ← 分离签名（Sileo 验签回退路径）
├── InRelease           ← 内嵌签名（Sileo 验签优先路径）
├── pool/main/          ← deb 包池（Packages 内相对路径引用）
│   └── dev.euphoria.trolle-installer_0.9.1_iphoneos-arm64.deb  ← 首包（巨魔E 安装器）
└── scripts/
    ├── build_repo.py   ← 索引构建器（dpkg-scanpackages + 架构过滤 + Release 生成）
    └── sign_repo.sh    ← GPG 签名器（InRelease + Release.gpg）
```

## 发布流程（每次更新）

```bash
# 1. 放新 deb 进 pool/main/（命名：<id>_<version>_<arch>.deb）
# 2. 重建索引
python3 scripts/build_repo.py
# 3. 签名（生产密钥，见下节）
sh scripts/sign_repo.sh <密钥ID>
# 4. 整目录推 Pages 仓库
git add -A && git commit -m "repo: add <包名>" && git push
```

## 一次性设置

1. **建 Pages**：GitHub 建仓（如 `euphoria-jb/euphoria-jb.github.io` 或项目仓）→ Settings → Pages → 选 main 分支根。整目录推上去即上线。
2. **生产密钥**（勿用测试密钥出货）：
   ```bash
   gpg --quick-gen-key "Euphoria Repo <repo@域名>" ed25519 sign never
   gpg --export --armor <密钥ID> > euphoria-repo.pub.asc   # 公钥随源分发
   ```
3. **自有域名**（可选，不阻塞上线）：仓库放 CNAME 文件，Pages 绑定——T18-0 域名定案后单点切换。

## 客户端接入

- Sileo/Zebra 手动添加源 URL：`https://euphoria-jb.github.io/`（或自有域名；Suite=`./`）
- PresetSources.plist 预置条目（T18-d 首装集成时接，参考 roothide 条目形状）：
  ```xml
  <dict>
    <key>Key</key><string>euphoria</string>
    <key>URL</key><string>https://euphoria-jb.github.io/</string>
    <key>Suites</key><string>./</string>
    <key>Components</key><string>main</string>
    <key>Fixed</key><true/>   <!-- 是否固定源（chflags 锁）由 T18-0 定案，建议 true -->
  </dict>
  ```
- 公钥分发：`euphoria-repo.pub.asc` 放源根目录，EU PM 首装时导入 keyring（对齐 SecureApt InRelease 验签，A_T18 情报底座 §二.3）。

## 设计依据（坑位规避）

| 坑 | 本源对策 |
|---|---|
| Zebra 不查 Release Architectures 字段（兼容性盲区） | 我们 Day1 写对 `iphoneos-arm64`；EU PM 侧必查（T18-a 落） |
| apt-key 已废弃（Cloudflare 2021） | per-repo 公钥文件分发，不用全局 keyring |
| Flat 无 ByHash（弱增量刷新） | 起步期包量小无感；V1.0 切 aptly dists 结构时升级（切源 URL 即可，用户无感） |
| Flat 结构 Sileo/Zebra/apt 通用性 | 本结构=Cydia 传统 Flat，三端全兼容（roothide 同款在产验证） |

## 已验证清单（本次实建）
- [x] dpkg-deb 构建巨魔E 安装器 deb（1692B，postinst 含目录结构+致谢）
- [x] dpkg-scanpackages 索引生成（相对 Filename 路径+三哈希）
- [x] 架构过滤（仅 iphoneos-arm64，防 rootful 包混入——A_T18 §一.4 坑）
- [x] Release 生成（MD5Sum+SHA256 双段）
- [x] ed25519 测试密钥签名 → InRelease+Release.gpg → gpg --verify 验签通过
- [ ] 生产密钥替换+Pages 实部署（需域名/账号定案，T18-0）
- [ ] PresetSources.plist 欧源槽接入（C 的 T18-d 窗口）
