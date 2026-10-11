# 巨魔E（TrollStore E）情报简报 —— 交接给盟友 GLM5.3

> 作者：并行搜索员B（巨魔E 核心与构建系统负责人，全部信息经主树源码逐行核实）
> 时间：2026-09-04 18:05
> 用途：向新盟友 GLM5.3 交接巨魔E 项目全量信息。信息密度优先，出处均为本仓库源码行号。
> 本简报遵守项目诚实边界：已验证/实验性/未实现三态分开陈述，不掺水分。

---

## 一、一句话定位

**巨魔E = Euphoria 越狱项目（Dopamine 衍生自研）里的"永久签名安装器"**——对标
opa334/TrollStore：把任意 IPA 装成"重启不失效、不依赖越狱态"的常驻 app。
Euphoria 主 app 负责越狱，巨魔E 负责"装出来的东西永久活着"。

## 二、三引擎架构（源码：`Application/Euphoria/Jailbreak/EUTrollE.h/.m`）

统一门面 API：`installApplicationAtURL:mode:error:`，四模式路由（EUTrollE.m L141-144：
Auto=越狱态→引擎A，未越狱→引擎B）。

### 引擎A —— Tier A 越狱态信任缓存秒装（✅ V0.9.1 已实现，随主树发布）

- **机制（B23 路线）**：解包 IPA → ChOma 算主二进制 CDHash →
  `jb_trustcache_add_cdhashes` 注入运行时信任缓存（条目与系统二进制同权）→
  拷入 `/var/jb/Applications` → uicache
- **持久**：条目落 `/var/jb/var/db/euphoria/trolle.plist`，每次越狱幂等重放
  （`replayTrustCacheEntries`）
- **边界（如实）**：重启未越狱期间不可用——这正是 Tier B 的攻坚动机
- **理论边界（B24 实证）**：XNU-12377 启动期 cryptex 信任缓存三道锁；
  攻击面=km daemon/TXM/amfid

### 引擎B —— Tier B 免越狱一次性会话 CT 永久档（⚠️ 实现体完整，【实验性】待实机）

**这是"不越狱就能安装"的主腿。** 八步零残留管线（EUTrollE.m L309 起，
独立版 `TrollE-Installer/src/EUStandaloneInstaller.m` 同构）：

1. 域校验（CT 域矩阵，见 §三）
2. helper 快路径：本体已装 → URL scheme `euphoria-trolle://install?url=` 移交
3. 漏洞会话：kfd（Kernel KRW）+ dmaFail/momentarius（PPL 绕过）dlopen 进程内
4. root 化（17+ 直接内核写入，B25-1 ② 判修）：`kwrite32` 直写 ucred 的
   svuid/uid/svgid/groups → 0，连 auditToken 四字段一并清零
5. staging 解包：dlopen 系统 `/usr/lib/libarchive.2.dylib`（免越狱无 unzip，动态解析符号）
6. 定位 `Payload/*.app`
7. **CT custom 法安装**（TrollStore 同构，全程不经 installd XPC）：
   `MCMAppContainer containerWithIdentifier:createIfNecessary:` 直建 Bundle 容器 →
   文件系统直拷 .app → `_TrollStore` 标记 + 环境变量 `_TROLLSTORE_INSTALLED_` →
   权限两遍法修正 → `LSApplicationWorkspace registerApplicationDictionary:`
   注册字典（ApplicationType=User/System、IsDeletable、FamilyID=0 等）
8. ChOma 算 CDHash → 登记重放表（role=body, engine=B）→ 收尾清 staging + 漏洞清理

成功输出（源码 L854 原话）："免越狱安装完成（永久签名，重启可用）"。

**最大未决风险（v1.2 风险簿首位）**：CT custom 法在 lsd/containermanagerd 侧的
**entitlement 门禁**——TrollStore 走 entitlement（有特权）、越狱走 AMFI 补丁，
本路线两条都不占。三候选 spike 未实机裁决：csflags 平台位单点写入 /
内核 entitlements 指针移植 / 绕 XPC 直写。

### 引擎C —— Tier C 免越狱容器化兜底（✅ 安装侧完整；启动器=V0.9.2 待办）

- **机制（B26 L1 基线）**：无漏洞、全版本域（iOS 15+）。解包 → 沙盒容器落位 →
  登记重放表（engine=C）。LiveContainer 机制**协议式重实现**（无 GPL 代码搬运）
- 主屏图标 = 快捷指令 + URL scheme（`euphoria-trolle://launch?id=<uuid>`）
- **边界（如实）**：L1 非"真永久"——宿主（安装器）签名过期未续签=容器内 app 全灭；
  UI 已暴露"签名健康度"提示

### 升级闭环（设计亮点）

免越狱期写**沙盒镜像表**（`Documents/EUTrollE/registry.plist`，条目结构与主表一致）→
越狱引导时 `migrateSandboxRegistryIfNeeded` 按 path 去重合并进主表 → 引擎A 重放 →
L1 自动升 L3 满血。**装出的东西不因"后来才越狱"而废**。

重放表条目结构：`bundleID / path / cdhash / role(body|guest) / engine(A|B|C) / container(uuid) / installedAt`

## 三、版本域矩阵（C24 修正版，含 16.7.x 勘误）

| 档位 | 域 | 通道 |
|---|---|---|
| CT 永久域（引擎B） | **14.0b2–16.7RC 连续带** + **17.0 全系**；16.7.x GA=死区（仅 RC build 20H18 例外） | 免越狱一次性会话 |
| 越狱会话域（引擎A 触发腿） | 15.0–18.7.1 / 26.0–26.0.1（DarkSword 域）；kfd landa=15.x | Dopamine 系漏洞链 |
| 容器域（引擎C） | iOS 15+ 全版本 | 无漏洞 |

**硬边界（如实，无解）**：**17.0.1+ 无公开第三 CT bug，免越狱永久档不可达**——
TrollStore 2.1.1（2026-04）佐证。域外设备只能：越狱会话档（实验性）/
16.7b、RC、17.0 的 PC 备份注入档（sparserestore，research/C25）/ 引擎C 容器兜底。

## 四、漏洞与工具资产（独立工程 `TrollE-Installer/Exploits/`，9 个向量）

| 向量 | 类型 | 域（Info.plist 实测值） | 备注 |
|---|---|---|---|
| kfd（landa/smith/physpuppet 多 flavor） | Kernel | landa=15.x | kqueue 系主力，纯用户态零 entitlements（TrollInstallerX 已验证形态） |
| DarkSword | Kernel | 15.0–18.7.1 / 26.0–26.0.1，priority 890 | 会话域主力 |
| momentarius | PPL | A12/A13，15.0–26.3.99，priority 999 | **断默认接线（v21 §6-6，B 线 09-04）**：研究级未武器化，源在树但默认不编译——PPL 首选回落 dmaFail |
| dmaFail | PPL | — | PPL 备选（09-04 起 PPL 为可选挂载：`ppl && isSupported` 才启用，纯 KRW 可独走 A12–A13 root 化） |
| Titan / weightBufs / multicast_bytecopy | Kernel | — | GPU/ANE/multicast 向量；**注意 iokit-user-client 白名单敏感**（巨魔通道装不受限，免费侧载档可能受限）；weightBufs 内含演示 main() 文件，构建自动剔除 |
| ClearSword / badRecovery | Kernel | — | 备选 |

工具库（vendor 自包含）：**ChOma**（CDHash/CSBlob 计算，引擎B ⑦⑧ 步硬依赖）、
**libjailbreak**（kread32/kwrite32/proc_ucred/koffsetof/gSystemInfo——17+ root 化
的内核读写底座）、**litehook**（编入 libjailbreak）。

特权集（`Entitlements.plist`，.tipa 通道生效）：platform-application /
no-sandbox / storage-exempt + AppBundles / tcc SystemPolicyAllFiles /
iokit-user-client-class 白名单 12 类（AGX/IOSurface/ANE/Framebuffer 系）/
extended-virtual-addressing + increased-memory-limit。

## 五、独立安装器工程（TrollE-Installer/，2026-09-03 交付）

应"安装器源码单独搞出来，且不越狱就能安装"指令产出，**可整目录拷走独立构建**：

- **形态** = TrollInstallerX 模式：安装器本体是普通签名 app（368 文件，
  vendor 全快照：ChOma/libjailbreak 源/私有头/litehook/IOMobileFramebuffer tbd），
  免越狱侧载进设备 → CT 域内跑引擎B 一次性会话 → 装出巨魔E 本体（脱狱常驻）
- **构建**：纯 Xcode 工具链 + ldid（已弃 THEOS），`make` 一键五步链：
  ChOma → libjailbreak → 9 exploit framework（`build-exploit.sh` 直编）→ app → 签名打包
- **双产物**：`.tipa`（ldid -S 带全特权——给已有 TrollStore/巨魔的设备装，门禁通过率最高）+
  `.ipa`（AltStore/SideStore/Sideloadly 重签通道）；另有 `make deb`（eu-repo 形态）
- **与主树的有意差异**：libjailbreak/choma 的 install_name 改 `@rpath`（app 内嵌布局）；
  exploit 由脚本直编 framework（DPExploit* 协议不变，注入 CFBundle* 键）
- **解耦架构**（C 线五点）：EUUIManager→EUStandaloneLogger、EUEnvironmentManager→
  EUStandaloneEnvironment、EUExploitManager→EUStandaloneExploitManager、JBROOT_PATH→
  EUStandaloneConfig、registryPath 双模→沙盒镜像表唯一化（引擎A 不进独立项目）
- **引擎A 不在独立版**：独立安装器使命=免越狱装本体；越狱态重放归主树 Euphoria

## 六、当前状态与待办（如实，三态分明）

| 项 | 状态 |
|---|---|
| 引擎A（越狱秒装） | ✅ 已实现，随主树 V0.9.1 |
| 引擎B（免越狱 CT 永久） | ⚠️ 代码完整（主树+独立版双份），**实验性**——entitlement 门禁三候选 spike 未实机裁决 |
| 引擎C（容器兜底） | ✅ 安装侧完整；进程内启动器=V0.9.2 待办（URL scheme 口已留） |
| TrollE-Installer 独立工程 | ✅ 静态交付完成；**编译验证待用户 macOS 首跑**（本环境无 iOS 工具链；BUILD.md 排障表备好） |
| V0.9.2 目标 | 引擎B 实机验证 + 门禁 spike 裁决 + 引擎C 启动器 |

## 七、给 GLM5.3 的接管接口

- **主树引擎源**：`shared/Euphoria/Application/Euphoria/Jailbreak/EUTrollE.h/.m`（门面+三引擎）
- **独立工程**：`shared/Euphoria/TrollE-Installer/`（README=架构/分发/边界；
  BUILD.md=环境/步骤/排障；vendor/README=快照与差异；scripts/sync-from-euphoria.sh=主树同步）
- **版本与变更史**：`shared/Euphoria/CHANGES.md` R41 条目（2026-09-03 交付记录）
- **研究依据**（内部 research 线）：B23（信任缓存）/B24（TC 三道锁）/B25（引擎B 契约+
  八步）/B25-1（root 化判修+门禁三候选）/B26（L1-L3 分层）/C23（CT 语义+TrollInstallerX）/
  C24（版本域修正）/C25（PC 备份注入档）/C29（重签透传判据）
- **上手建议**：若 GLM5.3 要攻 entitlement 门禁，从三候选 spike 入手（§二引擎B 风险段）；
  这是当前唯一挡在"免越狱永久安装"前的技术闸门

## 附：生态参照与致谢契约

- opa334/TrollStore（CoreTrust 永久签名语义与 custom 法先例，RootHelper/main.m 同构对照）
- alfiecg24/TrollInstallerX（免越狱侧载安装器形态先例）
- Dopamine/libjailbreak（KRW 抽象层）；JJTech0130（sparserestore 通道情报）
- 项目致谢契约（2026-08-27 用户指令）：所有自研件致谢含 mg13-14 与所用大模型
  （现行=清言 AgentMore 全员 + GLM-4-Plus；盟友 GLM5.3 加入后应补录）
