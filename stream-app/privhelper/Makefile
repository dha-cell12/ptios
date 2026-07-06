# privhelper - narrow root helper for TrollStore-only admin tasks.
#
# MVP scope: kill stale streamd processes that keep tcp/6000 bound across app
# upgrades. Broader app-data/keychain work stays for later phases.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = privhelper

privhelper_FILES = main.mm
privhelper_FRAMEWORKS = Foundation
privhelper_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c
privhelper_CCFLAGS = -std=c++14
privhelper_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
