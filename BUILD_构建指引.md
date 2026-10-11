# 构建指引 · Euphoria v1.0.8-R1（固定 Rootful 化构建）

> 适用源码包：`euphoria-v1.2-deadasset-clean-src.tar.gz`（终版完整树，patch v1.3 已全部合入）
> 对表口径：TS-1 自建验收口径——须出自自建构建流水线，不以过渡件充数。
> 措辞红线：用户口径验收通过前，构建产物状态只可表述为「内部自测通过」。

---

## 一、构建载体二选一

### 路线 A · GitHub Actions（推荐，唯一免本机依赖路线）

源码树自带 CI 定义 `.github/workflows/build-ipa.yml`：

1. 将完整源码树 push 到 GitHub 仓库（私有仓即可）。
2. 两种触发方式：
   - **手动**：仓库 → Actions → 选 `build-ipa` → Run workflow；
   - **自动**：打 tag（`v*`）→ 构建并自动挂 Release。
3. Runner：`macos-latest`（自带 Xcode + iOS SDK；私有仓免费额度 2000 分钟/月）。
4. 产物（Artifacts / Release 附件，网页直接下载）：
   - `TrollE-Installer.tipa` / `.ipa` —— 巨魔E 安装器（CT/巨魔通道 + 侧载双通道）；
   - `Euphoria.tipa` —— 巨魔E 本体主 App。

> 技术注：Codeberg（Woodpecker CI）无 macOS runner，iOS 构建只能走 GitHub Actions 或本地 Mac——这是选 GitHub 做构建载体的原因。

### 路线 B · 本地 Mac 构建

前置：macOS + Xcode（iOS SDK）+ 以下依赖（与 CI 同源）：

```
brew install dpkg libarchive
# ldid：必须用 Procursus 版（brew 版对目录递归 -s 有 flag_S 断言）
curl -fsSL "https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_arm64" -o /tmp/ldid
chmod +x /tmp/ldid && sudo mv /tmp/ldid /usr/local/bin/ldid
# theos（BaseBin 子项目 Makefile 依赖）
git clone --recursive https://github.com/theos/theos.git ~/theos
export THEOS=~/theos
# SDK 顶名 symlink（theos 硬校验 16.5 SDK，本机只有新版 SDK 时）
xcrun -sdk iphoneos -show-sdk-version   # 确认实际 SDK 版本后按 CI 内同法 symlink
```

构建命令（根 Makefile，四模块自底向上）：

```
make            # = BaseBin → Packages → Application → Standalone
make trolle-payload   # （可选）把 Euphoria.tipa 内嵌进安装器 payload 槽
```

产物位置：`Application/Euphoria.tipa`、`TrollE-Installer/`（安装器）。

---

## 二、依赖清单（完整）

| 依赖 | 版本/来源 | 用途 | 备注 |
|---|---|---|---|
| Xcode + iOS SDK | runner 自带 / 本地安装 | 全树编译 | |
| dpkg | brew | deb 打包（Packages/jbctl 安装件） | |
| libarchive | brew | bootstrap tar 解包链 | |
| ldid | **Procursus v2.1.5-procursus7** | 伪签名/entitlements | brew 版有 flag_S 断言缺陷，勿用 |
| theos | git clone（recursive） | BaseBin 部分子项目构建 | 需 `THEOS` 环境变量 + SDK symlink |

## 三、本构建（R1）相对 v1.0.7 的源码差异

- 修改 48 文件 / 统一补丁 3747 行（2795 主段 + 48 v1.1 + 203 v1.2 毛玻璃 + 701 v1.3 死资产清理：26 语言死键+EPM 移除，见 `euphoria-rootful-fixed.patch`，四段式顺序应用）。
- **源码包与补丁的版本对应**：`euphoria-v1.0.8-rootful-fixed-src.tar.gz` = DL-v1 基线快照（不含 P1-F1 增量段三修）；权威产出以 patch 为准（两段式顺序应用，已 GNU patch 全量验证）。终版源码包（euphoria-v1.2-deadasset-clean-src.tar.gz）：含 patch v1.3 全部改动 + AppIcon 五套集全槽位正确尺寸化（actool 门槛清除）+ 死键清理终态（图标 PNG 仅随源码包交付）。
- 全部修改为源码级，无新增外部依赖；构建流程与 v1.0.7 完全一致（零流水线改动）。
- 合入方式（如单独使用 patch 文件）：
  ```
  tar xzf euphoria-v1.0.7-src-full.tar.gz    # 原始基线
  cd euphoria-v1.0.7-src
  patch -p1 < ../euphoria-rootful-fixed.patch
  ```

## 四、构建后自检（出包前）

1. 括号/符号平衡已在源码层自检通过（19 文件全量）。
2. 建议构建后抽查产物内 `systemhook.dylib` 与 `Euphoria` 主二进制存在性 + `Euphoria.tipa` 可被 TrollE-Installer payload 槽识别（`make trolle-payload` 无报错即通）。
3. 功能验收对表介绍文档第八节（五向量口径）；**用户口径验收通过前，产物状态一律表述为「内部自测通过」**。

## 五、指纹注意（CI 工作流内已处理）

- theos TARGET 写死 SDK 与 runner 实际 SDK 不匹配时：theos 仅警告并取最高可用版本（可跑警告）。
- SDK 名称硬校验需 symlink 顶名（CI 步骤内已内置同法）。

---

*落款：汇总员主线 · 2026-10-11 · 配套交付：介绍文档（同目录 HTML）+ 统一 diff + 全量源码 tarball*
