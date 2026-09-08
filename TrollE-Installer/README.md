# TrollE-Installer（巨魔E 安装器·独立源码项目）

> 抽离自 Euphoria 主树（`Application/Euphoria/Jailbreak/EUTrollE.m`，作者 B 线），
> 独立成项目后**不依赖 Euphoria 主 App、不依赖越狱态 BaseBin 运行时**。
> 形态定位 = TrollInstallerX 模式（C29 透传腿工程化）：**安装器本体是普通签名的独立 app，
> 免越狱侧载进设备后，在 CT 域内跑一次性漏洞会话，装出巨魔E 本体（CT 永久签名，重启可用）**。
> 触发指令：用户 2026-09-03 19:36:04/19:36:33（"把巨魔E安装器源代码单独搞出来，且不越狱就能安装/就能安装巨魔E"）。
> 抽离与解耦：并行搜索员C，2026-09-03。深度移植与实机验证：B 线接手。

---

## 一、这个项目是什么

一个**自包含的 iOS app 工程**（纯 Xcode 工具链 + ldid，无需 theos），三个能力面：

| 面 | 能力 | 引擎 | 版本域 |
|---|---|---|---|
| **免越狱装巨魔E 本体**（主使命） | 一次性 kfd KRW 会话 → 17+ 直接内核 root 化 → CT custom 法安装（MCMAppContainer 直建容器+直拷+LSApplicationWorkspace 注册字典，全程不经 installd XPC） | 引擎 B | CT 全史域：14.0b2–16.7RC（连续带）+ 17.0 全系（C24 修正版矩阵） |
| 免越狱容器化兜底 | IPA 解包 → 沙盒容器落位 → 登记重放表（engine=C），主屏图标=快捷指令+URL scheme | 引擎 C | 全版本域（iOS 15+），无漏洞 |
| 越狱态兼容 | deb 形态进 eu-repo 源，Sileo 安装（`Depends` 已去 basebin 依赖） | — | 同主树 |

**装出巨魔E 本体后：本体脱狱独立常驻（CT 永久签名），不再需要本安装器、不依赖 Euphoria App。**

## 二、"不越狱就能安装"怎么实现（分发通道）

本安装器 **IPA 经任意免签侧载通道装入设备**（按 C29 矩阵，重签腿全可用）：

| 通道 | 有效期 | entitlements 档 | 说明 |
|---|---|---|---|
| AltStore/SideStore dev 签 | 7 天/1 年 | 免费证书=基础档 | 标准路径，SideStore 可无线续签 |
| Sideloadly（付费开发者证书） | 1 年 | 证书批什么有什么 | 可带 iokit 白名单（视证书） |
| **已有 TrollStore/巨魔E 的设备装 .tipa** | 永久 | **全档（platform/no-sandbox/iokit）** | 引擎 B 的 entitlement 门禁通过率最高（见 §七-1） |
| 企业签/公证（EU DMA） | 视通道 | 视通道 | 重签型，装进即用 |

**漏洞向量对 entitlements 的敏感度（如实分档）**：kqueue 系（kfd landa/smith）=
纯用户态、零 entitlements 依赖（TrollInstallerX 已验证形态）；IOSurface/AGX/ANE 系
（physpuppet/weightBufs/Titan/multicast/momentarius 的部分向量）在沙盒 app 内
受 iokit-user-client-class 白名单影响——巨魔通道装（.tipa）不受限，免费侧载档可能受限。

## 三、目录结构

```
TrollE-Installer/
├── README.md                 ← 本文件（架构/构建/分发/边界）
├── BUILD.md                  ← 构建指南（B 线权威版：环境/步骤/排障）
├── Makefile                  ← 自包含构建（ChOma→libjailbreak→exploit→app→签名→打包）
├── Entitlements.plist        ← .tipa 通道的特权集（platform/no-sandbox/iokit 白名单）
├── src/
│   ├── main.m                ← 入口 + AppDelegate（URL scheme 接引）
│   ├── InstallerViewController.h/.m  ← 最小 UI（选 IPA→双引擎→清单→日志；安装后台串行队列）
│   ├── EUStandaloneInstaller.h/.m   ← ★核心：引擎 B/C 完整抽取体（解耦版）
│   ├── EUStandaloneLogger.h/.m      ← 日志协议（替代 EUUIManager.sendLog）
│   ├── EUStandaloneEnvironment.h/.m ← isJailbroken/runAsRoot 独立实现
│   │                                    （替代 EUEnvironmentManager）
│   ├── EUStandaloneExploit.h/.m      ← exploit dylib 发现与选择独立实现
│   │                                    （替代 EUExploitManager，同 dlopen 协议）
│   ├── EUStandaloneConfig.h/.m       ← 宏与常量（替代 JBROOT_PATH 等主树宏）
│   └── Info.plist            ← Bundle ID + URL scheme（euphoria-trolle://）+ 文件共享
├── Exploits/                 ← 9 个 exploit 源码目录（kfd/DarkSword/momentarius/dmaFail/
│   │                             Titan/weightBufs/multicast_bytecopy/ClearSword/badRecovery；
│   │                             momentarius 断默认接线 v21 §6-6：源在树、默认不编译——
│   │                             研究级未武器化，PPL 首选回落 dmaFail）
├── scripts/
│   ├── build-exploit.sh      ← exploit 目录 → .framework（剔除演示 main、注入 CFBundle 键）
│   ├── package_ipa.sh        ← 重打包入口（不重编译出双产物）
│   ├── package-deb.sh        ← deb 形态（eu-repo）
│   └── sync-from-euphoria.sh ← 从主树重同步 vendor/Exploits 快照
├── DEBIAN/                   ← deb 形态（eu-repo 源分发，去 basebin 依赖）
│   ├── control
│   └── postinst              ← 含致谢契约（mg13-14 + AI 辅助）
└── vendor/                   ← 自包含依赖快照（详见 vendor/README.md）
    ├── ChOma/                ← CDHash/CSBlob 源码
    ├── libjailbreak/         ← kread/kwrite/proc_ucred/koffsetof 源码 + vendor 版 Makefile
    ├── include/              ← 私有/补充头（xpc/bsm/CoreServices/libarchive…）
    ├── modules/litehook/     ← 编入 libjailbreak
    ├── frameworks/           ← IOMobileFramebuffer tbd
    └── lib/                  ← 构建产物（libchoma/libjailbreak，make 产出）
```

## 四、依赖解耦映射（5 个耦合点 → 独立实现）

| # | 主树依赖 | 独立实现 | 说明 |
|---|---|---|---|
| 1 | `EUUIManager sendLog`（`EUTrolleLog` 宏） | `EUStandaloneLogger`（block 回调 + NSLog 双通道） | UI 侧注册回调即可拿到日志流 |
| 2 | `EUEnvironmentManager isJailbroken/runAsRoot` | `EUStandaloneEnvironment`（isJailbroken=/var/jb 符号链接探测；runAsRoot=getuid()==0 直跑否则失败） | 独立安装器无 launchdhook 通道，越狱态只做只读探测 |
| 3 | `EUExploitManager`（exploit 发现/选择） | `EUStandaloneExploitManager`（扫本 app `Frameworks/` 目录 + 同款 `exploit_init/run/deinit` dlopen 协议） | exploit dylib 独立分发，随安装器 IPA 打包 |
| 4 | `JBROOT_PATH` 宏 | `EUStandaloneConfig.h`：免越狱恒空前缀；越狱态兼容探测 | 引擎 A（信任缓存 XPC）**不进独立项目** |
| 5 | libjailbreak（kread/kwrite/koffsetof/proc_ucred/gSystemInfo）+ ChOma | `vendor/` 引入（见 §五） | 17+ root 化与 CDHash 计算的硬依赖 |

## 五、vendor 依赖（✅ 已自包含化，B 线 2026-09-03 完成）

原排期"从主树相对路径链接"**已废弃**——`vendor/` 现为完整快照（ChOma 源码 /
libjailbreak 源码 / 私有头 / litehook / IOMobileFramebuffer tbd），工程可整目录
拷走独立构建。与主树的两处有意差异（install_name=@rpath、exploit 直编 framework）
见 `vendor/README.md`。主树演进后用 `scripts/sync-from-euphoria.sh` 重同步
（src/EUStandalone* 解耦层不自动覆盖，需人工比对）。

## 六、构建（无需 theos；详见 BUILD.md）

```bash
cd TrollE-Installer
make        # → build/TrollE-Installer.tipa（巨魔通道，带特权）
            #   + build/TrollE-Installer.ipa（侧载通道）
make deb    # 另出 eu-repo deb（需 brew install dpkg）
```

环境：macOS 13+ / Xcode 15+ / `brew install ldid libarchive`。
排障表与验证状态（如实）见 `BUILD.md`。

## 七、边界与风险（如实，继承自主树口径）

1. **entitlement 门禁风险（v1.2 风险簿首位，B25-1 ➕）**：CT custom 法在 lsd/containermanagerd
   侧的 entitlement 门禁**无公开生态先例**（TrollStore=有 entitlement；越狱=有 AMFI 补丁；本路线两条都不占）。
   三候选 spike（csflags 平台位单点写入/内核 entitlements 指针移植/绕 XPC 直写）由 B 线实机裁决中。
   **实机验证完成前，本安装器的引擎 B 路线标注为【实验性】。**
2. **17.0.1+ 免越狱永久档不可达**（无公开第三 CT bug；TrollStore 2.1.1@2026-04 佐证）——域外设备
   自动降级提示（16.6.1~18.7.1 越狱会话档【实验性】；16.7b/RC/17.0 可用 PC 备份注入档，见 research/C25）。
3. 引擎 C（容器化）非"真永久"——宿主签名过期未续签=容器内 app 全灭；UI 须暴露签名健康度（B26 §3.1）。
4. 会话失败=零残留（staging 回滚+漏洞清理），契约见 research/B25。

## 八、出处

- 主树 `Application/Euphoria/Jailbreak/EUTrollE.m`（引擎 B 八步会话/引擎 C 安装侧/CT custom 法/17+ root 化——本项目的抽取源，逐段标注）
- research/C23（CT 语义/TrollInstallerX 模式/Havoc 源安装器分发）、C24（版本域矩阵）、C25（PC 备份注入档）、B25（Engine B 契约）、B26（分层可用 L1-L3）、C29（透传/重签判据）
- TrollStore custom 法同构依据：opa334/TrollStore RootHelper/main.m（B25-1 ③ 源码级对照）

## 九、B 线接手记录（2026-09-03，深度移植）

C 线骨架之上完成的深度移植（对应 §五/§六 的"已完成"状态）：

| # | 事项 | 说明 |
|---|---|---|
| 1 | vendor 自包含化 | ChOma/libjailbreak/私有头/litehook/IOMobileFramebuffer 全量快照入 `vendor/`，工程可整目录拷走独立构建 |
| 2 | 构建系统重写 | THEOS → 纯 Xcode 工具链 + ldid（根 Makefile：ChOma→libjailbreak→exploit→app→签名→双产物一键链） |
| 3 | exploit framework 直编 | `scripts/build-exploit.sh`：9 个 exploit 目录 → .framework（剔除含 main() 的演示件、注入 CFBundle* 键、@rpath 链 libjailbreak） |
| 4 | 双产物打包 | `.tipa`（ldid -SEntitlements.plist，巨魔通道保留特权）+ `.ipa`（侧载通道） |
| 5 | deb 形态 | `make deb` → `scripts/package-deb.sh`（需 dpkg） |
| 6 | UI 线程模型修正 | 安装链改后台串行队列（原主线程直跑=UI 冻结+看门狗风险）；引擎内 openURL hop 回主线程 |
| 7 | 现代化装载器 | UIDocumentPicker iOS 14+ UTType API（ipa/tipa 双后缀）+ 已装清单/卸载 + 致谢页 |
| 8 | 致谢契约对齐 | DEBIAN/postinst 与 UI 致谢页均含 mg13-14 + AI 辅助（契约 2026-08-27） |

**验证状态（如实）**：本环境无 iOS 工具链——全部为静态移植，**编译验证在 macOS 首跑完成**
（排障表见 BUILD.md）；引擎 B 的 entitlement 门禁 spike 仍未实机裁决（§七-1 优先级不变）。
