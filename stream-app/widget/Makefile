# TLinkBootWidget - WidgetKit wake trigger for the TrollStore build.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = TLinkBootWidget

TLinkBootWidget_FILES = TLinkBootWidget.swift TLinkWidgetWakeHelper.m
TLinkBootWidget_BUNDLE_EXTENSION = appex
TLinkBootWidget_DYNAMIC_LIBRARY = 0
TLinkBootWidget_INSTALL_PATH = /Applications/StreamControl.app/PlugIns
TLinkBootWidget_RESOURCE_FILES = Info.plist
TLinkBootWidget_FRAMEWORKS = Foundation SwiftUI WidgetKit
TLinkBootWidget_CFLAGS = -fobjc-arc
TLinkBootWidget_SWIFT_VERSION = 5
TLinkBootWidget_APP_EXTENSION_SAFE_API = 1
TLinkBootWidget_APP_EXTENSION_SAFE = 1
TLinkBootWidget_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/bundle.mk
