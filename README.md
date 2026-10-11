# Euphoria

<p align="center"><img src="Application/Euphoria/Assets.xcassets/Euphoria.imageset/Euphoria.png" width="96"></p>

**Euphoria** 是一款基于 [Dopamine](https://github.com/opa334/Dopamine)（MIT 协议）源码深度重构的全新 rootless 半不完美越狱工具。

## 支持范围（诚实口径，2026-08-28 修订）

> 修订说明：旧表"与上游保持一致（漏洞核心未改动）"与"A12/A13 支持到 18.7.1/26.x"自相矛盾，本表按树内 exploit 清单逐链核对后重写，三档标注。

| 档位 | 设备架构 | 系统版本 | 依据链 |
|---|---|---|---|
| **实证级**（漏洞链生态内已验证） | A12 / A13 | iOS 15.0 – 16.5.1 | kfd 系内核 + dmaFail PPL |
| | A14 – A17 | iOS 15.0 – 16.0 | kfd + dmaFail |
| | A14 – A17 | iOS 16.1 – 17.3.1 | kfd + Titan PPL |
| | arm64（A8–A11 旧设备） | iOS 15.0 – 16.5.1 | kfd 系 + dmaFail（15.4.1 以下另有 badRecovery PAC 路径） |
| **实验级**（代码已集成，实机验证未完成，可能卡在流程中段） | A12 / A13 | iOS 16.6.1 – 18.7.1 | ClearSword + momentarius（ClearSword 未实机验证） |
| | A12 / A13 | iOS 18.7.2 – 18.7.6, 26.0 – 26.3.x | DarkSword + momentarius（"零武器化直扩"，实机回归未做） |
| **不支持** | arm64 旧设备 16.6+ | — | 内核 exploit 覆盖但 PPL bypass 断链（无可用 PPL 绕过） |
| | A14+ 17.4+ | — | 无 SPTM/PPL bypass |
| | 全部 26.4+ | — | CT 已修复（详见 EUTrollE 域文档） |

⚠️ 两点如实声明：
1. **实证级≠本项目已实测**：本项目对上游 jailbreakd 做了大幅简化重构，所有版本段（含实证级）都需实机回归后才能承诺；实验级版本段在实机验证完成前一律视为"可能失败"。
2. 巨魔E（TrollStore-E）为独立免越狱安装域，其版本窗见 `EUTrollE.h` R32 契约，与上表越狱链分立。


## 相比上游的主要变更

- **全新品牌标识**：应用更名 Euphoria，全新分子主题图标（5 套配色）、启动 Logo
- **全新代码命名空间**：类前缀 `DO*` → `EU*`（52 个类），bundle ID `dev.euphoria.Euphoria`，核心二进制 `euphoria`
- **全新运行时标识**：dyld UUID 魔术前缀 `DOPA` → `EUPH`，XPC 域 `JBS_DOMAIN_EUPHORIA`，环境变量 `EUPHORIA_*`，自有 Debian 包系（`libkrw0-euphoria` / `libroot-euphoria` / `euphoria-basebin-link`）
- **健壮性修复**：更新检查器对不存在的 GitHub 仓库（404）做了优雅降级
- **完整中文文档**：架构解析、构建指南、二次定制指南见 `docs/`

详细变更清单见 [CHANGES.md](CHANGES.md)。

## 构建前必读

1. 本项目为源码交付，**不提供预编译产物**。请阅读 [docs/BUILD.md](docs/BUILD.md) 自行构建。
2. 越狱需要有效签名身份（开发者证书 / AltStore / TrollStore 等任一自签方案）。
3. 默认更新源指向占位仓库 `euphoria-jb/Euphoria`，部署前请在 `EUUIManager.m` 与 `EUUpdateViewController.m` 中替换为你自己的发布地址。

## 免责声明

本项目仅供安全研究与个人设备定制学习。越狱会使设备脱离厂商安全模型，可能影响保修、数据安全与部分应用（银行类）运行。请在充分理解风险后自担使用。

## 致谢

- [opa334](https://github.com/opa334) — Dopamine 上游作者，本项目绝大部分核心代码的缔造者
- Dopamine 全体贡献者（见应用内 Settings → Credits 完整名单）
- Fugu15、kfd、XPF、ChOma 等公开研究成果

Euphoria 以 MIT 协议开源，衍生自 Dopamine（MIT）。保留全部上游版权声明，见 [LICENSE.md](LICENSE.md)。
