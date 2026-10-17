include $(TOPDIR)/rules.mk

PKG_NAME:=ucode-analyzer
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

UCODE_MOD_NAME:=ucode_analyzer
CMAKE_OPTIONS += -DPKG_NAME=$(UCODE_MOD_NAME)

# One source tree, four packages. The analysis engine (ucode-analyzer-core) is
# shared; ucode-analyzer is the `ucode-analyzer` command, whose language server
# and linter are thin frontends over it. The native C extensions are split by
# consumer so each package installs only what it runs. Everything but the
# tree-sitter binding lives under the ucode_analyzer module namespace.
#
# DEPENDS lists every ucode module a package imports (ucode-mod-fs, -uloop,
# -io, …): OpenWrt splits ucode's modules into separate packages, and a base
# image is not guaranteed to have them. ucode-docopt (command-line parsing for
# the command) comes from the packages.ucode.dev feed, not OpenWrt's.

# ---- Native modules (C extensions) --------------------------------------

define Package/ucode-mod-tree-sitter
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=tree-sitter parser binding for ucode
  DEPENDS:=+ucode +libucode
endef

define Package/ucode-mod-tree-sitter/description
  Native tree-sitter binding (with the ucode grammar) plus its ucode wrapper.
  The shared parser used by both the language server and the linter.
endef

define Package/ucode-analyzer-test-client
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Test-only RPC client native module for ucode-analyzer
  DEPENDS:=+ucode +libucode
endef

define Package/ucode-analyzer-test-client/description
  JSON-RPC client primitives (spawn/read_raw/write_raw/close) used only by
  ucode-analyzer's end-to-end test harness. Not needed at runtime.
endef

# ---- Pure ucode packages ------------------------------------------------

define Package/ucode-analyzer-core
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Static analysis engine for ucode
  DEPENDS:=+ucode +libucode +ucode-mod-tree-sitter +ucode-mod-fs +ucode-mod-uloop
endef

define Package/ucode-analyzer-core/description
  Shared static-analysis engine for ucode: cross-file dependency graph,
  scope/type inference and diagnostics, plus the builtin module declarations.
endef

define Package/ucode-analyzer
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Language server and linter for ucode
  DEPENDS:=+ucode +libucode +ucode-analyzer-core +ucode-mod-fs +ucode-mod-io \
    +ucode-mod-uloop +ucode-docopt
endef

define Package/ucode-analyzer/description
  The ucode-analyzer command, written in ucode itself: a Language Server
  Protocol implementation (hover, completion, diagnostics, rename, code actions
  and more) and, as `ucode-analyzer lint`, a linter for files or a workspace.
endef

# ---- Build --------------------------------------------------------------

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./mod/* $(PKG_BUILD_DIR)/
	# rpc_client is a test-only native module; its source lives under test/mod/
	# but is flattened into the build dir alongside mod/ so CMakeLists resolves
	# it at the same relative path (rpc_client/native.c).
	$(CP) ./test/mod/* $(PKG_BUILD_DIR)/
	$(CP) ./third_party $(PKG_BUILD_DIR)/
endef

# ---- Install ------------------------------------------------------------

define Package/ucode-mod-tree-sitter/install
	$(INSTALL_DIR) $(1)/usr/lib/ucode/tree_sitter
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/tree_sitter/native.so \
		$(1)/usr/lib/ucode/tree_sitter/native.so
	$(INSTALL_DIR) $(1)/usr/share/ucode
	$(INSTALL_DATA) ./src/tree_sitter.uc $(1)/usr/share/ucode/tree_sitter.uc
endef

define Package/ucode-analyzer-test-client/install
	$(INSTALL_DIR) $(1)/usr/lib/ucode/rpc_client
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/rpc_client/native.so \
		$(1)/usr/lib/ucode/rpc_client/native.so
endef

define Package/ucode-analyzer-core/install
	$(INSTALL_DIR) $(1)/usr/share/ucode/ucode_analyzer/code_analysis
	$(CP) ./src/ucode_analyzer/code_analysis/* $(1)/usr/share/ucode/ucode_analyzer/code_analysis/
	$(INSTALL_DIR) $(1)/usr/share/ucode/ucode_analyzer/declarations
	$(CP) ./src/ucode_analyzer/declarations/*.d.uc $(1)/usr/share/ucode/ucode_analyzer/declarations/
endef

define Package/ucode-analyzer/install
	$(INSTALL_DIR) $(1)/usr/share/ucode/ucode_analyzer
	$(CP) ./src/ucode_analyzer/cli ./src/ucode_analyzer/language_server \
		./src/ucode_analyzer/linter $(1)/usr/share/ucode/ucode_analyzer/
	$(INSTALL_BIN) ./src/ucode-analyzer.uc $(1)/usr/share/ucode/ucode-analyzer.uc
	$(INSTALL_DIR) $(1)/usr/bin
	ln -sf /usr/share/ucode/ucode-analyzer.uc $(1)/usr/bin/ucode-analyzer
endef

$(eval $(call BuildPackage,ucode-mod-tree-sitter))
$(eval $(call BuildPackage,ucode-analyzer-test-client))
$(eval $(call BuildPackage,ucode-analyzer-core))
$(eval $(call BuildPackage,ucode-analyzer))
