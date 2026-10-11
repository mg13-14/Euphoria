export NIGHTLY ?= 0

export BUILD_STANDALONE ?= 0

ifeq ($(NIGHTLY), 1)
export COMMIT_HASH = $(shell git rev-parse HEAD)
endif

ifeq ($(BUILD_STANDALONE), 1)
export BUILD_STANDALONE = 1
endif

all:
	@$(MAKE) -C BaseBin
	@$(MAKE) -C Packages
	@$(MAKE) -C Application
	@$(MAKE) -C Standalone

clean:
	@$(MAKE) -C BaseBin clean
	@$(MAKE) -C Packages clean
	@$(MAKE) -C Application clean
	@$(MAKE) -C Standalone clean

update: all
	ssh $(DEVICE) "rm -rf /var/mobile/Documents/Euphoria.tipa"
	scp -C ./Application/Euphoria.tipa "$(DEVICE):/var/mobile/Documents/Euphoria.tipa"
	ssh $(DEVICE) "/var/jb/basebin/jbctl update tipa /var/mobile/Documents/Euphoria.tipa"

update-basebin: all
	ssh $(DEVICE) "rm -rf /var/mobile/Documents/basebin.tar"
	scp -C ./BaseBin/basebin.tar "$(DEVICE):/var/mobile/Documents/basebin.tar"
	ssh $(DEVICE) "/var/jb/basebin/jbctl update basebin /var/mobile/Documents/basebin.tar"

# 巨魔E 本体内嵌交付（用户 2026-09-06 14:48 指令"安装器里要内置巨魔E"）：
# 把主树产物 Euphoria.tipa 投放到独立安装器 payload/ 槽——安装器 make 检测到
# 即自动内嵌进 .app（用户拿到安装器=自带巨魔E 本体，无需另找 ipa）。
trolle-payload: all
	mkdir -p TrollE-Installer/payload
	cp -f Application/Euphoria.tipa TrollE-Installer/payload/Euphoria.tipa
	@echo "✅ 巨魔E 本体已投放安装器 payload/（安装器 make 自动内嵌）"

.PHONY: update clean trolle-payload