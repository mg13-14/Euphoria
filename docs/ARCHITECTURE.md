# Euphoria 架构解析

> 本文档基于对上游 Dopamine 源码的逐模块审读，适用于 Euphoria（命名已按本项目转换）。

## 顶层结构

```
Euphoria/
├── Application/      # iOS 越狱主应用（ObjC/UIKit）+ Xcode 工程
├── BaseBin/          # 越狱运行时核心（C/ObjC，以 root 运行于 /var/jb/basebin）
├── Packages/         # 随 bootstrap 安装的 Debian 包（libkrw 插件、libroot、basebin-link）
└── Standalone/       # Corellium 虚拟机自动化测试脚本
```

## 一次完整越狱的生命周期

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. 用户点击「Jailbreak」                                          │
│    EUJailbreaker（流程总指挥）                                     │
│      ├─ EUEnvironmentManager 校验环境（TrollStore/已越狱状态）      │
│      ├─ EUExploitManager 选择内核漏洞                              │
│      └─ EUBootstrapper 下载/校验 Procursus bootstrap              │
├─────────────────────────────────────────────────────────────────┤
│ 2. 内核漏洞利用（App 进程内）                                       │
│    Exploits/*.framework 之一被加载（用户可在设置中切换）：             │
│    kfd / Titan / DarkSword / ClearSword / badRecovery /           │
│    dmaFail / momentarius / weightBufs / multicast_bytecopy        │
│    → 取得内核读写原语（KRW），经 libkrw 抽象层供后续使用              │
├─────────────────────────────────────────────────────────────────┤
│ 3. 提权与落地                                                      │
│    App 以 root + 平台二进制权限启动 BaseBin/euphoria 二进制：        │
│      ├─ XPF: 对 dyld/AMFI 等关键 Mach-O 打补丁                     │
│      ├─ basebin_gen: 重写 dyld 的 LC_UUID（魔术前缀 EUPH<版本>）     │
│      ├─ MachOMerger: 合并 basebin 组件进 dyld 共享缓存              │
│      └─ 解包 bootstrap → /var/jb（rootless 根，实际位于应用容器）     │
├─────────────────────────────────────────────────────────────────┤
│ 4. 持久化注入                                                      │
│    launchdhook 注入 launchd：                                      │
│      ├─ 内嵌 jbserver（XPC 服务，域 JBS_DOMAIN_EUPHORIA 等）        │
│      ├─ spawn 钩子：为带 entitlement 的进程注入 systemhook          │
│      └─ 环境变量 EUPHORIA_INITIALIZED / EUPHORIA_IS_HIDDEN        │
│    systemhook 注入目标进程：                                        │
│      ├─ 校验 dyld UUID 的 EUPH 魔术前缀（防误注入）                  │
│      └─ 设置 DYLD 环境 → 加载越狱插件（tweaks）                     │
├─────────────────────────────────────────────────────────────────┤
│ 5. 用户态生态                                                      │
│    jailbreakd 功能由 launchdhook 内的 jbserver 承担：               │
│      ├─ 信任缓存管理（cdhash 增删查）                               │
│      ├─ 进程调试标记 / root 权限授予（JBS_EUPHORIA_GET_ROOT 等）     │
│      └─ jbctl CLI：proc_set_debugged / trustcache / update         │
└─────────────────────────────────────────────────────────────────┘
```

## Application/（越狱主应用）

| 模块 | 职责 |
|---|---|
| `Jailbreak/EUJailbreaker` | 越狱总流程状态机：环境检查 → 漏洞利用 → bootstrap 安装 → userspace 重启 |
| `Jailbreak/EUExploitManager` | 按系统版本/设备自动匹配最优漏洞，允许用户手动覆盖 |
| `Jailbreak/EUBootstrapper` | 从 `apt.procurs.us` 下载 bootstrap、管理自有 Debian 包版本、首选项写入 |
| `Jailbreak/EUEnvironmentManager` | 应用目录管理、系统状态探测（含 TrollStore 安装识别）、重复应用冲突处理 |
| `Jailbreak/EUPreferenceManager` | 偏好持久化（`dev.euphoria.Euphoria.plist`） |
| `Exploits/*` | 漏洞框架（Xcode 子 target，独立 bundle ID，可插拔切换） |
| `UI/*` | 主界面、设置（含漏洞/主题切换）、OTA 更新、日志、致谢 |
| `Frameworks/Preferences.framework` | 越狱后设置面板嵌入支持 |

## BaseBin/（运行时核心）

| 组件 | 语言 | 职责 |
|---|---|---|
| `euphoria` | ObjC | 提权后落地二进制：dyld 补丁、UUID 魔术改写、basebin 部署 |
| `libjailbreak` | C/ObjC | 核心库：jbserver 实现、XPC 客户端、trustcache/系统调用重实现 |
| `launchdhook` | C/ObjC | 注入 launchd，承载 jbserver、进程 spawn 钩子 |
| `systemhook` | C | 注入目标进程，加载 tweak 环境（校验 EUPH 魔术） |
| `jbctl` | ObjC | 管理 CLI：trustcache 管理、tipa/basebin 热更新 |
| `dyldhook` | asm | dyld 底层钩子 |
| `watchdoghook` / `forkfix` / `hookd` / `boomerang` / `idownloadd` / `rootlesshooks` | C | watchdog 绕过、fork 修复、进程内 hook 服务、信任缓存回环、下载守护、rootless 兼容钩子 |
| `ChOma`（子模块） | C | Mach-O 解析/伪造库（码签名操作） |
| `XPF`（子模块） | C++ | eXploit Prediction Framework：按版本定位内核符号与补丁点 |
| `MachOMerger` | C | 将多个 Mach-O 合并入 dyld 共享缓存 |

## 关键设计模式（继承自上游）

1. **rootless 布局**：所有越狱文件位于 `/var/containers/Bundle/Application/.jbroot-*`，`/var/jb` 为符号链接 —— 卸载即消失，杜绝系统分区污染。
2. **半不完美（semi-untethered）**：内核漏洞不持久化，重启后需重新打开 App 触发；launchdhook/systemhook 通过 dyld 缓存魔术改写实现无文件持久化。
3. **漏洞可插拔**：9 个独立漏洞框架 + `libkrw` 抽象层，新漏洞只需实现 KRW 接口即可接入。
4. **信任缓存链**：所有越狱二进制的 cdhash 经 jbserver 动态注册，绕过 AMFI 强制签名。

## 与上游的架构差异

无结构性改动 —— Euphoria 是标识层面的深度重构（详见 CHANGES.md），漏洞核心与运行时逻辑保持与上游逐字节等价（除文档中列出的两处功能性修补）。
