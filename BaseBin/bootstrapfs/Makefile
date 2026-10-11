TARGET = bootstrapfs

CC = clang

# Euphoria bootstrapfs: transactional mount-over rootful engine
# (hardened port of ghh-jb/Dopamine_Rootful BaseBin/bootstrapfs by untether,
#  re-licensed under upstream LICENSE for the Euphoria project)
CFLAGS = -framework Foundation -framework CoreFoundation -framework IOKit -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -D BUILD_STANDALONE=$(BUILD_STANDALONE)
LDFLAGS = -L../.build -ljailbreak

sign: $(TARGET)
	@ldid -Cadhoc -Sentitlements.plist $<

$(TARGET): $(wildcard src/*.m)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
