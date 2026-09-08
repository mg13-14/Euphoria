# libjailbreak（vendor 自包含版）——B 线深度移植 2026-09-03
# 源：主树 BaseBin/libjailbreak（同一套 src 快照；差异仅路径与 install_name）：
#   - include / frameworks / litehook 全在 ../ 内（脱离主树）
#   - install_name 改 @rpath（app 内嵌布局；主树原版 @loader_path 适配
#     /var/jb/basebin 平铺目录，两者产物不互换）
TARGET = libjailbreak.dylib

CC = clang

SDKROOT := $(shell xcrun --sdk iphoneos --show-sdk-path)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-path)
BREW_PREFIX ?= $(shell brew --prefix)

CFLAGS = -framework Foundation -framework CoreServices -framework Security \
	-framework CoreGraphics -framework ImageIO -lMobileGestalt \
	-isysroot $(SDKROOT) \
	-arch arm64 -arch arm64e -miphoneos-version-min=14.0 -fobjc-arc \
	-dynamiclib -install_name @rpath/$(TARGET) \
	-I../include -I../modules/litehook/src -I../ChOma/include \
	-I$(BREW_PREFIX)/opt/libarchive/include

# -F 段：IOKit/IOSurface 走 macOS SDK 桩（iOS SDK 不带 IOKit 头；
# 运行时 iOS DSC 均在位，weak 链接兜底）；IOMobileFramebuffer 走 vendor tbd
CFLAGS += -F$(MACOS_SDK)/System/Library/Frameworks -F../frameworks \
	-weak_framework IOKit -weak_framework IOSurface \
	-framework IOMobileFramebuffer

LDFLAGS = -L../lib -larchive -lbsm -lchoma

$(TARGET): $(wildcard src/*.c src/*.m src/*.S ../modules/litehook/src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

sign: $(TARGET)
	@ldid -Cadhoc -s $<

clean:
	@rm -f $(TARGET)
