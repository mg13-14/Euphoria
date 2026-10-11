TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = TrollStoreE
ARCHS = arm64

TARGET_CODESIGN = ../Exploits/fastPathSign/fastPathSign

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TrollStoreE

TrollStoreE_FILES = $(wildcard *.m) $(wildcard ../Shared/*.m)
TrollStoreE_FRAMEWORKS = UIKit CoreGraphics CoreServices CoreTelephony
TrollStoreE_PRIVATE_FRAMEWORKS = Preferences MobileIcons MobileContainerManager
TrollStoreE_LIBRARIES = archive
TrollStoreE_CFLAGS = -fobjc-arc -I../Shared -I$(shell brew --prefix)/opt/libarchive/include
TrollStoreE_CODESIGN_FLAGS = --entitlements entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
