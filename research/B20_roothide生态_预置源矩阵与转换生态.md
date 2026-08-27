# B20 · roothide 生态情报：roothide Dopamine 预置源矩阵 + rootless↔roothide 转换生态

- 触发：用户 18:49-18:50 三连指令（roothide 还要搞很多 / 去看 roothide 多巴胺 S 包管理器有几个源 / roothide 与 rootless 插件不互通、要用转换源转换）
- 作者：并行搜索员B · 2026-08-26 18:55 · 证据=roothide/Dopamine-roothide `1.x` 分支源码（GitHub codeload 全量下载，非截图非传闻）

## 1. roothide Dopamine 的 Sileo 到底预置几个源（Bootstrapper.swift:334-364 实锤）

`default.sources`（deb822，写入 `/etc/apt/sources.list.d/`）共 **6 节**：

| # | 源 | URI | 备注 |
|---|---|---|---|
| 1 | Chariz | `https://repo.chariz.com/` | 与原版一致 |
| 2 | **YouRepo** | `https://yourepo.com/` | **原版 Dopamine 没有** |
| 3 | Havoc | `https://havoc.app/` | 与原版一致 |
| 4 | BigBoss | `http://apt.thebigboss.org/repofiles/cydia/`（stable/main） | 与原版一致 |
| 5 | **roothide 官方插件源** | `https://roothide.github.io/` | 替代了原版的 ElleKit 位 |
| 6 | **roothide Procursus 镜像** | `https://roothide.github.io/procursus`（suite `iphoneos-arm64e/1800`） | 替代 `apt.procurs.us` |

即：**没有 ElleKit、没有 apt.procurs.us**——bootstrap 源换成 roothide 自家 github.io 镜像，腾出的位置给了 YouRepo 和 roothide 官方源。

**zh_CN 加菜（Bootstrapper.swift:427-442）**：设备 locale 为 `zh_CN` 时额外写 `sileo.sources`（iosjb.top 主源 + iosjb.top/procursus 镜像，代码注释明说"some cn users can not access github website"）→ **中文设备 Sileo 实际显示 8 个源**。

Zebra 单独写（xyz.willy.Zebra/sources.list）：getzbra.com + Chariz + YouRepo + Havoc + roothide + roothide/procursus（6 条，:366-375）。

未决项（需实机或 Sileo-roothide 二进制核实）：Sileo-roothide 是 Sileo 的 fork，stock Sileo 的首启播种（procursus.sources：apt.procurs.us+BigBoss）在 fork 里是否保留——若保留，Sileo 首启后还可能再多 apt.procurs.us 一条。

## 2. rootless↔roothide 转换生态（用户"最重要的"那条）

- **官方工具：roothide/RootHidePatcher**——"patch rootless packages to roothide"，把 rootless 包转成 roothide 兼容包（binary path/dylib 处理）。这是"专门解决不互通"的源头工具。
- **转换仓库生态**：社区用源生成器把主流 rootless 源整库镜像+转换后托管，例：基于 **Shuga/Silica** 二次开发的"现代化静态越狱源生成器"（2026-08 仍活跃更新），面向现代越狱生态（roothide/rootless 双态分发）。
- 工程含义（供 R20 拆解）：我们的 EU 源（R14 第六源）可以走同路线——**上游=rootless 源，服务端 Patcher 转换，客户端按当前 bootstrap 形态（rootless/roothide）自动取对应包**；roothide Bootstrap 官方源本身就是这个模式的样板。

## 3. 对 R14 清单的直接冲击（待用户/规划师裁定）

roothide 形态下"和多巴胺一样"出现两个参照系：原版 Dopamine（Chariz/Havoc/BigBoss/ElleKit+Sileo 播种 Procursus）vs **roothide Dopamine（Chariz/YouRepo/Havoc/BigBoss/roothide/roothide-procursus，zh_CN+iosjb.top）**。Euphoria 是 roothide 路线（R8/R16），用户点名看 roothide——预设清单大概率应切到 roothide 参照系（含 CN 镜像策略），EU 官方源再作 +1。

**与 A 18:52 七源口径的关系**：A 数的是 roothide **Bootstrap**（15-17 工具）sources.h：7 源（含 bootstrap 分发源单列）；本文数的是 **roothide Dopamine-roothide 1.x**（用户原话"roothide 多巴胺"）：default.sources 6 源 + zh_CN 镜像 2 源。两个代码库口径不同、均成立；EU 预置取哪个参照系由用户/规划师定，CN 镜像策略（iosjb.top 模式）建议直接借鉴。

**用户 18:53:23 新增**：EU 源还要出 **rootless→rootful** 插件转换（不止 roothide 方向）——转换管线设计需三态（rootless/rootful/roothide），比 RootHidePatcher 单向更宽，工程上=服务端重打包产物矩阵，供规划师 v6 收录。**用户 18:54:00 定名**：新版 TrollStore = **巨魔E**（要求见 18:40:45 前文 → B19-1）。

## 4. 出处

- github.com/roothide/Dopamine-roothide 分支 1.x：`Packages/Fugu15KernelExploit/Sources/Fugu15KernelExploit/Bootstrapper.swift`（:334-364 default.sources 六节；:366-390 Zebra；:427-442 zh_CN iosjb.top）
- github.com/roothide/RootHidePatcher（rootless→roothide 补丁工具）
- github.com/roothide/Bootstrap、roothide/Procursus-roothide（roothide 自举链 15.0-17.0，四大 PM 开箱支持）
- 中文"静态越狱源生成器"（基于 Shuga/Silica 定制，2026-08-18 活跃）
