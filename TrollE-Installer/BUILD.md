# TrollE-Installer 构建指南（B 线权威版）

> 自包含工程：**不需要** Euphoria 主树、不需要 theos、不需要 git submodule。
> 一条 `make` 出双产物。

## 环境要求

| 依赖 | 版本/说明 | 安装 |
|---|---|---|
| macOS | 13+（Ventura 及以上） | — |
| Xcode | 15+（含 iOS SDK 与 CLT） | App Store |
| ldid | 码签名/伪签 | `brew install ldid` |
| libarchive | 仅头文件（libjailbreak 构建期） | `brew install libarchive` |
| make/clang | 随 Xcode CLT | — |
| dpkg（可选） | 仅 `make deb` 出 eu-repo 包 | `brew install dpkg` |

```bash
xcode-select --install        # 若未装 CLT
brew install ldid libarchive
```

## 构建

```bash
cd TrollE-Installer
make            # 全链：ChOma → libjailbreak → 8 个 exploit framework（momentarius 断默认接线）→ app → 签名 → 打包
```

### 巨魔E 本体内嵌（用户 2026-09-06 14:48 指令"安装器里要内置巨魔E"）

安装器 bundle 可内嵌巨魔E 本体（免选文件直装）。Mac 上的完整顺序：

```bash
cd Euphoria                  # 主树根
make trolle-payload          # 构建主树 + 把 Application/Euphoria.tipa 投放 TrollE-Installer/payload/
cd TrollE-Installer
make                         # app 装配段检测到 payload/Euphoria.tipa → 自动内嵌进 .app
```

- 未跑 trolle-payload 时安装器照常构建，UI 显示"内置巨魔E（未随包）"禁用态 +
  日志指引（如实状态，不伪造"有本体"）。
- 只想要不带本体的裸安装器（测 UI/引擎）时直接 `make` 即可。

产物（`build/`）：

| 产物 | 通道 | 说明 |
|---|---|---|
| `TrollE-Installer.tipa` | **巨魔/TrollStore 通道** | ldid 已签 Entitlements.plist（platform-application/no-sandbox/iokit 白名单）；装进**已有** TrollStore/巨魔E 的设备 → 安装器自带平台权限，引擎 B 的 entitlement 门禁通过率最高 |
| `TrollE-Installer.ipa` | **免越狱侧载通道** | AltStore/SideStore/Sideloadly 重签（免费证书 7 天/3 app；SideStore 可无 PC 续签）。重签后 entitlements 由证书档决定——kqueue 系漏洞（kfd landa/smith）不受影响，IOSurface/AGX/ANE 系向量可能受限 |
| `TrollE-Installer_0.9.1_*.deb` | eu-repo 源生态（越狱态） | `make deb` 另出；Sileo 安装 |

两者 Payload 完全相同，扩展名仅标识通道意图。

> **eu-repo 分发 deb＝瘦身版**（B 2026-09-06 0.9.1-6 起）：剥离 vendor/ChOma/external/ios/
> 的 libcrypto.a（39.4MB）与 libssl.a（7.6MB）。本工程 make 链对 ChOma 走
> `DISABLE_SIGNING=1`（免 libcrypto），两个 .a 仅在 ChOma 全签名模式（DISABLE_SIGNING=0）
> 才被链接——剥离后 `make` 全链不受影响。如需该模式：openssl 源码
> `./Configure ios64-xcrun no-shared no-tests && make` 产出 arm64 .a 后放回原位。
> `make deb` 本地产物＝含 .a 全量版（devel 形态）；上 eu-repo 的分发版由打包线出瘦身版。

## 部署到设备（不越狱）

1. **侧载通道**（任意 iOS 15+，无需越狱）：Sideloadly/AltStore 装 `TrollE-Installer.ipa`
   → 打开安装器 → 选巨魔E 本体 `.ipa` → 按版本域走引擎 B（CT 域）/引擎 C（全版本）
2. **巨魔通道**（设备已有 TrollStore 的，如 16.5.1/16.6.1）：TrollStore 装 `.tipa`
   → 安装器自带特权，引擎 B 门禁风险最低

## 构建故障排查

| 症状 | 处理 |
|---|---|
| `xcrun --sdk iphoneos --show-sdk-path` 为空 | Xcode 未装/未接受许可：`sudo xcodebuild -license accept` |
| libjailbreake 链接报 `archive_XXX` 未定义 | iOS SDK 缺 libarchive tbd 的老 SDK：`brew install libarchive` 后重试；仍失败则改 vendor/libjailbreak/Makefile 的 LDFLAGS 去 `-larchive` 加 `-Wl,-undefined,dynamic_lookup`（运行时 dlopen 系统库兜底） |
| ldid 报 `code signature` 类错 | 先 `xattr -rc build/TrollE-Installer.app` 清隔离属性 |
| ChOma `-Werror` 报警告挡编译 | 加 `make vendor/ChOma` 时传 `CFLAGS="-Wno-error ..."`；或临时改 vendor/ChOma/Makefile 顶部 `-Werror` |
| exploit 编译缺 `IOKit/IOKitLib.h` | 确认装了完整 Xcode（非仅 CLT）；脚本已带 `-F$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks` |
| `make deb` 找不到 dpkg-deb | `brew install dpkg` |
| `make deb` 报 `maintainer script 'postinst' has bad permissions 644` | `chmod 755 DEBIAN/postinst` 后重跑（脚本内已做，手工拷包时注意） |
| `dpkg-deb: error: control directory has bad permissions 700` | `chmod 755 build/deb-stage/DEBIAN`（staging 目录权限过严） |
| 链接报 `No such file or directory: '-larchive'`（SDK tbd 解析失败的老 Xcode） | `brew install libarchive` 后确认 `$(brew --prefix)/include` 存在；终极兜底=Makefile LDFLAGS 去 `-larchive` 改 `-Wl,-undefined,dynamic_lookup` |
| ldid 找不到 Entitlements.plist | 在工程根目录跑 make（脚本按相对路径取 `Entitlements.plist`） |
| 编译期大量 `warning` 挡道（ChOma `-Werror`） | `make CFLAGS="-Wno-error"` 或临时注释 vendor/ChOma/Makefile 顶部 `-Werror`——**不要**为过编译改源码逻辑 |

## 首跑清单（Mac/盟友侧，B 线 09-04 增）

给编译侧（含 GLM5.3 盟友）的过检顺序，逐项过一遍再报错：

1. `xcodebuild -version` ≥ 15、`xcrun --sdk iphoneos --show-sdk-path` 非空、`sudo xcodebuild -license accept`。
2. `brew install ldid libarchive`（`make deb` 另需 `dpkg`）。
3. 在**工程根目录**跑 `make`（相对路径：Entitlements.plist/vendor/ 都以根为锚）。
4. 预期闭包=8 个 exploit framework（`Exploits/momentarius` 源在树但**默认不编译**——若想强行编它需从 Makefile `EXPLOIT_EXCLUDE` 移除，属研究行为，报错自负）。
5. 首跑建议顺序拆步排障：`make vendor/ChOma` → `make vendor/libjailbreak.dylib` → `make build/TrollE-Installer.app` → `make package`，哪步炸查哪步（全链 make 会把首个失败淹没在长日志里）。
6. 报错格式（回报 B 线用）：`失败步骤 + 完整错误行 + xcodebuild/clang 版本 + macOS 版本`，截图/复制原始报错，勿转述。
7. 已知工程事实：src 全 ObjC（无 Swift/无 Storyboard），min iOS 15.0，目标 arm64 真机（非模拟器）——`-miphoneos-version-min` 的弃用 warning 属正常，不是错误。

## 验证状态（如实）

- 本工程在无 iOS 工具链的开发环境完成静态移植——**编译验证在 macOS 首跑时完成**，
  首跑报错按上表排查，无法解决的带日志回报 B 线。
- 引擎 B（CT 永久档）为【实验性】：entitlement 门禁三候选 spike 未实机裁决（README §七-1）。
- 引擎 C（容器档）逻辑完整，装出形态=L1（宿主签名健康度依赖，见 README §七-3）。
