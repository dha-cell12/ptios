#import "TLinkJSNativeRequest.h"

NSString * const TLinkJSNativeMethodRawTask = @"rawTask";
NSString * const TLinkJSNativeMethodToast = @"toast";
NSString * const TLinkJSNativeMethodTap = @"tap";
NSString * const TLinkJSNativeMethodSwipe = @"swipe";
NSString * const TLinkJSNativeMethodLongPress = @"longPress";
NSString * const TLinkJSNativeMethodGesture = @"gesture";
NSString * const TLinkJSNativeMethodPickColor = @"pickColor";
NSString * const TLinkJSNativeMethodScreenshotRegion = @"screenshotRegion";
NSString * const TLinkJSNativeMethodBatch = @"batch";
NSString * const TLinkJSNativeMethodRunShell = @"runShell";
NSString * const TLinkJSNativeMethodReadText = @"readText";
NSString * const TLinkJSNativeMethodWriteText = @"writeText";
NSString * const TLinkJSNativeMethodReadJSON = @"readJSON";
NSString * const TLinkJSNativeMethodWriteJSON = @"writeJSON";
NSString * const TLinkJSNativeMethodFileExists = @"fileExists";
NSString * const TLinkJSNativeMethodDeleteFile = @"deleteFile";
NSString * const TLinkJSNativeMethodScreenshotTo = @"screenshotTo";
NSString * const TLinkJSNativeMethodCaptureFrame = @"captureFrame";
NSString * const TLinkJSNativeMethodReleaseFrame = @"releaseFrame";
NSString * const TLinkJSNativeMethodReleaseAllFrames = @"releaseAllFrames";
NSString * const TLinkJSNativeMethodOpenImage = @"openImage";
NSString * const TLinkJSNativeMethodCaptureImage = @"captureImage";
NSString * const TLinkJSNativeMethodReleaseImage = @"releaseImage";
NSString * const TLinkJSNativeMethodFramePickColor = @"framePickColor";
NSString * const TLinkJSNativeMethodFramePickColors = @"framePickColors";
NSString * const TLinkJSNativeMethodFrameFindColor = @"frameFindColor";
NSString * const TLinkJSNativeMethodFrameIsColors = @"frameIsColors";
NSString * const TLinkJSNativeMethodFrameFindMultiColor = @"frameFindMultiColor";
NSString * const TLinkJSNativeMethodFindImageInFrame = @"findImageInFrame";
NSString * const TLinkJSNativeMethodOcrLanguages = @"ocrLanguages";
NSString * const TLinkJSNativeMethodOcrFrame = @"ocrFrame";
NSString * const TLinkJSNativeMethodOcr = @"ocr";
NSString * const TLinkJSNativeMethodFrontMostAppId = @"frontMostAppId";
NSString * const TLinkJSNativeMethodOrientation = @"orientation";
NSString * const TLinkJSNativeMethodOpenApp = @"openApp";
NSString * const TLinkJSNativeMethodKillApp = @"killApp";
NSString * const TLinkJSNativeMethodAppState = @"appState";
NSString * const TLinkJSNativeMethodAppInfo = @"appInfo";
NSString * const TLinkJSNativeMethodAppPid = @"appPid";
NSString * const TLinkJSNativeMethodFrontMostPid = @"frontMostPid";
NSString * const TLinkJSNativeMethodAppPaths = @"appPaths";
NSString * const TLinkJSNativeMethodListBundles = @"listBundles";
NSString * const TLinkJSNativeMethodOpenUrl = @"openUrl";
NSString * const TLinkJSNativeMethodConnectivity = @"connectivity";
NSString * const TLinkJSNativeMethodRootDir = @"rootDir";
NSString * const TLinkJSNativeMethodCurrentDir = @"currentDir";
NSString * const TLinkJSNativeMethodBotPath = @"botPath";
NSString * const TLinkJSNativeMethodInfo = @"info";
NSString * const TLinkJSNativeMethodBatteryInfo = @"batteryInfo";
NSString * const TLinkJSNativeMethodMatchTemplate = @"matchTemplate";
NSString * const TLinkJSNativeMethodFindColor = @"findColor";
NSString * const TLinkJSNativeMethodIsColors = @"isColors";
NSString * const TLinkJSNativeMethodFindMultiColor = @"findMultiColor";
NSString * const TLinkJSNativeMethodGetScreenSize = @"getScreenSize";

@implementation TLinkJSNativeRequest

- (instancetype)initWithMethod:(NSString *)method arguments:(NSArray *)arguments {
    self = [super init];
    if (self) {
        _method = [method copy];
        _arguments = [arguments copy];
    }
    return self;
}

@end
