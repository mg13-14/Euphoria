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
