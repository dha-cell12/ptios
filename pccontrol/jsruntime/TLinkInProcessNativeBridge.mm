#import "TLinkInProcessNativeBridge.h"
#import "../Task.h"
#import "../Screen.h"
#import "../TLinkTaskContext.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include "../../shared/TLinkNativeOCRInput.h"
#include "../../shared/TLinkNativeImageOpen.h"
#include "../../shared/TLinkNativeImageCapture.h"

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

static NSString *TLinkautoJSSafeStringPart(NSArray *parts, NSUInteger index)
{
    if (index >= [parts count]) return @"";
    id value = parts[index];
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : [value description];
}

static NSString *TLinkautoJSBase64Encode(NSString *text)
{
    NSData *data = [(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return [data base64EncodedStringWithOptions:0] ?: @"";
}

static NSString *TLinkautoJSBase64Decode(NSString *text)
{
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return @"";
    NSData *data = [[NSData alloc] initWithBase64EncodedString:text options:0];
    if (!data) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSDictionary *TLinkautoJSResultByAdding(NSDictionary *result, NSDictionary *extra)
{
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:result ?: @{}];
    [out addEntriesFromDictionary:extra ?: @{}];
    return out;
}

static double TLinkautoJSDoubleOption(NSDictionary *options, NSString *key, double defaultValue)
{
    if (![options isKindOfClass:[NSDictionary class]]) return defaultValue;
    id value = options[key];
    return value ? [value doubleValue] : defaultValue;
}

static int TLinkautoJSIntOption(NSDictionary *options, NSString *key, int defaultValue)
{
    if (![options isKindOfClass:[NSDictionary class]]) return defaultValue;
    id value = options[key];
    return value ? [value intValue] : defaultValue;
}

static NSString *TLinkautoJSStringOption(NSDictionary *options, NSString *key, NSString *defaultValue)
{
    if (![options isKindOfClass:[NSDictionary class]]) return defaultValue;
    id value = options[key];
    if ([value isKindOfClass:[NSString class]]) return value;
    return value ? [value description] : defaultValue;
}

static NSString *TLinkautoJSOwnerField(NSString *value)
{
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return @"";
    NSString *out = [value stringByReplacingOccurrencesOfString:@";;" withString:@"_"];
    out = [out stringByReplacingOccurrencesOfString:@"\r" withString:@"_"];
    out = [out stringByReplacingOccurrencesOfString:@"\n" withString:@"_"];
    if ([out length] > 96) out = [out substringToIndex:96];
    return out ?: @"";
}

static NSString *TLinkautoJSOwnerSuffix(TLinkTaskExecutionContext *context)
{
    NSString *runtime = TLinkautoJSOwnerField(context.ownerRuntime);
    if ([runtime length] == 0) return @"";
    NSString *sessionId = TLinkautoJSOwnerField(context.ownerSessionId);
    NSString *runId = TLinkautoJSOwnerField(context.ownerRunId);
    return [NSString stringWithFormat:@";;%@;;%@;;%@", sessionId ?: @"", runId ?: @"", runtime ?: @""];
}

static BOOL TLinkautoJSStringContainsAny(NSString *value, NSArray<NSString *> *needles)
{
    if (![value isKindOfClass:[NSString class]]) return YES;
    for (NSString *needle in needles) {
        if ([value rangeOfString:needle].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL TLinkautoJSValidToken(NSString *value)
{
    return !TLinkautoJSStringContainsAny(value ?: @"", @[@";;", @"\r", @"\n"]);
}

static BOOL TLinkautoJSValidProtocolString(NSString *value)
{
    return [value isKindOfClass:[NSString class]] && [value length] > 0 && TLinkautoJSValidToken(value);
}

static NSString *TLinkautoJSEncodeGesturePoints(NSArray *points)
{
    if (![points isKindOfClass:[NSArray class]] || [points count] < 2 || [points count] > 512) return nil;
    NSMutableArray<NSString *> *encoded = [NSMutableArray arrayWithCapacity:[points count]];
    for (id item in points) {
        double x = 0;
        double y = 0;
        if ([item isKindOfClass:[NSArray class]] && [item count] >= 2) {
            NSArray *pair = (NSArray *)item;
            x = [pair[0] doubleValue];
            y = [pair[1] doubleValue];
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)item;
            x = [dict[@"x"] doubleValue];
            y = [dict[@"y"] doubleValue];
        } else {
            return nil;
        }
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) return nil;
        [encoded addObject:[NSString stringWithFormat:@"%.2f,%.2f", x, y]];
    }
    return [encoded componentsJoinedByString:@"|"];
}

// Numeric equivalent of the legacy point encoder; still used only after shape
// and original-value finite checks, with the same decimal/float conversion.
static bool TLinkautoJSDecodeGesturePoints(NSArray *points,std::vector<TLinkNativeGesturePoint> &out,size_t &encodedBytes)
{
    if(![points isKindOfClass:[NSArray class]]||points.count<2||points.count>512)return false;
    out.reserve(points.count);encodedBytes=0;
    for(id item in points){
        double x=0,y=0;
        if([item isKindOfClass:[NSArray class]]&&[item count]>=2){NSArray *pair=item;x=[pair[0] doubleValue];y=[pair[1] doubleValue];}
        else if([item isKindOfClass:[NSDictionary class]]){NSDictionary *dict=item;x=[dict[@"x"] doubleValue];y=[dict[@"y"] doubleValue];}
        else return false;
        if(!TLinkautoJSIsFiniteNumber(x)||!TLinkautoJSIsFiniteNumber(y))return false;
        size_t xBytes=0,yBytes=0;
        out.push_back({TLinkNativeTouchJSCoordinate(x,&xBytes),TLinkNativeTouchJSCoordinate(y,&yBytes)});
        encodedBytes+=xBytes+yBytes+2; // comma plus separator; no trailing separator
    }
    --encodedBytes;return true;
}

static bool TLinkautoJSDecodePointColors(NSArray *points,TLinkNativeFrameColorsRequest &out)
{
    if(![points isKindOfClass:[NSArray class]]||points.count==0||points.count>512)return false;
    out.points.reserve(points.count);
    for(id item in points){
        if(![item isKindOfClass:[NSDictionary class]])return false;
        NSDictionary *dict=item;double x=[dict[@"x"] doubleValue],y=[dict[@"y"] doubleValue];
        int r=[dict[@"red"] respondsToSelector:@selector(intValue)]?[dict[@"red"] intValue]:[dict[@"r"] intValue];
        int g=[dict[@"green"] respondsToSelector:@selector(intValue)]?[dict[@"green"] intValue]:[dict[@"g"] intValue];
        int b=[dict[@"blue"] respondsToSelector:@selector(intValue)]?[dict[@"blue"] intValue]:[dict[@"b"] intValue];
        if(!TLinkautoJSIsFiniteNumber(x)||!TLinkautoJSIsFiniteNumber(y))return false;
        out.append(x,y,r,g,b);
    }
    return true;
}

static bool TLinkautoJSDecodeLivePointColors(NSArray *points,TLinkNativeColorPointsRequest &out)
{
    if(![points isKindOfClass:[NSArray class]]||points.count==0||points.count>512)return false;
    out.points.reserve(points.count);
    for(id item in points){
        if(![item isKindOfClass:[NSDictionary class]])return false;
        NSDictionary *dict=item;double x=[dict[@"x"] doubleValue],y=[dict[@"y"] doubleValue];
        int r=[dict[@"red"] respondsToSelector:@selector(intValue)]?[dict[@"red"] intValue]:[dict[@"r"] intValue];
        int g=[dict[@"green"] respondsToSelector:@selector(intValue)]?[dict[@"green"] intValue]:[dict[@"g"] intValue];
        int b=[dict[@"blue"] respondsToSelector:@selector(intValue)]?[dict[@"blue"] intValue]:[dict[@"b"] intValue];
        if(!TLinkautoJSIsFiniteNumber(x)||!TLinkautoJSIsFiniteNumber(y))return false;
        out.append(x,y,r,g,b);
    }
    return true;
}

static NSDictionary *TLinkautoJSOCRResultByAddingDecodedError(NSDictionary *result)
{
    NSArray *parts = result[@"parts"];
    if ([result[@"ok"] boolValue] || [parts count] < 3) return result;
    return TLinkautoJSResultByAdding(result, @{
        @"errorCode": TLinkautoJSSafeStringPart(parts, 1),
        @"errorMessage": TLinkautoJSBase64Decode(TLinkautoJSSafeStringPart(parts, 2)),
    });
}

static NSDictionary *TLinkautoJSStateResult(NSDictionary *result, NSString *enabledKey)
{
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    BOOL enabled = [TLinkautoJSSafeStringPart(parts, 1) intValue] != 0;
    return TLinkautoJSResultByAdding(result, @{ enabledKey ?: @"enabled": @(enabled), @"value": @(enabled) });
}


static NSString *TLinkNativeStopCode(TLinkNativeStop reason) {
    switch (reason) {
        case TLinkNativeStop::Cancelled: return @"AbortError";
        case TLinkNativeStop::Deadline: return @"TimeoutError";
        case TLinkNativeStop::OutputLimit: return @"response_too_large";
        default: return @"native_failed";
    }
}
static NSDictionary *TLinkNativeFailure(NSString *code) {
    return @{@"ok": @NO, @"raw": [NSString stringWithFormat:@"1;;%@\r\n", code], @"parts": @[@"1", code]};
}

@protocol TLinkInProcessFacadeInterface <NSObject>
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)relativePath createParent:(BOOL)createParent;
- (void)trackFrameId:(int)frameId;
- (void)untrackFrameId:(int)frameId;
- (void)untrackAllFrameIds;
- (void)trackImageId:(int)imageId;
- (void)untrackImageId:(int)imageId;
@end

@interface TLinkInProcessNativeBridge ()
- (NSDictionary *)executeRawPayload:(NSString *)payload context:(TLinkTaskExecutionContext *)context;
@end

@implementation TLinkInProcessNativeBridge

// BEGIN bounded native dispatch (also exercised by the macOS integration harness).
- (NSDictionary *)executeRawPayload:(NSString *)payload context:(TLinkTaskExecutionContext *)context
{
    if (![payload isKindOfClass:[NSString class]] || payload.length < 2)
        return TLinkNativeFailure(@"invalid_payload");
    // NSString.length is UTF-16 units; byte length is checked independently before dispatch.
    if (payload.length > 8192) return TLinkNativeFailure(@"input_too_large");
    NSMutableData *payloadData = [[payload dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (!payloadData || payloadData.length > 32 * 1024 || memchr(payloadData.bytes, 0, payloadData.length))
        return TLinkNativeFailure(@"invalid_payload");
    const BOOL cleanup = [payload hasPrefix:@"67"] || [payload hasPrefix:@"483;;"] || [payload hasPrefix:@"300;;"];
    const BOOL frameCreate = [payload hasPrefix:@"66"];
    const BOOL imageCreate = [payload hasPrefix:@"481;;"] || [payload hasPrefix:@"482;;"];
    TLinkTaskExecutionContext *call = TLinkNativeCallContext(context, cleanup, YES);
    auto budget = [call nativeBudget];
    TLinkNativeBudgetScope scope(budget);
    if (budget->stopped()) return TLinkNativeFailure(TLinkNativeStopCode(budget->reason()));
    // Ensure an allocation's small ID response can always be retained for rollback on abort.
    if ((frameCreate || imageCreate) && budget->outputLimit() < 1024) return TLinkNativeFailure(@"response_too_large");
    UInt8 zero = 0;
    [payloadData appendBytes:&zero length:1];
    // Compatibility token for handlers that branch on non-NULL stream. All Task writers use
    // notifyClient; its scoped native sink owns the response and admits each bounded chunk.
    UInt8 compatibilityByte = 0;
    CFWriteStreamRef stream = CFWriteStreamCreateWithBuffer(kCFAllocatorDefault, &compatibilityByte, 1);
    if (!stream) return TLinkNativeFailure(@"stream_create_failed");
    @try {
        if (!CFWriteStreamOpen(stream)) return TLinkNativeFailure(@"stream_open_failed");
        processTaskWithContext((UInt8 *)payloadData.mutableBytes, [payloadData length] - 1, stream, call);
    } @catch (__unused NSException *exception) {
        return TLinkNativeFailure(@"native_exception");
    } @finally { CFWriteStreamClose(stream); CFRelease(stream); }
    const auto &written = budget->response();
    NSData *data = [NSData dataWithBytes:written.data() length:written.size()];
    NSString *raw = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"0\r\n";
    if (!raw) return TLinkNativeFailure(@"invalid_response_encoding");
    NSArray<NSString *> *parts = [[raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"];
    NSString *status = parts.count ? parts[0] : @"1";
    if (budget->stopped()) {
        if ((frameCreate || imageCreate) && [status isEqualToString:@"0"] && parts.count > 1 && [parts[1] longLongValue] > 0) {
            NSString *release = [NSString stringWithFormat:frameCreate ? @"67%@%@" : @"483;;%@%@", parts[1], TLinkautoJSOwnerSuffix(context)];
            [self executeRawPayload:release context:context];
        }
        return TLinkNativeFailure(TLinkNativeStopCode(budget->reason()));
    }
    return @{ @"ok": @([status isEqualToString:@"0"]), @"raw": raw, @"parts": parts ?: @[] };
}
// END bounded native dispatch.

- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request
                                  context:(TLinkTaskExecutionContext *)context
                                    error:(NSError **)error {
    NSString *method = request.method;
    NSArray *args = request.arguments;
    BOOL cleanup = [method isEqualToString:TLinkJSNativeMethodReleaseFrame] ||
        [method isEqualToString:TLinkJSNativeMethodReleaseAllFrames] || [method isEqualToString:TLinkJSNativeMethodReleaseImage] ||
        ([method isEqualToString:TLinkJSNativeMethodHardwareKey] && args.count > 0 && [args[0] intValue] == 0);
    auto inherited = context ? [context nativeBudget] : TLinkNativeBudgetPtr{};
    if (!inherited || (cleanup && !inherited->cleanup())) {
        double requested = [method isEqualToString:TLinkJSNativeMethodRunShell] && args.count > 1 ? [args[1] doubleValue] : 0;
        context = TLinkNativeCallContext(context, cleanup, NO, requested);
    }
    TLinkNativeBudgetScope requestScope([context nativeBudget]);
    if (TLinkNativeStopped()) return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(TLinkNativeStopCode([context nativeBudget]->reason()))];
    
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
            @"ok": @YES,
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
        TLinkNativeTouchRequest touch;touch.x1=TLinkNativeTouchJSCoordinate(x);touch.y1=TLinkNativeTouchJSCoordinate(y);
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeTouch(touch,context)];
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
        TLinkNativeTouchRequest touch;touch.kind=TLinkNativeTouchKind::Swipe;
        touch.x1=TLinkNativeTouchJSCoordinate(x1);touch.y1=TLinkNativeTouchJSCoordinate(y1);
        touch.x2=TLinkNativeTouchJSCoordinate(x2);touch.y2=TLinkNativeTouchJSCoordinate(y2);
        touch.durationMs=TLinkNativeTouchJSDuration(duration);
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeTouch(touch,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodLongPress]) {
        double x = [args count] > 0 ? [[args objectAtIndex:0] doubleValue] : 0;
        double y = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        double duration = [args count] > 2 ? [[args objectAtIndex:2] doubleValue] : 0;
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) {
            return [TLinkJSNativeResponse responseWithError:@"longPress(x, y, duration) requires finite numbers" code:@-1];
        }
        TLinkNativeTouchRequest touch;touch.x1=TLinkNativeTouchJSCoordinate(x);touch.y1=TLinkNativeTouchJSCoordinate(y);
        touch.durationMs=TLinkNativeTouchJSDuration(duration);
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeTouch(touch,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodGesture]) {
        NSArray *points = [args count] > 0 ? [args objectAtIndex:0] : @[];
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        TLinkNativeTouchRequest touch;touch.kind=TLinkNativeTouchKind::Gesture;size_t encodedBytes=0;
        if(!TLinkautoJSDecodeGesturePoints(points,touch.points,encodedBytes))return [TLinkJSNativeResponse responseWithError:@"gesture(points, options) requires 2-512 points as [x,y] arrays or {x,y} objects" code:@-1];
        touch.finger=TLinkautoJSIntOption(options,@"finger",0);
        touch.durationMs=TLinkautoJSIntOption(options,@"duration",TLinkautoJSIntOption(options,@"durationMs",300));
        touch.durationMs=MAX(0,MIN(touch.durationMs,60000));
        if(!TLinkNativeGestureInputFits(encodedBytes,touch.finger,touch.durationMs))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeTouch(touch,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodZoom]) {
        double centerX = [args count] > 0 ? [[args objectAtIndex:0] doubleValue] : NAN;
        double centerY = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : NAN;
        double startRadius = [args count] > 2 ? [[args objectAtIndex:2] doubleValue] : NAN;
        double endRadius = [args count] > 3 ? [[args objectAtIndex:3] doubleValue] : NAN;
        NSDictionary *options = [args count] > 4 && [[args objectAtIndex:4] isKindOfClass:[NSDictionary class]]
            ? [args objectAtIndex:4]
            : @{};
        if (!TLinkautoJSIsFiniteNumber(centerX) || !TLinkautoJSIsFiniteNumber(centerY) ||
            !TLinkautoJSIsFiniteNumber(startRadius) || !TLinkautoJSIsFiniteNumber(endRadius)) {
            return [TLinkJSNativeResponse responseWithError:@"zoom(...) requires finite center and radius values" code:@-1];
        }
        TLinkNativeTouchRequest touch;touch.kind=TLinkNativeTouchKind::Zoom;
        touch.x1=TLinkNativeTouchJSZoomNumber(centerX);touch.y1=TLinkNativeTouchJSZoomNumber(centerY);
        touch.startRadius=TLinkNativeTouchJSZoomNumber(startRadius);touch.endRadius=TLinkNativeTouchJSZoomNumber(endRadius);
        touch.durationMs=TLinkautoJSIntOption(options,@"durationMs",300);
        touch.fingerCount=TLinkautoJSIntOption(options,@"fingerCount",2);touch.steps=TLinkautoJSIntOption(options,@"steps",20);
        touch.angleDegrees=TLinkNativeTouchJSZoomNumber(TLinkautoJSDoubleOption(options,@"angleDegrees",0.0));
        touch.finger=TLinkautoJSIntOption(options,@"baseFinger",0);
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeTouch(touch,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodPickColor]) {
        double x = [args count] > 0 ? [[args objectAtIndex:0] doubleValue] : 0;
        double y = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
            return [TLinkJSNativeResponse responseWithError:@"pickColor(x, y) requires finite numbers" code:@-1];
        }
        const TLinkNativeColorPickRequest pick(x,y);
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeColorPick(pick,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodScreenshotRegion]) {
        NSString *targetPath = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        if (TLinkautoJSStringContainsAny(targetPath, @[@";;", @"\r", @"\n"])) {
            return [TLinkJSNativeResponse responseWithError:@"screenshot path contains unsupported protocol delimiter" code:@-1];
        }
        double x = TLinkautoJSDoubleOption(options, @"x", 0);
        double y = TLinkautoJSDoubleOption(options, @"y", 0);
        double width = TLinkautoJSDoubleOption(options, @"width", 0);
        double height = TLinkautoJSDoubleOption(options, @"height", 0);
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height) || width <= 0 || height <= 0) {
            return [TLinkJSNativeResponse responseWithError:@"screenshotRegion(path, options) requires finite positive width/height" code:@-1];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d1;;%@;;%.0f;;%.0f;;%.0f;;%.0f", TASK_SCREENSHOT, targetPath, x, y, width, height] context:context];
        NSArray *parts = result[@"parts"];
        NSString *resultPath = [parts count] >= 2 ? TLinkautoJSSafeStringPart(parts, 1) : targetPath;
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"path": resultPath ?: @"", @"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height)})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodBatch]) {
        NSArray *commands = [args count] > 0 ? [args objectAtIndex:0] : @[];
        if (![commands isKindOfClass:[NSArray class]]) return [TLinkJSNativeResponse responseWithError:@"batch(commands) requires an array" code:@-1];
        if ([commands count] > 256) return [TLinkJSNativeResponse responseWithError:@"batch(commands) accepts at most 256 commands" code:@-1];
        // RAW/mixed batches and nonstandard durations retain their exact legacy
        // grammar/intValue behavior. Select before any authorization or injection.
        bool structured=true;
        for(id item in commands) {
            if(![item isKindOfClass:[NSDictionary class]]){structured=false;break;}
            NSDictionary *cmd=item;id type=cmd[@"type"];
            if(![type isKindOfClass:[NSString class]]){structured=false;break;}
            NSString *name=[type lowercaseString];
            if([name isEqualToString:@"tap"]||[name isEqualToString:@"swipe"]) {
                id duration=cmd[@"duration"];
                if(duration&&(![duration isKindOfClass:[NSNumber class]]||
                    !TLinkautoJSIsFiniteNumber([duration doubleValue])||[duration doubleValue]<0||[duration doubleValue]>60000)) {
                    structured=false;break;
                }
            }
        }
        if(structured) {
            std::vector<TLinkNativeTouchRequest> touches;touches.reserve(commands.count);
            TLinkNativeBatchInputSize input;
            for(NSDictionary *cmd in commands) {
                TLinkNativeTouchRequest touch;size_t commandBytes=0;
                NSString *type=[cmd[@"type"] lowercaseString];
                if([type isEqualToString:@"tap"]||[type isEqualToString:@"swipe"]) {
                    const bool swipe=[type isEqualToString:@"swipe"];
                    double x=[cmd[swipe?@"x1":@"x"] doubleValue],y=[cmd[swipe?@"y1":@"y"] doubleValue];
                    double x2=swipe?[cmd[@"x2"] doubleValue]:0,y2=swipe?[cmd[@"y2"] doubleValue]:0;
                    double duration=cmd[@"duration"]?[cmd[@"duration"] doubleValue]:(swipe?300.0:50.0);
                    if(!TLinkautoJSIsFiniteNumber(x)||!TLinkautoJSIsFiniteNumber(y)||!TLinkautoJSIsFiniteNumber(x2)||
                        !TLinkautoJSIsFiniteNumber(y2)||!TLinkautoJSIsFiniteNumber(duration))
                        return [TLinkJSNativeResponse responseWithError:swipe?@"batch swipe requires finite coordinates/duration":@"batch tap requires finite x/y/duration" code:@-1];
                    size_t nx=0,ny=0,nx2=0,ny2=0,nd=0;
                    touch.kind=swipe?TLinkNativeTouchKind::Swipe:TLinkNativeTouchKind::Tap;
                    touch.x1=TLinkNativeTouchJSCoordinate(x,&nx);touch.y1=TLinkNativeTouchJSCoordinate(y,&ny);
                    touch.durationMs=TLinkNativeTouchJSDuration(duration,&nd);
                    commandBytes=6+nx+ny+nd;
                    if(swipe) {
                        touch.x2=TLinkNativeTouchJSCoordinate(x2,&nx2);touch.y2=TLinkNativeTouchJSCoordinate(y2,&ny2);
                        commandBytes+=4+nx2+ny2;
                    }
                } else if([type isEqualToString:@"gesture"]) {
                    size_t pointsBytes=0;
                    if(!TLinkautoJSDecodeGesturePoints([cmd[@"points"] isKindOfClass:[NSArray class]]?cmd[@"points"]:nil,touch.points,pointsBytes))
                        return [TLinkJSNativeResponse responseWithError:@"batch gesture requires 2-512 valid points" code:@-1];
                    touch.kind=TLinkNativeTouchKind::Gesture;
                    touch.finger=cmd[@"finger"]?[cmd[@"finger"] intValue]:0;
                    int duration=cmd[@"duration"]?[cmd[@"duration"] intValue]:(cmd[@"durationMs"]?[cmd[@"durationMs"] intValue]:300);
                    touch.durationMs=duration<0?0:(duration>60000?60000:duration);
                    commandBytes=6+TLinkNativeTouchIntegerBytes(touch.finger)+TLinkNativeTouchIntegerBytes(touch.durationMs)+pointsBytes;
                } else return [TLinkJSNativeResponse responseWithError:[NSString stringWithFormat:@"unsupported batch command type: %@",type?:@""] code:@-1];
                input.append(commandBytes);
                // Keep validating the whole input after overflow, without retaining
                // additional plans or committing any earlier command.
                if(input.fits())touches.push_back(std::move(touch));
            }
            if(!input.fits())return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
            return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeTouchBatch(touches,context)];
        }
        NSMutableArray<NSString *> *wireCommands = [NSMutableArray arrayWithCapacity:[commands count]];
        for (id item in commands) {
            if ([item isKindOfClass:[NSString class]]) {
                NSString *raw = (NSString *)item;
                if (TLinkautoJSStringContainsAny(raw, @[@"||", @"\r", @"\n"])) return [TLinkJSNativeResponse responseWithError:@"raw batch command contains unsupported protocol delimiter" code:@-1];
                if ([raw hasPrefix:@"62"] || [raw hasPrefix:@"63"] || [raw hasPrefix:@"64"]) [wireCommands addObject:raw];
                else return [TLinkJSNativeResponse responseWithError:@"raw batch command must start with allowed native task 62/63/64" code:@-1];
                continue;
            }
            if (![item isKindOfClass:[NSDictionary class]]) return [TLinkJSNativeResponse responseWithError:@"batch command must be an object or raw command string" code:@-1];
            NSDictionary *cmd = (NSDictionary *)item;
            NSString *type = [[cmd[@"type"] description] lowercaseString];
            if ([type isEqualToString:@"tap"]) {
                double x = [cmd[@"x"] doubleValue], y = [cmd[@"y"] doubleValue], duration = cmd[@"duration"] ? [cmd[@"duration"] doubleValue] : 50.0;
                if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) return [TLinkJSNativeResponse responseWithError:@"batch tap requires finite x/y/duration" code:@-1];
                [wireCommands addObject:[NSString stringWithFormat:@"62%.2f;;%.2f;;%.0f", x, y, duration]];
            } else if ([type isEqualToString:@"swipe"]) {
                double x1 = [cmd[@"x1"] doubleValue], y1 = [cmd[@"y1"] doubleValue], x2 = [cmd[@"x2"] doubleValue], y2 = [cmd[@"y2"] doubleValue], duration = cmd[@"duration"] ? [cmd[@"duration"] doubleValue] : 300.0;
                if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) || !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) || !TLinkautoJSIsFiniteNumber(duration)) return [TLinkJSNativeResponse responseWithError:@"batch swipe requires finite coordinates/duration" code:@-1];
                [wireCommands addObject:[NSString stringWithFormat:@"63%.2f;;%.2f;;%.2f;;%.2f;;%.0f", x1, y1, x2, y2, duration]];
            } else if ([type isEqualToString:@"gesture"]) {
                NSString *encoded = TLinkautoJSEncodeGesturePoints([cmd[@"points"] isKindOfClass:[NSArray class]] ? cmd[@"points"] : nil);
                if (!encoded) return [TLinkJSNativeResponse responseWithError:@"batch gesture requires 2-512 valid points" code:@-1];
                int finger = cmd[@"finger"] ? [cmd[@"finger"] intValue] : 0;
                int duration = cmd[@"duration"] ? [cmd[@"duration"] intValue] : (cmd[@"durationMs"] ? [cmd[@"durationMs"] intValue] : 300);
                if (duration < 0) duration = 0;
                if (duration > 60000) duration = 60000;
                [wireCommands addObject:[NSString stringWithFormat:@"64%d;;%d;;%@", finger, duration, encoded]];
            } else {
                return [TLinkJSNativeResponse responseWithError:[NSString stringWithFormat:@"unsupported batch command type: %@", type ?: @""] code:@-1];
            }
        }
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_NATIVE_BATCH, [wireCommands componentsJoinedByString:@"||"]] context:context]];
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
        int gray = TLinkautoJSIntOption(options, @"gray", 1);
        int bgra = TLinkautoJSIntOption(options, @"bgra", 1);
        int ttlMs = TLinkautoJSIntOption(options, @"ttlMs", 1000);
        TLinkNativeFrameCaptureRequest input;input.gray=gray!=0;input.bgra=bgra!=0;input.ttlMs=ttlMs>0?uint64_t(ttlMs):0;
        NSString *suffix=TLinkautoJSOwnerSuffix(context);NSData *encoded=[suffix dataUsingEncoding:NSUTF8StringEncoding];
        if(!encoded||(encoded.length&&memchr(encoded.bytes,0,encoded.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *wireOwner=[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]?:@"";
        NSArray *fields=[[@"0" stringByAppendingString:wireOwner] componentsSeparatedByString:@";;"];
        if(fields.count>1&&[fields[1] length])input.sessionId=[fields[1] UTF8String]?:"";
        if(fields.count>2&&[fields[2] length])input.runId=[fields[2] UTF8String]?:"";
        if(fields.count>3&&[fields[3] length])input.runtime=[fields[3] UTF8String]?:"";
        NSDictionary *result=TLinkExecuteNativeFrameCapture(input,context);
        if([result[@"ok"] boolValue])[runtime trackFrameId:[result[@"id"] intValue]];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodReleaseFrame]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (frameId < 0) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"invalid handle" }];
        TLinkNativeFrameReleaseRequest input;input.frameId=uint32_t(frameId);
        // Retain bounded owner-suffix canonicalization, including delimiter overlap and trailing whitespace.
        NSString *suffix=TLinkautoJSOwnerSuffix(context);NSData *encoded=[suffix dataUsingEncoding:NSUTF8StringEncoding];
        if(!encoded||(encoded.length&&memchr(encoded.bytes,0,encoded.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *wireOwner=[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]?:@"";
        NSString *owner=[[@"0" stringByAppendingString:wireOwner] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *fields=[owner componentsSeparatedByString:@";;"];input.scoped=fields.count>=4;
        if(input.scoped){input.sessionId=[fields[1] UTF8String]?:"";input.runId=[fields[2] UTF8String]?:"";input.runtime=[fields[3] UTF8String]?:"";}
        NSDictionary *result=TLinkExecuteNativeFrameRelease(input,context);
        if ([result[@"ok"] boolValue]) [runtime untrackFrameId:frameId];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodReleaseAllFrames]) {
        TLinkNativeFrameReleaseRequest input;input.all=true;
        NSDictionary *result=TLinkExecuteNativeFrameRelease(input,context);
        if ([result[@"ok"] boolValue] && [runtime respondsToSelector:@selector(untrackAllFrameIds)]) {
            [(id)runtime untrackAllFrameIds];
        }
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"released": @([TLinkautoJSSafeStringPart(parts, 1) intValue])})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOpenImage]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if ([path length] == 0) {
            return [TLinkJSNativeResponse responseWithError:@"openImage(path) requires a valid path" code:@-1];
        }
        // Preserve legacy delimiter overlap and Foundation %s conversion for path/owner fields.
        NSString *tail=[NSString stringWithFormat:@"%@%@",path,TLinkautoJSOwnerSuffix(context)];
        if(!TLinkNativeImageOpenInputFits(tail.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        NSData *encoded=[tail dataUsingEncoding:NSUTF8StringEncoding];
        if(!encoded||!TLinkNativeImageOpenBytesFit(encoded.length)||(encoded.length&&memchr(encoded.bytes,0,encoded.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *compatibilityBody=[@"2;;" stringByAppendingString:tail];
        NSString *wire=[NSString stringWithFormat:@"%s",[compatibilityBody UTF8String]];
        NSArray *fields=[wire componentsSeparatedByString:@";;"];TLinkNativeImageOpenRequest input;
        input.path=fields[1];
        if(fields.count>2&&[fields[2] length])input.sessionId=[fields[2] UTF8String]?:"";
        if(fields.count>3&&[fields[3] length])input.runId=[fields[3] UTF8String]?:"";
        if(fields.count>4&&[fields[4] length])input.runtime=[fields[4] UTF8String]?:"";
        NSDictionary *result=TLinkExecuteNativeImageOpen(input,context);
        if([result[@"ok"] boolValue])[runtime trackImageId:[result[@"id"] intValue]];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    
    else if ([method isEqualToString:TLinkJSNativeMethodCaptureImage]) {
        double x = [args count] > 0 ? [[args objectAtIndex:0] doubleValue] : 0;
        double y = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        double width = [args count] > 2 ? [[args objectAtIndex:2] doubleValue] : 0;
        double height = [args count] > 3 ? [[args objectAtIndex:3] doubleValue] : 0;
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
            return [TLinkJSNativeResponse responseWithError:@"captureImage(x, y, width, height) requires finite numbers" code:@-1];
        }
        TLinkNativeImageCaptureRequest input;size_t xu=0,yu=0,wu=0,hu=0;
        input.x=TLinkNativeImageCaptureJSInt(x,&xu);input.y=TLinkNativeImageCaptureJSInt(y,&yu);
        input.width=TLinkNativeImageCaptureJSInt(width,&wu);input.height=TLinkNativeImageCaptureJSInt(height,&hu);
        NSString *suffix=TLinkautoJSOwnerSuffix(context);
        if(!TLinkNativeImageCaptureInputFits(xu,yu,wu,hu,suffix.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        NSData *encoded=[suffix dataUsingEncoding:NSUTF8StringEncoding];
        if(!encoded||!TLinkNativeImageCaptureInputFits(xu,yu,wu,hu,encoded.length,32*1024)||(encoded.length&&memchr(encoded.bytes,0,encoded.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        // The original numeric prefix ends in an ASCII digit; retain %s owner decoding with that same boundary.
        NSString *owner=[NSString stringWithFormat:@"0%s",[suffix UTF8String]];
        NSArray *fields=[owner componentsSeparatedByString:@";;"];
        if(fields.count>1&&[fields[1] length])input.sessionId=[fields[1] UTF8String]?:"";
        if(fields.count>2&&[fields[2] length])input.runId=[fields[2] UTF8String]?:"";
        if(fields.count>3&&[fields[3] length])input.runtime=[fields[3] UTF8String]?:"";
        NSDictionary *result=TLinkExecuteNativeImageCapture(input,context);
        if([result[@"ok"] boolValue])[runtime trackImageId:[result[@"id"] intValue]];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodReleaseImage]) {
        int imageId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (imageId < 0) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"invalid handle" }];
        TLinkNativeImageReleaseRequest input;input.imageId=uint32_t(imageId);
        NSString *suffix=TLinkautoJSOwnerSuffix(context);NSData *encoded=[suffix dataUsingEncoding:NSUTF8StringEncoding];
        if(!encoded||(encoded.length&&memchr(encoded.bytes,0,encoded.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *wireOwner=[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]?:@"";
        // Image action 3 uses Foundation %s parsing and preserves trailing owner whitespace.
        NSString *owner=[NSString stringWithFormat:@"0%s",[wireOwner UTF8String]];
        NSArray *fields=[owner componentsSeparatedByString:@";;"];input.scoped=fields.count>=4;
        if(input.scoped){input.sessionId=[fields[1] UTF8String]?:"";input.runId=[fields[2] UTF8String]?:"";input.runtime=[fields[3] UTF8String]?:"";}
        NSDictionary *result=TLinkExecuteNativeImageRelease(input,context);
        if ([result[@"ok"] boolValue]) [runtime untrackImageId:imageId];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFramePickColor]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        double x = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        double y = [args count] > 2 ? [[args objectAtIndex:2] doubleValue] : 0;
        NSDictionary *options = [args count] > 3 ? [args objectAtIndex:3] : @{};
        if (frameId <= 0 || !TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) return [TLinkJSNativeResponse responseWithError:@"framePickColor(frameId, x, y) requires a frame id and finite coordinates" code:@-1];
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(coord)) return [TLinkJSNativeResponse responseWithError:@"coord contains unsupported protocol delimiter" code:@-1];
        int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
        TLinkNativeFramePickRequest pick;pick.frameId=frameId;pick.maxAgeMs=maxAgeMs;size_t xBytes=0,yBytes=0;
        pick.x=TLinkNativeFrameJSCoordinate(x,&xBytes);pick.y=TLinkNativeFrameJSCoordinate(y,&yBytes);
        if(!TLinkFramePickInputFits(frameId,maxAgeMs,xBytes,yBytes,coord.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        // Match RAW's actual UTF-8 conversion and byte-level NUL rejection, on the bounded token only.
        NSData *coordData=[coord dataUsingEncoding:NSUTF8StringEncoding];
        if(!coordData||(coordData.length&&memchr(coordData.bytes,0,coordData.length)))
            return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *space=[coord lowercaseString];pick.pointCoord=[space isEqualToString:@"point"];
        pick.validCoord=pick.pointCoord||[space isEqualToString:@"pixel"];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFramePick(pick,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFramePickColors]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSArray *points = [args count] > 1 ? [args objectAtIndex:1] : @[];
        NSDictionary *options = [args count] > 2 ? [args objectAtIndex:2] : @{};
        if (frameId <= 0 || ![points isKindOfClass:[NSArray class]] || [points count] == 0) return [TLinkJSNativeResponse responseWithError:@"framePickColors(frameId, points) requires a frame id and non-empty points array" code:@-1];
        TLinkNativeFramePickManyRequest pick;pick.frame.frameId=frameId;
        pick.points.reserve(points.count<512?points.count:512);
        for (id point in points) {
            double x = 0, y = 0;
            if ([point isKindOfClass:[NSArray class]] && [point count] >= 2) {
                NSArray *arrayPoint = (NSArray *)point;
                x = [arrayPoint[0] doubleValue];
                y = [arrayPoint[1] doubleValue];
            }
            else if ([point isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dictPoint = (NSDictionary *)point;
                x = [dictPoint[@"x"] doubleValue];
                y = [dictPoint[@"y"] doubleValue];
            }
            else return [TLinkJSNativeResponse responseWithError:@"framePickColors points must be [x,y] arrays or {x,y} objects" code:@-1];
            if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) return [TLinkJSNativeResponse responseWithError:@"framePickColors points require finite coordinates" code:@-1];
            pick.append(x,y);
        }
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(coord)) return [TLinkJSNativeResponse responseWithError:@"coord contains unsupported protocol delimiter" code:@-1];
        int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
        pick.frame.maxAgeMs=maxAgeMs;
        if(!TLinkFramePickManyInputFits(frameId,maxAgeMs,pick.tableUnits,coord.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        NSData *coordData=[coord dataUsingEncoding:NSUTF8StringEncoding];
        if(!coordData||(coordData.length&&memchr(coordData.bytes,0,coordData.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *space=[coord lowercaseString];pick.frame.pointCoord=[space isEqualToString:@"point"];
        pick.frame.validCoord=pick.frame.pointCoord||[space isEqualToString:@"pixel"];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFramePickMany(pick,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFrameFindColor]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        if (frameId <= 0) return [TLinkJSNativeResponse responseWithError:@"frameFindColor(frameId, options) requires a positive frame id" code:@-1];
        double x = TLinkautoJSDoubleOption(options, @"x", 0), y = TLinkautoJSDoubleOption(options, @"y", 0), width = TLinkautoJSDoubleOption(options, @"width", 0), height = TLinkautoJSDoubleOption(options, @"height", 0);
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(coord) || !TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) return [TLinkJSNativeResponse responseWithError:@"frameFindColor options require finite x/y/width/height and valid coord" code:@-1];
        TLinkNativeFrameSearchRequest search;search.frame.frameId=frameId;
        search.setRegion(x,y,width,height);
        search.redMin=TLinkautoJSIntOption(options,@"redMin",TLinkautoJSIntOption(options,@"rMin",0));search.redMax=TLinkautoJSIntOption(options,@"redMax",TLinkautoJSIntOption(options,@"rMax",255));
        search.greenMin=TLinkautoJSIntOption(options,@"greenMin",TLinkautoJSIntOption(options,@"gMin",0));search.greenMax=TLinkautoJSIntOption(options,@"greenMax",TLinkautoJSIntOption(options,@"gMax",255));
        search.blueMin=TLinkautoJSIntOption(options,@"blueMin",TLinkautoJSIntOption(options,@"bMin",0));search.blueMax=TLinkautoJSIntOption(options,@"blueMax",TLinkautoJSIntOption(options,@"bMax",255));
        search.skip=TLinkautoJSIntOption(options,@"skip",0);search.frame.maxAgeMs=TLinkautoJSIntOption(options,@"maxAgeMs",1000);
        if(!TLinkFrameSearchInputFits(search,coord.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        NSData *coordData=[coord dataUsingEncoding:NSUTF8StringEncoding];
        if(!coordData||(coordData.length&&memchr(coordData.bytes,0,coordData.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *space=[coord lowercaseString];search.frame.pointCoord=[space isEqualToString:@"point"];search.frame.validCoord=search.frame.pointCoord||[space isEqualToString:@"pixel"];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFrameSearch(search,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFrameIsColors]) {
        int frameId=[args count]>0?[[args objectAtIndex:0] intValue]:0;
        NSArray *points=[args count]>1?[args objectAtIndex:1]:@[];
        NSDictionary *options=[args count]>2?[args objectAtIndex:2]:@{};
        TLinkNativeFrameColorsRequest check;const bool decoded=TLinkautoJSDecodePointColors(points,check);
        if(frameId<=0||!decoded)return [TLinkJSNativeResponse responseWithError:@"frame color method requires a frame id and point colors" code:@-1];
        NSString *coord=TLinkautoJSStringOption(options,@"coord",@"pixel");
        if(!TLinkautoJSValidToken(coord))return [TLinkJSNativeResponse responseWithError:@"coord contains unsupported protocol delimiter" code:@-1];
        check.frame.frameId=frameId;check.frame.maxAgeMs=TLinkautoJSIntOption(options,@"maxAgeMs",1000);check.mode=TLinkautoJSIntOption(options,@"mode",1);
        // Keep the small scalar formatter: it defines legacy four-decimal and nonfinite spelling.
        NSString *threshold=[NSString stringWithFormat:@"%.4f",TLinkautoJSDoubleOption(options,@"value",TLinkautoJSDoubleOption(options,@"tolerance",0))];
        check.toleranceUnits=threshold.length;check.toleranceValid=TLinkColorDouble(threshold.UTF8String,check.tolerance);
        if(!TLinkFrameColorsInputFits(check,coord.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        NSData *coordData=[coord dataUsingEncoding:NSUTF8StringEncoding];
        if(!coordData||(coordData.length&&memchr(coordData.bytes,0,coordData.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *space=[coord lowercaseString];check.frame.pointCoord=[space isEqualToString:@"point"];check.frame.validCoord=check.frame.pointCoord||[space isEqualToString:@"pixel"];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFrameColors(check,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFrameFindMultiColor]) {
        int frameId=[args count]>0?[[args objectAtIndex:0] intValue]:0;
        NSArray *points=[args count]>1?[args objectAtIndex:1]:@[];
        NSDictionary *options=[args count]>2?[args objectAtIndex:2]:@{};
        TLinkNativeFrameMultiRequest search;const bool decoded=TLinkautoJSDecodePointColors(points,search.colors);
        if(frameId<=0||!decoded)return [TLinkJSNativeResponse responseWithError:@"frame color method requires a frame id and point colors" code:@-1];
        NSString *coord=TLinkautoJSStringOption(options,@"coord",@"pixel");
        if(!TLinkautoJSValidToken(coord))return [TLinkJSNativeResponse responseWithError:@"coord contains unsupported protocol delimiter" code:@-1];
        search.colors.frame.frameId=frameId;search.colors.frame.maxAgeMs=TLinkautoJSIntOption(options,@"maxAgeMs",1000);
        double x=TLinkautoJSDoubleOption(options,@"x",0),y=TLinkautoJSDoubleOption(options,@"y",0),width=TLinkautoJSDoubleOption(options,@"width",0),height=TLinkautoJSDoubleOption(options,@"height",0);
        if(!TLinkautoJSIsFiniteNumber(x)||!TLinkautoJSIsFiniteNumber(y)||!TLinkautoJSIsFiniteNumber(width)||!TLinkautoJSIsFiniteNumber(height))return [TLinkJSNativeResponse responseWithError:@"frameFindMultiColor options require finite x/y/width/height" code:@-1];
        search.setRegion(x,y,width,height);search.colors.mode=TLinkautoJSIntOption(options,@"mode",1);
        // Preserve the bounded scalar formatter's four decimals and nonfinite spelling.
        NSString *threshold=[NSString stringWithFormat:@"%.4f",TLinkautoJSDoubleOption(options,@"value",TLinkautoJSDoubleOption(options,@"tolerance",0))];
        search.colors.toleranceUnits=threshold.length;search.colors.toleranceValid=TLinkColorDouble(threshold.UTF8String,search.colors.tolerance);
        search.skip=TLinkautoJSIntOption(options,@"skip",0);
        if(!TLinkFrameMultiInputFits(search,coord.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        NSData *coordData=[coord dataUsingEncoding:NSUTF8StringEncoding];
        if(!coordData||(coordData.length&&memchr(coordData.bytes,0,coordData.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *space=[coord lowercaseString];search.colors.frame.pointCoord=[space isEqualToString:@"point"];search.colors.frame.validCoord=search.colors.frame.pointCoord||[space isEqualToString:@"pixel"];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFrameMulti(search,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFindImageInFrame]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        int imageId = [args count] > 1 ? [[args objectAtIndex:1] intValue] : 0;
        NSDictionary *options = [args count] > 2 ? [args objectAtIndex:2] : @{};
        if (frameId <= 0 || imageId <= 0) return [TLinkJSNativeResponse responseWithError:@"findImageInFrame(frameId, imageId, options) requires positive ids" code:@-1];
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(coord)) return [TLinkJSNativeResponse responseWithError:@"coord contains unsupported protocol delimiter" code:@-1];
        TLinkNativeFrameImageRequest search;search.frameId=frameId;search.imageId=imageId;
        // Bounded scalar strings preserve Foundation decimal/nonfinite spelling and input units.
        const double region[]={TLinkautoJSDoubleOption(options,@"x",0),TLinkautoJSDoubleOption(options,@"y",0),TLinkautoJSDoubleOption(options,@"width",0),TLinkautoJSDoubleOption(options,@"height",0)};
        for(unsigned i=0;i<4;++i){NSString *text=[NSString stringWithFormat:@"%.0f",region[i]];search.regionPart(i,text.UTF8String,text.length);}
        const double scalars[]={TLinkautoJSDoubleOption(options,@"acceptable",.95),TLinkautoJSDoubleOption(options,@"scaleMin",1),TLinkautoJSDoubleOption(options,@"scaleMax",1),TLinkautoJSDoubleOption(options,@"scaleStep",1)};
        for(unsigned i=0;i<4;++i){NSString *text=[NSString stringWithFormat:@"%.4f",scalars[i]];search.scalarPart(i,text.UTF8String,text.length);}
        search.pixelSkip=TLinkautoJSIntOption(options,@"pixelSkip",0);search.maxAgeMs=TLinkautoJSIntOption(options,@"maxAgeMs",1000);
        if(!TLinkNativeFrameImageInputFits(search,coord.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        NSData *coordData=[coord dataUsingEncoding:NSUTF8StringEncoding];
        if(!coordData||(coordData.length&&memchr(coordData.bytes,0,coordData.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];
        NSString *space=[coord lowercaseString];search.pointCoord=[space isEqualToString:@"point"];search.validCoord=search.pointCoord||[space isEqualToString:@"pixel"];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFrameImage(search,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOcrLanguages]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02dcheck_langs", TASK_OCR_TESSERACT_REGION] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 3) return [TLinkJSNativeResponse responseWithValue:TLinkautoJSOCRResultByAddingDecodedError(result)];
        NSString *langsText = TLinkautoJSBase64Decode(TLinkautoJSSafeStringPart(parts, 2));
        NSArray *langs = [langsText length] > 0 ? [langsText componentsSeparatedByString:@","] : @[];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"languages": langs, @"value": langsText ?: @""})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOcrFrame]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        if ([context.cancellationToken isCancelled]) return [TLinkJSNativeResponse responseWithError:@"JavaScript execution was aborted" code:@-1];
        if (frameId <= 0) return [TLinkJSNativeResponse responseWithError:@"ocrFrame(frameId, options) requires a positive frame id" code:@-1];
        double x = TLinkautoJSDoubleOption(options, @"x", 0), y = TLinkautoJSDoubleOption(options, @"y", 0), width = TLinkautoJSDoubleOption(options, @"width", 0), height = TLinkautoJSDoubleOption(options, @"height", 0);
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) return [TLinkJSNativeResponse responseWithError:@"ocrFrame options require finite x/y/width/height" code:@-1];
        NSString *lang = TLinkautoJSStringOption(options, @"lang", @"vie");
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(lang) || !TLinkautoJSValidToken(coord)) return [TLinkJSNativeResponse responseWithError:@"ocrFrame lang/coord contains unsupported protocol delimiter" code:@-1];
        TLinkNativeFrameOCRRequest input;input.frameId=uint32_t(frameId);size_t regionUnits=0;
        const double region[]={x,y,width,height};int *positions[]={&input.x,&input.y,&input.width,&input.height};
        for(unsigned i=0;i<4;++i){NSString *part=[NSString stringWithFormat:@"%.0f",region[i]];*positions[i]=[part intValue];regionUnits+=part.length;}
        input.oem=TLinkautoJSIntOption(options,@"oem",1);input.psm=TLinkautoJSIntOption(options,@"psm",7);
        NSString *encodedWhitelist=TLinkautoJSBase64Encode(TLinkautoJSStringOption(options,@"whitelist",@""));input.whitelist=TLinkautoJSBase64Decode(encodedWhitelist);
        input.scaleUp=TLinkautoJSIntOption(options,@"scaleUp",2);input.thresholdMode=TLinkautoJSIntOption(options,@"thresholdMode",0);
        const int age=TLinkautoJSIntOption(options,@"maxAgeMs",1000);input.maxAgeMs=age>0?uint64_t(age):1000;
        if(!TLinkNativeOCRInputFits(frameId,input.oem,input.psm,input.scaleUp,input.thresholdMode,age,regionUnits,lang.length,encodedWhitelist.length,coord.length))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        for(NSString *token in @[lang,coord]){NSData *data=[token dataUsingEncoding:NSUTF8StringEncoding];if(!data||(data.length&&memchr(data.bytes,0,data.length)))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"invalid_payload")];}
        input.lang=lang;input.coord=coord;
        NSDictionary *result=TLinkExecuteNativeFrameOCR(input,context);
        if (![result[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:TLinkautoJSOCRResultByAddingDecodedError(result)];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOcr]) {
        NSDictionary *options = [args count] > 0 ? [args objectAtIndex:0] : @{};
        TLinkJSNativeResponse *frameRes = [self executeRequest:[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodCaptureFrame arguments:@[@{@"gray": @1, @"bgra": @0, @"ttlMs": @(TLinkautoJSIntOption(options, @"ttlMs", 1000))}]] context:context error:error];
        NSDictionary *frame = frameRes.value;
        if (![frame[@"ok"] boolValue]) return frameRes;
        int frameId = [frame[@"id"] intValue];
        NSMutableDictionary *ocrOptions = [NSMutableDictionary dictionaryWithDictionary:[options isKindOfClass:[NSDictionary class]] ? options : @{}];
        if (!ocrOptions[@"width"]) ocrOptions[@"width"] = frame[@"width"] ?: @0;
        if (!ocrOptions[@"height"]) ocrOptions[@"height"] = frame[@"height"] ?: @0;
        TLinkJSNativeResponse *ocrRes = [self executeRequest:[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodOcrFrame arguments:@[@(frameId), ocrOptions]] context:context error:error];
        [self executeRequest:[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodReleaseFrame arguments:@[@(frameId)]] context:context error:nil];
        return ocrRes;
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFrontMostAppId]) {
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFrontmost(TASK_FRONTMOST_APP_ID,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOrientation]) {
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFrontmost(TASK_FRONTMOST_APP_ORIENTATION,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOpenApp] || [method isEqualToString:TLinkJSNativeMethodKillApp] || [method isEqualToString:TLinkJSNativeMethodAppState] || [method isEqualToString:TLinkJSNativeMethodAppInfo] || [method isEqualToString:TLinkJSNativeMethodAppPid] || [method isEqualToString:TLinkJSNativeMethodAppPaths]) {
        NSString *bundleId = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if (!TLinkautoJSValidProtocolString(bundleId)) return [TLinkJSNativeResponse responseWithError:@"app method requires a valid bundle id" code:@-1];
        if ([method isEqualToString:TLinkJSNativeMethodAppPid]) return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeAppPid(bundleId,context)];
        if ([method isEqualToString:TLinkJSNativeMethodAppState]) return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeAppState(bundleId,context)];
        if ([method isEqualToString:TLinkJSNativeMethodAppInfo]) return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeAppInfo(bundleId,context)];
        if ([method isEqualToString:TLinkJSNativeMethodAppPaths]) return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeAppPaths(bundleId,context)];
        if ([method isEqualToString:TLinkJSNativeMethodKillApp]) return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeKillApp(bundleId,context)];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeOpenApp(bundleId,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFrontMostPid]) {
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeFrontmostPid(context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodListBundles]) {
        BOOL withInfo = [args count] > 0 ? [[args objectAtIndex:0] boolValue] : NO;
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_LIST_BUNDLES, withInfo ? @"1" : @"0"] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        if (withInfo) {
            NSString *json = TLinkautoJSBase64Decode(TLinkautoJSSafeStringPart(parts, 1));
            NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
            id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSArray *items = [obj isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)obj)[@"items"] : @[];
            return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"items": [items isKindOfClass:[NSArray class]] ? items : @[]})];
        }
        NSString *raw = TLinkautoJSSafeStringPart(parts, 1);
        NSArray *bundleIds = [raw length] > 0 ? [raw componentsSeparatedByString:@",,"] : @[];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"bundleIds": bundleIds})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOpenUrl]) {
        NSString *url = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if (!TLinkautoJSValidProtocolString(url)) return [TLinkJSNativeResponse responseWithError:@"openUrl(url) requires a valid URL string" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_OPEN_URL, url] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodConnectivity]) {
        int task = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSString *enabledKey = [args count] > 1 ? [args objectAtIndex:1] : @"enabled";
        id value = [args count] > 2 ? [args objectAtIndex:2] : [NSNull null];
        NSString *payload = (value && value != [NSNull null]) ? [NSString stringWithFormat:@"1;;%d", [value boolValue] ? 1 : 0] : @"0";
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", task, payload] context:context];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSStateResult(result, enabledKey)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodRootDir] || [method isEqualToString:TLinkJSNativeMethodCurrentDir] || [method isEqualToString:TLinkJSNativeMethodBotPath]) {
        int task = [method isEqualToString:TLinkJSNativeMethodRootDir] ? TASK_ROOT_DIR : ([method isEqualToString:TLinkJSNativeMethodCurrentDir] ? TASK_CURRENT_DIR : TASK_BOT_PATH);
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativePath(task,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodInfo]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d30", TASK_GET_DEVICE_INFO] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 6) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"name": TLinkautoJSSafeStringPart(parts, 1), @"systemName": TLinkautoJSSafeStringPart(parts, 2), @"systemVersion": TLinkautoJSSafeStringPart(parts, 3), @"model": TLinkautoJSSafeStringPart(parts, 4), @"identifierForVendor": TLinkautoJSSafeStringPart(parts, 5)})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodBatteryInfo]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d31", TASK_GET_DEVICE_INFO] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 3) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"state": @([TLinkautoJSSafeStringPart(parts, 1) intValue]), @"level": @([TLinkautoJSSafeStringPart(parts, 2) doubleValue])})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodAlert]) {
        NSString *title = [args count] > 0 ? [args objectAtIndex:0] : @"TLinkauto";
        NSString *message = [args count] > 1 ? [args objectAtIndex:1] : @"";
        int duration = [args count] > 2 ? [[args objectAtIndex:2] intValue] : 3;
        if (duration <= 0) duration = 3;
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@;;%@;;%d", TASK_SHOW_ALERT_BOX, title ?: @"TLinkauto", message ?: @"", duration] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodDialog]) {
        NSString *title = [args count] > 0 ? [args objectAtIndex:0] : @"TLinkauto";
        NSString *message = [args count] > 1 ? [args objectAtIndex:1] : @"";
        NSString *ok = [args count] > 2 ? [args objectAtIndex:2] : @"OK";
        NSString *cancel = [args count] > 3 ? [args objectAtIndex:3] : @"Cancel";
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@;;%@;;%@;;%@", TASK_DIALOG, title ?: @"TLinkauto", message ?: @"", ok ?: @"OK", cancel ?: @"Cancel"] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"response": @([TLinkautoJSSafeStringPart(parts, 1) intValue])})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodClearDialogValues]) {
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d", TASK_CLEAR_DIALOG] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodKeyboard]) {
        int kind = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSString *content = [args count] > 1 && [args objectAtIndex:1] != [NSNull null] ? [args objectAtIndex:1] : nil;
        NSString *payload = content ? [NSString stringWithFormat:@"%d;;%@", kind, content] : [NSString stringWithFormat:@"%d", kind];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_TEXT_INPUT, payload] context:context];
        if (kind != 6) return [TLinkJSNativeResponse responseWithValue:result];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"text": TLinkautoJSSafeStringPart(parts, 1)})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodHardwareKey]) {
        int keyAction = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        int keyType = [args count] > 1 ? [[args objectAtIndex:1] intValue] : -1;
        if (keyType <= 0 || keyAction < 0) return [TLinkJSNativeResponse responseWithError:@"hardwareKey requires valid normalized key/action" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeHardwareKey(keyAction,keyType,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodPressHardwareKey]) {
        int keyType = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (keyType <= 0) return [TLinkJSNativeResponse responseWithError:@"pressHardwareKey requires valid normalized key" code:@-1];
        TLinkJSNativeResponse *down = nil;
        TLinkJSNativeResponse *up = nil;
        NSDictionary *downValue = nil;
        BOOL completed = NO;
        @try {
            down = [self executeRequest:[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodHardwareKey arguments:@[@1, @(keyType)]] context:context error:error];
            downValue = down.value;
            // DOWN may have committed just before the child dispatch reports cancellation.
            if (![downValue[@"ok"] boolValue]) return down;
            completed = TLinkNativeWaitNs(50 * 1000000);
        } @finally {
            up = [self executeRequest:[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodHardwareKey arguments:@[@0, @(keyType)]] context:context error:error];
        }
        if (!completed) return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(TLinkNativeStopCode([context nativeBudget]->reason()))];
        if (up.ok) up.value = TLinkautoJSResultByAdding(up.value, @{@"down": downValue ?: @{}});
        return up;
    }
    else if ([method isEqualToString:TLinkJSNativeMethodKeepAwake]) {
        BOOL enabled = [args count] > 0 ? [[args objectAtIndex:0] boolValue] : NO;
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeKeepAwake(enabled,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodTouchIndicator]) {
        int value = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (value < 0) return [TLinkJSNativeResponse responseWithError:@"touchIndicator requires valid normalized action" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeIndicator(value,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodSaveScreenshotToAlbum]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if (!TLinkautoJSValidProtocolString(path)) return [TLinkJSNativeResponse responseWithError:@"saveScreenshotToAlbum(path) requires a valid path" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d2;;%@", TASK_SCREENSHOT, path] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodClearScreenshotAlbum]) {
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d3", TASK_SCREENSHOT] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodSetAutoLaunch]) {
        NSString *name = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *script = [args count] > 1 ? [args objectAtIndex:1] : @"";
        BOOL enabled = [args count] > 2 ? [[args objectAtIndex:2] boolValue] : NO;
        if (!TLinkautoJSValidProtocolString(name) || !TLinkautoJSValidProtocolString(script)) return [TLinkJSNativeResponse responseWithError:@"setAutoLaunch(name, script, enabled) requires valid name and script path" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@;;%@;;%d", TASK_SET_AUTO_LAUNCH, name, script, enabled ? 1 : 0] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodListAutoLaunch]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d", TASK_LIST_AUTO_LAUNCH] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:result];
        NSMutableArray *items = [NSMutableArray array];
        for (NSUInteger i = 1; i < [parts count]; i++) {
            NSString *entry = TLinkautoJSSafeStringPart(parts, i);
            if ([entry length] == 0) continue;
            NSArray *fields = [entry componentsSeparatedByString:@",,"];
            if ([fields count] >= 3) [items addObject:@{@"name": TLinkautoJSSafeStringPart(fields, 0), @"script": TLinkautoJSSafeStringPart(fields, 1), @"enabled": @([TLinkautoJSSafeStringPart(fields, 2) intValue] != 0)}];
        }
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"items": items})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodSetTimer]) {
        NSString *name = [args count] > 0 ? [args objectAtIndex:0] : @"";
        double interval = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        BOOL repeat = [args count] > 2 ? [[args objectAtIndex:2] boolValue] : NO;
        NSString *script = [args count] > 3 ? [args objectAtIndex:3] : @"";
        if (!TLinkautoJSValidProtocolString(name) || !TLinkautoJSValidProtocolString(script) || !TLinkautoJSIsFiniteNumber(interval) || interval <= 0) return [TLinkJSNativeResponse responseWithError:@"setTimer(name, interval, repeat, script) requires valid values" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@;;%.3f;;%d;;%@", TASK_SET_TIMER, name, interval, repeat ? 1 : 0, script] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodRemoveTimer]) {
        NSString *name = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if (!TLinkautoJSValidProtocolString(name)) return [TLinkJSNativeResponse responseWithError:@"removeTimer(name) requires a valid timer name" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_REMOVE_TIMER, name] context:context]];
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
        TLinkNativeColorRangeRequest search;search.setRegion(x,y,width,height);
        search.redMin=redMin;search.redMax=redMax;search.greenMin=greenMin;search.greenMax=greenMax;search.blueMin=blueMin;search.blueMax=blueMax;search.skip=skip;
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeColorRange(search,context)];
    }

    else if ([method isEqualToString:TLinkJSNativeMethodIsColors]) {
        NSArray *points=[args count]>0?[args objectAtIndex:0]:@[];
        NSDictionary *options=[args count]>1?[args objectAtIndex:1]:@{};
        TLinkNativeColorPointsRequest check;
        if(!TLinkautoJSDecodeLivePointColors(points,check))return [TLinkJSNativeResponse responseWithError:@"requires 1-512 valid point colors" code:@-1];
        check.mode=[options[@"mode"] respondsToSelector:@selector(intValue)]?[options[@"mode"] intValue]:1;
        double value=[options[@"value"] respondsToSelector:@selector(doubleValue)]?[options[@"value"] doubleValue]:([options[@"tolerance"] respondsToSelector:@selector(doubleValue)]?[options[@"tolerance"] doubleValue]:0);
        // Preserve the legacy four-decimal, signed-zero and nonfinite scalar spelling.
        NSString *threshold=[NSString stringWithFormat:@"%.4f",value];check.toleranceUnits=threshold.length;
        check.toleranceValid=TLinkColorDouble(threshold.UTF8String,check.tolerance);
        if(!TLinkNativeColorPointsInputFits(check))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeColorPoints(check,context)];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodFindMultiColor]) {
        NSArray *points=[args count]>0?[args objectAtIndex:0]:@[];
        NSDictionary *options=[args count]>1?[args objectAtIndex:1]:@{};
        TLinkNativeColorMultiRequest search;
        if(!TLinkautoJSDecodeLivePointColors(points,search.colors))return [TLinkJSNativeResponse responseWithError:@"requires 1-512 valid point colors" code:@-1];
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
        search.setRegion(x,y,width,height);search.colors.mode=mode;search.skip=skip;
        // Keep the legacy four-decimal, signed-zero and nonfinite scalar spelling.
        NSString *threshold=[NSString stringWithFormat:@"%.4f",value];search.colors.toleranceUnits=threshold.length;
        search.colors.toleranceValid=TLinkColorDouble(threshold.UTF8String,search.colors.tolerance);
        if(!TLinkNativeColorMultiInputFits(search))return [TLinkJSNativeResponse responseWithValue:TLinkNativeFailure(@"input_too_large")];
        return [TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeColorMulti(search,context)];
    }

    return [TLinkJSNativeResponse responseWithError:[NSString stringWithFormat:@"Unimplemented method: %@", method] code:@-1];
}

@end
