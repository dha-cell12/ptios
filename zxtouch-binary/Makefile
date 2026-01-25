#export THEOS_DEVICE_IP = 192.168.101.245

include $(THEOS)/makefiles/common.mk

TOOL_NAME = zxtouchd zxtouchb
zxtouchd_ARCH = arm64e arm64
zxtouchb_ARCH = arm64e arm64

zxtouchd_FILES = main.mm SocketServer.mm ../pccontrol/TemplateMatch.xm ../pccontrol/TextRecognization/VKOcrManager.xm
zxtouchb_FILES = main.mm SocketServer.mm
zxtouchd_FRAMEWORKS = CoreFoundation UIKit CoreGraphics CoreImage Vision ImageIO AVFoundation CoreMedia CoreVideo
zxtouchb_FRAMEWORKS = CoreFoundation UIKit CoreGraphics
zxtouchd_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -s -DNDEBUG -DZX_DAEMON=1
zxtouchb_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -s -DNDEBUG

zxtouchd_CCFLAGS = -std=c++11 -DZX_DAEMON=1
zxtouchd_CFLAGS += -F$(THEOS_PROJECT_DIR)/frameworks -DZX_DAEMON=1
zxtouchd_LDFLAGS += -F$(THEOS_PROJECT_DIR)/frameworks
zxtouchd_CFLAGS += -I$(THEOS_PROJECT_DIR)/frameworks/opencv2.framework/Versions/A/Headers -DZX_DAEMON=1
zxtouchd_CCFLAGS += -I$(THEOS_PROJECT_DIR)/frameworks/opencv2.framework/Versions/A/Headers -DZX_DAEMON=1
zxtouchd_EXTRA_FRAMEWORKS = opencv2

zxtouchb_CCFLAGS = -std=c++11

include $(THEOS_MAKE_PATH)/tool.mk
