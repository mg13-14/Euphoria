TARGET = aegisd

CC = clang

# 构建修复：util.c 包含 <archive.h>，与 libjailbreak 对齐补 libarchive 头文件路径
CFLAGS = -I../.include -I./src -I$(shell brew --prefix)/opt/libarchive/include -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -Wno-deprecated-declarations -D BUILD_STANDALONE=$(BUILD_STANDALONE) -O2
LDFLAGS = -lbsm -larchive -L../.build -ljailbreak -framework CoreFoundation -framework IOKit -framework CoreServices

sign: $(TARGET)
	@ldid -Cadhoc -Sentitlements.plist $<

$(TARGET): $(wildcard src/*.c) ../libjailbreak/src/jbclient_xpc.c ../libjailbreak/src/jbclient_mach.c ../libjailbreak/src/aegis.c ../libjailbreak/src/inline_svc.c ../libjailbreak/src/util.c ../libjailbreak/src/jbroot.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)

default: $(TARGET)
