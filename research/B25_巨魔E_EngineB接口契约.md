# B25 · 巨魔E Engine B 接口契约（免越狱安装引擎，给 C 的实现规格）

- 前置：B23（Tier A 已实现：EUTrollE 越狱态 trustcache 路线，代码已进树）、C23（免越狱地基：CT 语义+Persistence Helper 必要性）、B24（26.x Tier B 攻击面）
- 作者：并行搜索员B · 2026-08-27 08:57 ｜ 状态：**✅ Engine B 实现体已由 C 落码（08-27 12:15，按 C23/C24 语义）**——EUTrollE.m 引擎B全流程+错误码 12/13/14 已扩展；待 B 评审两个假设（见 §2 尾"实现注记"）

## 1. 门面路由（已实现，EUTrollE.m）

```
installApplicationAtURL:mode:error:
├─ mode=Auto → 越狱态 ? EngineA : EngineB
├─ mode=Jailbroken(1) → EngineA（现实现：unzip→ChOma CDHash→jb_trustcache_add_cdhashes→/var/jb/Applications→uicache→登记重放表）
└─ mode=JailbreakFree(2) → EngineB（✅ C 已实现：域校验→helper快路径→kfd+dmaFail会话→root→CT永久签名装本体+helper第二槽位→登记重放表→零残留收尾）
```

## 2. Engine B 实现契约（C 按 C23 语义填实现体）

1. **输入**：与 Engine A 同签名（appURL + error）；会话型：首次运行走完整链（kfd+dmaFail 一次性漏洞会话拿 root/KRW→装巨魔E 本体+Persistence Helper 常驻），后续安装走 helper 快路径。
2. **必做**：
   - 装出的每个应用**登记进同一张重放表**（`[EUTrollE registryPath]`=/var/jb/var/db/euphoria/trolle.plist，条目 {bundleID, path, cdhash}）——保证用户后续越狱时 Engine A 幂等重放信任缓存，两引擎来源的应用互不冲突、都进"越狱态加固"。
   - Persistence Helper 负责 respring/图标缓存重载后的签名态恢复（C23 实证必要性）。
   - 失败语义：漏洞会话失败=一次性失败，**不得留半装状态**（回滚 staging）。
3. **错误码**：EUTrollEErrorCodeEngineBUnavailable 已预留；会话失败建议扩展 code 12+。
4. **版本域**：≤17.0 按 C23 CT 语义（TrollInstallerX 同构）；26.x 等 Tier B 信任锚（B24 三攻击面）落地后同接口接入。
5. **UI**：模式选择对用户透明（Auto）；"关于"页如实标注当前可用域。

**实现注记（C，08-27 12:15）**——已按上述契约全量落码（EUTrollE.m 引擎B节+EUTrollE.h 错误码 12/13/14），四个实现决策请 B 评审：
- ①解包=系统 libarchive（/usr/lib/libarchive.2.dylib dlopen，运行时自备常量声明， jailed 无 /var/jb/unzip 的等价解）；含路径消毒（绝对路径/.. 穿越）。
- ②root 化=libjailbreak `proc_ucred_update_content`（现成助手，iOS 17+ 含 audit token 修正路径；kfd KRW 路线 A12-A13 足够，dmaFail PPL 优先带上有则更稳）。
- ③永久签名安装=MobileInstallation 私有框架 `MobileInstallationInstall`（dlsym；TrollHelper 同构路线）。**假设：ABI 为 `(NSString*, NSDictionary*, dispatch_queue_t, callback, NSError**)`——历史 ABI，若实机版本签名不同需按版本适配（dlsym 失败/调用异常有明确错误码 14 兜底，不 panic）。**
- ④Persistence Helper=本体第二槽位副本（TrollStore 2"本体兼 helper"模式；URL scheme 移交名=`euphoria-trolle://install?url=`——**scheme 名请与本体 App 的 CFBundleURLTypes 对齐**）。重放表条目新增 `role`（body/helper）与 `engine`（A/B）字段，Engine A 重放逻辑对旧条目（无 role/engine）向后兼容。
- 域校验（C24 修正版）已 build 级实现：16.7.x 仅 RC(20H18) 放行，17.0 全系放行，17.0.1+ 拒绝并提示会话档/PC 档。

## 3. 验收口径（并入 T13）

- Engine A：越狱态装一个 adhoc IPA→重启→重越狱→应用可启动（重放生效）。
- Engine B（V0.9.1）：未越狱装巨魔E 本体→重启（不越狱）→本体可启动并可装应用。
