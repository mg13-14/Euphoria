# C27 · Coruna 链 PPL/SPTM 绕过情报——真根拼图与合规边界（用户 08-29 00:15"你们自己看看最新公布 PPL 绕过的"应答）

- 交付人：并行搜索员C · 2026-08-29 00:40 · 状态：**情报交付**
- 检索存档：research_ts/ppl1-ppl6.json + agent-browser 实勘（khanhduytran0/coruna 仓库+ANALYSIS.md 原文）
- 关联：C26（真根可行性评估）·A 真根定案（00:15:42）·用户 00:11/00:15 裁定

---

## 一、用户所指"最新公布的 PPL 绕过"=Coruna 链（三件套实证）

| 组件 | 事实 | 出处 |
|---|---|---|
| **Coruna exploit kit** | 在野武器化工具包：23 漏洞/五条链/iOS 13.0-17.2.1，Google GTIG 2026-03-03 曝光；配套 GhostBlade 窃密载荷；商用攻击者实战部署**先于公布**（用户"公布之前就是已经成功的"属实） | cloud.google.com GTIG 报告/securityaffairs/Lookout |
| **Rocket** | **SPTM+PPL 双 bypass，iOS 16.6-17.3.1**，2026-03-03 披露；17.4 修复 | theapplewiki.com/Rocket 词条 |
| **Sparrow** | 另一枚 PPL bypass（Reddit 技术讨论与 Rocket 并列"Coruna 的两个最终 PPL/SPTM 绕过"） | r/jailbreak 2026-03/07 多帖 |

泄露工具包公开：**github.com/khanhduytran0/coruna**（从攻击服务器提取，去 C2/去混淆/可本地托管；教育研究发布）。实测三档：15.4.1（jacurutu→VariantB）/16.5（terrorbird→seedbell→VariantB）/17.0（cassowary→seedbell_pre→seedbell_17→VariantB）。

## 二、链架构（ANALYSIS.md 原文实证）

```
Stage1  WebKit/WASM 内存破坏 → RW 原语
Stage2  PAC bypass（A12+）
Stage3  沙箱逃逸+载荷投递（Stage3_VariantB.js：MachOPayloadBuilder 内存构 dylib + qbrdr() 桥）
Payload 19 加密 bundle→65+ Mach-O arm64/arm64e dylib（iOS 13-17 全域）
加密    ChaCha20(DJB 变体)→LZMA(0x306)→F00DBEEF 容器→Mach-O（密钥已全恢复）
```

opa334（2026-03-23）："Huge revelations——arm64e jailbreak up to **17.3.1** using PPL/SPTM Bypasses from Coruna chain"；Dopamine 3 月底发布 DarkSword 内核洞版（iOS 15.0-16.7.15）。**越狱上限被 Coruna 推至 17.3.1**（17.4+ 修死）。

## 三、对 Euphoria 的三个落点

1. **树内缺口实锤**：Exploits/ 已有 DarkSword 系全家（ClearSword/DarkSword/Titan/momentarius/weightBufs），但 **Sparrow/Rocket（PPL/SPTM bypass）不在树内**——A15+/17.x 域 PPL 墙组件缺位。
2. **真根 L2 把握度上调**（修正 C26 §一）：Rocket=SPTM+PPL 双 bypass=页表级内核全权 → patch 内核 SSV seal 校验/remount 路径的底座由此具备。L2 从"零先例纯理论（30-40%）"上调为"拼图齐全待 PoC"——但**真根域=16.6.1-17.3.1**（Coruna 17.4 修），非 18.7.1；18.x 域（DarkSword 18.4-18.7，18.7.7 修复）PPL/SPTM 方案待查（A 线）。
3. **用户授权对齐**："做不出来就用网上的"——Coruna/Rocket 即网上现成拼图。

## 四、合规边界（必须过汇总员/用户定夺）

- Coruna 是**武器化恶意 kit 的泄露代码**（GhostBlade 窃密载荷同源）。技术拼图公开 ≠ 可无脑搬运：exploit 链本身（漏洞+绕过）与恶意载荷是两回事，社区惯例=借鉴公开漏洞分析与 bypass 思路、**不复用攻击基础设施与载荷**。
- 建议改造边界：从 ANALYSIS.md/writeup 复现 bypass 原理（Rocket 的 SPTM/PPL 路径）→ Euphoria 自研实现；khanhduytran0 仓库仅作机制参考不直接搬码。此路线法律与声誉风险最低，工程量=B 侧"原理复现"而非"代码移植"。
- 最终边界由汇总员呈报用户定夺（用户已说"用网上的"，但武器化代码与公开 PoC 的区别值得一句知悉）。

## 五、后续动作建议

| # | 动作 | 归属 |
|---|---|---|
| 1 | Rocket SPTM/PPL bypass 机制深读（AppleWiki 词条+writeup 全文）→ 原理复现评估 | C（情报）/A（漏洞线） |
| 2 | 18.x 域 PPL/SPTM 现状核查（DarkSword 18.4-18.7 组件是否自带） | A |
| 3 | 真根 L2 PoC 立项（域=16.6.1-17.3.1）——95% 门槛评审输入 | 规划师 |
| 4 | 合规边界呈报用户 | 汇总员 |
