# streamd - unified click + stream daemon (NON-root).
#
# Phase 3: click/touch + capture probe + video stream paths are compiled into streamd.
# Ports 7001-7006 are opened by H264Stream.mm.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = streamd

streamd_FILES = main.mm TouchInjector.mm POCSocketServer.mm RemoteBridgeAgent.mm HIDInjectCore.mm WireProtocolParser.mm CaptureCore.mm StreamCaptureProbe.mm StreamCaptureSource.mm H264Stream.mm ../../shared/TLinkAdaptiveStreaming.mm ../../shared/TLinkEventChannel.mm ../../shared/TLinkJSFileHandle.mm ../../shared/TLinkRunHistory.mm ../../shared/TLinkVPNDiagnostics.mm ../../shared/TLinkLicenseVerifier.mm
streamd_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore IOSurface Security VideoToolbox CoreVideo CoreMedia Vision CoreML ImageIO JavaScriptCore Accelerate Photos
streamd_PRIVATE_FRAMEWORKS = IOKit
streamd_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -Iheaders
streamd_CCFLAGS = -std=c++14
ifeq ($(TLINK_LICENSE_FORCE_ENFORCEMENT),1)
streamd_CFLAGS += -DTLINK_LICENSE_FORCE_ENFORCEMENT=1
endif
TESSERACT_ROOT = $(THEOS_PROJECT_DIR)/../../third_party/TesseractOCR/TesseractOCR
streamd_CFLAGS += -I$(TESSERACT_ROOT)/xcframework/Tesseract.xcframework/ios-arm64/Headers -I$(TESSERACT_ROOT)/xcframework/Leptonica.xcframework/ios-arm64/Headers -I$(TESSERACT_ROOT)/xcframework/JPEG.xcframework/ios-arm64/Headers -I$(TESSERACT_ROOT)/xcframework/PNG.xcframework/ios-arm64/Headers -I$(TESSERACT_ROOT)/xcframework/TIFF.xcframework/ios-arm64/Headers
streamd_CCFLAGS += -I$(TESSERACT_ROOT)/xcframework/Tesseract.xcframework/ios-arm64/Headers -I$(TESSERACT_ROOT)/xcframework/Leptonica.xcframework/ios-arm64/Headers -I$(TESSERACT_ROOT)/xcframework/JPEG.xcframework/ios-arm64/Headers -I$(TESSERACT_ROOT)/xcframework/PNG.xcframework/ios-arm64/Headers -I$(TESSERACT_ROOT)/xcframework/TIFF.xcframework/ios-arm64/Headers
streamd_LDFLAGS += $(TESSERACT_ROOT)/xcframework/Tesseract.xcframework/ios-arm64/libtesseract.a $(TESSERACT_ROOT)/xcframework/Leptonica.xcframework/ios-arm64/libleptonica.a $(TESSERACT_ROOT)/xcframework/PNG.xcframework/ios-arm64/libpng16.a $(TESSERACT_ROOT)/xcframework/JPEG.xcframework/ios-arm64/libjpeg.a $(TESSERACT_ROOT)/xcframework/TIFF.xcframework/ios-arm64/libtiff.a -lz -lc++
streamd_CODESIGN_FLAGS = -Sentitlements.plist
streamd_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
