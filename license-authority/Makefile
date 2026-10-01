include $(THEOS)/makefiles/common.mk

TLINK_LICENSE_FORCE_ENFORCEMENT ?= 0
TLINK_ROOTHIDE_RUNTIME ?= 0

TOOL_NAME = tlinkauto-licensed

tlinkauto-licensed_FILES = main.mm ../shared/TLinkLicenseVerifier.mm ../shared/TLinkRootfullLicenseBuild.mm
tlinkauto-licensed_FRAMEWORKS = Foundation CoreFoundation Security
tlinkauto-licensed_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -s -DNDEBUG -DTLINK_LICENSE_ROOTFULL_RUNTIME=1 -DTLINK_LICENSE_FORCE_ENFORCEMENT=$(TLINK_LICENSE_FORCE_ENFORCEMENT) -DTLINK_ROOTHIDE_RUNTIME=$(TLINK_ROOTHIDE_RUNTIME)
tlinkauto-licensed_CCFLAGS = -std=c++14
tlinkauto-licensed_CODESIGN_FLAGS = -S../layout/license-authority-entitlements.plist
ifeq ($(TLINK_ROOTHIDE_RUNTIME),1)
tlinkauto-licensed_CODESIGN_FLAGS = -S../layout/license-authority-entitlements-roothide.plist
endif
tlinkauto-licensed_INSTALL_PATH = /usr/libexec
tlinkauto-licensed_ARCHS = $(ARCHS)

include $(THEOS_MAKE_PATH)/tool.mk
