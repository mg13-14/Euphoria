# 清扫首报（A 线）：deb 架构谎报类 + 内容构成核验

**批次**：0.9.2 清扫线第一批 ｜ **执行**：并行搜索员A ｜ **时间**：2026-09-05 19:43 ~ 09-06 00:19
**触发**：用户指令「修复所有问题」；汇总员宣告「旧模型代码全树逐文件复核清扫」；C 定位 21.5MB deb 根因。

---

## 一、范围与方法

- **范围**：树内全部 9 个 deb（eu-repo/pool 3 个 + Application/Resources 5 个 + Packages/basebin 1 个）
- **方法**：`dpkg-deb` 读声明 Architecture 字段；解包后对包内每个 ≥64 字节文件读 Mach-O 魔数（`cffaedfe`/`cafebabe`），解析 cputype 逐二进制比对——防「声明 arm64、实发 arm64e」类架构谎报（ElleKit 事故同类）
- **可复跑**：脚本存 `agents/6a8d0a5300ccbc1a3c89cec0/audit_debs.py` + `audit3.py`（修正了首版短文件边界 bug）

## 二、结果总表

| 包 | 声明架构 | 可执行体 | 实际 cputype | 判定 |
|---|---|---|---|---|
| dev.euphoria.trolle-installer 0.9.1-4 | iphoneos-arm64 | 0（源码分发包） | —* | ✓ |
| launchctl 1.2.0 | iphoneos-arm64 | 1 | arm64 | ✓ |
| euphoria-basebin-link 1.0.0 | iphoneos-arm64 | 0（链接包） | — | ✓ |
| basebin-link.deb | iphoneos-arm64 | 0 | — | ✓ |
| sileo.deb | iphoneos-arm64 | 2 | arm64 | ✓ |
| ellekit_roothide.deb | iphoneos-arm64 | 3 | arm64 | ✓ |
| ellekit.deb | iphoneos-arm64 | 5 | arm64 | ✓ |
| zebra.deb | iphoneos-arm64 | 1 | arm64 | ✓ |

**结论：9/9 全绿，树内零架构谎报，ElleKit 修复实际生效**（pool 内 0.9.1-4 为 09-05 19:32 重打版，时间戳佐证）。

\* 安装器包内 libcrypto.a/libssl.a/.hwx 文件首字节恰为 Mach-O 魔数（见三）。

## 三、口径修正记录（如实留痕）

首版审计报「安装器包 2 个 arm64 二进制」，复核更正：该 2 项匹配实为 **静态库 .a 与模型权重 .hwx 的魔数命中，非可执行体**。包内零可执行、零 .app 结构。该修正不影响「零架构谎报」结论，且与 C 的「包内不含构建产物」诊断完全互证。

## 四、内容层复核（与 C 根因①交叉验证）

21.5MB 安装器 deb 实测构成：211 .h + 92 .c + 24 .m 全源码文本 + vendor 构建依赖；Description 原文明载「完整源码分发包……产物由 Mac 侧构建产出」。
**定谳：用户侧「安装不了/装了没东西」的包级根因成立**（叠加 surge 免费层 KB/s 级截断，传输层根因由 C 实测）。

## 五、瘦身定案数据（已采纳进 0.9.1-5）

未压缩 47MB 主体 = ChOma vendor 的 **libcrypto.a（39,387,760B ≈ 39.4MB）+ libssl.a（7,583,784B ≈ 7.6MB）** 构建依赖。
剥离方案（汇总员已裁定，B 落实）：Sileo 分发版剥离二 .a + devel 指引自建 openssl，分发包缩至 KB 级——surge 下载截断痛点直接消解，迁 GitHub Pages 降为可选。

## 六、遗留与下批建议

1. ✅ 架构谎报类：清零（本批）
2. ✅ 安装器包内容如实性：已核（本批）
3. ⏭ 建议下批：其余 8 包 control 字段（Name/Description/Installed-Size）vs 实际内容全量如实性核验——低危但属「正确废话 vs 如实交付」纪律面
4. ⏭ 源码级逐文件复核：汇总员/C 推进中，A 侧二进制面数据可随时供给交叉比对
5. 📌 版本一致性（源内 0.9.1-4 vs 交付 zip 0.9.1）已由源侧四验覆盖，无重复劳动

——A 线首报收口，脚本与证据可复跑复核。
