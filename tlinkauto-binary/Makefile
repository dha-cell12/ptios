#export THEOS_DEVICE_IP = 192.168.101.245

include $(THEOS)/makefiles/common.mk

TLINKAUTO_FILE_LOG ?= 0

TOOL_NAME = tlinkautod tlinkautob
tlinkautod_ARCH = arm64e arm64
tlinkautob_ARCH = arm64e arm64

tlinkautod_FILES = main.mm SocketServer.mm ../pccontrol/TemplateMatch.xm ../pccontrol/TextRecognization/VKOcrManager.xm
tlinkautob_FILES = main.mm SocketServer.mm
tlinkautod_FRAMEWORKS = CoreFoundation UIKit CoreGraphics CoreImage Vision ImageIO AVFoundation CoreMedia CoreVideo
tlinkautob_FRAMEWORKS = CoreFoundation UIKit CoreGraphics
tlinkautod_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -s -DNDEBUG -DZX_DAEMON=1 -DTLINKAUTO_FILE_LOG=$(TLINKAUTO_FILE_LOG)
tlinkautob_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -s -DNDEBUG -DTLINKAUTO_FILE_LOG=$(TLINKAUTO_FILE_LOG)

tlinkautod_CCFLAGS = -std=c++11 -DZX_DAEMON=1
tlinkautod_CFLAGS += -F$(THEOS_PROJECT_DIR)/frameworks -DZX_DAEMON=1
tlinkautod_LDFLAGS += -F$(THEOS_PROJECT_DIR)/frameworks
tlinkautod_CFLAGS += -I$(THEOS_PROJECT_DIR)/frameworks/opencv2.framework/Versions/A/Headers -DZX_DAEMON=1
tlinkautod_CCFLAGS += -I$(THEOS_PROJECT_DIR)/frameworks/opencv2.framework/Versions/A/Headers -DZX_DAEMON=1
tlinkautod_EXTRA_FRAMEWORKS = opencv2

tlinkautob_CCFLAGS = -std=c++11

include $(THEOS_MAKE_PATH)/tool.mk
