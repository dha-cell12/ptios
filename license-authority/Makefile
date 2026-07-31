include $(THEOS)/makefiles/common.mk

TLINK_LICENSE_FORCE_ENFORCEMENT ?= 0

TOOL_NAME = tlinkauto-licensed

tlinkauto-licensed_FILES = main.mm ../shared/TLinkLicenseVerifier.mm ../shared/TLinkRootfullLicenseBuild.mm
tlinkauto-licensed_FRAMEWORKS = Foundation CoreFoundation Security
tlinkauto-licensed_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -s -DNDEBUG -DTLINK_LICENSE_ROOTFULL_RUNTIME=1 -DTLINK_LICENSE_FORCE_ENFORCEMENT=$(TLINK_LICENSE_FORCE_ENFORCEMENT)
tlinkauto-licensed_CCFLAGS = -std=c++14
tlinkauto-licensed_CODESIGN_FLAGS = -S../layout/license-authority-entitlements.plist
tlinkauto-licensed_INSTALL_PATH = /usr/libexec
tlinkauto-licensed_ARCHS = arm64e arm64

include $(THEOS_MAKE_PATH)/tool.mk
