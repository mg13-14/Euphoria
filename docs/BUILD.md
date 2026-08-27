# Euphoria 构建指南

## 环境要求

| 依赖 | 版本/说明 |
|---|---|
| macOS | 13+（Ventura 及以上） |
| Xcode | 15+（含 iOS SDK 与命令行工具） |
| theos | 越狱生态构建系统（`BaseBin` 依赖） |
| ldid | 码签名/伪签工具 |
| make / clang | 随 Xcode CLT 提供 |

```bash
# 安装 theos（若未安装）
brew install ldid make
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS

# 初始化子模块（ChOma / XPF / opainject / litehook）
git init && git submodule update --init
# 注：若以纯源码目录交付（无 .git），参考 .gitmodules 手动克隆四个依赖到对应路径
```

## 构建步骤

```bash
# 1. 构建 BaseBin（运行时核心）+ Packages + Application
make

# 2. 仅构建 BaseBin
make -C BaseBin

# 3. 产物
#    Application/Euphoria.tipa   ← 越狱主产物（TrollStore IPA）
```

## 部署到设备

### 方式 A：TrollStore（推荐）

1. 将 `Euphoria.tipa` 传入设备
2. TrollStore → Install（获得平台二进制权限，App 内更新通道可用）

### 方式 B：开发者证书自签

- Xcode 直接运行 `Application/Euphoria.xcodeproj`（需配置 Signing Team）
- 注意：无 TrollStore 时部分功能（如 App 内 OTA 更新）受系统限制

### 开发迭代（已越狱设备热更新）

```bash
# 在根 Makefile 中配置设备 SSH 后：
make update          # 推送 tipa 并热更新
make update-basebin  # 仅更新 basebin.tar
```

## 构建故障排查

| 症状 | 处理 |
|---|---|
| `xcodebuild` 找不到 scheme Euphoria | 确认在 `Application/` 目录执行，或打开 xcodeproj 让 Xcode 生成 scheme |
| theos 报 `TARGET` 未定义 | 检查 `$THEOS` 环境变量与子模块初始化 |
| 签名失败 | `xattr -rc` 清除扩展属性后重试；确认 ldid 在 PATH |

## 发布前检查清单

- [ ] 替换 `EUUIManager.m` / `EUUpdateViewController.m` 中的占位更新源为真实仓库
- [ ] 确认 `Euphoria.entitlements` 与签名方式匹配
- [ ] 在真实设备上回归：全新越狱 / 重复越狱 / 卸载（`Restore System`）三个路径
- [ ] 更新 `CHANGES.md` 版本记录
