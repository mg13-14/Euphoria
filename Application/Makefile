.PHONY: all clean build_clean

all: Euphoria.ipa

Euphoria.ipa: build/Build/Products/Debug-iphoneos/Euphoria.app
	@echo Ad-Hoc signing Euphoria
	xattr -rc build/Build/Products/Debug-iphoneos/Euphoria.app
	ldid -SEuphoria/Euphoria.entitlements build/Build/Products/Debug-iphoneos/Euphoria.app/Euphoria
	ldid -s build/Build/Products/Debug-iphoneos/Euphoria.app
	rm -rf Payload Euphoria.ipa
	mkdir Payload
	cp -r build/Build/Products/Debug-iphoneos/Euphoria.app Payload/Euphoria.app
	zip -Ar Euphoria.ipa Payload
	rm -rf Payload
	rm -rf Euphoria.tipa
	cp Euphoria.ipa Euphoria.tipa

ifeq ($(NIGHTLY), 1)
build/Build/Products/Debug-iphoneos/Euphoria.app: FORCE
	xcodebuild -scheme Euphoria -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO GCC_PREPROCESSOR_DEFINITIONS='NIGHTLY=1 COMMIT_HASH=\"$(COMMIT_HASH)\"'
else
build/Build/Products/Debug-iphoneos/Euphoria.app: FORCE
	xcodebuild -scheme Euphoria -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
endif

clean:
	rm -rf build Payload Euphoria.ipa Euphoria.tipa

build_clean:
	rm -rf Payload build

FORCE: ;