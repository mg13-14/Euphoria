# Euphoria Aegis — 应用屏蔽专用隐藏组件

本组件是 Euphoria 完全自研路线下新增的**专用应用屏蔽**子系统，
按用户 2026-08-26 00:21 硬指标要求开发：越狱过程中以挂载形式部署、
越狱完成即具备；2026-08-26 17:27 更新：隐藏栈（cloak/aegis）在 roothide 与
rootful+roothide 两种模式下均默认启用（全机型全版本，软件途径，禁用硬件漏洞），
rootful 开关仅 A12/A13 @ iOS 16.6.1–18.7.1 可用。

---

## 一、与 cloak 的分工

| 维度 | cloak | aegis |
|---|---|---|
| 隐藏对象 | 越狱**本身**（挂载/凭据/trustcache，系统级） | 指定**应用**的越狱检测能力（API 级） |
| 作用域 | 全局（所有进程） | 按 App（shield 列表中的进程及其子进程） |
| 拦截面 | getfsstat/statfs/sysctl KERN_PROC | stat/lstat/access/open/faccessat/posix_spawn/getfsent |
| 策略粒度 | 开关 + stealthLevel | 按 bundleId 的 per-app level |
| 持久化 | jbinfo（固定字段） | jbinfo（开关）+ `aegis.conf`（per-app 列表） |

cloak 解决"系统层面看不到越狱"，aegis 解决"特定 App（银行/游戏/DRM）
即使主动探测也测不到"——两者互补，可叠加启用。

## 二、架构（与 cloakd 同构，完全自研）

```
libjailbreak/src/aegis.c|h           XPC 客户端 API + 路径分类器
launchdhook/src/jbserver/
  jbdomain_aegis.c                   JBS_DOMAIN_AEGIS=7 XPC 域（运行态权威）
BaseBin/aegisd/src/main.c            守护进程：挂载生命周期 + 策略文件 + XPC 同步
BaseBin/_external/basebin/LaunchDaemons/
  dev.euphoria.Euphoria.aegisd.plist 随 bootstrap 加载、KeepAlive 保活
systemhook/src/aegis_interpose.c|h   进程级 API 拦截（shielded App 进程内）
```

## 三、Shield Level（递进激进）

| Level | 含义 |
|---|---|
| `AEGIS_LEVEL_OFF=0` | 不屏蔽该 App |
| `AEGIS_LEVEL_LITE=1` | 文件存在性屏蔽（stat/lstat/access/open/faccessat 返回 ENOENT）+ spawn 环境清洗（剥离 DYLD_INSERT_LIBRARIES 等） |
| `AEGIS_LEVEL_FULL=2` | LITE + 完整路径分类（/var/jb、/basebin、TweakLoader、Substrate、Cydia/Sileo/Zebra 遗留路径） |
| `AEGIS_LEVEL_PARANOID=3` | FULL + 挂载枚举屏蔽（getfsent 隐藏越狱挂载条目） |

凭据清洗（sysctl KERN_PROC）**不在此组件**——cloak 已在系统级全局做，
避免与 cloak 的 sysctl hook 冲突。

## 四、策略文件（人机可编辑）

路径：`/var/jb/basebin/aegis.conf`
格式：每行一条，`bundleId=level` 或裸 `bundleId`（默认 FULL）
aegisd 启动时解析此文件并通过 `aegis_add_app()` XPC 推入 launchdhook 运行态；
运行时通过 jbctl 修改后，aegisd 同步回写此文件。

## 五、XPC 域（JBS_DOMAIN_AEGIS=7）

| Action | 权限 | 用途 |
|---|---|---|
| GET_POLICY | 全局可读 | systemhook 在每个进程启动时查询 |
| ENABLE / DISABLE | 平台二进制 | 开关 |
| SET_DEFAULT_LEVEL | 平台二进制 | 设默认 shield level |
| ADD_APP / REMOVE_APP / CLEAR_APPS | 平台二进制 | per-app 列表 CRUD |
| MOUNT_REPORT | 平台二进制 | aegisd → launchdhook 上报挂载状态 |

权限模型与 cloak 域一致：GET_POLICY 全局可达（systemhook 需要），
变更操作通过 `csops_audittoken` + `CS_PLATFORM_BINARY` 校验调用方。

## 六、jbctl 子命令

```
jbctl aegis status                              # 查看策略+挂载+应用列表
jbctl aegis enable / disable
jbctl aegis set-level <0|1|2|3>                 # 默认 shield level
jbctl aegis add <bundleId> [level]              # 添加 App（默认 FULL）
jbctl aegis remove <bundleId>
jbctl aegis clear
jbctl aegis list
```

## 七、构建集成

- `BaseBin/Makefile`：`aegisd` 已加入 `subprojects`，产物拷贝至 `.build/`，随 basebin.tar 打包；
- LaunchDaemon：`dev.euphoria.Euphoria.aegisd.plist`（随 bootstrap 加载，无 Disabled 默认启动）；
- `systemhook/Makefile`：编入 `libjailbreak/src/aegis.c`；
- 头文件经 `.include/libjailbreak/` 暂存机制自动可用。

## 八、默认行为（两种模式均启用）

aegis 随 bootstrap 启动（守护进程+挂载常驻，全机型全版本），
`aegisEnabled` 默认 true、`aegisDefaultLevel` 默认 FULL；per-app 列表默认空
（用户通过 jbctl aegis add 按需添加）。退订标记 `.aegis_disabled`。

## 九、致谢

- **mg13-14**（用户指定，2026-08-26）

## 十、完全自研声明

本组件从零自研，未使用 roothide Bootstrap 或任何第三方隐藏项目代码。
路径分类器（`aegis_path_is_jailbreak_artefact`）覆盖 rootless/rootful 两代
越狱的常见指纹路径，可按需扩展。
