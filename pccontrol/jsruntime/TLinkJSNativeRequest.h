#ifndef TLINK_JS_NATIVE_REQUEST_H
#define TLINK_JS_NATIVE_REQUEST_H

#import <Foundation/Foundation.h>

extern NSString * const TLinkJSNativeMethodRawTask;
extern NSString * const TLinkJSNativeMethodToast;
extern NSString * const TLinkJSNativeMethodTap;
extern NSString * const TLinkJSNativeMethodSwipe;
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
extern NSString * const TLinkJSNativeMethodOpenImage;
extern NSString * const TLinkJSNativeMethodCaptureImage;
extern NSString * const TLinkJSNativeMethodReleaseImage;
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
