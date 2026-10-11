# ldid iOS arm64 嵌入套件（TrollStoreE「自带 ldid」需求素材）

## 内容
- `bin/ldid`：**iOS arm64 Mach-O**（2.1.5-procursus7，取自 Procursus 官方源 apt.procurs.us，1800 套件/iphoneos-arm64-rootless）
- `lib/`：ldid 的全部运行时依赖 dylib（均为 @rpath 引用）：
  - libiosexec.1.dylib（Procursus 1.3.1）
  - libplist-2.0.3.dylib（2.2.0+git20230130）
  - libssl.3.dylib / libcrypto.3.dylib（OpenSSL 3.2.1，约 5MB）
- `COPYING`：**ldid 许可证 = AGPL-3.0**（分发/嵌入需随附许可证与源码指引；用户已确认不担心版权，此处仅备档合规事实）
- 来源：https://apt.procurs.us/pool/main/iphoneos-arm64-rootless/1800/ldid/（以及 libiosexec / libplist / openssl 各目录）

## 嵌入到 App 的工程要点（给构建负责人）
1. ldid 的动态库引用形如 `@rpath/libcrypto.3.dylib`。它作为独立可执行文件被 App spawn 时，@rpath 按**它自己的 LC_RPATH**解析（原为 /var/jb/usr/lib，rootless 越狱路径）。
2. 两种落地法：
   a. **改 LC_RPATH**：把 ldid 的 rpath patch 成 `@executable_path/Frameworks`（可用 Mach-O patch 工具改写 LC_RPATH 字符串；原有字符串长度足够容纳）；四个 dylib 放进 App 的 `Frameworks/`。
   b. 保持 @rpath，在越狱设备上依赖 /var/jb 环境——不可靠，不推荐。
3. jailed（TrollStore 纯巨魔态）下 `DYLD_*` 环境变量会被剥离，不要指望用环境变量传 rpath，必须走方法 a。
4. 这些 dylib 自带 Procursus 签名，经 TrollStore 安装时会被 CoreTrust 重签，无需预处理。
5. 若嫌 5MB 太大：ldid 对 libssl.3 的依赖可尝试去掉（Procursus ldid 仅用 libcrypto 做签名散列；可试 patch 掉 LC_LOAD_DYLIB libssl.3 —— ldid.cpp 实际不调用 libssl 符号，风险低），可省 ~1.7MB。
6. 替代方案：不嵌 ldid 二进制，直接把 **ChOma**（TrollStore 自家的 C 库，仓库里就有：BaseBin/ChOma，支持签名/entitlements/CT bypass）编译进 App 调 API，体积更小、集成更深——TrollStore 本尊就是这么干的。ldid 只是兼容命令行习惯时的备选。

## 附
- 同目录上级放有 `dop_vs_euph.diff`：mg13-14/Euphoria vs opa334/Dopamine 官方 HEAD 的全量 diff（321 行，证明源码树纯净）。
- Linux x86_64 版 ldid（供本机改包流水线用）：`../ldid-linux-x86_64`。
