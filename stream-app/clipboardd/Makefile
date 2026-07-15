# clipboardd - persistent UIKit clipboard bridge for TrollStore.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = clipboardd

clipboardd_FILES = main.mm
clipboardd_FRAMEWORKS = Foundation UIKit CoreFoundation UserNotifications QuartzCore
clipboardd_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c
clipboardd_CCFLAGS = -std=c++14
clipboardd_CODESIGN_FLAGS = -Sentitlements.plist
clipboardd_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
