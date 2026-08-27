# B19-1 · R19 地基情报：TrollStore 机制全拆解与"免 CT 永签"路径盘点

- 需求：R19（用户 18:40:45）——"再创建一个新版 TrollStore……能安装的东西加进包管理器，能装持久性助手，没越狱也能用，可以不用 CT 漏洞，自己挖掘"；**用户 18:54:00 定名：巨魔E**
- 作者：并行搜索员B · 2026-08-26 · 全部结论附出处，未经证实的推测单独标注

## 1. 需求拆解（用户一句话 → 四个技术要件）

| 要件 | 含义 | 现有 TrollStore 对应物 |
|---|---|---|
| ①永久安装 | 装完不闪签、不7天过期 | CT 漏洞永签 |
| ②持久性助手 | 系统应用槽位内驻留，重签/重启后仍可自愈 | persistence helper（装入 Tips 等系统应用） |
| ③无越狱可用 | jailed 环境，不依赖完整越狱 | TrollStore 本体就是 jailed app |
| ④不依赖 CT 漏洞 | 需要新的代码签名信任绕过或替代信任锚 | **无对应物——这是 R19 的核心攻坚点** |

## 2. TrollStore 三层机制拆解（它是怎么工作的）

1. **一次性安装向量（把 TS 装进去）**：历史上换过很多代——MacDirtyCow（14.0-15.7.1）、kfd 系 TrollInstallerX（alfiecg24，用 kfd 内核漏洞替换系统应用为持久助手，14.0-17.0 区间）、TrollHelper（CT bug ≤16.6.1 直装）、sparserestore 类（MisakaX，restore 篡改系统应用数据）。来源：github.com/alfiecg24/TrollInstallerX、ios.cfw.guide、r/jailbreak。
2. **CoreTrust 永签（核心）**：TrollStore 1.x 用 **CT 根证书校验漏洞**，2.0+ 用 **CT 多签名者校验漏洞**（AMFI 对多签名者二进制校验错误→可伪装成 App Store 签名）→ 装入的 IPA 永久有效、可带几乎任意 entitlement。来源：github.com/opa334/TrollStore README、theapplewiki.com/wiki/TrollStore。
3. **root helper + 持久助手（运行期）**：安装 App、刷新图标缓存等需要 root——TS 通过 CT 漏洞签出的平台二进制+persona-mgmt 私有 entitlement 从非 root 进程派生 root 进程；持久助手装进系统应用槽位（如 Tips），免重签自愈。来源：theapplewiki（XNU 源码变更注）、r/Trollstore。

## 3. 版本边界：为什么 17.6/18+ TrollStore "近乎不可能"

- 支持矩阵（主线 TS 2.1.1，2026-04-01 仍在维护）：**14.0–16.6.1、16.7RC、17.0**。来源：theapplewiki。
- **两道新墙**：
  - iOS **17.6/18.0** 起 XNU 加了缓解：非 root 进程禁止派生 root 进程（persona-mgmt entitlement 路径封死）→ 就算有新 CT 漏洞，**root helper 架构直接作废**，新工具必须换运行期架构。来源：theapplewiki + XNU 源码链接。
  - CT 两代漏洞均已修复；18+ 至今无公开等效签名绕过。TrollInstallerX 开发者 2024-06 结论：iOS 18 硬化后"开发 TrollStore 类工具近乎不可能"。来源：idownloadblog 2024-06-11。
- **26.x 现状**：主线 TS 不支持；无公开 CT 级签名漏洞。

## 4. "泄露 Apple 证书安装器"骗局警告（重要）

- 2025-12 iPhone **原型机软件真泄露**过（内含早期 iOS 26 构建）——事实为真。来源：macrumors 2025-12-15。
- 但随后 GitHub/YouTube 上冒出的"用泄露 Apple 内部证书永久签名、18.0-26.2 可用"类安装器，被 FCE365（iDevice Central）等直接定性为 **AI slop 骗局仓**（"AI slop weaponized GitHub"）。来源：YouTube FCE365 2026-01-04 视频说明页。
- **结论：勿采信、勿引用任何"泄露证书永签"仓库作为技术路径**；即便真有内部签名身份，Apple 可通过在线信任链更新吊销，且不满足"自己挖掘"要求。

## 5. 真正的技术前沿：TaskPortHaxxApp（2025-10 ~ 2026-04 活跃）

**这是与本需求最相关的公开先例**：khanhduytran0 的 TaskPortHaxxApp——标题即"仅凭 CoreTrust bug 操纵平台进程 task port"，**iOS 16.7RC/17.0 无内核漏洞半越狱 PoC**。组合拳（全部用户态）：

1. **Launch Constraint 绕过**（iOS 16.0+ 平台二进制启动约束）
2. 从 launchd 派生 root 进程（无需平台二进制身份）
3. **异常端口（exception port）劫持平台进程线程状态**→ 平台进程内任意代码执行（目标含 Spotlight）
4. **硬件断点实现的用户态 PAC 绕过**（提交记录："Bye PAC I guess"，2025-11）

生态位：**NathanLR 2.0**（2025-12-05）已把该 PoC 产品化为 iOS 17.0 半越狱（依赖先装 TrollStore；cfw.guide 2026-08 仍在维护安装指南）。onejailbreak 2025-11 评测：受限环境半越狱。

**对 R19 的启示与边界**：TaskPortHaxx 证明"免内核漏洞、纯用户态链"在 17.0 可行——LC 绕过/异常端口/PAC 绕过这三件套**不依赖 CT 漏洞本身**，理论上可移植到 26.x（每件都需找新版原语）；但该链在 17.0 仍以 CT bug 为最终签名信任锚。**"免 CT"在 26.x 上没有公开先例，必须自挖**——候选方向：AMFI/CoreTrust 校验逻辑新缺陷、异常端口类原语在 26.x 的复刻、sparserestore 类一次性写入+持久助手槽位组合。

## 6. 与本项目树内资产的接口（供 A/规划师对表）

- 树内已有 momentarius（PPL 侧）+ ClearSword 链（README 注明两链勿拆）——**内核态一次性永签**在 26.x 理论可做（install 时改 AMFI 信任态），但半 tethered 重启即失效，**不满足 R19"持久"**；仅可作为"安装向量"备选（要件①）。
- R19 与 R15/R17 包管理器的集成点=要件①②的产物（能装 IPA + 持久助手），不与 R14 冲突。
- 建议的攻坚分工（供规划师 v6）：签名信任锚（要件④）= 新漏洞挖掘级任务，周期最长、无保证；其余三件可先行设计。

## 7. 出处清单

- github.com/opa334/TrollStore（README：AMFI/CT 多签名者机制）
- theapplewiki.com/wiki/TrollStore（版本矩阵、两代 CT 漏洞、17.6/18.0 persona-mgmt 缓解）
- github.com/alfiecg24/TrollInstallerX（kfd 安装向量；iOS 18 硬化结论）
- github.com/khanhduytran0/TaskPortHaxxApp（LC 绕过/异常端口/PAC 绕过全拆解，2026-04 仍在更新）
- ios.cfw.guide/installing-trollstore、/installing-trollstore-trollinstallerx、/installing-nathanlr（安装向量与 NathanLR 指南）
- idownloadblog.com 2024-06-11（TrollInstallerX 开发者谈 iOS 18）；macrumors.com 2025-12-15（原型机泄露）；YouTube FCE365 2026-01-04（泄露证书骗局定性）；onejailbreak.com 2025-11-09（NathanLR 评测）
