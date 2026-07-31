# vpnagent - TrollStore background NEVPNManager control agent.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = vpnagent

vpnagent_FILES = main.mm ../../shared/TLinkVPNManager.mm ../../shared/TLinkVPNDiagnostics.mm ../../shared/TLinkLicenseVerifier.mm
vpnagent_FRAMEWORKS = Foundation CoreFoundation NetworkExtension Security
vpnagent_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -DTLINK_VPN_TROLLSTORE_RUNTIME=1
vpnagent_CCFLAGS = -std=c++14
ifeq ($(TLINK_LICENSE_FORCE_ENFORCEMENT),1)
vpnagent_CFLAGS += -DTLINK_LICENSE_FORCE_ENFORCEMENT=1
endif
vpnagent_CODESIGN_FLAGS = -Sentitlements.plist
vpnagent_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
