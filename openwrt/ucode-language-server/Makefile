include $(TOPDIR)/rules.mk

PKG_NAME:=ucode-language-server
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

UCODE_MOD_NAME:=ucode_language_server
CMAKE_OPTIONS += -DPKG_NAME=$(UCODE_MOD_NAME)

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Language Server Protocol implementation for ucode
  DEPENDS:=+ucode +libucode
endef

define Package/$(PKG_NAME)/description
  A Language Server Protocol implementation for ucode, written in ucode
  itself, with a native C extension for tree-sitter parsing.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./mod/* $(PKG_BUILD_DIR)/
	$(CP) ./third_party $(PKG_BUILD_DIR)/
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/ucode/tree_sitter
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/tree_sitter/native.so \
		$(1)/usr/lib/ucode/tree_sitter/native.so
	$(INSTALL_DIR) $(1)/usr/lib/ucode/rpc_client
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/rpc_client/native.so \
		$(1)/usr/lib/ucode/rpc_client/native.so
	$(INSTALL_DIR) $(1)/usr/share/ucode
	$(CP) ./src/tree_sitter.uc $(1)/usr/share/ucode/tree_sitter.uc
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
