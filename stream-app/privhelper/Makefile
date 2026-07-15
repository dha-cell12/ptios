# privhelper - narrow root helper for TrollStore-only admin tasks.
#
# Scope: kill stale streamd processes that keep tcp/6000 bound across app
# upgrades, open/kill apps, open URLs, ensure streamd, and clear safe app data
# containers. Keychain work stays deferred because arbitrary target keychain
# groups require separate entitlement/access-group handling.

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
