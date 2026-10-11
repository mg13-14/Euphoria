# 06 · rootful 开关与进度 · 视觉交付包（v4 T15 / SSOT R11 配套）

> 并行搜索员B · 2026-08-26 · 状态：**交付**（后端已并入主线树，本文为 App 前端消费契约）
> 配套实现：`BaseBin/bootstrapfs/`（引擎）、`libjailbreak/src/rootful_fakefs.{h,c}`（编排）、
> `jbctl internal rootful`（维护命令）、`BaseBin/euphoria/src/main.m`（[STAGE] 转发）
> 样式令牌与动画三阶段/辉光区分**直接对照 05-UI设计规范.md v1.1 §4 执行**（汇总员 17:45 口径）；编号口径以 01 号 SSOT 为准（本文 T15=v4 拆解号）

---

## 一、事件协议（前端唯一需要解析的东西）

越狱/开关流程中，`euphoria` 进程 stdout 会输出形如下面的行（一行一个 JSON，**前缀 `[STAGE] `**）：

```
[STAGE] {"v":1,"ev":"probe","key":"container","value":"disk0s1"}
[STAGE] {"v":1,"ev":"stage","stage":"precheck","dir":"","index":0,"total":6}
[STAGE] {"v":1,"ev":"stage","stage":"create","dir":"/usr","index":2,"total":6}
[STAGE] {"v":1,"ev":"copy","dir":"/usr","bytes":486539264,"bytesTotal":3982938112,"files":12873,"pct":12.2,"pctGlobal":4.1}
[STAGE] {"v":1,"ev":"stage","stage":"mount","dir":"/private/etc","index":1,"total":6}
[STAGE] {"v":1,"ev":"done","mode":"enable","elapsed":213.7}
[STAGE] {"v":1,"ev":"error","stage":"copy","dir":"/usr","path":"/usr/lib/x","errno":28,"msg":"...","fatal":true}
[STAGE] {"v":1,"ev":"rollback","reason":"...","unmounted":0,"destroyed":6}
```

字段规范：
- `ev`：`probe | stage | copy | done | error | rollback`
- `stage`（ev=stage 时）：`precheck | probe | create | copy | verify | mount | unmount | commit | rollback | done`
- `mode`（ev=done 时）：`enable（首次激活） | recover（恢复，秒级） | disable | purge | rollback`
- `pct`：当前目录进度 0–100；`pctGlobal`：六目录总进度 0–100（**进度条主数据源**）
- `index/total`：目录序数，恒为 x/6
- 未知 `ev`/`stage` 直接忽略（向前兼容）

`jbctl internal rootful <sub>` 的 JSON 输出去掉 `[STAGE] ` 前缀，其余一致（App 编程式调用时可复用同一解析器）。

## 二、双流程分叉（T14 核心逻辑，App 侧）

| 场景 | 触发 | 引擎动作 | UI 呈现 |
|---|---|---|---|
| 首次开启开关后越狱 | toggle 开 && 无已建卷 | `enable`：建卷+全量复制（分钟级） | **激活进度页**（§三） |
| 开关已开后的历次越狱 | toggle 开 && 卷已存在 | `recover`：纯 remount（秒级） | 「恢复 rootful 环境」短进度，文案区分 |
| 越狱中关闭开关 | toggle 关 | `disable`：仅卸载覆盖挂载，**卷与数据保留** | 提示「已回到 rootless，数据保留，可随时再开」 |
| 彻底删除 | 用户显式操作 | `purge --confirm`：卸载+销毁卷+清状态 | **独立入口**，二次确认（红色警示，防误删范式同 protection） |

- 判定来源：`[STAGE] {"ev":"done","mode":...}` 与 `jbctl internal rootful status`（`state: committed=1` 等）；App 不需要自读 plist。
- 开关默认态：矩阵内机型（A12/A13 @ 16.6.1–18.7.1）**默认开**（R4 要求）；矩阵外**灰置**，副标题注明原因（"当前设备/系统不在 rootful 支持范围"）——与 App 既有 `rootfulSupported` 门控口径一致。

## 三、激活进度页规格（首次 enable 专用）

```
┌──────────────────────────────────┐
│      [标题] 正在激活 rootful      │
│   [副标题] 迁移系统目录，请勿锁屏  │
│                                  │
│   ████████████░░░░░░  47.3%      │  ← pctGlobal，主进度条
│   正在迁移 /usr（2/6）            │  ← dir + index/total
│   已迁移 1.9 GB / 4.0 GB          │  ← bytes 汇总（App 自行累计）
│                                  │
│   [提示] 首次激活约需 2–6 分钟     │
└──────────────────────────────────┘
```

- 阶段→文案映射（stage 事件驱动子状态）：
  - `precheck` →「检查存储空间」；空间不足（error.errno=28）→ 直接失败页（§四）
  - `probe` →「检测系统卷布局」
  - `create` →「创建可写卷（i/6）」
  - `copy` →「迁移 <dir>（i/6）」+ 双行进度
  - `mount`/`commit` →「挂载可写层（i/6）」
- 熄屏窗口对齐（流程无关，C 17:51 口径修正）：熄屏是 A12/A13@16.6+ exploit 阶段自身特性，**两条流程（rootful/roothide 默认）都会熄屏**，脉动节奏统一锚定 exploit 注入起止边界事件（`[STAGE]` exploit begin/end，ADR-013），不得只在 rootful 分支做；辉光层次追加（05 v1.1 §4.4"能量注入"层）保持**唯一**流程区分。`copy` 阶段预计 >30s，App 应在进入 copy 前 `idleTimerDisabled=YES`；脉冲动画周期 0.8–1.8s（与 ADR-013 应用内主动画节奏一致）。
- 微文案（防误判，C 建议）：A12/A13@16.6+ 双流程进度页固定展示"屏幕短暂熄灭属正常现象"（官方指南先例），默认流用户同样可见。
- `recover` 流程复用同页但隐藏字节行，仅显示 6/6 挂载计数，预期 <10s。

## 四、失败与回滚呈现

- 任一 `error` 且 `fatal:true` → 切失败态：
  - 主文案「激活失败：{msg 中文摘要}」（errno→文案表：28=空间不足、13=权限、5=I/O）
  - `rollback` 事件到达后追加：「已自动回滚，系统未做任何更改，重启亦可完全还原」
  - 动作按钮：[重试] [取消]（重试=重跑 enable，引擎幂等：会清理半成品再重来）
- 部分提交失败（`rollback.unmounted>0 && destroyed==0`）：文案改为「已卸载本次挂载，已迁移数据保留，可直接重试」

## 五、资产清单（需 UI 出图，本文档定规格）

| 资产 | 规格 | 用途 |
|---|---|---|
| rootful 开关图标 | 48pt @3x，线风格同 05 规范 Settings 组 | 设置页开关行 |
| 进度页主插画 | 240×240pt @3x，静态+脉冲两态 | 进度页头部（脉冲 0.8–1.8s 循环） |
| 失败态插画 | 240×240pt @3x | 失败页 |
| purge 警示图标 | 32pt @3x，红色 #FF3B30 | 独立删除入口与二次确认 |
| 文案表 zh-Hans/en | Localizable.strings 键值见本文 §二–§四 | 全部用户可见字符串（键前缀 `rootful.`） |

## 六、cloakd 接口（风险 #10 收编，汇总员 17:47 派发）

引擎不设全局固定标记路径；卷身份唯一权威源 = 状态文件 `$JBROOT/basebin/.rootful_fs_state.plist`（`roles.<id>.volume/device` 键值即全部需隐藏的卷名/设备清单，含 `prefix` 字段）。cloakd 侧应收编：

1. IOKit `AppleAPFSVolume`/`IOMedia` 枚举过滤：FullName 命中状态文件卷名或前缀 `com.apple.storage.`（可配置）的条目不向查询方返回；
2. 挂载表（`getfsstat`）过滤：`f_mntfromname` 命中状态文件 device 的挂载项，对越狱检测类查询隐藏；
3. 状态文件本体纳入 cloakd 已有的 jbroot 保护清单（同 `.rootful_disabled` 等 marker 一致范式）。

卷内 dotfile `/.com.apple.storage.ready`（`EUFS_READY_MARKER`）仅作内容完整性提示，**不作为**身份判定依据，无需单独隐藏策略（随卷隐藏覆盖）。

## 七、验收对照（并入 v4 T13/T14 自验关卡）

1. 开关关：越狱走默认 rootless 流，全程无 [STAGE] 输出 ✅（euphoria 仅 rootfulWanted 分支才调引擎）
2. 开关开·首次：enable 全流程 + 进度页数据流 ✅（协议 §一）
3. 开关开·复越狱：recover 秒级 + 文案「恢复」✅
4. 中途关：disable 保数据 ✅；purge 独立入口+确认 ✅（jbctl 侧已强制 --confirm）
5. 矩阵外：开关灰置（App 门控既有）+ 引擎侧 rootful_supported_configuration 双保险 ✅
6. 空间预检：不足时**不建任何卷**即失败（precheck 在 create 之前）✅
7. 失败回滚：pre-commit 失败销毁全部新建卷；commit 失败逆序卸载 ✅（rollback 事件上报）
