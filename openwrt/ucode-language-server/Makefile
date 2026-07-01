include $(TOPDIR)/rules.mk

PKG_NAME:=ucode-language-server
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

UCODE_MOD_NAME:=language_server
CMAKE_OPTIONS += -DPKG_NAME=$(UCODE_MOD_NAME)

# One source tree, six packages. The analysis engine (code_analysis) is shared;
# the language server and the linter are thin frontends over it, and the native
# C extensions are split by consumer so each package installs only what it runs.

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

define Package/ucode-mod-language-server
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Raw stdin I/O native module for the ucode language server
  DEPENDS:=+ucode +libucode
endef

define Package/ucode-mod-language-server/description
  Native raw-stdin I/O primitives for the language server's uloop read loop.
endef

define Package/ucode-mod-language-server-test-client
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Test-only RPC client native module for the ucode language server
  DEPENDS:=+ucode +libucode
endef

define Package/ucode-mod-language-server-test-client/description
  JSON-RPC client primitives (spawn/read_raw/write_raw/close) used only by the
  ucode language server's end-to-end test harness. Not needed at runtime.
endef

# ---- Pure ucode packages ------------------------------------------------

define Package/ucode-code-analysis
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Static analysis engine for ucode
  DEPENDS:=+ucode +libucode +ucode-mod-tree-sitter
endef

define Package/ucode-code-analysis/description
  Shared static-analysis engine for ucode: tree-sitter wrappers, cross-file
  dependency graph, scope/type inference and diagnostics, plus the builtin
  module declarations. Consumed by both the language server and the linter.
endef

define Package/ucode-language-server
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Language Server Protocol implementation for ucode
  DEPENDS:=+ucode +libucode +ucode-code-analysis +ucode-mod-language-server
endef

define Package/ucode-language-server/description
  A Language Server Protocol implementation for ucode, written in ucode itself:
  hover, completion, diagnostics, rename, code actions and more, built on the
  shared code_analysis engine.
endef

define Package/ucode-linter
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Standalone linter for ucode
  DEPENDS:=+ucode +libucode +ucode-code-analysis
endef

define Package/ucode-linter/description
  Command-line ucode linter (file and workspace modes) built on the shared
  code_analysis engine.
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

define Package/ucode-mod-language-server/install
	$(INSTALL_DIR) $(1)/usr/lib/ucode/language_server
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/language_server/native.so \
		$(1)/usr/lib/ucode/language_server/native.so
endef

define Package/ucode-mod-language-server-test-client/install
	$(INSTALL_DIR) $(1)/usr/lib/ucode/rpc_client
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/rpc_client/native.so \
		$(1)/usr/lib/ucode/rpc_client/native.so
endef

define Package/ucode-code-analysis/install
	$(INSTALL_DIR) $(1)/usr/share/ucode/code_analysis
	$(CP) ./src/code_analysis/* $(1)/usr/share/ucode/code_analysis/
	$(INSTALL_DIR) $(1)/usr/share/ucode/declarations
	$(CP) ./src/declarations/*.d.uc $(1)/usr/share/ucode/declarations/
endef

define Package/ucode-language-server/install
	$(INSTALL_DIR) $(1)/usr/share/ucode/language_server
	$(CP) ./src/language_server/* $(1)/usr/share/ucode/language_server/
	$(INSTALL_DATA) ./src/ucode-language-server.uc \
		$(1)/usr/share/ucode/ucode-language-server.uc
	$(INSTALL_DIR) $(1)/usr/bin
	ln -sf /usr/share/ucode/ucode-language-server.uc \
		$(1)/usr/bin/ucode-language-server
endef

define Package/ucode-linter/install
	$(INSTALL_DIR) $(1)/usr/share/ucode/linter
	$(CP) ./src/linter/* $(1)/usr/share/ucode/linter/
	$(INSTALL_DATA) ./src/ucode-linter.uc \
		$(1)/usr/share/ucode/ucode-linter.uc
	$(INSTALL_DIR) $(1)/usr/bin
	ln -sf /usr/share/ucode/ucode-linter.uc \
		$(1)/usr/bin/ucode-linter
endef

$(eval $(call BuildPackage,ucode-mod-tree-sitter))
$(eval $(call BuildPackage,ucode-mod-language-server))
$(eval $(call BuildPackage,ucode-mod-language-server-test-client))
$(eval $(call BuildPackage,ucode-code-analysis))
$(eval $(call BuildPackage,ucode-language-server))
$(eval $(call BuildPackage,ucode-linter))
