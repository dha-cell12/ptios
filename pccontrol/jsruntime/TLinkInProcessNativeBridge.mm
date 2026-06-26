#import "TLinkInProcessNativeBridge.h"
#import "../Task.h"
#import "../Screen.h"
#import "../TLinkTaskContext.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

#ifndef TASK_IMAGE_OBJECT
#define TASK_IMAGE_OBJECT 48
#endif

#ifndef TASK_FRAME_CAPTURE
#define TASK_FRAME_CAPTURE 66
#endif

#ifndef TASK_FRAME_RELEASE
#define TASK_FRAME_RELEASE 67
#endif
#import "TLinkJSRuntimeCore.h"

static BOOL TLinkautoJSIsFiniteNumber(double value) { return isfinite(value); }
static const unsigned long long kTLinkautoJSMaxStorageFileBytes = 512 * 1024;
static const NSUInteger kTLinkautoJSMaxResponseBytes = 1024 * 1024;


@protocol TLinkInProcessFacadeInterface <NSObject>
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)relativePath createParent:(BOOL)createParent;
- (void)trackFrameId:(int)frameId;
- (void)untrackFrameId:(int)frameId;
- (void)trackImageId:(int)imageId;
- (void)untrackImageId:(int)imageId;
@end

@interface TLinkInProcessNativeBridge ()
- (NSDictionary *)executeRawPayload:(NSString *)payload context:(TLinkTaskExecutionContext *)context;
@end

@implementation TLinkInProcessNativeBridge

- (NSDictionary *)executeRawPayload:(NSString *)payload context:(TLinkTaskExecutionContext *)context
{
    if (![payload isKindOfClass:[NSString class]] || [payload length] == 0) {
        return @{ @"ok": @NO, @"raw": @"1;;invalid_payload\r\n", @"parts": @[@"1", @"invalid_payload"] };
    }
    BOOL cleanupRelease = [payload hasPrefix:@"67"] || [payload hasPrefix:@"483;;"];
    if ([context.cancellationToken isCancelled] && !cleanupRelease) {
        return @{ @"ok": @NO, @"raw": @"1;;AbortError\r\n", @"parts": @[@"1", @"AbortError"] };
    }
    NSString *safePayload = payload;
    if ([safePayload length] > 8192) safePayload = [safePayload substringToIndex:8192];
    NSMutableData *payloadData = [[safePayload dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (!payloadData) {
        return @{ @"ok": @NO, @"raw": @"1;;invalid_payload\r\n", @"parts": @[@"1", @"invalid_payload"] };
    }
    UInt8 zero = 0;
    [payloadData appendBytes:&zero length:1];
    CFWriteStreamRef stream = CFWriteStreamCreateWithAllocatedBuffers(kCFAllocatorDefault, kCFAllocatorDefault);
    if (!stream) {
        return @{ @"ok": @NO, @"raw": @"1;;stream_create_failed\r\n", @"parts": @[@"1", @"stream_create_failed"] };
    }
    CFWriteStreamOpen(stream);
    processTask((UInt8 *)[payloadData mutableBytes], stream);
    CFWriteStreamClose(stream);
    CFDataRef written = (CFDataRef)CFWriteStreamCopyProperty(stream, kCFStreamPropertyDataWritten);
    CFRelease(stream);
    NSData *data = CFBridgingRelease(written);
    if (!data || [data length] == 0) {
        return @{ @"ok": @YES, @"raw": @"0\r\n", @"parts": @[@"0"] };
    }
    if ([data length] > kTLinkautoJSMaxResponseBytes) {
        return @{ @"ok": @NO, @"raw": @"1;;response_too_large\r\n", @"parts": @[@"1", @"response_too_large"] };
    }
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@";;"];
    NSString *status = [parts count] > 0 ? parts[0] : @"1";
    return @{ @"ok": @([status hasPrefix:@"0"]), @"raw": raw, @"parts": parts ?: @[] };
}

- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request
                                  context:(TLinkTaskExecutionContext *)context
                                    error:(NSError **)error {
    NSString *method = request.method;
    NSArray *args = request.arguments;
    
    id<TLinkInProcessFacadeInterface> runtime = (id<TLinkInProcessFacadeInterface>)self.host;
    if (!runtime && ![method isEqualToString:TLinkJSNativeMethodRawTask]) {
        return [TLinkJSNativeResponse responseWithError:@"in-process bridge host missing" code:@-1];
    }
    if ([method isEqualToString:TLinkJSNativeMethodRawTask]) {
        NSString *payload = [args count] > 0 ? [args objectAtIndex:0] : @"";
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:payload context:context]];
    }
    
    if ([method isEqualToString:TLinkJSNativeMethodGetScreenSize]) {
        CGFloat width = [Screen getScreenWidth];
        CGFloat height = [Screen getScreenHeight];
        CGFloat scale = [UIScreen mainScreen].scale;
        int orientation = [Screen getScreenOrientation];
        NSDictionary *result = @{
            @"width": @((int)width),
            @"height": @((int)height),
            @"scale": @(scale),
            @"orientation": @(orientation),
            @"coordinateSpace": @"native-pixels",
            @"revision": @0,
        };
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodToast]) {
        NSString *message = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        NSString *safeMessage = [message isKindOfClass:[NSString class]] ? message : [message description];
        safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@";;" withString:@"; "];
        safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
        safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if ([safeMessage length] > 180) safeMessage = [safeMessage substringToIndex:180];
        if ([safeMessage length] == 0) {
            return [TLinkJSNativeResponse responseWithError:@"toast(message) requires a non-empty message" code:@-1];
        }
        int type = [options[@"type"] respondsToSelector:@selector(intValue)] ? [options[@"type"] intValue] : 3;
        int duration = [options[@"duration"] respondsToSelector:@selector(intValue)] ? [options[@"duration"] intValue] : 2;
        int position = [options[@"position"] respondsToSelector:@selector(intValue)] ? [options[@"position"] intValue] : 0;
        int fontSize = [options[@"fontSize"] respondsToSelector:@selector(intValue)] ? [options[@"fontSize"] intValue] : 14;
        if (type < 0 || type > 4) type = 3;
        if (duration <= 0 && type != 0) duration = 2;
        NSString *payload = [NSString stringWithFormat:@"%d;;%@;;%d;;%d;;%d", type, safeMessage, duration, position, fontSize];
        NSDictionary *res = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_SHOW_TOAST, payload] context:context];
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodTap]) {
        double x = [[args objectAtIndex:0] doubleValue];
        double y = [[args objectAtIndex:1] doubleValue];
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
            return [TLinkJSNativeResponse responseWithError:@"tap(x, y) requires finite numbers" code:@-1];
        }
        NSString *payload = [NSString stringWithFormat:@"%.2f;;%.2f", x, y];
        NSDictionary *res = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_NATIVE_TAP, payload] context:context];
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodSwipe]) {
        double x1 = [[args objectAtIndex:0] doubleValue];
        double y1 = [[args objectAtIndex:1] doubleValue];
        double x2 = [[args objectAtIndex:2] doubleValue];
        double y2 = [[args objectAtIndex:3] doubleValue];
        double duration = [[args objectAtIndex:4] doubleValue];
        if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) ||
            !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) ||
            !TLinkautoJSIsFiniteNumber(duration)) {
            return [TLinkJSNativeResponse responseWithError:@"swipe(...) requires finite numbers" code:@-1];
        }
        if (duration < 0) duration = 0;
        if (duration > 60000) duration = 60000;
        NSString *payload = [NSString stringWithFormat:@"%.2f;;%.2f;;%.2f;;%.2f;;%.0f", x1, y1, x2, y2, duration];
        NSDictionary *res = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_NATIVE_SWIPE, payload] context:context];
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    
    else if ([method isEqualToString:TLinkJSNativeMethodRunShell]) {
        NSString *command = [args count] > 0 ? [args objectAtIndex:0] : @"";
        double timeoutSeconds = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        
        if ([command length] == 0) {
            return [TLinkJSNativeResponse responseWithError:@"runShell(command) requires a non-empty single-line command" code:@-1];
        }
        
        NSString *payload = command;
        if (TLinkautoJSIsFiniteNumber(timeoutSeconds) && timeoutSeconds > 0) {
            payload = [NSString stringWithFormat:@"%.3f;;%@", timeoutSeconds, command];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_RUN_SHELL, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 3) return [TLinkJSNativeResponse responseWithValue:result];
        
        // Base64 decode logic from original method
        NSString *encodedOutput = [parts count] > 2 ? parts[2] : @"";
        NSString *output = @"";
        if ([encodedOutput length] > 0) {
            NSData *data = [[NSData alloc] initWithBase64EncodedString:encodedOutput options:0];
            if (data) output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        }
        
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"exitCode"] = @([parts[1] intValue]);
        res[@"output"] = output;
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodReadText]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *resolvedPath = nil;
        NSDictionary *resolved = [runtime bundleStoragePathForRelativePath:path createParent:NO];
        if (![resolved[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:resolved];
        resolvedPath = resolved[@"path"];
        if (!resolvedPath) return [TLinkJSNativeResponse responseWithError:@"context runtime missing for path resolution" code:@-1];
        
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:resolvedPath error:nil];
        if (!attrs) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"file not found", @"path": resolvedPath ?: @"" }];
        if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkautoJSMaxStorageFileBytes) {
            return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"file is too large", @"path": resolvedPath ?: @"" }];
        }
        NSError *err = nil;
        NSString *text = [NSString stringWithContentsOfFile:resolvedPath encoding:NSUTF8StringEncoding error:&err];
        if (!text) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to read file", @"path": resolvedPath ?: @"" }];
        return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @YES, @"path": resolvedPath ?: @"", @"text": text }];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodWriteText]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *text = [args count] > 1 ? [args objectAtIndex:1] : @"";
        NSString *resolvedPath = nil;
        NSDictionary *resolved = [runtime bundleStoragePathForRelativePath:path createParent:YES];
        if (![resolved[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:resolved];
        resolvedPath = resolved[@"path"];
        if (!resolvedPath) return [TLinkJSNativeResponse responseWithError:@"context runtime missing for path resolution" code:@-1];
        
        NSString *safeText = [text isKindOfClass:[NSString class]] ? text : [text description];
        safeText = safeText ?: @"";
        NSData *data = [safeText dataUsingEncoding:NSUTF8StringEncoding];
        if ([data length] > kTLinkautoJSMaxStorageFileBytes) {
            return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"text is too large", @"path": resolvedPath ?: @"" }];
        }
        NSError *err = nil;
        BOOL ok = [safeText writeToFile:resolvedPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (!ok) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to write file", @"path": resolvedPath ?: @"" }];
        return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @YES, @"path": resolvedPath ?: @"", @"bytes": @([data length]) }];
    }
    
    else if ([method isEqualToString:TLinkJSNativeMethodReadJSON]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        TLinkJSNativeRequest *subReq = [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodReadText arguments:@[path]];
        TLinkJSNativeResponse *subRes = [self executeRequest:subReq context:context error:error];
        if (!subRes.ok) return subRes;
        NSDictionary *textResult = subRes.value;
        if (![textResult[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:textResult];
        NSData *data = [textResult[@"text"] dataUsingEncoding:NSUTF8StringEncoding];
        NSError *err = nil;
        id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&err] : nil;
        if (!value) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to parse JSON", @"path": textResult[@"path"] ?: @"" }];
        return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @YES, @"path": textResult[@"path"] ?: @"", @"value": value }];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodWriteJSON]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        id object = [args count] > 1 ? [args objectAtIndex:1] : nil;
        if ([object isKindOfClass:[NSNull class]]) object = nil;
        if (!object || ![NSJSONSerialization isValidJSONObject:object]) {
            return [TLinkJSNativeResponse responseWithError:@"writeJSON(path, value) requires a JSON-serializable object or array" code:@-1];
        }
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&err];
        if (!data) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to encode JSON" }];
        if ([data length] > kTLinkautoJSMaxStorageFileBytes) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"JSON is too large" }];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
        TLinkJSNativeRequest *subReq = [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodWriteText arguments:@[path, text]];
        return [self executeRequest:subReq context:context error:error];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFileExists]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *resolvedPath = nil;
        NSDictionary *resolved = [runtime bundleStoragePathForRelativePath:path createParent:NO];
        if (![resolved[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:resolved];
        resolvedPath = resolved[@"path"];
        if (!resolvedPath) return [TLinkJSNativeResponse responseWithError:@"context runtime missing for path resolution" code:@-1];
        BOOL isDir = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:resolvedPath isDirectory:&isDir];
        return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @YES, @"path": resolvedPath ?: @"", @"exists": @(exists), @"directory": @(exists && isDir) }];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodDeleteFile]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *resolvedPath = nil;
        NSDictionary *resolved = [runtime bundleStoragePathForRelativePath:path createParent:NO];
        if (![resolved[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:resolved];
        resolvedPath = resolved[@"path"];
        if (!resolvedPath) return [TLinkJSNativeResponse responseWithError:@"context runtime missing for path resolution" code:@-1];
        if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
            return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @YES, @"path": resolvedPath ?: @"", @"deleted": @NO }];
        }
        NSError *err = nil;
        BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:resolvedPath error:&err];
        if (!ok) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to delete file", @"path": resolvedPath ?: @"" }];
        return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @YES, @"path": resolvedPath ?: @"", @"deleted": @YES }];
    }
    
    else if ([method isEqualToString:TLinkJSNativeMethodScreenshotTo]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *targetPath = ([path isKindOfClass:[NSString class]] && [path length] > 0) ? path : @"/var/mobile/Media/DCIM/100APPLE/screenshot.png";
        if ([targetPath rangeOfString:@";;"].location != NSNotFound || [targetPath rangeOfString:@"\r"].location != NSNotFound || [targetPath rangeOfString:@"\n"].location != NSNotFound) {
            return [TLinkJSNativeResponse responseWithError:@"screenshot path contains unsupported protocol delimiter" code:@-1];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d1;;%@", TASK_SCREENSHOT, targetPath] context:context];
        NSArray *parts = result[@"parts"];
        NSString *resultPath = [parts count] >= 2 ? parts[1] : targetPath;
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"path"] = resultPath ?: @"";
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodCaptureFrame]) {
        NSDictionary *options = [args count] > 0 ? [args objectAtIndex:0] : @{};
        int format = [options[@"format"] respondsToSelector:@selector(intValue)] ? [options[@"format"] intValue] : 1;
        if (format < 0) format = 1;
        double scale = [options[@"scale"] respondsToSelector:@selector(doubleValue)] ? [options[@"scale"] doubleValue] : 1.0;
        double quality = [options[@"quality"] respondsToSelector:@selector(doubleValue)] ? [options[@"quality"] doubleValue] : 0.8;
        NSString *payload = [NSString stringWithFormat:@"1;;%d;;%.4f;;%.4f", format, scale, quality];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_FRAME_CAPTURE, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        int frameId = [parts[1] intValue];
        [runtime trackFrameId:frameId];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"id"] = @(frameId);
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodReleaseFrame]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (frameId < 0) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"invalid handle" }];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%d", TASK_FRAME_RELEASE, frameId] context:context];
        if ([result[@"ok"] boolValue]) [runtime untrackFrameId:frameId];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOpenImage]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if ([path length] == 0) {
            return [TLinkJSNativeResponse responseWithError:@"openImage(path) requires a valid path" code:@-1];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d1;;%@", TASK_IMAGE_OBJECT, path] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        int imageId = [parts[1] intValue];
        [runtime trackImageId:imageId];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"id"] = @(imageId);
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    
    else if ([method isEqualToString:TLinkJSNativeMethodCaptureImage]) {
        double x = [args count] > 0 ? [[args objectAtIndex:0] doubleValue] : 0;
        double y = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        double width = [args count] > 2 ? [[args objectAtIndex:2] doubleValue] : 0;
        double height = [args count] > 3 ? [[args objectAtIndex:3] doubleValue] : 0;
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
            return [TLinkJSNativeResponse responseWithError:@"captureImage(x, y, width, height) requires finite numbers" code:@-1];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d2;;%.0f;;%.0f;;%.0f;;%.0f", TASK_IMAGE_OBJECT, x, y, width, height] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        int imageId = [parts[1] intValue];
        [runtime trackImageId:imageId];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"id"] = @(imageId);
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodReleaseImage]) {
        int imageId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (imageId < 0) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"invalid handle" }];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d3;;%d", TASK_IMAGE_OBJECT, imageId] context:context];
        if ([result[@"ok"] boolValue]) [runtime untrackImageId:imageId];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    
    else if ([method isEqualToString:TLinkJSNativeMethodMatchTemplate]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        if ([path length] == 0 || [path rangeOfString:@";;"].location != NSNotFound || [path rangeOfString:@"\r"].location != NSNotFound || [path rangeOfString:@"\n"].location != NSNotFound) {
            return [TLinkJSNativeResponse responseWithError:@"matchTemplate(path, options) requires a valid template path" code:@-1];
        }
        int maxTryTimes = [options[@"maxTryTimes"] respondsToSelector:@selector(intValue)] ? [options[@"maxTryTimes"] intValue] : 2;
        double acceptable = [options[@"acceptable"] respondsToSelector:@selector(doubleValue)] ? [options[@"acceptable"] doubleValue] : 0.8;
        double scaleRatio = [options[@"scaleRatio"] respondsToSelector:@selector(doubleValue)] ? [options[@"scaleRatio"] doubleValue] : 0.8;
        NSString *payload = [NSString stringWithFormat:@"%@;;%d;;%.4f;;%.4f", path, maxTryTimes, acceptable, scaleRatio];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_TEMPLATE_MATCH, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 5) return [TLinkJSNativeResponse responseWithValue:result];
        double x = [parts[1] doubleValue];
        double y = [parts[2] doubleValue];
        double width = [parts[3] doubleValue];
        double height = [parts[4] doubleValue];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"matched"] = @(width > 0 && height > 0);
        res[@"x"] = @(x);
        res[@"y"] = @(y);
        res[@"width"] = @(width);
        res[@"height"] = @(height);
        res[@"centerX"] = @(x + width / 2.0);
        res[@"centerY"] = @(y + height / 2.0);
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFindColor]) {
        NSDictionary *options = [args count] > 0 ? [args objectAtIndex:0] : @{};
        double x = [options[@"x"] respondsToSelector:@selector(doubleValue)] ? [options[@"x"] doubleValue] : 0;
        double y = [options[@"y"] respondsToSelector:@selector(doubleValue)] ? [options[@"y"] doubleValue] : 0;
        double width = [options[@"width"] respondsToSelector:@selector(doubleValue)] ? [options[@"width"] doubleValue] : 0;
        double height = [options[@"height"] respondsToSelector:@selector(doubleValue)] ? [options[@"height"] doubleValue] : 0;
        int redMin = [options[@"redMin"] respondsToSelector:@selector(intValue)] ? [options[@"redMin"] intValue] : 0;
        int redMax = [options[@"redMax"] respondsToSelector:@selector(intValue)] ? [options[@"redMax"] intValue] : 255;
        int greenMin = [options[@"greenMin"] respondsToSelector:@selector(intValue)] ? [options[@"greenMin"] intValue] : 0;
        int greenMax = [options[@"greenMax"] respondsToSelector:@selector(intValue)] ? [options[@"greenMax"] intValue] : 255;
        int blueMin = [options[@"blueMin"] respondsToSelector:@selector(intValue)] ? [options[@"blueMin"] intValue] : 0;
        int blueMax = [options[@"blueMax"] respondsToSelector:@selector(intValue)] ? [options[@"blueMax"] intValue] : 255;
        int skip = [options[@"skip"] respondsToSelector:@selector(intValue)] ? [options[@"skip"] intValue] : 0;
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
            return [TLinkJSNativeResponse responseWithError:@"findColor(options) requires finite x/y/width/height" code:@-1];
        }
        NSString *payload = [NSString stringWithFormat:@"1;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d",
                             x, y, width, height, redMin, redMax, greenMin, greenMax, blueMin, blueMax, skip];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_COLOR_SEARCHER, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 6) return [TLinkJSNativeResponse responseWithValue:result];
        int foundX = [parts[1] intValue];
        int foundY = [parts[2] intValue];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"matched"] = @(foundX >= 0 && foundY >= 0);
        res[@"x"] = @(foundX);
        res[@"y"] = @(foundY);
        res[@"red"] = @([parts[3] intValue]);
        res[@"green"] = @([parts[4] intValue]);
        res[@"blue"] = @([parts[5] intValue]);
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    
    else if ([method isEqualToString:TLinkJSNativeMethodIsColors] || [method isEqualToString:TLinkJSNativeMethodFindMultiColor]) {
        NSArray *points = [args count] > 0 ? [args objectAtIndex:0] : @[];
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        
        // Inline TLinkautoJSEncodePointColorTable
        NSMutableString *table = [NSMutableString string];
        for (NSUInteger i = 0; i < [points count]; i++) {
            NSDictionary *pt = points[i];
            if (![pt isKindOfClass:[NSDictionary class]]) return [TLinkJSNativeResponse responseWithError:@"Invalid point colors" code:@-1];
            double px = [pt[@"x"] respondsToSelector:@selector(doubleValue)] ? [pt[@"x"] doubleValue] : 0;
            double py = [pt[@"y"] respondsToSelector:@selector(doubleValue)] ? [pt[@"y"] doubleValue] : 0;
            int r = [pt[@"red"] respondsToSelector:@selector(intValue)] ? [pt[@"red"] intValue] : 0;
            int g = [pt[@"green"] respondsToSelector:@selector(intValue)] ? [pt[@"green"] intValue] : 0;
            int b = [pt[@"blue"] respondsToSelector:@selector(intValue)] ? [pt[@"blue"] intValue] : 0;
            if (i > 0) [table appendString:@",,"];
            [table appendFormat:@"%.0f;;%.0f;;%d;;%d;;%d", px, py, r, g, b];
        }
        if ([table length] == 0) return [TLinkJSNativeResponse responseWithError:@"requires 1-512 point colors" code:@-1];
        
        if ([method isEqualToString:TLinkJSNativeMethodIsColors]) {
            int mode = [options[@"mode"] respondsToSelector:@selector(intValue)] ? [options[@"mode"] intValue] : 1;
            double value = [options[@"value"] respondsToSelector:@selector(doubleValue)] ? [options[@"value"] doubleValue] : ([options[@"tolerance"] respondsToSelector:@selector(doubleValue)] ? [options[@"tolerance"] doubleValue] : 0);
            NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d2;;%@;;%d;;%.4f", TASK_COLOR_SEARCHER, table, mode, value] context:context];
            NSArray *parts = result[@"parts"];
            if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
            BOOL matched = [parts[1] intValue] != 0;
            NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
            res[@"matched"] = @(matched);
            res[@"value"] = @(matched);
            return [TLinkJSNativeResponse responseWithValue:res];
        } else {
            double x = [options[@"x"] respondsToSelector:@selector(doubleValue)] ? [options[@"x"] doubleValue] : 0;
            double y = [options[@"y"] respondsToSelector:@selector(doubleValue)] ? [options[@"y"] doubleValue] : 0;
            double width = [options[@"width"] respondsToSelector:@selector(doubleValue)] ? [options[@"width"] doubleValue] : 0;
            double height = [options[@"height"] respondsToSelector:@selector(doubleValue)] ? [options[@"height"] doubleValue] : 0;
            int mode = [options[@"mode"] respondsToSelector:@selector(intValue)] ? [options[@"mode"] intValue] : 1;
            double value = [options[@"value"] respondsToSelector:@selector(doubleValue)] ? [options[@"value"] doubleValue] : ([options[@"tolerance"] respondsToSelector:@selector(doubleValue)] ? [options[@"tolerance"] doubleValue] : 0);
            int skip = [options[@"skip"] respondsToSelector:@selector(intValue)] ? [options[@"skip"] intValue] : 0;
            if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
                return [TLinkJSNativeResponse responseWithError:@"findMultiColor(options) requires finite x/y/width/height" code:@-1];
            }
            NSString *payload = [NSString stringWithFormat:@"3;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%.4f;;%d", x, y, width, height, table, mode, value, skip];
            NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_COLOR_SEARCHER, payload] context:context];
            NSArray *parts = result[@"parts"];
            if (![result[@"ok"] boolValue] || [parts count] < 3) return [TLinkJSNativeResponse responseWithValue:result];
            int foundX = [parts[1] intValue];
            int foundY = [parts[2] intValue];
            NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
            res[@"matched"] = @(foundX >= 0 && foundY >= 0);
            res[@"x"] = @(foundX);
            res[@"y"] = @(foundY);
            return [TLinkJSNativeResponse responseWithValue:res];
        }
    }
    
    return [TLinkJSNativeResponse responseWithError:[NSString stringWithFormat:@"Unimplemented method: %@", method] code:@-1];
}

@end
