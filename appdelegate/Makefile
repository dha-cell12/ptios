#export THEOS_DEVICE_IP = 192.168.0.6

include $(THEOS)/makefiles/common.mk

TLINK_LICENSE_FORCE_ENFORCEMENT ?= 0

TWEAK_NAME = appdelegate

appdelegate_FILES = Tweak.xm UIKeyboard.xm ../shared/TLinkRootfullLicenseBuild.mm
appdelegate_CFLAGS = -Wno-error -Wno-module-import-in-extern-c -fobjc-arc -DTLINK_LICENSE_FORCE_ENFORCEMENT=$(TLINK_LICENSE_FORCE_ENFORCEMENT)

appdelegate_ARCHS = arm64e arm64
appdelegate_FRAMEWORKS = UIKit
#appdelegate_CCFLAGS = -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk
