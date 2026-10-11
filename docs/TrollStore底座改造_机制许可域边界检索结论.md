# TrollStore 底座改造：机制·许可·域边界（检索结论）

**执行**：并行搜索员A ｜ **时间**：2026-09-06 15:0x ｜ **用途**：裁定汇总员 14:51:22 方案（巨魔E 以 TrollStore 源码为底座内置进安装器树）的可行性边界
**方法**：web-search 广度筛源 → GitHub raw 原文直读（README/LICENSE/releases API）→ 全部结论带官方原话出处

---

## 一、结论速览（三条硬边界）

| # | 结论 | 等级 |
|---|---|---|
| 1 | **许可：可行**。TrollStore 主体 **MIT**（Copyright 2022-2026 Lars Fröder，DEP-5 著作权文件明示），仅 `RootHelper/uicache.m` 一个文件为 BSD-4-Clause（CoolStar/Procursus 系）。以之为底座改造并内置进安装器树，许可层无障碍 | ✅ |
| 2 | **域：17.0 封顶**。官方 README 原话：支持 14.0b2~16.6.1、16.7 RC(20H18)、17.0；**「16.7.x (excluding 16.7 RC) and 17.0.1+ will NEVER be supported (unless a third CoreTrust bug is discovered, which is unlikely)」**。→ 用户 18.1.1 现役机在此路线**域外，且官方定性为 NEVER** | ⛔ 关键 |
| 3 | **能力天花板**：TrollStore 通道产出的是「permasigned 越权 app」（任意 entitlements+unsandbox+root helper），**装不出完整越狱形态**（官方明示三项 not-possible，见 §四） | ⚠ 决定巨魔E 形态 |

## 二、许可详情（合规落点）

- 主体（含安装/签名/persistence 全部核心代码）：**MIT**——改造、闭源分发均可，仅需保留版权与许可声明。与 Euphoria 基于 Dopamine（MIT）的既有合规模式同级，团队已有成熟做法。
- **唯一例外文件** `RootHelper/uicache.m`：BSD-4-Clause——若改造中复用该文件，须 ①保留版权声明 ②广告性材料需致谢 CoolStar ③不得用其名义背书。建议：改写绕开或原样保留声明（该文件功能=icon cache 刷新，与安装器职责相邻，大概率会碰到）。
- 佐证：树内 `shared/Euphoria` 既有 LICENSE.md 合规链路可平移复用。

## 三、域边界证据链（17.0.1+ = NEVER）

1. **TrollStore 官方 README**（raw.githubusercontent.com/opa334/TrollStore/main/README.md）：
   - 支持域：`14.0 beta 2 - 16.6.1, 16.7 RC (20H18), 17.0`
   - 原话：`16.7.x (excluding 16.7 RC) and 17.0.1+ will NEVER be supported (unless a third CoreTrust bug is discovered, which is unlikely)`
2. **roothide Bootstrap**（官方 README + releases 全系 2024-01~2026-06-12）：域 = `iOS 15.0-17.0 A8-A17Pro & M1+M2`；最新 2.2.1（2026-06-12）仍在此域内做加固（DarkSword 内核漏洞也只覆盖 16.5~17.0）；且 **Bootstrap 自身必须用 TrollStore 安装**（`.tipa`，官方原话 must be installed with TrollStore）——即越狱生态主线同样封顶 17.0。
3. **18.x 无公开替代特权通道**：检索 2025-2026 全网（idownloadblog/onejailbreak/cfw.guide 等）：18.x 上只有 SideStore（7 天开发者证书重签，非永久、无任意 entitlements）与 LiveContainer（容器化，无越权）；2026-01 传出的「iOS 26.2~18.0 泄露 Apple 内部证书类 TrollStore 安装器」已被公开分析**辟谣**（Analyzed & Debunked）。
4. CoreTrust bug 漏洞学背景：两个 bug 均已修（Google TAG 在野间谍链报告→Apple 修复）；第三个 CoreTrust bug 无公开发现——官方「unlikely」判断可信。

## 四、能力天花板（C 改造时必须绕的坑）

TrollStore 机制 = AMFI/CoreTrust 多签者验签缺陷 → installd 层装「System」态 app。官方 README 明示的硬限制：

1. **Icon cache reload 后全员回退 User 态**——必须向系统 app（如 Tips）注入 **persistence helper** 才能重注册救活。→ 安装器若基于此底座，巨魔E 装出后**必须自带持久化方案**，否则重启/刷图标即失效。
2. **iOS 15 A12+ 三个 entitlements 被 ban**（无 PPL bypass 签了就崩）：`com.apple.private.cs.debugger`、`dynamic-codesigning`、`com.apple.private.skip-library-validation`。→ 巨魔E 若依赖这三项，此通道给不了。
3. **官方 not-possible 清单**：拿不到 `TF_PLATFORM/CS_PLATFORMIZED`；**起不了 launch daemon**；**注不进系统进程**（需 TF_PLATFORM+PAC+PMAP trust bypass）。→ TrollStore 式安装器装出的巨魔E = 「越权 app 形态」（root helper 可用、可 unsandbox），**非完整越狱形态**。若巨魔E 需 jbserver/tweak 注入/daemon，仍须越狱态通道（引擎A 信任缓存路线）。

## 五、对用户三连诉求的逐条映射

| 用户诉求 | 检索裁定 |
|---|---|
| 安装器要内置巨魔E（14:48） | 汇总员已认缺口（「管道有了管子里没水」）；**可行**，但内置形态=越权 app 级（§四.3） |
| 巨魔E 根据 TrollStore 源码去改（14:49） | 许可 ✅（MIT 主体）；改造可行；**产出一律落 ≤17.0 域**（§三） |
| 没有巨魔E 怎么安装 | ≤17.0 域内机：底座方案成立；**18.1.1：TrollStore 域外 NEVER**，此路线上无解 |

## 六、悬案与建议（抛汇总员裁定）

1. **用户 18.1.1 的越狱态从何而来**：公开生态（TrollStore/Bootstrap 主线/Dopamine/Serotonin）在 18.x 均无通道；用户自述 roothide arm64e 越狱态与公开生态**矛盾**。建议：设备落位问询升级为「版本号+越狱工具名+安装方式」三连问——若用户 18.1.1 真有越狱态，则它来自非公开/魔改渠道，那台机上装巨魔E 应走引擎A（信任缓存），与 TrollStore 底座方案并行不悖；若无，用户 18.1.1 上任何安装器路线都无解，需直面并告知。
2. **两台机策略**：若白巨魔落在 ≤17.0 域内机（汇总员 00:22:57 待答），底座方案在该机完整成立；18.1.1 主力机走越狱态或如实告知边界。
3. **口径建议**：向用户讲清「TrollStore 底座=域内机方案，18.1.1 官方 NEVER」宜早不宜迟——Mac 构建投入前给用户明确预期，护住信任。

## 七、出处清单

- TrollStore README/LICENSE（官方，raw 直读）：github.com/opa334/TrollStore（MIT+单文件 BSD-4；域声明；banned entitlements；not-possible 清单；persistence helper 机制）
- roothide Bootstrap README+releases（官方，raw+API 直读）：github.com/roothide/Bootstrap（15.0-17.0；must be installed with TrollStore；2.2.1@2026-06-12 仍在域内）
- 检索原始数据：`agents/6a8d0a5300ccbc1a3c89cec0/`（ts_q1~q9.json + raw_*.md/txt + rh_releases.json），可复跑复核

——A 检索线收口。机制+许可+域三结论齐备，方案裁定权在汇总员。
