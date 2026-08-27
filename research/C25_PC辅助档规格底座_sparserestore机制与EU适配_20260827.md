# C25 专项：PC 辅助档规格底座——sparserestore 备份注入机制与 EU 适配（16.7b/RC/17.0 段）

- 交付人：并行搜索员C　时间：2026-08-27 15:35
- 触发：用户 11:44:59 定域含 16.7b/RC/17.0（设备端 kfd 装法死的"永久档拼图"段）；C24 §五-3 已留 Engine B PC 辅助子模式占位；本轮"接着搞"补规格
- 用途：V0.9.1 EU PC 辅助安装器（暂名 EUPCInstaller）的机制规格与工程量评估
- 检索存档：`agents/6a8d0a5300ccbc1a3c89cebe/research_ts/`（sr1/sr2 + r2 + q 系列）

---

## 一、机制三件套（leminlimez《A deep dive into the iOS backup/restore system》一手拆解）

1. **备份域（domains）**：iOS 备份用域映射写入位置。普通域=路径容器（如 HomeDomain=/var/mobile 受限）；特殊域三个带 `-` 扩展：`SysContainerDomain-<名>`、`SysSharedContainerDomain-<名>`、`AppDomain-<bundleid>`——扩展部分决定子目录名。
2. **backpathing 注入（CVE-2024-44252 核心）**：`SysContainerDomain-../../../../../../../..` 中 `-` 后接 `..` 连续回溯——起点 `/private/var/.backup.i/var/root/Library/Backup/SystemContainers/Data/`（Shared 变体在 `/Shared/`），可回溯至 `/private` 分区根；配合 `/` 前进=**/var 分区任意非 SSV 路径可写**（/System 为 SSV 封读，/var 不受保护——这是边界而非限制，目标路径全在 /var）。
3. **备份结构**：四件套 Info.plist / Manifest.mbdb / Manifest.plist / Status.plist + SHA1 命名的内容文件；部分恢复（sparse restore）要求 Status.plist `IsFullBackup=false`、`Version=2.4`（mbdb 格式）。

## 二、TrollRestore 先例解剖（JJTech0130/sparserestore + verygenericname/TrollRestore）

- **注入目标=系统 app 主二进制替换**：选一个系统 app（如 Tips），把其容器内主二进制换成 CT 假签的 TrollHelper——**借用现成合法 bundle 的注册关系**（图标/启动项免注册），替换后的二进制靠 CT bug 过验证（16.7 GA+/17.0.1+ CT 修→换入即失效，故范围止步 17.0）。
- **流程**：PC 端 pymobiledevice3 恢复恶意备份→设备打开被替换的 app→TrollHelper 界面→装 TrollStore 本体→**再手装真 Persistence Helper**（TrollRestore 无真 helper——注意：我们 C23 的 helper 机制直接内置，是明确改进点）。
- **范围**：15.2–16.7RC(20H18)+17.0 全 4 build（21A326/327/329/331）；<15.2 备份恢复不稳被禁用；写原语活到 18.0（18.1b5 修）。
- **PC 要求**：macOS 11+（原生）/ Win10+ 装 iTunes；Python+pymobiledevice3（USB 配对）。

## 三、EU PC 辅助档规格（V0.9.1）

| 项 | 规格 |
|---|---|
| 目标段 | **16.6.2/16.7b1-b6/16.7RC + 17.0 全系**（设备端 kfd 死的 CT 域；14.0~16.6.1 走 Engine B 设备端，无需 PC） |
| payload | 巨魔E 本体（CT 假签/多签名混淆管线同 Engine B） |
| 注入方式 | 系统 app 二进制替换（TrollRestore 同构；候选=Tips/Watch 等可还原 app） |
| helper | **内置装配**（优于 TrollRestore）：替换后的巨魔E 首启即自动装 Persistence Helper（C23 机制） |
| 技术栈 | pymobiledevice3（跨平台 Python，MIT）+ sparsersetore 库同构实现（注意 JJTech 库许可证自查）+ 自研 UI |
| 平台 | macOS 11+ / Windows 10+（iTunes）；Linux 理论可（pymobiledevice3 支持，USB 栈不稳如实标注） |
| 还原路径 | 被替换 app 删除+App Store 重装即复原（如实写入用户文档） |

## 四、风险与边界（如实）

1. **<15.2 不纳入**（上游恢复不稳实测）；18.1+ 写原语死、17.0.1+ 启动死（无 CT）——PC 档扩不了永久域，与 C24 矩阵一致。
2. CVE-2025-24104（2025-01 修）证明备份面会复发，但 17.0.1+ 无 CT 照样启动不可达——新写洞不改变永久档边界。
3. 系统锁屏密码设备：备份恢复需配对+可能要求解锁交互——UI 流程需预期引导（上游教程实测口径）。
4. 工程量：参考实现全开源，EU 定制=签名管线复用（Engine B 同一产物）+UI+中文化——**量级"周"**，建议排 V0.9.1 与 Engine C 启动器并行。

## 五、出处

- leminlimez gist《A deep dive into the iOS backup/restore system》（domains/backpathing/mbdb 结构一手拆解）
- github.com/JJTech0130/TrollRestore README（raw 全量：范围 21A326-331/PC 要求/系统 app 替换流程/无真 helper）
- Reddit r/jailbreak：sparserestore 18.1b5 修复实锤；ios.cfw.guide TrollRestore 指南
- CVE-2024-44252（Apple HT121563，MobileBackup）；CVE-2025-24104（备份域二枚）
