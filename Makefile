IMAGE        := ucode-analyzer-test:latest
SDK_VERSION  ?= 25.12.4
SDK_ARCH     ?= x86-64
GIT_COMMIT   ?= $(shell git rev-parse --short HEAD)

PKG_NAME         := ucode-analyzer
UCODE_MOD_NAME   := ucode_analyzer
PKG_VERSION_BASE := $(shell grep -oP 'PKG_VERSION:=\K.*' openwrt/$(PKG_NAME)/Makefile)
PKG_VERSION      := $(if $(GIT_COMMIT),$(PKG_VERSION_BASE)~$(GIT_COMMIT),$(PKG_VERSION_BASE))

SDK_MAJOR_MINOR := $(shell echo $(SDK_VERSION) | cut -d. -f1,2)
BUILD_DIR       := build/$(SDK_ARCH)/$(SDK_MAJOR_MINOR)
REPORTER        := $(if $(CI),,-r compact)

BUILD_IMAGE = docker run --rm \
	-v $(CURDIR)/src:/builder/package/$(PKG_NAME)/src:ro \
	-v $(CURDIR)/mod:/builder/package/$(PKG_NAME)/mod:ro \
	-v $(CURDIR)/test/mod:/builder/package/$(PKG_NAME)/test/mod:ro \
	-v $(CURDIR)/third_party:/builder/package/$(PKG_NAME)/third_party:ro \
	-v $(CURDIR)/$(BUILD_DIR)/$(PKG_NAME)-Makefile:/builder/package/$(PKG_NAME)/Makefile:ro \
	-v $(CURDIR)/$(BUILD_DIR):/builder/bin \
	-v $(CURDIR)/$(BUILD_DIR)/include:/builder/out_include \
	openwrt/sdk:$(SDK_ARCH)-$(SDK_VERSION)

TEST_IMAGE = docker run --rm $(TEST_OPTS) \
	-v $(CURDIR):/app \
	$(if $(wildcard $(BUILD_DIR)/tree_sitter_native.so),-v $(CURDIR)/$(BUILD_DIR)/tree_sitter_native.so:/usr/lib/ucode/tree_sitter/native.so:ro) \
	$(if $(wildcard $(BUILD_DIR)/rpc_client_native.so),-v $(CURDIR)/$(BUILD_DIR)/rpc_client_native.so:/usr/lib/ucode/rpc_client/native.so:ro) \
	-w /app \
	$(IMAGE)

.PHONY: compile test test-unit test-e2e test-integration lint shell package

.docker-image: Dockerfile
	@docker build \
		--build-arg SDK_ARCH=$(SDK_ARCH) \
		--build-arg SDK_VERSION=$(SDK_VERSION) \
		-t $(IMAGE) .
	@touch .docker-image

compile: $(BUILD_DIR)/tree_sitter_native.so mod/compile_flags.txt test/mod/compile_flags.txt

$(BUILD_DIR)/tree_sitter_native.so: $(shell find mod test/mod third_party/tree-sitter-ucode/common third_party/tree-sitter-ucode/bindings/c third_party/tree-sitter-ucode/*/src third_party/tree-sitter/lib/src -name '*.c' -o -name '*.h') third_party/tree-sitter-ucode/CMakeLists.txt openwrt/$(PKG_NAME)/Makefile
	@mkdir -p $(BUILD_DIR)/include
	@chmod 777 $(BUILD_DIR) $(BUILD_DIR)/include
	@sed 's/PKG_VERSION:=.*/PKG_VERSION:=$(PKG_VERSION)/' \
		openwrt/$(PKG_NAME)/Makefile > $(BUILD_DIR)/$(PKG_NAME)-Makefile
	@$(BUILD_IMAGE) \
		sh -c " \
			./scripts/feeds update base && \
			./scripts/feeds install ucode && \
			make defconfig && \
			printf 'CONFIG_PACKAGE_%s=y\n' ucode-mod-tree-sitter ucode-analyzer-test-client ucode-analyzer-core ucode-analyzer >> .config && \
			make defconfig && \
			make package/$(PKG_NAME)/compile V=s && \
			find /builder/build_dir -path '*/tree_sitter/native.so' \
				-exec cp {} /builder/bin/tree_sitter_native.so \; -quit && \
			find /builder/build_dir -path '*/rpc_client/native.so' \
				-exec cp {} /builder/bin/rpc_client_native.so \; -quit && \
			test -f /builder/bin/tree_sitter_native.so && \
			test -f /builder/bin/rpc_client_native.so && \
			cp -fpR /builder/staging_dir/target-*/usr/include/* /builder/out_include/ \
		"; EC=$$?; rm -f $(BUILD_DIR)/$(PKG_NAME)-Makefile; exit $$EC

# clangd compile flags for the native C sources (mod/ ships modules, test/mod/
# holds the test-only rpc_client). Same include set; the extra tree-sitter paths
# are harmless for rpc_client. -Wno-unused-parameter as in ucode's own build:
# every native function takes (uc_vm_t *vm, size_t nargs), used or not.
define gen_compile_flags
	@printf -- '-I%s\n-I%s\n-I%s\n-Wall\n-Wextra\n-Wno-unused-parameter\n-Werror\n-std=gnu99\n' \
		"$(CURDIR)/$(BUILD_DIR)/include" \
		"$(CURDIR)/third_party/tree-sitter/lib/include" \
		"$(CURDIR)/third_party/tree-sitter-ucode/bindings/c" > $@
endef

mod/compile_flags.txt: $(BUILD_DIR)/include
	$(gen_compile_flags)

test/mod/compile_flags.txt: $(BUILD_DIR)/include
	$(gen_compile_flags)

test: test-unit test-integration test-e2e

test-unit: .docker-image $(BUILD_DIR)/tree_sitter_native.so
	@$(TEST_IMAGE) utest -c test/utest.config.uc $(REPORTER) \
		test/unit/ \
		test/unit/linter/ \
		test/unit/code_analysis/ \
		test/unit/code_analysis/dag/ \
		test/unit/code_analysis/diagnostics/ \
		test/unit/code_analysis/types/ \
		test/unit/language_server/ \
		test/unit/language_server/handlers/ \
		test/unit/language_server/handlers/code_actions/

test-e2e: .docker-image $(BUILD_DIR)/tree_sitter_native.so
	@$(TEST_IMAGE) utest -c test/utest.config.uc $(REPORTER) -j 8 test/e2e/language_server/

test-integration: .docker-image $(BUILD_DIR)/tree_sitter_native.so
	@$(TEST_IMAGE) utest -c test/integration/language_server/utest.config.uc $(REPORTER) test/integration/language_server/
	@$(TEST_IMAGE) utest -c test/integration/tree_sitter/utest.config.uc $(REPORTER) test/integration/tree_sitter/

# Self-lint the repo with its own linter (`ucode-analyzer lint`), using the committed shared
# config at .lsp/config.json. Fails on any error or warning, enforcing the
# zero-diagnostics invariant. Only needs the tree-sitter native module.
lint: .docker-image $(BUILD_DIR)/tree_sitter_native.so
	@$(TEST_IMAGE) ucode -L /app/src /app/src/ucode-analyzer.uc lint --workspace /app --fail-on=warning

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
			printf 'CONFIG_PACKAGE_%s=y\n' ucode-mod-tree-sitter ucode-analyzer-core ucode-analyzer >> .config && \
			make defconfig && \
			make package/$(PKG_NAME)/compile V=s \
		"; EC=$$?; rm -f $(BUILD_DIR)/$(PKG_NAME)-Makefile; exit $$EC
