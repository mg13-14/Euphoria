# cloakd 隐形挂载设计规范

> 版本：v1.1 ｜ 作者：报告汇总员 ｜ 实现负责人：并行搜索员B（BaseBin 侧）
> v1.1 变更：实现基座由 Polaris 树切换为 **shared/Euphoria 树（EU 契约）**；类名/路径同步为 EU 前缀实测值
> 需求来源（用户原话）："再开发一个隐藏软件，用于隐藏 ROOT 权限，这个你们要加在越狱过程里，当一个挂载，挂在越狱后的状态下。"

---

## 一、需求解读与设计目标

| 用户要求 | 设计响应 |
|---|---|
| "隐藏软件" | 独立组件 cloakd（守护进程 + 挂载视图），非散落补丁 |
| "加在越狱过程里" | `EUBootstrapper` 越狱流程新增 `installCloak` 阶段，随 bootstrap 一起部署 |
| "当一个挂载" | 以挂载形式存在：`/var/jb/.cloak` 隐形视图卷（复用 fakelib 同款挂载机制） |
| "挂在越狱后的状态下" | 越狱成功后 cloakd 常驻（launchd daemon），隐藏态可一键切换 |

**功能定义**：开启"隐形模式"后，越狱/root 状态对受保护 App 的检测不可见（银行类、风控类 App 的越狱检测场景），同时**越狱本身保持可用**（区别于现有 hide-jailbreak 的全系统关闭方案）。

**边界声明（写进用户文档）**：cloakd 仅做状态隐藏，用于 App 兼容场景；不提供、不承诺对系统安全机制本身的规避。

## 二、现有地基（已逐行核实，勿重复造轮子；类名以 Euphoria 树 EU 前缀为准）

| 现有机制 | 位置（Euphoria 树） | cloakd 复用方式 |
|---|---|---|
| hide-jailbreak 全系统隐藏 | `EUEnvironmentManager setJailbreakHidden`（删 /var/jb 符号链接 + 关 systemwide domain + 卸 fakelib） | 作为"深度隐藏"档位保留；cloakd 常规档位不删符号链接 |
| fakelib 挂载 | `setFakilibMounted` → `jbctl internal fakelib mount/unmount` | cloak 视图卷用同一挂载通道实现 |
| per-process 注入框架 | `BaseBin/systemhook`（main.c：dyld_dlsym_hook、necp_open_hook、DYLD_INSERT_LIBRARIES 处理） | 检测过滤 hook 挂在 systemhook 内，按保护名单启用 |
| jailbreakd XPC | `libjailbreak` jbclient（如 `jbclient_platform_set_systemwide_domain_enabled`） | cloakd 与 jailbreakd 走同通道，避免第二条特权通路 |
| 私有卷保护 | `setPrivatePrebootProtected` → `jbctl internal protection activate/deactivate` | 隐藏态联动开启 |

## 三、总体架构（三层）

```
┌─────────────────────────────────────────────────────┐
│  越狱流程（EUBootstrapper）                            │
│  bootstrap → installCloak（新增阶段）→ 挂载 cloak 视图   │
│                        ↓                             │
│  ┌────────────── 越狱成功后常驻 ──────────────────┐    │
│  │ L1 系统层：cloakd 守护进程（launchd daemon）      │    │
│  │    · 持有挂载视图 /var/jb/.cloak               │    │
│  │    · 状态机：visible ⇄ cloaked                 │    │
│  │    · jbctl 子命令：cloak hide/unhide/status    │    │
│  ├──────────────────────────────────────────────┤    │
│  │ L2 进程层：systemhook 扩展（按保护名单生效）        │    │
│  │    · 文件路径检测过滤（/var/jb、/private/preboot）│    │
│  │    · dyld 环境与注入痕迹过滤                     │    │
│  ├──────────────────────────────────────────────┤    │
│  │ L3 数据层：痕迹清理                              │    │
│  │    · 已注册越狱 App 的图标/缓存标记遮蔽           │    │
│  │    · sandbox 容器路径视图净化                    │    │
│  └──────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### L1 cloakd 守护进程（新增 `BaseBin/cloakd/`）
- 形态：模仿 `BaseBin/idownloadd` 的结构（Makefile + xcodeproj + LaunchDaemons plist）
- 服务标签：`dev.euphoria.Euphoria.cloakd`（与 App bundle ID 命名契约同步，见 02 号文档）
- 职责：
  1. 维护 `/var/jb/.cloak` 挂载视图（挂/卸由 jbctl 以 root 执行，cloakd 只读状态）
  2. 状态机切换 `visible ⇄ cloaked`，与 fakelib / preboot protection 联动
  3. 对 systemhook 提供"保护名单 + 模式"的查询接口（走 jailbreakd XPC，不新开端口的特权面）

### L2 systemhook 进程级过滤（扩展 `BaseBin/systemhook/src/`）
在现有 hook 框架内新增 `cloak.c`，进程初始化时查询本进程是否命中保护名单，命中则启用以下过滤：

| 检测向量 | 过滤手段 |
|---|---|
| `/var/jb`、`/var/jb/*` 路径存在性（stat/access/open/fopen） | hook 对应 syscall/libc 入口，对名单进程返回 ENOENT |
| `/private/preboot/*` 特征路径 | 同上（仅过滤越狱相关子路径，防误伤系统自身） |
| `DYLD_INSERT_LIBRARIES` 等 dyld 环境变量 | env 净化（systemhook 现有逻辑已有判断点 main.c:376） |
| 注入 dylib 在进程镜像列表中的可见性（dyld_image/task_info 枚举） | 镜像名过滤 |
| 越狱 App 图标缓存 / 注册标记（unregisterJailbreakApps 遗留） | L3 联动清理 |
| `cydia://` 等 URL scheme 注册检测 | scheme 注册遮蔽（沙盒内） |

### L3 数据层
- 隐藏态开启时：执行 `unregisterJailbreakApps` 等价逻辑的"遮蔽版"（不卸载，仅从 Spotlight/图标缓存隐藏）
- 深度隐藏档位 = 现有 `setJailbreakHidden` 全套（删符号链接 + 关 domain + 卸 fakelib）

## 四、配置面

- 配置文件：`/var/jb/.cloak/config.plist`
  - `ProtectedApps`：bundle ID 数组（保护名单）
  - `Mode`：`standard`（默认，三层全开）/ `deep`（= 现有 hide-jailbreak 全关）
  - `Enabled`：总开关
- UI 接入：设置页新增"隐形模式"cell（`EUSettingsController`）+ 偏好持久化（`EUPreferenceManager`）——UI 侧由 C 对接
- 命令行接入：`jbctl cloak hide|unhide|status`（管理员调试通道）

## 五、与越狱流程的集成（满足"加在越狱过程里"）

`EUBootstrapper` 现有阶段：bootstrap 解包 → basebin 安装 → 包管理器安装 → 收尾。
新增阶段（顺序在包管理器之后）：

1. 解包 `cloak.tar` → `/var/jb/.cloak/`
2. 安装 cloakd LaunchDaemon 并 `launchctl load`
3. 挂载 cloak 视图卷（`jbctl internal cloak mount`）
4. 写入默认配置（`Enabled=false`，用户后续在设置页开启）

**卸载/升级路径**：`uninstall` 流程同步清理 cloakd 服务与 `/var/jb/.cloak`；升级时保留 `config.plist`。

## 六、里程碑

| 里程碑 | 内容 | 验收 |
|---|---|---|
| M1 | 本规范 v1.1 评审（基座已切换 Euphoria/EU） | B/C/规划师无异议 |
| M2 | cloakd 骨架 + jbctl cloak 子命令 | 编译通过，status 返回正确状态 |
| M3 | systemhook cloak.c 过滤器（6 类检测向量） | 单向量逐一单测 |
| M4 | 挂载视图 + 状态机联动（fakelib/protection） | visible⇄cloaked 切换 100 次无泄漏 |
| M5 | 设置页 UI + 越狱流程集成 | 全流程回归 |
| M6 | 总验收（对照 01 号文档验收标准第 7 条） | 保护名单 App 内全部检测向量不可见 |

## 七、风险与对策

| 风险 | 对策 |
|---|---|
| systemhook 过滤面过宽导致系统 App 异常 | 保护名单默认为空，仅用户显式添加的 App 生效；过滤器加白名单兜底 |
| 与 tweak 注入冲突（保护进程内 ElleKit 仍注入） | cloaked 进程默认跳过 tweak 注入（等价于该进程的 per-app 禁用注入，机制已存在） |
| cloakd 自身被检测（进程名/端口扫描） | daemon 以普通系统服务形态运行，无独立监听端口（XPC 走 jailbreakd 通道） |
| 状态切换失败留下半隐藏态 | 状态机所有转移幂等且可重入；`jbctl cloak status` 暴露真实状态供 App 侧核对 |
| B 在旧 PL 前缀基座上的工作混入 | cloakd 一律 EU 前缀；最终审计 V3 项（grep PL 前缀=0）兜底 |

## 八、给 B 的开工指引（v1.1 新增）

1. **基座**：直接在 `shared/Euphoria/` 树上开发（该树已含 A 的闸门叠加，是当前唯一权威树）；你此前的 Polaris/PL BaseBin 工作全部作废，勿迁移任何 PL 命名
2. 参考样板：`BaseBin/idownloadd/`（守护进程结构）+ `BaseBin/euphoria/src/`（jbctl 子命令注册方式）
3. 完成后跑 02 号文档 §四验证清单（重点 V1/V3/V5/V6）+ 本文档 M2-M4 里程碑验收
4. 注意 Euphoria 树的 XPC 域是 `JBS_DOMAIN_EUPHORIA`，新代码勿写回 DOPAMINE
