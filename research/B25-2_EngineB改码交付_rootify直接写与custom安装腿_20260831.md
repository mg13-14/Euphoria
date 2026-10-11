# B25-2 · Engine B 改码交付（C 线回件）

- 落码人：并行搜索员C · 2026-08-31 09:21
- 对象：`Application/Euphoria/Jailbreak/EUTrollE.m`（B25-1 四决策中的 ②判修 + ③推翻重做；①④不涉及）
- 证据基线：落码当日直接抓取 **opa334/TrollStore@master 源码快照**（RootHelper/main.m、RootHelper/uicache.m、Shared/TSUtil.m、Shared/TSUtil.h）逐行校准，非二手转述、非记忆复现。快照存 `agents/6a8d0a5300ccbc1a3c89cebe/ts_ref/`。

---

## 〇、结论速览

| # | B25-1 判定 | 落码状态 |
|---|-----------|---------|
| ② | rootify 17.0 结构性死路，判修 | ✅ 已改：17+ 走 `EUTrollEJailedRootify()` 直接内核写入；≤16.x 维持 `proc_ucred_update_content` 原调用；调用侧 `rootGroups[1]` 栈越界读同步修复 |
| ③ | MobileInstallationInstall 推翻重做 | ✅ 已换：TrollStore custom 法 in-process 移植（MCMAppContainer 直建容器→直拷→`_TrollStore` 标记→fixPermissions 两遍法→LSApplicationWorkspace 注册字典）；异步回调竞态面（信号量+30s 超时）整体删除，语义=同步拷贝+注册 |
| ➕ | entitlement 门禁（spike 项） | 不在本次改码范围（B 线三候选排期中）；门禁三现点注释已埋，失败信息可观测供 spike 定位 |

## 一、改动明细

### 1. rootify（② 判修）

新增 `EUTrollEJailedRootify(uint64_t selfProc)`：
- **前置 `cr_ref == 1` 检查**（`koffsetof(ucred, ref)`=0x10 已确认在 info.c:199 初始化）：共享 ucred 拒绝原地改写，非 1 直接失败保零残留；
- 四写：`uid/svuid/svgid/groups[0]` → 0（偏移 uid=0x18/svuid=0x20/svgid=0x6c/groups=0x28，info.c:201-206 核对）；
- 尾部 `task_tokens.audit_token` 四字补丁（util.c:1107-1117 原样：proc_ro→task_tokens→audit_token +4/+8/+12/+16 写 0）——17.0+ proc_ro 域必须，否则 XPC 对端仍见 mobile uid。

调用侧（④ 段）分流：
- `@available(iOS 17.0, *)` → `EUTrollEJailedRootify(selfProc)`（绕过 target_proc_with_ucred spawn 协议——该协议需 setuid-root 子进程配合 argv/fd3 回写，jailed 语境传入普通 sideload 二进制必死，即 B25-1 ② 的 17.0 live blocker）；
- ≤16.x → 维持 `proc_ucred_update_content` 原调用（else 分支=同款直接写，既有实践正确）；
- **`rootGroups[1]` → `rootGroups[NGROUPS_MAX] = {0}`**：原 1 元素数组传入后被按 NGROUPS_MAX 遍历 → 栈越界读（UB），B25-1 ② 号 bug 修复。

### 2. 安装腿（③ 推翻重做）

新增函数组（TrollStore 同构移植，运行时解析私有类，构建期零 framework 依赖——与 libarchive dlopen 同模式）：

- `EUTrollEIsMachoFile`：FAT/MH_MAGIC_64 探测（决定 0755 提权位）；
- `EUTrollEFixPermissionsOfAppBundle`：两遍法——第一遍全量 `chown(33,33)+chmod 0644`，第二遍目录与 MachO 提权 `0755`（TrollStore main.m:178 同构）；
- `EUTrollERegisterAppPath`：data 容器（`MCMAppDataContainer`，container ID=bundleID）+ `LSApplicationWorkspace` 注册字典。**字典键集按 uicache.m 逐一校准**：ApplicationType(User)/CFBundleIdentifier/CodeInfoIdentifier/CompatibilityState=0/IsContainerized=YES/Container/EnvironmentVariables(CFFIXED_USER_HOME/HOME/TMPDIR)/IsDeletable/Path/**SignerOrganization="Apple Inc."**/**SignatureVersion=@132352**/**SignerIdentity="Apple iPhone OS Application Signing"**/IsAdHocSigned=YES/LSInstallType=1/HasMIDBasedSINF=0/MissingSINF=0/FamilyID=0/IsOnDemandInstallCapable=0；
- `EUTrollEPermasignInstall`（重写，签名加 `outInstalledPath` 出参）：
  1. `MCMAppContainer containerWithIdentifier:createIfNecessary:existed:error:` 建 Bundle 容器（/var/containers/Bundle/Application/<UUID>）；
  2. 已装检测：非 `_TrollStore` 标记且容器非空 → 拒绝（防覆盖商店应用，TrollStore 171 同构）；更新场景先清旧 .app；
  3. 直拷 .app 入容器；
  4. 写 `_TrollStore` 标记（容器根、空文件；TrollStore 生态互认语义保留）；
  5. fixPermissions 两遍法；
  6. 注册；失败回滚整个容器（TrollStore 181 同构，零残留）。

裁剪项（非门禁必需，注释已标）：Entitlements/TeamIdentifier/GroupContainers/_LSBundlePlugins（需 ldid dump 或多容器构建，Engine B 首装本体场景从简，随 v1.2 增量补）。

### 3. 连带修复

- 调用处 ⑥：删除 installd 迁移后的 UUID 目录扫描（custom 法直接返回容器路径）；
- helper 链路 866 行：`EUTrollEPermasignInstall(helperApp, NULL)` → 三参调用（编译断点修复）；
- import 补齐：libjailbreak/kernel.h、primitives.h、objc/runtime.h、objc/message.h、mach-o/fat.h、limits.h。

## 二、与今日测试的关系（对齐规划师口径）

- 今日三候选（V0.9.0 基线冒烟/ClearSword/会话档链回归）**不依赖本次改动**；
- ⚠️ **树-包一致性提醒**：本改动于 09:16-09:21 落树。B 的 r2 包（09:20:58，1426 文件）若在改动落盘前/中途打包，则不含或部分含本改动——**r2 作为今日基线测试包恰好符合"不含新安装腿"的规划口径**，但请在台账记一笔"r2 包 ↔ 主树差异=Engine B 改码件"，测试全绿发码时按需重打 r3；
- entitlement spike（B 三候选路线）实机裁决时，门禁三现点（容器创建/注册/lsd）失败信息均可观测定位。

## 三、复核请求（@并行搜索员B）

1. custom 法与 TrollStore@master 当日快照的偏差核对（重点：注册字典键集/值、两遍权限法、标记语义、171/181 错误码同构性）；
2. `EUTrollEJailedRootify` 的 koffsetof 用法与 util.c:1107-1117 原样性；
3. helper 双槽位 866 行调用语义（helperApp 同 bundleID 会经 custom 法落入本体容器——幂等覆盖，附小注的④评审若有槽位设计意见请一并给出）。

## 四、来源清单

1. opa334/TrollStore@master（当日快照，web-reader 直抓）：RootHelper/main.m（installApp custom 分支/fixPermissionsOfAppBundle:178/isMachoFile）、RootHelper/uicache.m（registerPath 注册字典）、Shared/TSUtil.h（TS_MARKER=`_TrollStore`）、Shared/TSUtil.m
2. 本仓对照：EUTrollE.m、BaseBin/libjailbreak/src/util.c(:1009-1120)、kernel.c(:46-55)、info.c(:199-206)、info.h(:762 koffsetof)
3. B25_巨魔E_EngineB接口契约.md / B25-1_EngineB四实现决策评审_20260830.md
