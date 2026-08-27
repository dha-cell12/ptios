# TLinkUIService - compositor-hosted passthrough toast service for TrollStore.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = TLinkUIService

TLinkUIService_FILES = main.mm
TLinkUIService_FRAMEWORKS = Foundation UIKit CoreFoundation QuartzCore
TLinkUIService_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c
TLinkUIService_CCFLAGS = -std=c++14
TLinkUIService_CODESIGN_FLAGS = -Sentitlements.plist
TLinkUIService_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
