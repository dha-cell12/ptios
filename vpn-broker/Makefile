include $(THEOS)/makefiles/common.mk

TLINK_LICENSE_FORCE_ENFORCEMENT ?= 0

TOOL_NAME = tlinkauto-vpnd

tlinkauto-vpnd_FILES = main.mm ../shared/TLinkVPNManager.mm ../shared/TLinkVPNDiagnostics.mm ../shared/TLinkLicenseVerifier.mm ../shared/TLinkLicenseAuthorityClient.mm ../shared/TLinkRootfullLicenseBuild.mm
tlinkauto-vpnd_FRAMEWORKS = Foundation CoreFoundation NetworkExtension Security
tlinkauto-vpnd_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -DTLINK_LICENSE_ROOTFULL_RUNTIME=1 -DTLINK_LICENSE_FORCE_ENFORCEMENT=$(TLINK_LICENSE_FORCE_ENFORCEMENT) -DTLINK_LICENSE_AUTHORITY_CLIENT=1
tlinkauto-vpnd_CCFLAGS = -std=c++14
tlinkauto-vpnd_CODESIGN_FLAGS = -S../layout/entitlements.plist
tlinkauto-vpnd_INSTALL_PATH = /usr/libexec
tlinkauto-vpnd_ARCHS = arm64e arm64

include $(THEOS_MAKE_PATH)/tool.mk
