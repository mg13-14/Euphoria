# Euphoria 衍生变更清单（相对上游 Dopamine）

> 基准：上游 main 分支（commit `eaa0494`，"Updated Korean Translations"）
> 转换脚本自动化执行 + 人工定向修补，全程可审计复现。

## 1. 品牌 / 标识重命名

| 维度 | 上游 | Euphoria |
|---|---|---|
| 应用名 / 显示名 | Dopamine | Euphoria |
| ObjC 类前缀 | `DO*`（52 个类） | `EU*` |
| 主 App bundle ID | `com.opa334.Dopamine` | `dev.euphoria.Euphoria` |
| 漏洞利用框架 bundle ID | `com.opa334.{Titan,kfd,...}` | `dev.euphoria.{Titan,kfd,...}` |
| BaseBin 核心二进制 | `dopamine` | `euphoria` |
| dyld UUID 魔术前缀 | `DOPA<version>` | `EUPH<version>`（写入端 `basebin_gen.m` 与读取端 `systemhook/main.c` 同步替换） |
| XPC 服务域 | `JBS_DOMAIN_DOPAMINE` / `JBS_DOPAMINE_*` | `JBS_DOMAIN_EUPHORIA` / `JBS_EUPHORIA_*` |
| launchd 守护进程标签 | `com.opa334.Dopamine.startup` 等 | `dev.euphoria.Euphoria.startup` 等 |
| 环境变量 | `DOPAMINE_INITIALIZED` / `DOPAMINE_IS_HIDDEN` | `EUPHORIA_INITIALIZED` / `EUPHORIA_IS_HIDDEN` |
| Debian 包名 | `libkrw0-dopamine` / `libroot-dopamine` / `dopamine-basebin-link` | `libkrw0-euphoria` / `libroot-euphoria` / `euphoria-basebin-link` |
| 产物文件 | `Dopamine.tipa` / `Dopamine.ipa` | `Euphoria.tipa` / `Euphoria.ipa` |
| 更新源 | `github.com/opa334/Dopamine` | 占位 `github.com/euphoria-jb/Euphoria` |

**统计**：187 个文件内容改写、103 个文件重命名、5 个目录重命名。

## 2. 刻意保留的上游标识（功能依赖，不可改）

- `com.opa334.TrollStore` — 对外部应用 TrollStore 的运行时探测
- `.gitmodules` 全部子模块 URL（ChOma / XPF / opainject / litehook）— 上游构建依赖
- `/var/jb` 越狱根路径 — 与 Procursus bootstrap 生态兼容
- 应用内致谢名单、`control` 文件中的作者字段 — MIT 协议署名要求
- `Credits_Made_By` 本地化字符串 — 上游作者署名

## 3. 功能性修改

1. **`EUUIManager.m` `getLatestReleases`**：增加 `isKindOfClass:[NSArray class]` 校验。原实现在更新仓库返回非数组 JSON（如 404 的 dict 响应）时可能产生类型混淆，现在统一优雅降级为空列表。
2. **`Credits.plist`**：致谢分组新增 "Dopamine (upstream)" 条目。

## 4. 资源重制

- 5 套应用图标（默认紫、蓝、绿、紫罗兰、红）全部重新绘制：渐变底 + 儿茶酚胺分子抽象图形，共 75 张 PNG
- 应用内 Logo（`Euphoria.imageset` 1x/2x/3x）与 `EuphoriaLogo.pdf` 重制

## 5. 文档新增

- `README.md`（重写）、`LICENSE.md`（双版权）、`docs/ARCHITECTURE.md`、`docs/BUILD.md`、`docs/CUSTOMIZE.md`

## 6. 修复的上游遗留问题

- `.gitmodules` 中指向已不存在路径 `Application/Dopamine/Dopamine/Exploits/kfd/kfd` 的失效子模块条目已移除（kfd 漏洞源码现已直接内置于仓库）

## 7. rootful mount-over 引擎（2026-08-26，并行搜索员B，T5/T14/T15）

> 基于 ghh-jb/Dopamine_Rootful（作者 untether，MIT）bootstrapfs 组件的加固移植；
> 移植分析输入：C7 报告。上游署名保留于源文件头与 `LICENSE.md`。

- **新增 `BaseBin/bootstrapfs/`**：事务式 mount-over rootful 引擎
  - `probe`：容器/卷布局探测（IOKit 注册表父节点遍历为主，布局猜测仅作已验证的兜底）+ APFS SPI 存在性上报
  - `enable`：空间预检（statfs+全量测量，1.1×+512MiB 裕量）→ 建卷+staging 区复制（不触活系统目录）→ 校验 → 六卷一次性 commit 挂载；pre-commit 任何失败自动销毁全部新建卷（重启亦完全干净）
  - `recover`：秒级纯 remount；`disable`：逆序卸载保数据；`purge`：强制 `--confirm` 双确认后销毁卷+状态；`rollback`：清理未提交残卷
  - 加固项：相对/绝对符号链接原样保留（readlink+symlink，闭合 ghh TODO）、单文件 3 次指数退避重试、fseventsd 噪声跳过、进度 JSON 事件流（`--progress-fd`）、卷名默认伪装前缀 `com.apple.storage.`（cloakd 可按状态文件过滤）
- **`libjailbreak/src/rootful_fakefs.{h,c}`**：引擎编排（posix_spawn+pipe 流式进度回调）；`rootful.c` 三个占位函数替换为引擎委托，KRW 内存改挂载路径保留为兜底；`rootful_enable_ex` 带进度回调导出
- **`jbctl internal rootful <status|enable|recover|disable|rollback|purge>`**：App 驱动的维护命令组（purge 拒绝无 `--confirm` 执行）
- **`euphoria` 越狱流程（T14 分叉）**：开关开启→引擎 enable/recover（`[STAGE] {json}` 事件转发到 stdout 供 App 进度页解析）；开关关闭→默认 rootless 流零改动；矩阵外机型灰置（rootful_supported_configuration 双保险）
- **`docs/06-rootful开关与进度视觉交付包_T15.md`**：前端消费契约（事件协议、双流程文案「激活/恢复」、失败与回滚话术、资产清单、验收对照）
- **`scripts/verify_bootstrapfs.py`**：交付静态自验（39/39 通过）

## 8. V0.9.1 变更总集（2026-08-27，版本基线 ADR-012 再修订）

> 版本号统一 V0.9.1（MARKETING_VERSION 20/20 已落，含 B 评审三处修正收编——用户 16:17 裁定：beta 未发布，直接定版 V0.9.1，不设 beta 序号）；「测试版」定性=转正条件达成前一律 V0.9.x。

### 8.1 巨魔E（TrollStore E）核心 —— `EUTrollE.{h,m}`（R19/B23~B26/R31~R32）

- **Engine A（越狱态 Tier A，本版满血）**：ChOma 取主二进制 CDHash → `jb_trustcache_add_cdhashes` 注入运行时信任缓存 → 拷入 `/var/jb/Applications` + uicache；重放表 `/var/jb/var/db/euphoria/trolle.plist`，`EUBootstrapper` 每次越狱幂等重放——秒装秒签、重启重放。
- **R32 build 级版本域契约（EUTrollE.h 固化）**：未越狱 Engine B/C = iOS 14.0~18.7.1 @ A12~A13 三档分层——①永久档 14.0b2~16.6.1 ＋ 16.7b1~b6/RC（20H18）＋ 17.0 全系（中间版本不降级，与原版巨魔同域）；②会话/容器档 16.7 GA（CT 修复首发 20H19 死区）＋ 17.0.1~18.7.1；③PC 辅助子模式仅限未越狱 16.7b/RC/17.0 段（arm64e 设备端 kfd 装法死，走备份注入=TrollRestore 先例）。越狱态 Engine A = 越狱链可及域（15.0~18.7.6 + 26.0~26.3.99）零辅助直装。
- **Engine B 实现体（漏洞级免越狱，错误码 12/13/14）**：域校验（build 级，16.7 仅 RC 20H18 放行）→ helper 快路径（URL scheme `euphoria-trolle://` 移交）→ kfd+dmaFail 一次性会话 → `proc_ucred_update_content` root 化 → libarchive 解包 → MobileInstallation CT 永久签名装本体 → helper 第二槽位 → 重放表登记（role/engine 新字段向后兼容）→ 零残留收尾。实现注记见 research/B25（MIInstall 历史 ABI 假设等四项决策随评审更新）。
- **Engine C 实现体（L1 容器模式，安装侧）**：`installApplicationContainerizedAtURL`——libarchive 解包 → 沙盒 `Documents/EUTrollEContainers/<uuid>/` 落位 → 重放表 engine=C → 零残留回滚；主屏图标=快捷指令 + `euphoria-trolle://launch?id=<uuid>`（快捷指令机制实证无 GPL 传染；LiveContainer 仅机制借鉴，零代码搬运）。进程内启动器运行时（dlopen 引导+宿主代签）→ **V0.9.2**。
- **跨引擎三缺陷修复**：①`registryPath` 双模化（免越狱=沙盒镜像表，越狱=/var/jb 主表，原实现免越狱态必崩）②`saveEntries` 三路（root 直写/沙盒直写/runAsRoot）③`replayTrustCacheEntries` 前置 `migrateSandboxRegistryIfNeeded` 幂等合并——免越狱期装的 app 下次越狱自动进主表重放（B25「L1→L3 升级」闭环）。
- **B 评审（15:15，四决策+三修复全过，三处修正）**：①MIInstall 异步竞态——补信号量等回调终态（Progress=100/Error，30s 超时兜底，TrollHelper 同构）②libarchive symlink 逃逸——条目级硬拒绝 AE_IFLNK（版本无关）③scheme `euphoria-trolle` CFBundleURLTypes 落 Info.plist（评审前缺失）；另补 .h 声明（sandboxRegistryPath/migrateSandboxRegistryIfNeeded）与门面注释刷新。

### 8.2 漏洞域与闸门（R29 快胜线）

- **DarkSword → 18.7.6 / 26.3.99**（Apple 18.7.7 公告点名修复，18.7.2~18.7.6+26.1~26.3 双窗零武器化直扩）；**momentarius → 26.3.99**；versionSupportString 同步。
- 偏移走 XPF patchfinder 动态寻找（无逐 build 表），实机回归批次验证。
- ClearSword 闸门保守未动（同 IOSurface 家族、疑与 DarkSword 同窗，待实机冒烟后拉宽——R29 文档 §九）。
- **18.x 永久档设计约束（T26-c）**：非 root 授权进程不能再派生 root 进程（root helper 路在 18+ 不可用）→ Engine B/C 会话链进程内自持 KRW，不碰 root helper。

### 8.3 分发与致谢

- **`trolle-installer/` deb 骨架**（`dev.euphoria.trolle-installer`，B24 分发架构）：control + postinst 只放文件不跑安装，随 EU 源分发。
- **R12 致谢落地**：主 App `Credits.plist`（特别致谢 mg13-14 + AI 协作「清言 AgentMore 全员 + GLM/Z.ai」，三语言键）+ 安装器 CREDITS。

### 8.4 其余就绪项（V0.9.1 收录）

- R21 设置 18 项（diff=0 对齐）、R22 挂载管理、R14 固定源锁定、R25 ElleKit 开箱注入、R24 iDownload（`BaseBin/idownloadd/`）。

### 8.5 V0.9.2/后续边界（如实标注，不阻塞本版）

- **EU PM**（R17/T18，规格已定 v5 §四，实现未启动）、Engine C 进程内启动器运行时、ClearSword 闸门拉宽（待实机）、免越狱会话域重启持久化（非 CT 向量攻坚线未定）。

### 8.6 用户实锤四连修复（2026-08-28 00:19 夜间，R34——"漏洞百出"投诉落地）

> 用户实测反馈逐条核实为真，当日修复。诚实记录：四条全对，不辩解。

- **①Credits 页多巴胺作者残留（实锤）**：`Credits.plist` 三组上游署名格（Developers：opa334 等 6 人；UI and Design：3 人；Credits：Dopamine/Fugu15 等 28 条）整组移除——界面不再出现任何 Dopamine 系署名；License 按钮保留（GPL 合规走 License 页文本，不上 UI 致谢墙）。保留：mg13-14 特别致谢 + AI 协作 + 三按钮。
- **②rootful 设置开关被吃（实锤）**：`EUSettingsController` 全文 0 个 rootful 引用，底层 jbsettings 域 `rootfulUserEnabled` get/set 齐备却从未接线。已补：A12/A13@16.6.1~18.7.1（`rootful_supported_configuration()`）显示可用开关，域外灰置+脚注说明矩阵；双模读写（未越狱=本地偏好下次越狱生效/越狱态=jbsettings XPC 直推）+ 重越狱生效提示；27 语言包三键补齐。
- **③"卡住→假已越狱"状态机（实锤，最严重）**：`jbdomain_euphoria.c` 的 `euphoria_is_jailbroken` 原实现**无条件 return true**——launchdhook 一注入即"越狱成功"，bootstrap/包管理/隐藏装一半卡死照样显示已越狱。改事务式：daemon 全流程走完写 `.bootstrap_complete` 标记（起点清除），判定要求 `.version`+`.bootstrap_complete` 双证；半程=未越狱，可幂等重跑。
- **④移除越狱按钮越狱态不可见（实锤）**：两处入口被 `!isJailbroken` 门控（上游"俄罗斯轮盘"注释原样保留）。恢复越狱态红色入口（C 侧落 UI+确认弹窗；后端按 A 方案：清 /var/jb+bootout+标记清理）。
- 未完项（如实）：卡死具体步骤待用户实机日志；越狱源有效性/自有 EU 源（T18 线）；UI/颜色/重启视觉整改；用户外部 AI 修改版待回传合并。

### 8.7 R35 用户 UI/源三连（2026-08-28 10:17，B 主刀）

- **默认主题色=App 图标背景板（实锤）**：default 主题原引用 `Background_Green.jpg`（多巴胺遗产绿）——绿从哪来实锤。已生成 `Background_EU`（3000×2000，图标同款 #55298C→#F1509D 紫粉渐变+光晕+防 banding 噪点），default 主题 image/windowColor(9955298C)/actionMenuColor(72F1509D) 三点切换；其余四主题（ellekit/blue/red/purple）暂存为可选项，砍留待用户裁定。
- **开机图全屏化（实锤"中间小图标四周黑"）**：`EUTheme.generateBootLogo` 旧实现=主题横图(3000×2000)+固定 350×350 logo，竖屏开机显示必然黑边+占比过小。重构：竖屏全屏画布 1179×2556、背景=图标渐变直绘（不再依赖主题图）、logo 放大至画布宽 55% 居中——Dopamine 全屏构图同款，黑边来源根除。
- **六源实测（用户令"验证是否真实有效"）**：YouRepo（302→200，今日 04:08 更新）✓/Chariz 200✓/Havoc 200✓/BigBoss 200✓/roothide Procursus 镜像——静态 dists 根路径 404 属正常，实际 suite=`iphoneos-arm64e/{BOOTSTRAP}` 替换=1900（iOS 16+ 亦用 1900 rootless bootstrap，代码 `cfver>=2000→1900` 实证），`dists/iphoneos-arm64e/1900/Release` 200 且 2026-04-24 更新 ✓；EU 自家源=eu-repo/ 实体（Release/InRelease/pool 齐，A 建）。**rootless/rootful 共用同一源集合（用户 10:17 定案，含 EU 源）**；EU 源挂入 PresetSources 第六槽待域名定案。

### 8.8 R36 模式分叉隐藏入口（2026-08-28 10:27:28 用户定案，B 落码）

- **规则**：选 rootless（未勾 roothide/rootful）→ 设置页**不给隐藏软件**双开关，只给"隐/显越狱"（Dopamine 同款：Euphoria 图标主屏隐藏，Spotlight 可找回）；roothide 模式才显示 aegis"隐藏越狱应用"+cloak"隐藏越狱痕迹"双开关。
- **实现**：新增 `EUEnvironmentManager.isRoothideMode`（越狱态+未开 rootful=roothide 默认链，与 activate_rootful_and_cloak 语义一致）；EUSettingsController 按模式分叉渲染——roothide 分支保留原双开关（后端 jbctl aegis/cloak），rootless 分支新增 Hide_Jailbreak 开关（复用 aegis 同后端，独立偏好键 jailbreakHidden）；26 语言包补 Hide_Jailbreak/Hide_Jailbreak_Footer 两键。
- **用户叮嘱"你们一定要检查好"**：三个改动文件语法粗检（括号平衡/符号存在）全过；roothide 判定与 daemon 侧 rootfulUserEnabled 消费点（main.m L411）同键同源，无双头。

### 8.9 R37 真根口径+三态联动（2026-08-29 00:11 用户定案，B 落码）

- **真根口径（用户"不能是伪根"）**：root 权限=uid0+KRW+内核补丁，漏洞链直取，**从来不是伪根**；rootful 引擎三条路径均不占额外内存——fakefs 主路径（bootstrapfs 新卷+拷贝+重挂载）占的是**磁盘**（rootfs 一份拷贝，业界唯一绕 SSV 密封的可行路线）；overlay 降级（六目录 nullfs）upper 层落 jbroot 磁盘；remount 仅清 MNT_RDONLY 标志。"SSV 密封卷直接可写"物理不存在（Secure Enclave 持钥，内核 root 也解不开），opa334 的 Dopamine fakefs 同理。95% 把握门槛+做不出用网上的授权已记录，降级链（fakefs→remount→overlay）本身就是该原则的工程化。
- **三态联动（daemon+服务端+UI 三层落地）**：
  - `info.h`/`jbsettings.c`：新增 `roothideUserEnabled` 键（get/set+序列化）；**服务端写侧兜底**——写 rootful=true 自动捆绑 roothide=true；写 roothide=false 强制 rootful=false。
  - `main.m activate_rootful_and_cloak`：rootfulWanted 前置校验 roothideToggle，存量违规状态打日志强制关 rootful。
  - `EUEnvironmentManager.isRoothideMode`：R36 推断式判定改显式键三态（都没勾=rootless；roothide 或捆绑中的 rootful=roothide 视角，隐藏栈在 rootful 下同样在）。
  - `EUSettingsController`：新增 roothide 独立开关（Roothide_Mode 两键 26 语言包）；rootful set 开启时自动置 roothide（本地偏好+XPC 双写）；roothide set 关闭时强制关 rootful（双写+日志提示）。
- **反检测语义（用户令）**：rootful 状态=cloak（hideMounts/hideCredentials/hideTrustcache）+aegis 全套在身——activate_rootful_and_cloak 既有语义"rootful 捆绑完整隐藏栈"与新定案天然一致，无需改。

### 8.10 R37 续：43520 修复点铁证+EUTrollE 域注释修正（2026-08-29 00:24，B 情报核对）

- **CVE-2025-43520 修复点定案**（A 待办、规划师 v18.1 提请注意②的"版本矛盾双悬"闭一半）：**单点修复=iOS 18.7.2 / iPadOS 18.7.2 / iOS 26.1**（NVD NIST 官方原文+Apple 26.1 安全公告双源一致）。8kSec 口径"≥18.7.7 或 ≥26.3"是 **DarkSword 全链 fleet 安全基线**（原文"18.7.2 and 18.7.3 closed most CVEs but not all"），非任何单 CVE 修复点——树内此前把"18.7.7 修复"挂到 43520 属错误挂靠。影响：DarkSword 声明窗 18.7.2~18.7.6 段内核段已补、链断；17.4~18.7.1 可用域终定待 A 按 8kSec Part1/2 逐 CVE 对表。
- **EUTrollE.h 越狱态域注释修正**：去掉 R29 拉宽口径（15.0~18.7.6+26.0~26.3.x），改为 R34 诚实矩阵（实证 15.0~16.5.1；16.6.1+ 实验性，A12/A13 卡点=momentarius PPL 假设级未实测）+43520 修补注记（18.7.2+）+"勿混用 fleet 基线与单 CVE 修复点"警示。
- 相关情报（见 shared/B_RocketPPL收编评估_三档定案_20260829.md）：Rocket=CVE-2024-23296 首个公开 SPTM+PPL bypass（16.6~17.3.1）；Relaxin 整仓 MIT 开源（08-17，AI 复现先例，RootHide 架构）；pattern-f 到 26.0.1 未公开；bl4ckh0l3z 演示 18.x~26.0.1 全链——26.x PPL 绕过物理可行已证。

### 8.11 R38 屏蔽软件双形态（2026-08-29 11:41 用户定案，B 落码）

- **规则**：检测"是 rootful 还是普通 roothide"决定屏蔽目标方向——rootful 态=深档（挂载面大/检测面大→激进过滤），普通 roothide=基础档。屏蔽软件两种形态。
- **实现**：
  - daemon `main.m` activate_rootful_and_cloak：cloak_enable 后按 rootfulWanted 落形态——深档 stealthLevel=3+三 hide 全开；基础档 stealthLevel=1+三 hide 全开；每次越狱幂等重放，用户 set_options 手动覆盖仍可。
  - `cloak.h` 档位语义订正（原注释"0=paranoid"与 interpose 实现相反——实现是等级越高隐藏越深：stealth>=2 时 getfsstat 白名单外挂载全隐）。深档=3 正好吃到该分支（rootful 的 fakefs/overlay 六目录全被滤掉）。
  - `main.c` csops_hook 增强：深档（hideTrustcache 开）时 CS_GET_TASK_ALLOW 一并抹除（CS_DEBUGGED 抹除为既有行为）；csops_hook 注册从 arm64 专属段提到全架构（arm64e=A12+ 主流，深档必须生效）。csops_audittoken_hook 保持原位（其动机=arm64 自写页 CS_VALID 补活，arm64e 无需）。
  - App `EUEnvironmentManager.cloakStealthForm`：形态读出（3=深档 rootful/1=基础档 roothide/0=rootless 未随行），供 UI 与检测展示消费。
- **深/基础档差异表**（行为定义）：基础档=jbroot+/var/jb 挂载隐藏+凭据隐藏+CS_DEBUGGED 抹除；深档=基础档全部+白名单外挂载全隐（fakefs/overlay/cover mount）+CS_GET_TASK_ALLOW 抹除（反检测 SDK 常用两位）。
- 质量关：五文件语法粗检过（main.c 括号差 1 系原生注释表情 ":("，去注释后纯代码全平衡——非本次引入）；csops 单实现（误建的重复段已清）。

### 8.12 R38 附带：支持矩阵串双档化（2026-08-29 11:47，随 A 终定）

- EUEnvironmentManager versionSupportString 三处更新：①A12/A13 实验段上限随 DarkSword 声明窗收敛（16.6.1-18.7.1/26.0-26.0.1，43520 修复点 18.7.2/26.1 硬边界）；②A14（PPL）与 A15+（SPTM）拆"持久化档/L1 会话档"双标注——A 11:47 认知修正（43520 data-only 不需 PPL→L1 会话档全域可行，断链只在 17.4+ 持久化档）。

### 8.13 R38 收尾：S2 全局 csops 过滤检查项落账（2026-08-29 11:48）

- jbdomain_cloak.c 尾部落 R38/S2 TODO：未注入进程的 csops 呈现（data-only 链签名翻转后，未注入子进程查询 csflags 无遮蔽——systemhook csops_hook 只保护被注入进程）。深档完整闭环需 launchdhook/系统级全局过滤，S2 执行层重写时随 C 的 Form-B 六面向量一并落（B 认领）。
- 技术依据：csops_hook=位掩码抹除（CS_DEBUGGED|CS_GET_TASK_ALLOW，不管 flags 来源形态），翻转路径新暴露形态已被盖住；边界=注入名单外进程。

### 8.14 R39 用户实机靶场落账（2026-08-29 11:48 报备，B 对矩阵）

- 四台：A15@15.6.1（持久化甜点区，首发实测位）/A13@18.1.1（A12/A13 线实验段主验证位）/A17 Pro@17.6.1（17.4+ 断链区→L1 会话档测试位）/A15@26.5.2（超 43520 修复点 26.1，无公开链→自研线攻面评审参考位）。
- 已落 EUEnvironmentManager versionSupportString 前注释，实测回归按此排序。

### 8.15 R38-bis：L3 模式感知过滤升级注记（2026-08-29 11:49，随 A 集成重评）

- main.c csops_hook 注记三件：①data-only 链不碰 trustcache→hideTrustcache 在 Form-B 空转（无害但无效，Form-A 持久化档才需要）；②新暴露向量=cs_flags 翻转痕迹——L3 终态="序列还原"（完整正常 flags 序列，防按位组合指纹）+AMFI 策略位呈现，S2 随 Form-B 六面重构，现有位掩码=过渡档；③验收标准=翻转后进程检测面呈现与干净设备逐位一致。

### 8.16 战略图景对表（B 补充：四台设备×三条线×我的落码覆盖位）

- 易胜线（A15@15.6.1）：现有 Dopamine 经典域拼图齐——B 名下 BaseBin（rootful 引擎/三态联动/卸载链/假越狱事务化）全部即用。
- 主力线（A13@18.1.1+A17Pro@17.6.1）：共用 43520 复刻成果——B 认领 S2 全局 csops 过滤（jbdomain_cloak TODO 已落）+cloak 双形态（R38 已落）是该线的反检测执行件。
- 长尾线（A15@26.5.2）：等新洞，不进承诺；自研线 CVE 批次（A）对着它。

### 8.17 R40 屏蔽软件黑名单制（2026-08-29 17:00:57 用户定案，B 落码）

- **规则**：屏蔽软件有黑名单——拉黑的 app 检测不到越狱环境；**不在名单的 app 默认信任**（用户收回"文件管理器也不能知道 root"：文件管理器靠越狱/巨魔提权工作，屏蔽它等于废掉它）。
- **实现（九文件）**：
  - `cloak.h/cloak.c`：cloak_policy_t 加 `blacklistMode`（默认 on）+序列化三处（serialize/deserialize/get_policy reply）。
  - `info.h/jbsettings.c`：`cloakBlacklistMode` 持久化键（get/set+序列化宏）——读路径统一走此键（**jbserver 框架限 8 参，GET_POLICY 表已满**，曾误插致处理器错位+error 出参截断，已回滚并注记）。
  - `jbdomain_cloak.c`：SET_OPTIONS 加 blacklistMode 入参（a6 位，6/8 参安全）+处理器写入。
  - `cloak_interpose.h/c`：cache 加 blacklistMode；reload 补读 jbsettings 键；`cloak_process_on_aegis_list()`（aegis 名单弹性匹配——与 aegis_interpose.c 同逻辑内联解耦，root 属主文件不动，双处同步义务已注记）；`cloak_process_is_trusted()` 黑名单短路——blacklistMode 且不在名单→信任（名单外=完整可见可管）。
  - daemon `main.m`：越狱时 cloak_set_options 落 blacklistMode=true（默认开，幂等重放）。
  - `jbctl`：cloak set blacklistMode=0|1 + status 显示 Blacklist mode。
- **语义**：黑名单（aegis 名单）内=全套过滤视图（R38 双形态档位照常）；名单外=root/受信规则之外一律信任；blacklistMode=false=R40 前旧语义（非受信全隐藏）留兜底开关。
- **用户三答收讫**：①"能动系统"验收=系统最高控制权（删改系统文件+常驻+L2 全要，具体验收条 S0 评审自拟）；②目前自用将来或分发（分发合规要留）；③顺序=容易的放先（易胜线 A15@15.6.1 先行）。
- **致谢合规提醒（用户叮嘱"记得致谢的事"）**：R34 机制延续——Relaxin（MIT）收编时 Credits/License 页按 MIT 署名 OwnGoal Studio；**Titan 无许可证=默认保留所有权利，直接武器化有合规红线**，95% 评审需先裁（联系作者补许可或走自研/write-up 复现路线）。
