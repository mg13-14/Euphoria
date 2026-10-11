# TrollStoreE 功能设计（Euphoria 定制版）

## 定位
基于 TrollStore 2.1.1（MIT, opa334dev）改装升级版，交付 Euphoria 生态的巨魔应用本体。

## 已完成的源码改造
| 项 | 实现 |
|---|---|
| 品牌 | TrollStoreE / dev.euphoria.trollstoree / 图标全 18 尺寸替换为紫巨魔白底（官方原图像素级变色） |
| 底部工具栏 | 4 tab：应用 · 注入插件 · 修改安装包 · 设置（TSRootViewController） |
| 注入插件 | TSInjectPluginViewController：中文界面 + 真实导入链（UIDocumentPicker + ZIP 魔数校验 + 落盘） |
| 修改安装包 | TSIpaEditorViewController：中文界面 + 导入 + 名称/包名/版本三字段编辑流 |
| 自带 ldid | Resources/ldid-ios-kit（iOS arm64 2.1.5 + 依赖 dylib）+ scripts/embed_ldid.sh 构建期 RPATH 修复 |
| 界面语言 | 新增页面全中文；存量页面中文化=后续逐文件替换（代码内英文字符串直改，无 strings 机制） |

## 引擎接线点（构建环境落地，纯代码工作无需决策）
1. **解包**：工程已链接 libarchive（TrollStoreE_LIBRARIES = archive）→ 实现 archive_read 抽 Payload
2. **注入**：ChOma（仓库自带，TrollStore 本尊用的库）Mach-O API 补 LC_LOAD_DYLIB，dylib 入 .app/Frameworks
3. **重签**：posix_spawn Resources/ldid -S<path>（embed_ldid.sh 已修 RPATH；备选直接调 ChOma API）
4. **回填**：改包功能读 Payload/*.app/Info.plist（NSDictionary）→ 表单回填 → 写回 → 重打包
5. **安装**：复用 TSInstallationController 现成安装管线

## 构建方式
- theos 工程（TARGET iphone:clang:16.5:14.0）→ mac 或 CI 构建，构建后执行 scripts/embed_ldid.sh
- 上游构建细节见 TrollStore-main/BUILD.md 与 README.md
