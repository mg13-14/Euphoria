# B21 · Dopamine 设置项全量清单（R21 对齐参照，逐行源码提取）

- 需求：R21（用户 23:24:06）"越狱工具的设置中的那些功能，必须跟Dopamine的那些一样"
- 提取源：`Dopamine_Rootful/Application/Dopamine/UI/Settings/DOSettingsController.m`（specifiers 构建 + getter/setter 语义）+ `zh-Hans.lproj/Localizable.strings`（官方中文标题）
- 作者：并行搜索员B · 2026-08-26 23:30 ｜ 用途：Euphoria 设置页 100% 对齐的验收基线

## 1. 分区与设置项总表（4 分区 / 13 项）

### 分区① 漏洞利用（Section_Exploits"漏洞利用"）
显隐条件：`isSupported && !isJailbroken`（已越狱时整区隐藏）

| 项 | 中文标题 | Cell | key | 默认 | 备注 |
|---|---|---|---|---|---|
| 内核漏洞 | Kernel Exploit | 列表→子页 | `selectedKernelExploit` | preferred 内核 exploit | 推荐项=列表第一个（priority 排序后）；子页带"推荐"标记（DOPSExploitListItemsController） |
| PAC 绕过 | PAC Bypass | 列表→子页 | `selectedPACBypass` | `none`（不需要时）| 仅 arm64e 设备显示；不需要 PAC 时多一个"无"选项 |
| PPL 绕过 | PPL Bypass | 列表→子页 | `selectedPPLBypass` | preferred PPL bypass | 仅 arm64e 设备显示 |

### 分区② 越狱设置（Section_Jailbreak_Settings"越狱设置"）
显隐条件：`isSupported`（越狱前后都在）

| 项 | 中文标题 | Cell | key | 默认 | 行为语义 |
|---|---|---|---|---|---|
| 插件注入 | Settings_Tweak_Injection | 开关 | `tweakInjectionEnabled` | 开 | 越狱中切换→弹"立即重启用户空间/稍后"双选警告框，确认后 `rebootUserspace` |
| 详细日志 | Settings_Verbose_Logs | 开关 | `verboseLogsEnabled` | 关 | 仅 `!isJailbroken` 时显示 |
| iDownload（开发者终端） | Settings_iDownload | 开关 | `idownloadEnabled` | 关 | 越狱中切换即时生效（`setIDownloadLoaded:needsUnsandbox:`） |
| 允许 App 使用 JIT | Settings_Apps_JIT | 开关 | `appJITEnabled` | 开 | 越狱中读写 jbserver 键 `markAppsAsDebugged` |
| Jetsam 倍数 | Settings_Jetsam_Multiplier | 列表→子页 | `jetsamMultiplier` | 6（=3x，标"推荐"） | 选项 2~8 ↔ 标签 1x/1.5x/2x/2.5x/3x(推荐)/3.5x/4x；越狱中 jbserver 键 `jetsamMultiplier`（double=value/2，读时 ×2 取整） |
| 移除越狱（开关形态） | Button_Remove_Jailbreak | 开关 | `removeJailbreakEnabled` | — | 仅 `!isJailbroken && !isInstalledThroughTrollStore`；打开即弹确认框，取消自动回弹 |

### 分区③ 操作（Section_Actions"操作"）
显隐条件：`isJailbroken || (isInstalledThroughTrollStore && isBootstrapped)`

| 按钮 | 中文标题 | 条件 | 动作 |
|---|---|---|---|
| 刷新越狱 App | Button_Refresh_Jailbreak_Apps | isJailbroken | `refreshJailbreakApps`（icon: arrow.triangle.2.circlepath） |
| 修改"mobile"密码 | Button_Change_Mobile_Password | isJailbroken | 先 LAContext 设备认证（支持则强制），再弹双密码输入框（两次不一致重弹），`changeMobilePassword:`（icon: key） |
| 重新安装包管理器 | Button_Reinstall_Package_Managers | isJailbroken | push `DOPkgManagerPickerViewController`（icon: shippingbox.and.arrow.backward，iOS16- 降级为 shippingbox） |
| 隐藏/取消隐藏越狱 | Button_Hide/Unhide_Jailbreak | isJailbroken 或 TS+已引导；已隐藏且未越狱时不显示 | 切换 `isJailbreakHidden` 后 reload（icon: eye / eye.slash） |
| 移除越狱 | Button_Remove_Jailbreak | 同上 | 确认框→`deleteBootstrap`；越狱中则重启，未越狱则重定位 jbroot；隐藏按钮可见时 footer 显示"可先隐藏越狱"提示（icon: trash） |

### 分区④ 自定义（Section_Customization"自定义"）
显隐条件：无条件（始终显示）

| 项 | 中文标题 | Cell | key | 备注 |
|---|---|---|---|---|
| 主题 | Theme | 列表→子页 | `theme` | 主题切换→App 自动重启（relaunch）+ 更换备用 App 图标（setAlternateIconName）；主题来自 DOThemeManager/Themes.plist |

## 2. 实现细节备忘（对齐时容易漏的语义）

1. **未越狱 vs 已越狱读写路径不同**：未越狱读写本地偏好（DOPreferenceManager）；已越狱时多数项直连 jbserver 实时键（tweakInjection/idownload/markAppsAsDebugged/jetsamMultiplier）——EU 版须保留这套双路径语义，否则"开关不生效"。
2. **exploit 三项仅在未越狱时出现**；PAC/PPL 两项仅 arm64e。
3. **Jetsam 换算**：UI 值/2 写入内核键，读取 ×2 向上取整；越狱中读到 <1 或 NaN 回落 6。
4. **TrollStore 安装形态的特殊显隐**（isInstalledThroughTrollStore 分支）——EU 版巨魔E 安装形态会用到同一分支逻辑。
5. 子页控制器：exploit 选择列表带"推荐"徽标（recommendedExploitIdentifier）；jetsam 列表 3x 带"(推荐)"后缀。
6. 中间层 Reset：`resetSettingsPressed` 存在但未挂 UI（EU 版可不实现，不算缺口）。

## 3. 与 R22（新增挂载功能）的落点建议

设置页对齐完成后，挂载功能自然落位=分区③"操作"内新增挂载类按钮（或分区②新增开关），与 Dopamine 布局风格一致。语义选项（团队自决，不问用户）：A. 越狱卷手动挂载/卸载（不重启进出越狱态）B. 挂载状态显示+一键重挂 C. 开机自动挂载开关。建议 A+C 组合（A 为按钮落位"操作"区，C 为开关落位"越狱设置"区）。

## 4. 版本口径（R23）

源代码交付版本 = **V0.9.0（测试版）**（用户 23:24:06）：修正 ADR-012 V1 基线；落点=Info.plist CFBundleShortVersionString / 关于页显示 / 源码交付标注。
