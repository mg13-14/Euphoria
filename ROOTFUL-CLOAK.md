# Euphoria Rootful 引擎与 Cloak 隐形挂载模块（BaseBin 增补）

本文档说明 Euphoria 在上游 Dopamine 3.x（rootless 架构）基础上新增的两个核心模块。

**模式与开关（用户指令，2026-08-26 17:27 更新）**：
设置中新增 **rootful 用户开关**（jbinfo 键 `rootfulUserEnabled`，App 设置页 UI 控制）：
- **关（默认）→ roothide 模式**：rootless 越狱 + cloak/aegis 隐藏（自研 roothide 等价栈）；
- **开 → rootful + roothide 模式**：rootful 引擎（fakefs 主路径 / 内存重挂载+nullfs 降级）
  叠加完整隐藏栈；仅 **A12/A13 @ iOS 16.6.1–18.7.1** 可开（矩阵外 App 灰置开关，
  CLI 强开时明确提示并回落 roothide 模式）。
- 两种模式走**不同的越狱流程分支**（`activate_rootful_and_cloak()`）；
- 隐藏栈（cloak/aegis）在两种模式下均默认启用，仅标记文件可退订。

---

## 一、Rootful 引擎（`libjailbreak/src/rootful.c|h`）

### 目标（双路径架构，2026-08-26 汇总员00:29:49指令更新）
在 SSV（签名系统卷）约束下交付 rootful，主路径为 fakefs，降级路径为内存重挂载+nullfs覆盖：

**主路径：fakefs（非sealed新卷+复制+remount）**
1. 在数据分区创建一个**不带 APFS_INCOMPAT_SEALED_VOLUME 标志**的新 APFS 卷；
2. 将 sealed 根卷的内容复制到新卷（读取 sealed 数据通过 hash 校验，写入非 sealed 新卷无校验约束）；
3. 切换根挂载到新卷（内核 mount 结构数据段操作，复用本引擎的 KRW + mount 校验基础设施）。
此路径是纯内核**数据段操作**，不需 kernel text patch，不动 PPL 保护页表——A12/A13 无 PPL 是利好。
三阶段子函数为骨架（`rootful_fakefs_create_volume`/`_copy_contents`/`_switch_root_mount`），
APFS 具体机制待移植 ghh-jb 的 APFSRW/Makerw/bootstrapfs 三组件（C 的源码深析输入）。

**降级路径：内存重挂载 + nullfs 覆盖**（fakefs 不可用时的兜底）
1. 遍历内核 mount TAILQ（`kernelSymbol.mount_list`），逐项内容校验，仅对确证为 `/` 的 mount 清除 `MNT_RDONLY`/`MNTK_*` 标志；
2. 对 `/`、`/usr`、`/etc`、`/var`、`/tmp`、`/private/var` 建立 nullfs（XNU 自带）覆盖，失败时回退 bindfs。staging 目录位于 jbroot 内。

### 安全设计（重要）
- 任一校验失败（mount 列表不可读、名字非法、偏移缺失）**拒绝写入任何内核内存**，自动降级为纯覆盖模式；
- 遍历上限 64 个条目，防止链表损坏导致死循环；
- 偏移缺失时 `koffsetof(mount,*) == 0` → `rootful_find_root_mount()` 直接返回 0 → 安全降级；
- 内存级标志清除**不落盘**，重启后系统卷密封状态原样恢复。

### 配置门控（用户指令 2026-08-26 17:27，矩阵收窄）
| 机型×版本 | 行为 |
|---|---|
| A12/A13 @ iOS 16.6.1–18.7.1 | rootful 开关可用（用户开→rootful+roothide；关→roothide） |
| 其余全部组合（非 A12/A13，iOS < 16.6.1 或 26.x） | 仅 roothide 模式（rootless + 隐藏栈） |

**交付形态**（关键诚实声明）：
| 路径 | 形态 |
|---|---|
| fakefs 主路径 | 非 sealed 新 APFS 卷 + 内容复制 + remount（纯内核数据段操作；参考 ghh-jb 三组件机制，自研实现，骨架已就位待 C 的源码分析输入） |
| 降级路径 | 内存重挂载尝试 + nullfs 全系统覆盖 + uid 0/KRW/内核补丁（能力推到物理上限，唯不直接改写密封卷） |

实现细节：`rootful_supported_configuration()` 按 Darwin 版本判定
（21.x 即 15.x 排除；22.0–22.5 即 16.0–16.5 排除；22.6 即 16.6/16.6.1/16.7.x 包含——
三者同报 22.6，16.6 与 16.6.1 仅差安全补丁；23.x 即 17.x 包含；24.x 即 18.x 全系含 18.7.1 包含；
25.x 即 iOS 26 排除）。越狱本身的支持范围与 Dopamine 上游一致（全量），不受此门控影响。

### 启用方式
```
# 区间内（A12/A13 @ 15.0–18.7.1）：默认开启，无需任何操作
# 退订：touch /var/jb/basebin/.rootful_disabled

# 区间外实验性开启：touch /var/jb/basebin/.rootful_enabled
#   （引擎仍受 supported_configuration 门控，不满足时报错并说明所需配置）

# 或手动
jbctl rootful enable
jbctl rootful status
jbctl rootful disable
```

### 已知边界（诚实声明，按带分层）
- **iOS 15.0–15.4.1**：公开生态有 A12+ 真 rootful 先例（Fugu15_Rootful、Dopamine_Rootful），
  走 fakefs（非sealed新卷+复制+remount）纯软件路径，可移植参考。
- **iOS 15.5–18.7.1**：fakefs 通用路径物理逻辑成立（A 的分析：SSV 是内核读路径 hash 校验
  非硬件密封，非sealed新卷绕过读路径校验是纯数据段操作），但 16+ APFS/mount 路径是否有
  新增校验需逆向验证（C 标注的开放风险，纳入 B 的逆向验证清单）。15.5 至今无公开等效
  漏洞披露，工程实现待移植 ghh-jb 三组件（C 深析中）。
- **A12/A13 无 BootROM 漏洞**：palera1n rootful 仅限 A11 及以下 checkm8 设备；用户死要求
  禁用硬件漏洞，本引擎全程软件途径（KRW + 内核数据段操作），合规。
- `kernelStruct.mount` 偏移与 `kernelSymbol.mount_list` 需按目标内核版本分析后填入 XPF 偏移表；
  未填充时引擎自动运行于纯覆盖模式（功能可用，根分区内存重挂载不生效）。
- 对密封卷的写入即使重挂载成功也可能触发 vnode 层故障，因此覆盖挂载是主要交付路径。

---

## 二、Cloak 隐形挂载模块（ROOT 权限隐藏）

### 组成
| 组件 | 位置 | 职责 |
|---|---|---|
| `cloakd` 守护进程 | `BaseBin/cloakd/` | 挂载生命周期管理；常驻（GCD 每 5s 同步策略）；SIGTERM 优雅卸载 |
| Cloak XPC 域 | `JBS_DOMAIN_CLOAK`（jbdomain_cloak.c） | 策略权威存储（launchdhook 内） |
| 客户端 API | `libjailbreak/src/cloak.c|h` | cloak_get_policy / enable / disable / set_options / report_mount |
| systemhook 拦截器 | `systemhook/src/cloak_interpose.c|h` | 每进程注入的过滤层 |

### 隐匿能力（对不可信进程）
- `getfsstat/getfsstat64`：从结果中剔除越狱相关挂载点；
- `statfs/statfs64`：对隐藏挂载点返回 `ENOENT`；
- `sysctl(KERN_PROC*)`：将被提升为 uid 0 的进程凭据改写回原始 mobile 身份。

**可信进程判定**：euid 0，或可执行文件位于 `/usr`、`/bin`、`/sbin`、`/System`、`/usr/libexec`。
其余进程（App Store 应用、第三方守护进程）获得过滤视图。

### 权限模型
- `GET_POLICY`：全系统可达（systemhook 每进程需要）；
- `ENABLE/DISABLE/SET_OPTIONS/MOUNT_REPORT`：仅平台二进制（Euphoria App、jbctl、cloakd），
  通过 `csops_audittoken` + `CS_PLATFORM_BINARY` 校验。

### 常驻挂载（"越狱后状态"标记）
cloakd 的覆盖挂载（cover mount）为只读 nullfs，挂载点外观无越狱特征；
内核在 unmount/重启前保持该挂载，即使用户态崩溃也不丢失——满足"以挂载形式常驻"的需求。

### 启用方式
```
# 区间内默认开启；退订：touch /var/jb/basebin/.cloak_disabled
# 区间外（roothide 链接管隐藏前的过渡）：touch /var/jb/basebin/.cloak_enabled
jbctl cloak status                     # 查看策略与挂载状态
jbctl cloak enable
jbctl cloak set hideMounts=1 hideCredentials=1 hideTrustcache=1 stealthLevel=2
jbctl cloak disable
```

---

## 三、设置持久化

Cloak 策略全部纳入 `JAILBREAK_SETTINGS_ITERATE` 序列化（jbinfo 机制），重启后保持。
新增键：`cloakEnabled`、`cloakHideMounts`、`cloakHideCredentials`、`cloakHideTrustcache`、`cloakStealthLevel`。

## 四、构建集成

- `BaseBin/Makefile`：`cloakd` 已加入 `subprojects`，产物拷贝至 `.build/`，随 basebin.tar 打包；
- LaunchDaemon：`_external/basebin/LaunchDaemons/dev.euphoria.Euphoria.cloakd.plist`
  （随 bootstrap 加载，KeepAlive 保活；是否实际挂载由策略决定）；
- `systemhook/Makefile`：编入 `libjailbreak/src/cloak.c`；
- 头文件经 `.include/libjailbreak/` 暂存机制自动可用。

## 五、致谢

- **mg13-14**（用户指定，2026-08-26）
- 上游 Dopamine（opa334dev，MIT 协议）——本项目自研路线中仅漏洞利用与安全绕过模块参考其公开实现

## 六、与上游的关系

- Mach 魔数：`JBSERVER_MACH_MAGIC` 已从 `0x444F50414D494E45`(DOPAMINE) 改为
  `0x455550484F524941`(EUPHORIA)，客户端/服务端共用同一宏定义，天然一致；
- 本模块不触碰 `Application/Euphoria/Exploits/`（漏洞闸门保持上游全量范围）。
