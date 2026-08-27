TARGET = aegisd

CC = clang

CFLAGS = -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -Wno-deprecated-declarations -D BUILD_STANDALONE=$(BUILD_STANDALONE) -O2
LDFLAGS = -lbsm -L../.build -ljailbreak -framework CoreFoundation -framework IOKit -framework CoreServices

sign: $(TARGET)
	@ldid -Cadhoc -Sentitlements.plist $<

$(TARGET): $(wildcard src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)

default: $(TARGET)
