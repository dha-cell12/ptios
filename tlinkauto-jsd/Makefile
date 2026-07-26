include $(THEOS)/makefiles/common.mk

TLINK_LICENSE_FORCE_ENFORCEMENT ?= 0

TOOL_NAME = tlinkauto-jsd
tlinkauto-jsd_ARCHS = arm64e arm64
tlinkauto-jsd_FILES = main.mm TLinkJSHelperServer.mm ../pccontrol/jsruntime/TLinkJSHelperProtocol.mm ../shared/TLinkJSFileHandle.mm ../shared/TLinkRootfullLicenseBuild.mm ../shared/TLinkLicenseVerifier.mm ../shared/TLinkRootfullLicensePolicy.mm
tlinkauto-jsd_CFLAGS = -fobjc-arc -Wno-error -O2 -s -DNDEBUG -DTLINK_LICENSE_FORCE_ENFORCEMENT=$(TLINK_LICENSE_FORCE_ENFORCEMENT) -DTLINK_LICENSE_ROOTFULL_RUNTIME=1
tlinkauto-jsd_CCFLAGS = -std=c++14
tlinkauto-jsd_FRAMEWORKS = Foundation JavaScriptCore Security
tlinkauto-jsd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
