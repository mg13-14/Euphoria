# ADR-R14：固定软件源预置与"不可删除"锁定机制

- 状态：已采纳（清单口径已由用户裁定：与 Dopamine 安装默认一致，18:32:59）
- 需求：R14（01-需求追溯 第48行）："刚开始要记得加好固定的几个源，不能删"
- 决策人：B（机制设计）／实施：C（预置写入）＋ B（bootstrapfs 侧重放点）
- 日期：2026-08-26

## 1. 背景与事实基础

1. Sileo 与 Zebra 的"软件源"在磁盘上就是 `/var/jb/etc/apt/sources.list.d/*.list` 文本文件（每行一条 `deb <URL> ./`）。**UI 里删除源 = unlink 掉对应 .list 文件**，两个包管理器行为一致。
2. Sileo/Zebra 均**以 root 运行**（需要 root 才能执行 dpkg）。
3. POSIX 关键事实：`unlink()` 的授权看**父目录写权限**，与文件自身 rwx 权限**无关**。因此：
   - ❌ chmod 444 / chown root —— root 进程照样删（且文件权限根本不参与 unlink 判定）
   - ❌ 目录去写权限 —— 会连带挡住"用户新增源"，违反 R5 可用性
   - ✅ 文件级 immutable flag（`chflags(UF_IMMUTABLE)`，BSD fflags）—— 内核在 unlink/rename/write 路径上强制 EPERM，root 进程不主动 `chflags nouchg` 就无法绕过。这是唯一不需要改包管理器代码的单文件"禁删"锁。
4. fflags 存在 APFS inode 上；我们的 bootstrapfs 引擎（BaseBin/bootstrapfs）在 APFS 卷上做 copy_dir_recursive，**copyfile 未必保留 fflags** → 锁定动作必须在卷挂载后重放，不能只在打包时打一次。

## 2. 决策（三层）

### 层1 预置（C 实施，EUBootstrapper 域）
- 清单收敛到 `Application/Resources/PresetSources.plist`（数组：name / url / 固定标记），改清单只动这一个文件。
- bootstrap tar 解包完成后、`bootstrapfs create` 之前，EUBootstrapper 把每条固定源写为 `/var/jb/etc/apt/sources.list.d/<key>.list` → **首次打开 Sileo/Zebra 源列表即已存在**（满足"刚开始就加好"）。

### 层2 内核级禁删（核心机制）
- 在 bootstrapfs 卷挂载完成、以 root 上下文调用 C API `chflags(path, UF_IMMUTABLE)`（`<sys/stat.h>`，无需外部二进制，Procursus 里有没有 chflags 命令都不影响）。
- **每次越狱流程幂等重放**（挂载后顺手执行），彻底规避 copyfile 丢 flag 与系统卷重建问题。
- 效果：Sileo/Zebra 删除操作直接失败（EPERM）→ UI 表现为"删除失败"，即"不能删"；用户新增/删除**非固定**源不受任何影响。

### 层3 自愈（P2，暂缓）
- 防 SSH 手动 `chflags nouchg && rm` 的兜底：startup 阶段校验固定源存在性与内容哈希，缺失则从 App Resources 重写+重新上锁。
- 当前先不做（R14 语义是"防呆不防盗"，UI 层已满足）；ADR 留接口，用户提需求再启用。

## 3. 预置清单（口径：**六源**；18:52 B 实证修订第五源注入点）

**演变**：用户 18:32:59"和多巴胺一样"→ 树内核对 Dopamine 代码写入四源（DOBootstrapper.m:505-524）→ 用户 18:43"Sileo 显示五源"→ 规划师 18:45 猜"第五源 bootstrap 自带"→ **A 18:48 strings Sileo 主二进制实锤**（内嵌 `/procursus.sources` deb822 模板，含 `URIs: https://apt.procurs.us/` 与 BigBoss 两节）+ **B 18:52 独立复核**（sileo.deb 解包：postinst 无写源，仅 checkra1n 清理与 uicache；二进制模板确认）→ 第五源 Procursus 的真实注入点 = **Sileo.app 首启自播种**。C 的 tar 扫描（bootstrap 无源）同时成立。用户同句"你们装还得多装一个"→ 第六源 = **EU 官方源**。

| # | 源 | URI | 真实来源 |
|---|---|---|---|
| 1 | Chariz | `https://repo.chariz.com/` | Dopamine App 写入 |
| 2 | Havoc | `https://havoc.app/` | Dopamine App 写入 |
| 3 | BigBoss | `http://apt.thebigboss.org/repofiles/cydia/` | Dopamine App 写入（Sileo 模板亦含，需去重） |
| 4 | ElleKit | `https://ellekit.space/` | Dopamine App 写入 |
| 5 | Procursus | `https://apt.procurs.us/` | **Sileo 首启播种**（须由我们预置才能开箱即锁） |
| 6 | EU 官方源 | 待 PM 命名定 | 我们预置 |

**18:55 终版口径（SSOT v2.13）**：R14 预置清单定为**七源架构（roothide 对齐）**——A 18:52 按 roothide Bootstrap `sources.h` 实证：Chariz/Havoc/BigBoss/YouRepo 四公共源 + roothide 官方插件源 + roothide Procursus 镜像 + bootstrap 分发源（七项；EU 版逐项把 roothide 自家源替换为 EU 自家源）。**Zebra 容器写法先例**：roothide 对 Zebra 单独写 `xyz.willy.Zebra/sources.list`（`ZEBRA_SOURCES` 单行格式、与 Sileo 的 deb822 分开维护）——EU 双 PM 预置照此先例，Zebra 侧容器路径 + 单行格式独立落盘，锁定机制不变（chflags 同样适用）。roothide Dopamine 分支的逐行证据（default.sources 六节 + zh_CN iosjb.top 镜像 + Zebra 六条）与 CN 镜像策略建议见 `research/B20_roothide生态_预置源矩阵与转换生态.md`（B）。

实现口径（**C 已实施，18:42**）：不采用单文件复刻，按层1 逐源落盘——每条固定源一个 `/var/jb/etc/apt/sources.list.d/<key>.list`（单行 `deb <URL> <Suite> <Components>` 格式，Sileo/Zebra 均识别）；写入前先清上游遗留 `default.sources` 与自管 `*.list`，幂等防重复；锁定对象=各 `<key>.list`（与层2 重放口径一致，清单变更只动 `PresetSources.plist`）。清单与机制解耦：PresetSources.plist 单点维护。~~C 实测增证：Procursus bootstrap tar 无自带源、sileo/zebra deb 无 postinst 写源~~（18:52 B 补充：deb 侧确无写源，但 **Sileo.app 主程序首启自播种 procursus.sources**，见 §3——"预置即完备"结论修正为"预置+Sileo 播种行为适配后才完备"）。

## 4. 影响面与分工

| 位置 | 改动 | 负责 |
|---|---|---|
| `Application/Resources/PresetSources.plist` | 新增（清单单点） | C |
| `EUBootstrapper` bootstrap 安装流程 | 解包后写 .list；挂载后 chflags 重放 | C（写入）/ B（提供重放时机与 bootstrapfs 侧验证） |
| Sileo / Zebra 代码 | **零改动**（不改上游，规避重命名风险面） | — |
| bootstrapfs 引擎 | 不改逻辑；文档记录 fflags 不保证保留的前提 | B |

## 5. 风险与边界

- SSH root 可 `chflags nouchg` 解锁 —— 属预期（防呆不防盗），P2 自愈层可覆盖。
- 删除失败在 Sileo/Zebra UI 上无中文提示（显示系统错误）—— 视为"受保护"信号，可接受。
- 若上游 Procursus bootstrap 自带 sources.list.d 条目：C 需先清再写，避免重复源。
- **覆盖边界（R14×R15 接缝，B 18:38 核）**：本锁的作用对象是 `sources.list.d/*.list` 文件。Sileo/Zebra 的源管理均走该路径 ✅。Installer 5 按 TheAppleWiki 属 APT 系包管理器，但其 beta 公告（r/jailbreak BETA 5）提及"sources 数据库"与导入机制，疑存在自有源存储层——chflags 是否覆盖**未证实**。待 Installer 实机就绪后验证：添加源后检查 sources.list.d 是否新增 .list（有→锁自动覆盖；无→需为 Installer 出适配或注明固定源锁仅覆盖 Sileo/Zebra）。
