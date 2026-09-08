# ============================================================================
# TrollE-Installer（巨魔E 安装器·独立源码工程）自包含构建
# B 线深度移植：并行搜索员B，2026-09-03（骨架与解耦：并行搜索员C，2026-09-03）
#
# 产物（build/ 下）：
#   TrollE-Installer.tipa  ← CT/巨魔通道装（ldid 带 entitlements；装进已有
#                             TrollStore/巨魔E 的设备→安装器自带平台权限）
#   TrollE-Installer.ipa   ← 免越狱侧载通道（AltStore/SideStore/Sideloadly，
#                             重签后 entitlements 由证书档决定）
#   两者 Payload 相同，扩展名仅标识通道意图。
#
# 构建链（全部 vendor 自包含，脱离主树）：
#   ① vendor/ChOma        → libchoma.dylib
#   ② vendor/libjailbreak → libjailbreak.dylib（编入 litehook）
#   ③ Exploits/*          → 8 个 exploit framework 进默认闭包（kfd/DarkSword/
#                            dmaFail 等；momentarius 断默认接线，见 EXPLOIT_EXCLUDE）
#   ④ src/*               → 安装器 app（引擎B/C 门面 + 独立 UI）
#   ⑤ 装配 + ldid 签名 + 打包
#
# 环境要求见 BUILD.md：macOS 13+ / Xcode 15+（iOS SDK）/ ldid /
#   brew libarchive（仅取头文件，-larchive 由 SDK tbd 解析）
#
# 用法：
#   make          # 全链构建 + 双产物
#   make deb      # 另出 eu-repo deb（需 brew install dpkg）
#   make clean
# ============================================================================

SHELL := /bin/bash
.PHONY: all app exploits package deb clean check-env

APP_NAME    := TrollE-Installer
BUNDLE_ID   := dev.euphoria.trolle-installer
VERSION     := 0.9.1
APP_MIN_IOS := 14.0
EXP_MIN_IOS := 15.0   # exploit 域下限（iOS 14.x 无可用内核向量→引擎C 兜底）

BUILD       := build
VENDOR_LIB  := vendor/lib
APP_DIR     := $(BUILD)/$(APP_NAME).app
FW_DIR      := $(BUILD)/frameworks

# Apple 工具链（构建宿主=macOS）
SDK       := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)
BREW      ?= $(shell brew --prefix 2>/dev/null)

# exploit 目录（含 Info.plist 即视为 framework 目标；weightBufs 演示入口
# exploit/exploit.m 含 main()，由构建脚本自动剔除）
# 断默认接线清单（v21 §6-6，B 线 09-04）：研究级/未武器化链不进首发闭包——
# 源保留在树，武器化完成后再移出清单。
#   momentarius：A13 26.x 攻击面研究件（T24：无公开 weaponized exploit，
#   自研武器化未启动）——默认不编译不装包。
EXPLOIT_EXCLUDE := momentarius
EXPLOIT_DIRS := $(filter-out $(EXPLOIT_EXCLUDE),$(patsubst Exploits/%/, %, $(wildcard Exploits/*/)))

# 头文件搜索路径（app 与 exploit 共用的公共段）
COMMON_INCS := -Ivendor/libjailbreak/src -Ivendor/ChOma/include -Ivendor/include
COMMON_FWS  := -F$(MACOS_SDK)/System/Library/Frameworks \
	       -Fvendor/frameworks \
	       -weak_framework IOKit -weak_framework IOSurface

all: package

# ── 环境自检（失败早退，给出可读提示）─────────────────────────────────
check-env:
	@test -n "$(SDK)" || { echo "❌ 找不到 iOS SDK（xcrun --sdk iphoneos）——先装 Xcode"; exit 1; }
	@test -n "$(MACOS_SDK)" || { echo "❌ 找不到 macOS SDK"; exit 1; }
	@command -v ldid >/dev/null || { echo "❌ 缺 ldid（brew install ldid）"; exit 1; }
	@test -d "$(BREW)/opt/libarchive/include" || \
	        echo "⚠️  brew libarchive 头文件缺失——libjailbreak 若链不到 -larchive 见 BUILD.md 故障表"
	@echo "✅ 环境就绪：SDK=$(SDK)"

# ── ① ChOma（代码签名/CDHash 计算；DISABLE_SIGNING=1 免 libcrypto）────
$(VENDOR_LIB)/libchoma.dylib: check-env $(wildcard vendor/ChOma/src/*.c)
	$(MAKE) -C vendor/ChOma TARGET=ios DISABLE_SIGNING=1 DISABLE_TESTS=1 \
	        DYLIB_LDFLAGS="-install_name @rpath/libchoma.dylib"
	mkdir -p $(VENDOR_LIB)
	cp vendor/ChOma/output/ios/lib/libchoma.dylib $(VENDOR_LIB)/
	@echo "✅ libchoma.dylib（install_name=@rpath，免 libcrypto）"

# ── ② libjailbreak（KRW 读写层+内核结构 offset；编入 litehook）────────
$(VENDOR_LIB)/libjailbreak.dylib: $(VENDOR_LIB)/libchoma.dylib \
	$(wildcard vendor/libjailbreak/src/*) \
	$(wildcard vendor/modules/litehook/src/*.c)
	$(MAKE) -C vendor/libjailbreak
	cp vendor/libjailbreak/libjailbreak.dylib $(VENDOR_LIB)/
	@echo "✅ libjailbreak.dylib（install_name=@rpath）"

# ── ③ exploit frameworks（每个目录一个 .framework）──────────────────
exploits: $(VENDOR_LIB)/libjailbreak.dylib
	mkdir -p $(FW_DIR)
	@for d in $(EXPLOIT_DIRS); do \
	        bash scripts/build-exploit.sh "$$d" "$(FW_DIR)" \
	                "$(SDK)" "$(MACOS_SDK)" "$(EXP_MIN_IOS)" || exit 1; \
	done
	@echo "✅ exploit frameworks：$(EXPLOIT_DIRS)"

# ── ④ app 二进制 + .app 装配 ─────────────────────────────────────────
app: exploits $(wildcard src/*.m) src/Info.plist
	mkdir -p $(APP_DIR)/Frameworks
	clang -isysroot $(SDK) -arch arm64 \
	        -miphoneos-version-min=$(APP_MIN_IOS) -fobjc-arc \
	        $(COMMON_INCS) $(COMMON_FWS) \
	        -framework Foundation -framework UIKit -framework UniformTypeIdentifiers \
	        -framework QuartzCore -framework CoreGraphics \
	        -L$(VENDOR_LIB) -ljailbreak -lchoma \
	        -rpath @executable_path/Frameworks \
	        src/main.m src/InstallerViewController.m \
	        src/EUStandaloneConfig.m src/EUStandaloneEnvironment.m \
	        src/EUStandaloneExploit.m src/EUStandaloneInstaller.m src/EUStandaloneLogger.m \
	        src/EUFairyStyle.m \
	        -o $(APP_DIR)/$(APP_NAME)
	# 修复#11：app 链接补 -lchoma（src 用 ChOma 符号）+QuartzCore/CoreGraphics
	#（EUFairyStyle 的 CA 层与 CoreGraphics 绘制；rpath 已带 Frameworks/，dylib 装配同帧不变）
	cp src/Info.plist $(APP_DIR)/Info.plist
	printf 'APPL????' > $(APP_DIR)/PkgInfo
	# 巨魔E 本体内嵌（用户 2026-09-06 14:48 指令）：payload/Euphoria.tipa 在位
	# 则随包装入（主树 make trolle-payload 投放）；不在位则跳过（如实：未构建主树
	# 时安装器不带本体，UI 显示"无内置载荷"态）
	@if [ -f payload/Euphoria.tipa ]; then \
	        cp payload/Euphoria.tipa $(APP_DIR)/Euphoria.tipa; \
	        echo "✅ 内置巨魔E 本体已随包（$(APP_DIR)/Euphoria.tipa）"; \
	else \
	        echo "⚠️ 无内置巨魔E 本体（payload/ 为空）——主树 make trolle-payload 投放后再 make"; \
	fi
	cp $(VENDOR_LIB)/libjailbreak.dylib $(VENDOR_LIB)/libchoma.dylib $(APP_DIR)/Frameworks/
	cp -R $(FW_DIR)/*.framework $(APP_DIR)/Frameworks/
	@echo "✅ $(APP_DIR) 装配完成"

# ── ⑤ 签名 + 打包（.tipa 与 .ipa 同 Payload 双通道）──────────────────
package: app
	xattr -rc $(APP_DIR) 2>/dev/null || true
	# 主二进制带 entitlements（ldid -s/-S 无文件参数时保留既有 ents，
	# 故后续递归 adhoc 签不会覆盖主二进制特权——与主树 Application/Makefile 同序）
	ldid -SEntitlements.plist $(APP_DIR)/$(APP_NAME)
	# 递归 adhoc 签全部嵌入 mach-o（frameworks/libjailbreak/libchoma）
	ldid -s $(APP_DIR)
	rm -rf $(BUILD)/Payload $(BUILD)/$(APP_NAME).tipa $(BUILD)/$(APP_NAME).ipa
	mkdir -p $(BUILD)/Payload
	cp -R $(APP_DIR) $(BUILD)/Payload/
	(cd $(BUILD) && zip -qry $(APP_NAME).tipa Payload)
	cp $(BUILD)/$(APP_NAME).tipa $(BUILD)/$(APP_NAME).ipa
	@echo "✅ 产物就绪："
	@echo "   $(BUILD)/$(APP_NAME).tipa  ← 巨魔/TrollStore 通道（保留 entitlements）"
	@echo "   $(BUILD)/$(APP_NAME).ipa   ← 侧载通道（AltStore/SideStore/Sideloadly）"

# ── ⑥ eu-repo deb（可选；需 brew install dpkg）────────────────────────
deb: package
	bash scripts/package-deb.sh "$(APP_DIR)" "$(VERSION)"
	@echo "✅ build/$(APP_NAME)_$(VERSION)_iphoneos-arm64.deb（eu-repo 源生态）"

clean:
	rm -rf $(BUILD) $(VENDOR_LIB)
	$(MAKE) -C vendor/ChOma clean-output 2>/dev/null || true
	rm -f vendor/libjailbreak/libjailbreak.dylib
	@echo "✅ 已清理（vendor 源不动，仅产物）"

# 2026-09-05 C 修复记录：①补 src/EUFairyStyle.m 入编译列表（VC 19 处引用
# 零接线=undefined symbol）；②配方行 8 空格→TAB 定向转换 59 行（原版全空格
# 缩进，make 在 L67 即 missing separator 熔断——"老是编译错"实锤之一）；
# ③前置条件续行保留空格（规避规则头 TAB 续行歧义）。备份：
# agents/6a8d0a5300ccbc1a3c89cebe/Makefile.bak_20260905
