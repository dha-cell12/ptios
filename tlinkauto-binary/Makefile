#export THEOS_DEVICE_IP = 192.168.101.245

include $(THEOS)/makefiles/common.mk

TLINKAUTO_FILE_LOG ?= 0
TLINK_LICENSE_FORCE_ENFORCEMENT ?= 0

TOOL_NAME = tlinkautod tlinkautob
tlinkautod_ARCH = arm64e arm64
tlinkautob_ARCH = arm64e arm64

tlinkautod_FILES = main.mm SocketServer.mm ../pccontrol/TemplateMatch.xm ../pccontrol/TextRecognization/VKOcrManager.xm ../shared/TLinkAdaptiveStreaming.mm ../shared/TLinkEventChannel.mm ../shared/TLinkRootfullLicenseBuild.mm ../shared/TLinkLicenseVerifier.mm ../shared/TLinkLicenseAuthorityClient.mm ../shared/TLinkRootfullLicensePolicy.mm
tlinkautob_FILES = main.mm SocketServer.mm ../shared/TLinkAdaptiveStreaming.mm ../shared/TLinkEventChannel.mm ../shared/TLinkRootfullLicenseBuild.mm ../shared/TLinkLicenseVerifier.mm ../shared/TLinkLicenseAuthorityClient.mm ../shared/TLinkRootfullLicensePolicy.mm
tlinkautod_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics CoreImage Vision ImageIO AVFoundation CoreMedia CoreVideo Security
tlinkautob_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics Security
tlinkautod_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -s -DNDEBUG -DZX_DAEMON=1 -DTLINKAUTO_FILE_LOG=$(TLINKAUTO_FILE_LOG) -DTLINK_LICENSE_FORCE_ENFORCEMENT=$(TLINK_LICENSE_FORCE_ENFORCEMENT) -DTLINK_LICENSE_ROOTFULL_RUNTIME=1 -DTLINK_LICENSE_AUTHORITY_CLIENT=1
tlinkautob_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -s -DNDEBUG -DTLINKAUTO_FILE_LOG=$(TLINKAUTO_FILE_LOG) -DTLINK_LICENSE_FORCE_ENFORCEMENT=$(TLINK_LICENSE_FORCE_ENFORCEMENT) -DTLINK_LICENSE_ROOTFULL_RUNTIME=1 -DTLINK_LICENSE_AUTHORITY_CLIENT=1

tlinkautod_CCFLAGS = -std=c++11 -DZX_DAEMON=1
tlinkautod_CFLAGS += -F$(THEOS_PROJECT_DIR)/frameworks -DZX_DAEMON=1
tlinkautod_LDFLAGS += -F$(THEOS_PROJECT_DIR)/frameworks
tlinkautod_CFLAGS += -I$(THEOS_PROJECT_DIR)/frameworks/opencv2.framework/Versions/A/Headers -DZX_DAEMON=1
tlinkautod_CCFLAGS += -I$(THEOS_PROJECT_DIR)/frameworks/opencv2.framework/Versions/A/Headers -DZX_DAEMON=1
tlinkautod_EXTRA_FRAMEWORKS = opencv2

tlinkautob_CCFLAGS = -std=c++11

include $(THEOS_MAKE_PATH)/tool.mk
