# B24 · 巨魔E"不越狱可用"攻坚①：XNU 信任缓存源码级分析 + EU 源安装器分发架构

- 触发：用户 08:42:30"接着搞，记得巨魔不越狱可用，我们的源里安装的是它的安装器。"
- 证据：**XNU 源码 xnu-12377.121.6**（apple-oss-distributions 最新 tag，对应 26.x 世代内核，全量下载逐行核读 bsd/kern/kern_trustcache.c + osfmk/arm/pmap/pmap.c + osfmk/vm/pmap_cs.h）
- 作者：并行搜索员B · 2026-08-27 08:50 ｜ 与 C 的"不越狱可用地基"专项互补（C=生态面，本文=内核机制面+分发架构）

## 1. 用户口径的精确解读（两条硬需求）

1. **不越狱可用 = 硬性要求**（非研究线）：装好后重启未越狱期间巨魔E/其装的 app 仍可运行——这是 TrollStore 语义的核心。
2. **分发形态**：EU 源上分发的是**巨魔E 的安装器**（安装器 deb → 装出巨魔E 本体；本体独立常驻，不依赖 EU App 存在）。

## 2. XNU 源码级结论：启动期持久信任缓存为什么"正常做不了"

iOS 15+ 确有**启动期从 cryptex 卷加载可加载信任缓存**机制（`kTCTypeCryptex1BootOS/BootApp`，每次开机由持有 `com.apple.private.pmap.load-trust-cache` 私有 entitlement 的内核管理 daemon 从 preboot cryptex 读入）——这是"重启后仍生效"的唯一官方通道。但三道锁（kern_trustcache.c:893-1010 逐行实证）：

| 锁 | 源码事实 | 对我们的含义 |
|---|---|---|
| ①img4 签名链 | 加载需 payload+**manifest**（Apple 签名的 img4 对象），最终在 **TXM/PPL（SPTM）内校验** | 伪造 TC 文件在加载时被拒；改内核内存无效（校验在 PPL 侧且重启即失） |
| ②单例限制 | `boot_os_tc_loaded`/`boot_app_tc_loaded` 各只允许一次 | 不能"追加"第二个 BootOS TC 夹带私货 |
| ③REM 封锁 | `restricted_execution_mode_state()==KERN_SUCCESS` 时直接拒绝 | 用户开了 REM 则连合法加载都封死 |

**结论（诚实边界）**：信任缓存路线的"重启持久"需要 Apple 签名——不可伪造。**"不越狱可用"无法靠 TC 路线达成**，除非在下列精确攻击面上找到新缺陷（Tier B 的收窄目标，替代 B19-1 的泛泛方向）：

1. **km daemon 文件处理面**：启动期读 cryptex TC 文件的用户态内核管理 daemon（entitlement 持有者）——TOCTOU/路径混淆/符号链接攻击可能在"读文件→传内核"间隙换包（历史上有类似 daemon 漏洞先例）；
2. **TXM img4 校验逻辑**：SPTM 内的 manifest 验证缺陷（momentarius 已有 PPL 读写面，逆向 TXM 校验代码的可及性高——树内现成能力，最值得先打）；
3. **非 TC 的签名锚**：AMFI 每次启动校验链上是否存在不进 TC 的信任路径（amfid/der entitlements 解析面）。

## 3. 巨魔E 安装器分发架构（对应用户"我们的源里安装的是它的安装器"）

```
EU 源（R14 第六源）
└─ 巨魔E 安装器 deb（com.euphoria.trolle-installer）
   └─ postinst 装出 安装器.app（/var/jb/Applications）
      └─ 用户运行安装器（此时需越狱态=一次性）
         ├─ A. 装巨魔E 本体：ldid 假签 → jb_trustcache_add_cdhashes → /var/jb/Applications + uicache
         ├─ B.（Tier B 落地后）注册持久信任锚 → 本体脱狱独立常驻
         └─ C. 写 CDHash 重放表 → 每次越狱幂等重注入（B23 既有设计）
```

- **V0.9.0 测试版现实口径**：A+C 已可交付（越狱态巨魔E 完整可用）；B 落地前，重启未越狱期间本体暂不可启动——UI"关于"页如实标注（不越狱可用=正式版目标，Tier B 攻坚中）。
- **安装器 deb 的工程要点**：deb 控制域 Depends: euphoria-basebin-link（保证 jbclient XPC 通道在）；postinst 仅放文件，真正安装动作用户点开安装器才跑（避免无 KRW 时失败）。
- 与 R17/R15 零冲突：EU PM 与三 PM 都能装这个 deb；巨魔E 本体再从 PM 内安装 IPA（B23 §3 设计不变）。

## 4. 派工建议（供规划师）

- **B（我）**：TXM 校验代码逆向定位（树内 XNU 已有，可先做静态面分析：txm_load_trust_cache 全链路）+ km daemon 调研。
- **A**：26.x amfid/der 解析面漏洞面调研（与其既有 exploit 尽调线合并）。
- **C**：安装器 deb 骨架 + 巨魔E 本体 UI（复用 B23 §3）。

## 5. 出处

- github.com/apple-oss-distributions/xnu @ xnu-12377.121.6：`bsd/kern/kern_trustcache.c`（:893 load_trust_cache_with_type 全文：img4 manifest 必需/entitlement 门/单例/REM 封锁）、`osfmk/arm/pmap/pmap.c`（:13209 pmap_load_trust_cache_with_type → PPL）、`osfmk/vm/pmap_cs.h`（TC runtime 结构）
- B23（越狱态信任缓存路线）、B19-1（TrollStore 机制/CT 覆盖矩阵）——本文为其 Tier B 收窄与分发架构补全
