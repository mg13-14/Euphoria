# vendor/ —— 自包含依赖快照（B 线深度移植，2026-09-03）

> 本目录让 TrollE-Installer **脱离 Euphoria 主树独立构建**。全部内容为主树快照，
> 重同步用 `scripts/sync-from-euphoria.sh`（在 Euphoria 主树 checkout 内跑）。

## 布局与出处

| 子目录 | 内容 | 主树出处 | 用途 |
|---|---|---|---|
| `ChOma/` | ChOma 源码（src/include/external + Makefile；tests/ChOma.xcodeproj/cert.p12 已裁） | `BaseBin/ChOma` | CDHash/CSBlob 计算（引擎B ⑦登记步）；构建产物 `libchoma.dylib` |
| `libjailbreak/` | libjailbreak 源码快照 + **vendor 版 Makefile** | `BaseBin/libjailbreak` | kread32/kwrite32/koffsetof/proc_ucred/gSystemInfo（17+ root 化与内核读写的硬依赖） |
| `include/` | 私有/补充头快照（xpc/bsm/CoreServices(LSApplicationWorkspace)/libarchive/sys/sandbox/…） | `BaseBin/_external/include` | libjailbreak 与 exploit 编译的头来源 |
| `modules/litehook/` | litehook 源码 | `BaseBin/_external/modules/litehook` | 编入 libjailbreak.dylib（同主树 wildcard 编译） |
| `frameworks/IOMobileFramebuffer.framework` | tbd | `BaseBin/_external/frameworks` | libjailbreak 运行时权限修正 IOKit 类 |
| `lib/`（构建产物，不入库） | `libchoma.dylib` / `libjailbreak.dylib` | — | 由根 Makefile ①② 步产出 |

## 与主树的两处构建差异（有意为之）

1. **install_name**：主树 libjailbreak/libchoma 用 `@loader_path`（适配 `/var/jb/basebin`
   平铺目录）；vendor 版改 `@rpath`（适配 app 内嵌 `Frameworks/` 布局，
   app 与 exploit dylib 都加 `-rpath @executable_path/Frameworks`）。
   产物**不与主树互换**。
2. **exploit 分发形态**：主树 exploit 是 xcodeproj framework target（随主 App 构建）；
   独立版由 `scripts/build-exploit.sh` 从 `Exploits/` 源码直编（DPExploit* 协议不变，
   注入 CFBundle* 必需键后照常被 `EUStandaloneExploitManager` 发现）。

## exploit 目录（../Exploits/）

| 目录 | 类型 | 说明 |
|---|---|---|
| kfd | Kernel | kfd 全家（landa/smith/physpuppet）——CT 域主力 KRW |
| DarkSword | Kernel | 会话域向量（Info.plist 域 15.0~18.7.1） |
| momentarius | PPL | PPL 绕过（A12/A13） |
| dmaFail | PPL | PPL 绕过（备选） |
| Titan / weightBufs / multicast_bytecopy | Kernel | GPU/ANE/multicast 向量（侧载无 entitlements 档位可能受限） |
| ClearSword / badRecovery | Kernel | 备选向量 |

`weightBufs/exploit/exploit.m` 含独立 `main()`（演示件）——构建脚本自动剔除，不进 framework。
