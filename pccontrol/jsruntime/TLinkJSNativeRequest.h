#ifndef TLINK_JS_NATIVE_REQUEST_H
#define TLINK_JS_NATIVE_REQUEST_H

#import <Foundation/Foundation.h>

extern NSString * const TLinkJSNativeMethodRawTask;
extern NSString * const TLinkJSNativeMethodToast;
extern NSString * const TLinkJSNativeMethodTap;
extern NSString * const TLinkJSNativeMethodSwipe;
extern NSString * const TLinkJSNativeMethodLongPress;
extern NSString * const TLinkJSNativeMethodGesture;
extern NSString * const TLinkJSNativeMethodZoom;
extern NSString * const TLinkJSNativeMethodPickColor;
extern NSString * const TLinkJSNativeMethodScreenshotRegion;
extern NSString * const TLinkJSNativeMethodBatch;
extern NSString * const TLinkJSNativeMethodRunShell;
extern NSString * const TLinkJSNativeMethodReadText;
extern NSString * const TLinkJSNativeMethodWriteText;
extern NSString * const TLinkJSNativeMethodReadJSON;
extern NSString * const TLinkJSNativeMethodWriteJSON;
extern NSString * const TLinkJSNativeMethodFileExists;
extern NSString * const TLinkJSNativeMethodDeleteFile;
extern NSString * const TLinkJSNativeMethodScreenshotTo;
extern NSString * const TLinkJSNativeMethodCaptureFrame;
extern NSString * const TLinkJSNativeMethodReleaseFrame;
extern NSString * const TLinkJSNativeMethodReleaseAllFrames;
extern NSString * const TLinkJSNativeMethodOpenImage;
extern NSString * const TLinkJSNativeMethodCaptureImage;
extern NSString * const TLinkJSNativeMethodReleaseImage;
extern NSString * const TLinkJSNativeMethodFramePickColor;
extern NSString * const TLinkJSNativeMethodFramePickColors;
extern NSString * const TLinkJSNativeMethodFrameFindColor;
extern NSString * const TLinkJSNativeMethodFrameIsColors;
extern NSString * const TLinkJSNativeMethodFrameFindMultiColor;
extern NSString * const TLinkJSNativeMethodFindImageInFrame;
extern NSString * const TLinkJSNativeMethodOcrLanguages;
extern NSString * const TLinkJSNativeMethodOcrFrame;
extern NSString * const TLinkJSNativeMethodOcr;
extern NSString * const TLinkJSNativeMethodFrontMostAppId;
extern NSString * const TLinkJSNativeMethodOrientation;
extern NSString * const TLinkJSNativeMethodOpenApp;
extern NSString * const TLinkJSNativeMethodKillApp;
extern NSString * const TLinkJSNativeMethodAppState;
extern NSString * const TLinkJSNativeMethodAppInfo;
extern NSString * const TLinkJSNativeMethodAppPid;
extern NSString * const TLinkJSNativeMethodFrontMostPid;
extern NSString * const TLinkJSNativeMethodAppPaths;
extern NSString * const TLinkJSNativeMethodListBundles;
extern NSString * const TLinkJSNativeMethodOpenUrl;
extern NSString * const TLinkJSNativeMethodConnectivity;
extern NSString * const TLinkJSNativeMethodRootDir;
extern NSString * const TLinkJSNativeMethodCurrentDir;
extern NSString * const TLinkJSNativeMethodBotPath;
extern NSString * const TLinkJSNativeMethodInfo;
extern NSString * const TLinkJSNativeMethodBatteryInfo;
extern NSString * const TLinkJSNativeMethodAlert;
extern NSString * const TLinkJSNativeMethodDialog;
extern NSString * const TLinkJSNativeMethodClearDialogValues;
extern NSString * const TLinkJSNativeMethodKeyboard;
extern NSString * const TLinkJSNativeMethodHardwareKey;
extern NSString * const TLinkJSNativeMethodPressHardwareKey;
extern NSString * const TLinkJSNativeMethodKeepAwake;
extern NSString * const TLinkJSNativeMethodTouchIndicator;
extern NSString * const TLinkJSNativeMethodSaveScreenshotToAlbum;
extern NSString * const TLinkJSNativeMethodClearScreenshotAlbum;
extern NSString * const TLinkJSNativeMethodSetAutoLaunch;
extern NSString * const TLinkJSNativeMethodListAutoLaunch;
extern NSString * const TLinkJSNativeMethodSetTimer;
extern NSString * const TLinkJSNativeMethodRemoveTimer;
extern NSString * const TLinkJSNativeMethodMatchTemplate;
extern NSString * const TLinkJSNativeMethodFindColor;
extern NSString * const TLinkJSNativeMethodIsColors;
extern NSString * const TLinkJSNativeMethodFindMultiColor;
extern NSString * const TLinkJSNativeMethodGetScreenSize;

@interface TLinkJSNativeRequest : NSObject

@property(nonatomic, copy) NSString *method;
@property(nonatomic, copy) NSArray *arguments;
@property(nonatomic, strong) NSNumber *deadlineMs; // optional
@property(nonatomic, copy) NSString *sessionId; // optional
@property(nonatomic, copy) NSDictionary *metadata; // optional

- (instancetype)initWithMethod:(NSString *)method arguments:(NSArray *)arguments;

@end

#endif
