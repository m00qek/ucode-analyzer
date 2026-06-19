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
	$(INSTALL_DIR) $(1)/usr/lib/ucode/$(UCODE_MOD_NAME)
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/$(UCODE_MOD_NAME)/native.so \
		$(1)/usr/lib/ucode/$(UCODE_MOD_NAME)/native.so
	$(INSTALL_DIR) $(1)/usr/lib/ucode
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/spawn_pipes.so \
		$(1)/usr/lib/ucode/spawn_pipes.so
	$(INSTALL_DIR) $(1)/usr/share/ucode/$(UCODE_MOD_NAME)
	$(CP) ./src/$(UCODE_MOD_NAME)/* $(1)/usr/share/ucode/$(UCODE_MOD_NAME)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
