# Euphoria 二次定制指南

本文档面向希望继续魔改本项目的开发者，说明各定制点的位置与风险等级。

## 1. 改名 / 换标（低风险）

| 定制点 | 位置 |
|---|---|
| 应用显示名 | `Application/Euphoria/Info.plist` 相关 target 配置（pbxproj `PRODUCT_NAME`/`INFOPLIST_KEY_CFBundleDisplayName`） |
| 启动 Logo / 图标 | `Assets.xcassets/Euphoria.imageset`、`AppIcon*.appiconset`（直接替换 PNG，保持尺寸规格） |
| 主题 | `UI/Themes/`（上游自带多主题框架，含 bootlogo 渲染） |

## 2. 切换 / 新增内核漏洞（中风险）

漏洞框架全部位于 `Application/Euphoria/Exploits/`，接入步骤：

1. 复制任一现有框架（如 `Titan`）作为模板，改 bundle ID 前缀 `dev.euphoria.<Name>`
2. 在 `EUExploitManager` 中注册：声明支持的系统版本区间与设备范围
3. 实现 `EUExploit` 接口：`exploitWithError:` 内完成 KRW 原语获取并写入 `libkrw` provider
4. Xcode 工程添加 framework target 并挂入主 App 的 Embed 列表

> 漏洞本体需要你对目标 iOS 版本有深入的内核研究；本项目继承的 9 个公开漏洞均已随上游适配 iOS 15–18.7.1 / 26.x。

## 3. 更换 bootstrap（中风险）

`EUBootstrapper.m`：

- 下载源硬编码为 `https://apt.procurs.us/bootstraps/%@/bootstrap-ssh-iphoneos-arm64.tar.zst`
- 换自建 bootstrap 时需同步修改 `bootstrapVersion`、zstd 解包逻辑（`EUBootstrapper+zstd`）与默认源列表（Chariz/Havoc/ElleKit）

## 4. 调整运行时路径（高风险，破坏生态兼容）

- `/var/jb` 符号链接：由 `libjailbreak` 与 bootstrap 共同维护，**强烈不建议改动**（所有 deb 包的依赖路径都锚定于此）
- `basebin` 目录名：同上，牵涉 launchd 守护进程、jbctl、MachOMerger 合并逻辑
- dyld UUID 魔术前缀 `EUPH`：写入端 `BaseBin/libjailbreak/src/basebin_gen.m`，读取端 `BaseBin/systemhook/src/main.c`，两处必须同步

## 5. XPC 服务扩展（中风险）

jbserver 域与操作码定义于 `BaseBin/libjailbreak/src/jbserver_domains.h`：

- 新操作码追加到对应域枚举尾部（顺序即线上协议，不可插队）
- 服务端实现：`BaseBin/launchdhook/src/jbserver/jbdomain_*.c`
- 客户端封装：`BaseBin/libjailbreak/src/jbclient_xpc.c`

## 6. 已知雷区（必读）

1. **`com.opa334.TrollStore` 不可改名** —— 这是对外部应用的真实探测
2. **子模块不可混入品牌重命名** —— ChOma/XPF/opainject/litehook 是独立上游，保持原样
3. **`Provides:` 字段**（`control` 文件）是虚拟包契约，改名会破坏依赖解析
4. **`JBS_*` 枚举顺序**是 XPC 线上协议的一部分，只能在尾部追加
5. 更新检查 URL 当前指向占位仓库 `euphoria-jb/Euphoria`，正式发布前务必替换
