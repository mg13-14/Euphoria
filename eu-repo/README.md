# EU 官方源（eu-repo）——T18-e 实建交付

> 模式：roothide 同款 Flat 结构 + GitHub Pages 零服务器分发（A_T18 情报底座 §五方案 A）。
> 状态：**实体已建成+2026-09-04 真实化修复**（池 3 包·死依赖闭合·索引/签名链全通）。
> 交付人：并行搜索员A，2026-08-28 凌晨（应汇总员 00:25:01 派件②）。
> 2026-09-04 修复：并行搜索员C（对应用户实测批评"源里没有真实文件/依赖死链"——见文末修复记录）。

## 2026-09-04 修复记录（C）

| 项 | 修复前 | 修复后 |
|---|---|---|
| 池内包数 | 1（trolle-installer 1.6KB 骨架） | 3（见下） |
| 死依赖 | trolle-installer `Depends: euphoria-basebin-link` 池内不存在→安装必失败 | basebin-link 真实入池（1.0.0），依赖可解 |
| 真实包 | 0 | **2**（basebin-link + launchctl） |
| 签名 | 旧测试密钥（私钥已随 08-28 会话失传，仅公钥残留） | 新 ed25519 测试密钥 `6FE1C7C972DBA26B`（loopback 无头生成），InRelease+Release.gpg 验签 Good |

- `euphoria-basebin-link 1.0.0`：纯数据包（control+3 符号链接→/var/jb/basebin/*），本地构出。
  构建注记：沙盒禁 `ln -s`，改用 Python tarfile 在归档层生成符号链接条目后手工组 ar（源码级
  等价于 Packages/basebin-link/Makefile 的 dpkg-deb 产物，dpkg-deb -I/-c 验证通过）。
- `launchctl 1:1.2.0`：主树 `Packages/additional/` 既有真实成品（52KB，rootless 布局 /var/jb）。
- `trolle-installer 0.9.1`：仍是骨架（真实载荷=安装器本体，卡 macOS 构建——B 线口径"编译验证待
  用户 macOS 首跑"）；依赖已可解析，装它不再报依赖错误。
- **部署 URL 仍卡（如实）**：①账号/域名定案（T18-0，管理员级）；②安装器真包入池（B 线构建后）。
  当前池内容=诚实最小集：源可用、无死链、无虚假宣称。

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

## 已验证清单
- [x] dpkg-deb 构建巨魔E 安装器 deb（1692B，postinst 含目录结构+致谢）
- [x] dpkg-scanpackages 索引生成（相对 Filename 路径+三哈希）
- [x] 架构过滤（仅 iphoneos-arm64，防 rootful 包混入——A_T18 §一.4 坑）
- [x] Release 生成（MD5Sum+SHA256 双段）
- [x] ed25519 测试密钥签名 → InRelease+Release.gpg → gpg --verify 验签通过
- [x] 【09-04】basebin-link 纯数据包本地构出（tar 层符号链接注入，dpkg-deb -I/-c 双验）
- [x] 【09-04】launchctl 真实成品入池；死依赖闭合（trolle-installer Depends 可解析）
- [x] 【09-04】新测试密钥 6FE1C7C972DBA26B 重签全链（InRelease+Release.gpg+公钥导出）
- [ ] 生产密钥替换+Pages 实部署（需域名/账号定案，T18-0）
- [ ] PresetSources.plist 欧源槽接入（C 的 T18-d 窗口）
- [ ] trolle-installer 真实载荷入池（B 线 macOS 构建后，替换 0.9.1 骨架）
