IMAGE        := ucode-language-server-test:latest
SDK_VERSION  ?= 25.12.4
SDK_ARCH     ?= x86-64
GIT_COMMIT   ?= $(shell git rev-parse --short HEAD)

PKG_NAME         := ucode-language-server
UCODE_MOD_NAME   := ucode_language_server
PKG_VERSION_BASE := $(shell grep -oP 'PKG_VERSION:=\K.*' openwrt/$(PKG_NAME)/Makefile)
PKG_VERSION      := $(if $(GIT_COMMIT),$(PKG_VERSION_BASE)~$(GIT_COMMIT),$(PKG_VERSION_BASE))

SDK_MAJOR_MINOR := $(shell echo $(SDK_VERSION) | cut -d. -f1,2)
BUILD_DIR       := build/$(SDK_ARCH)/$(SDK_MAJOR_MINOR)
REPORTER        := $(if $(CI),,-r compact)

BUILD_IMAGE = docker run --rm \
	-v $(CURDIR)/src:/builder/package/$(PKG_NAME)/src:ro \
	-v $(CURDIR)/mod:/builder/package/$(PKG_NAME)/mod:ro \
	-v $(CURDIR)/third_party:/builder/package/$(PKG_NAME)/third_party:ro \
	-v $(CURDIR)/$(BUILD_DIR)/$(PKG_NAME)-Makefile:/builder/package/$(PKG_NAME)/Makefile:ro \
	-v $(CURDIR)/$(BUILD_DIR):/builder/bin \
	-v $(CURDIR)/$(BUILD_DIR)/include:/builder/out_include \
	openwrt/sdk:$(SDK_ARCH)-$(SDK_VERSION)

TEST_IMAGE = docker run --rm $(TEST_OPTS) \
	-v $(CURDIR):/app \
	$(if $(wildcard $(BUILD_DIR)/native.so),-v $(CURDIR)/$(BUILD_DIR)/native.so:/usr/lib/ucode/$(UCODE_MOD_NAME)/native.so:ro) \
	-w /app \
	$(IMAGE)

.PHONY: compile test test-unit shell package

.docker-image: Dockerfile
	@docker build \
		--build-arg SDK_ARCH=$(SDK_ARCH) \
		--build-arg SDK_VERSION=$(SDK_MAJOR_MINOR) \
		-t $(IMAGE) .
	@touch .docker-image

compile: $(BUILD_DIR)/native.so mod/compile_flags.txt

$(BUILD_DIR)/native.so: $(shell find mod third_party/tree-sitter-ucode/src third_party/tree-sitter-ucode/ucdocs/src third_party/tree-sitter/lib/src -name '*.c' -o -name '*.h') openwrt/$(PKG_NAME)/Makefile
	@mkdir -p $(BUILD_DIR)/include
	@chmod 777 $(BUILD_DIR) $(BUILD_DIR)/include
	@sed 's/PKG_VERSION:=.*/PKG_VERSION:=$(PKG_VERSION)/' \
		openwrt/$(PKG_NAME)/Makefile > $(BUILD_DIR)/$(PKG_NAME)-Makefile
	@$(BUILD_IMAGE) \
		sh -c " \
			./scripts/feeds update base && \
			./scripts/feeds install ucode && \
			make defconfig && \
			make package/$(PKG_NAME)/compile V=s && \
			find /builder/build_dir -name native.so \
				-exec cp {} /builder/bin/native.so \; -quit && \
			test -f /builder/bin/native.so && \
			cp -fpR /builder/staging_dir/target-*/usr/include/* /builder/out_include/ \
		"; EC=$$?; rm -f $(BUILD_DIR)/$(PKG_NAME)-Makefile; exit $$EC

mod/compile_flags.txt: $(BUILD_DIR)/include
	@printf -- '-I%s\n-I%s\n-I%s\n-Wall\n-Wextra\n-Werror\n-std=gnu99\n' \
		"$(CURDIR)/$(BUILD_DIR)/include" \
		"$(CURDIR)/third_party/tree-sitter/lib/include" \
		"$(CURDIR)/third_party/tree-sitter-ucode/src" > mod/compile_flags.txt

test: test-unit

test-unit: .docker-image $(BUILD_DIR)/native.so
	@$(TEST_IMAGE) utest -c test/utest.config.uc $(REPORTER) test/unit/

shell: TEST_OPTS := -it
shell: .docker-image
	@$(TEST_IMAGE) sh

package:
	@mkdir -p $(BUILD_DIR)/include
	@chmod 777 $(BUILD_DIR) $(BUILD_DIR)/include
	@sed 's/PKG_VERSION:=.*/PKG_VERSION:=$(PKG_VERSION)/' \
		openwrt/$(PKG_NAME)/Makefile > $(BUILD_DIR)/$(PKG_NAME)-Makefile
	@$(BUILD_IMAGE) \
		sh -c " \
			./scripts/feeds update base && \
			./scripts/feeds install ucode && \
			make defconfig && \
			make package/$(PKG_NAME)/compile V=s \
		"; EC=$$?; rm -f $(BUILD_DIR)/$(PKG_NAME)-Makefile; exit $$EC
