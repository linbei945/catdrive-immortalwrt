include $(TOPDIR)/rules.mk

PKG_NAME:=wget-any
PKG_VERSION:=1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/wget-any
  SECTION:=net
  CATEGORY:=Network
  TITLE:=wget provider alias (uclient-fetch)
  DEPENDS:=+uclient-fetch
endef

define Package/wget-any/description
  Virtual package satisfying luci-theme-argon dependency via uclient-fetch.
endef

$(eval $(call BuildPackage,wget-any))
