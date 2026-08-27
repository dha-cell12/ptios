# StreamControl - TrollStore app: UI + supervisor that spawns streamd.
#
# Builds a standalone iOS application (NOT a tweak), packaged for TrollStore.
# The streamd binary is bundled inside StreamControl.app so the supervisor can
# spawn it by relative path.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = StreamControl

StreamControl_FILES = main.mm AppDelegate.mm TLinkTheme.mm TLinkLogStore.mm DashboardViewController.mm ServiceLogViewController.mm BackgroundServiceScheduler.mm StreamSupervisor.mm TLinkSocketClient.mm ScriptsViewController.mm ScriptEditorViewController.mm ScriptLogViewController.mm ImageViewerViewController.mm PlaySettingsViewController.mm BootScriptViewController.mm SettingsViewController.mm LicenseManager.mm LicenseLifecycleCoordinator.mm LicenseViewController.mm TLinkVPNForegroundBroker.mm ../../TLinkauto/TLinkauto/Settings/TLinkVPNSettingsViewController.m ../../shared/TLinkVPNManager.mm ../../shared/TLinkVPNDiagnostics.mm ../../shared/TLinkLicenseVerifier.mm
StreamControl_RESOURCE_FILES = Info.plist LicenseConfig.plist
StreamControl_RESOURCE_DIRS = CompatibilityExamples
StreamControl_FRAMEWORKS = UIKit CoreFoundation CoreGraphics QuartzCore Vision CoreML ImageIO Photos UserNotifications BackgroundTasks Security NetworkExtension
StreamControl_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -DTLINK_VPN_TROLLSTORE_RUNTIME=1
StreamControl_CCFLAGS = -std=c++14
ifeq ($(TLINK_LICENSE_FORCE_ENFORCEMENT),1)
StreamControl_CFLAGS += -DTLINK_LICENSE_FORCE_ENFORCEMENT=1
endif
StreamControl_CODESIGN_FLAGS = -Sentitlements.plist
StreamControl_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
