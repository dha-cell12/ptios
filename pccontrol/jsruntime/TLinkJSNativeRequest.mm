#import "TLinkJSNativeRequest.h"

NSString * const TLinkJSNativeMethodRawTask = @"rawTask";
NSString * const TLinkJSNativeMethodToast = @"toast";
NSString * const TLinkJSNativeMethodTap = @"tap";
NSString * const TLinkJSNativeMethodSwipe = @"swipe";
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
NSString * const TLinkJSNativeMethodOpenImage = @"openImage";
NSString * const TLinkJSNativeMethodCaptureImage = @"captureImage";
NSString * const TLinkJSNativeMethodReleaseImage = @"releaseImage";
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
