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

# -F 段：IOKit/IOSurface 头文件与 tbd 均由 iPhoneOS SDK 自带，直接 weak 链接
# 即可（旧版曾 -F 整个 macOS SDK Frameworks 目录取桩，Xcode 26 下会让 UIKit
# 链误命中 macOS 版 CoreImage/CoreVideo——CVOpenGLESTexture.h 缺失报错）；
# IOMobileFramebuffer 走 vendor tbd
CFLAGS += -F../frameworks \
	-weak_framework IOKit -weak_framework IOSurface \
	-framework IOMobileFramebuffer

LDFLAGS = -L../lib -larchive -lbsm -lchoma

$(TARGET): $(wildcard src/*.c src/*.m src/*.S ../modules/litehook/src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

sign: $(TARGET)
	@ldid -Cadhoc -s $<

clean:
	@rm -f $(TARGET)
