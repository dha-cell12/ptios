include $(THEOS)/makefiles/common.mk

TOOL_NAME = tlinkauto-jsd
tlinkauto-jsd_ARCHS = arm64e arm64
tlinkauto-jsd_FILES = main.mm TLinkJSHelperServer.mm ../pccontrol/jsruntime/TLinkJSHelperProtocol.mm ../shared/TLinkJSFileHandle.mm
tlinkauto-jsd_CFLAGS = -fobjc-arc -Wno-error -O2 -s -DNDEBUG
tlinkauto-jsd_CCFLAGS = -std=c++14
tlinkauto-jsd_FRAMEWORKS = Foundation JavaScriptCore
tlinkauto-jsd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
