TARGET = cloakd

CC = clang

CFLAGS = -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -Wno-deprecated-declarations -D BUILD_STANDALONE=$(BUILD_STANDALONE) -O2 -I$(shell brew --prefix)/opt/libarchive/include
LDFLAGS = -lbsm -larchive -framework CoreFoundation -framework IOKit -framework CoreServices

sign: $(TARGET)
	@ldid -Cadhoc -Sentitlements.plist $<

$(TARGET): $(wildcard src/*.c) ../libjailbreak/src/jbclient_xpc.c ../libjailbreak/src/jbclient_mach.c ../libjailbreak/src/cloak.c ../libjailbreak/src/inline_svc.c ../libjailbreak/src/util.c ../libjailbreak/src/jbroot.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)

default: $(TARGET)
