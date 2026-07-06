#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <string.h>
#include <ctype.h>
#include <dispatch/dispatch.h>
#include <netinet/tcp.h>
#include <sys/utsname.h>

#include "POCSocketServer.h"
#include "TouchInjector.h"
#import "CaptureCore.h"
#import "StreamCaptureProbe.h"

// ---------------------------------------------------------------------------
// POC socket server
//
// Trimmed-down standalone version of the original tlinkauto-binary SocketServer.
// Listens on TCP 6000 and handles ONLY the legacy task-10 (touch) wire format,
// calling POCPerformTouchFromRawData directly in-process. There is no IPC /
// CFMessagePort hop, because everything now lives in one app process.
//
// Wire format (legacy, line-delimited, terminated by \n or \r\n):
//   "10" + count(1) + [type(1) index(2) x(5) y(5)] per finger
// Task 10 is fire-and-forget: no response is written back, matching the
// original daemon behaviour so existing Python clients don't block.
// ---------------------------------------------------------------------------

static BOOL sServerStarted = NO;

static dispatch_queue_t POCSocketQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.tlinkauto.trollstore.task-server", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@interface POCClientContext : NSObject
@property(nonatomic, assign) CFReadStreamRef readStream;
@property(nonatomic, assign) CFWriteStreamRef writeStream;
@property(nonatomic, assign) CFRunLoopRef runLoop;
@property(nonatomic, strong) NSMutableData *buffer;
@end

@implementation POCClientContext
@end

static NSMutableDictionary *sClients = nil;
static const NSUInteger kMaxBuffer = 64 * 1024;

static int POCTaskTypeFromBuffer(const char *buffer)
{
    if (!buffer || !isdigit(buffer[0]) || !isdigit(buffer[1])) return -1;
    return (buffer[0] - '0') * 10 + (buffer[1] - '0');
}

static NSData *TLinkResponse(BOOL ok, NSString *payload)
{
    payload = [[payload ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "]
        stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    NSString *line = nil;
    if (payload.length > 0) {
        line = [NSString stringWithFormat:@"%@;;%@\r\n", ok ? @"0" : @"-1", payload];
    } else {
        line = ok ? @"0\r\n" : @"-1;;unknown_error\r\n";
    }
    return [line dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData *TLinkSuccess(NSString *payload)
{
    return TLinkResponse(YES, payload);
}

static NSData *TLinkError(NSString *payload)
{
    return TLinkResponse(NO, payload ?: @"unknown_error");
}

static NSData *TLinkUnsupported(int taskType, NSString *detail)
{
    NSString *message = detail.length > 0
        ? [NSString stringWithFormat:@"unsupported_on_trollstore task=%d %@", taskType, detail]
        : [NSString stringWithFormat:@"unsupported_on_trollstore task=%d", taskType];
    return TLinkError(message);
}

static NSString *TLinkBodyFromLine(const char *line)
{
    if (!line || strlen(line) < 2) return @"";
    const char *body = line + 2;
    if (body[0] == ';' && body[1] == ';') body += 2;
    return [NSString stringWithUTF8String:body] ?: @"";
}

static NSArray<NSString *> *TLinkSplitBody(NSString *body)
{
    if (!body) return @[];
    return [body componentsSeparatedByString:@";;"];
}

static int TLinkClampTouchCoord(CGFloat value)
{
    if (value < 0) value = 0;
    int fixed = (int)(value * 10.0f + 0.5f);
    if (fixed > 99999) fixed = 99999;
    return fixed;
}

static NSString *TLinkTouchPayload(int type, int finger, CGFloat x, CGFloat y)
{
    if (finger < 0) finger = 0;
    if (finger > 99) finger = 99;
    return [NSString stringWithFormat:@"1%d%02d%05d%05d",
            type, finger, TLinkClampTouchCoord(x), TLinkClampTouchCoord(y)];
}

static void TLinkPerformSingleTouch(int type, int finger, CGFloat x, CGFloat y)
{
    NSString *payload = TLinkTouchPayload(type, finger, x, y);
    POCPerformTouchFromRawData((const unsigned char *)[payload UTF8String]);
}

static BOOL TLinkHandleNativeTap(NSString *body, NSString **error)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 2) {
        if (error) *error = @"Native tap format: x;;y[;;duration_ms;;finger]";
        return NO;
    }
    CGFloat x = [parts[0] floatValue];
    CGFloat y = [parts[1] floatValue];
    int durationMs = parts.count >= 3 ? [parts[2] intValue] : 50;
    int finger = parts.count >= 4 ? [parts[3] intValue] : 0;
    if (durationMs < 0) durationMs = 0;

    TLinkPerformSingleTouch(POC_TOUCH_DOWN, finger, x, y);
    if (durationMs > 0) usleep((useconds_t)durationMs * 1000);
    TLinkPerformSingleTouch(POC_TOUCH_UP, finger, x, y);
    return YES;
}

static BOOL TLinkHandleNativeSwipe(NSString *body, NSString **error)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 5) {
        if (error) *error = @"Native swipe format: x1;;y1;;x2;;y2;;duration_ms[;;finger;;steps]";
        return NO;
    }
    CGFloat x1 = [parts[0] floatValue];
    CGFloat y1 = [parts[1] floatValue];
    CGFloat x2 = [parts[2] floatValue];
    CGFloat y2 = [parts[3] floatValue];
    int durationMs = [parts[4] intValue];
    int finger = parts.count >= 6 ? [parts[5] intValue] : 0;
    int steps = parts.count >= 7 ? [parts[6] intValue] : durationMs / 16;
    if (durationMs < 0) durationMs = 0;
    if (steps < 2) steps = 2;
    if (steps > 120) steps = 120;

    TLinkPerformSingleTouch(POC_TOUCH_DOWN, finger, x1, y1);
    int sleepPerStep = steps > 0 ? durationMs * 1000 / steps : 0;
    for (int i = 1; i < steps; i++) {
        if (sleepPerStep > 0) usleep((useconds_t)sleepPerStep);
        CGFloat t = (CGFloat)i / (CGFloat)steps;
        TLinkPerformSingleTouch(POC_TOUCH_MOVE, finger, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
    if (sleepPerStep > 0) usleep((useconds_t)sleepPerStep);
    TLinkPerformSingleTouch(POC_TOUCH_UP, finger, x2, y2);
    return YES;
}

static BOOL TLinkParseGesturePoint(NSString *text, CGFloat *x, CGFloat *y)
{
    NSArray<NSString *> *xy = [text componentsSeparatedByString:@","];
    if (xy.count != 2) return NO;
    if (x) *x = [xy[0] floatValue];
    if (y) *y = [xy[1] floatValue];
    return YES;
}

static BOOL TLinkHandleNativeGesture(NSString *body, NSString **error)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 3) {
        if (error) *error = @"Native gesture format: finger;;duration_ms;;x,y|x,y|...";
        return NO;
    }
    int finger = [parts[0] intValue];
    int durationMs = [parts[1] intValue];
    NSArray<NSString *> *pointTexts = [parts[2] componentsSeparatedByString:@"|"];
    if (pointTexts.count < 2) {
        if (error) *error = @"Native gesture requires at least two points";
        return NO;
    }
    if (durationMs < 0) durationMs = 0;

    CGFloat x = 0, y = 0;
    if (!TLinkParseGesturePoint(pointTexts[0], &x, &y)) {
        if (error) *error = @"Invalid first gesture point";
        return NO;
    }
    TLinkPerformSingleTouch(POC_TOUCH_DOWN, finger, x, y);

    int intervals = (int)pointTexts.count - 1;
    int sleepPerInterval = intervals > 0 ? durationMs * 1000 / intervals : 0;
    for (NSUInteger i = 1; i < pointTexts.count; i++) {
        if (!TLinkParseGesturePoint(pointTexts[i], &x, &y)) {
            TLinkPerformSingleTouch(POC_TOUCH_UP, finger, x, y);
            if (error) *error = @"Invalid gesture point";
            return NO;
        }
        TLinkPerformSingleTouch(POC_TOUCH_MOVE, finger, x, y);
        if (sleepPerInterval > 0) usleep((useconds_t)sleepPerInterval);
    }
    TLinkPerformSingleTouch(POC_TOUCH_UP, finger, x, y);
    return YES;
}

static BOOL TLinkHandleNativeBatch(NSString *body, NSString **error)
{
    if (body.length == 0) {
        if (error) *error = @"Native batch format: command||command, command starts with 10/62/63/64";
        return NO;
    }
    NSArray<NSString *> *commands = [body componentsSeparatedByString:@"||"];
    for (NSString *cmd in commands) {
        if (cmd.length < 2) continue;
        int task = [[cmd substringToIndex:2] intValue];
        NSString *payload = [cmd substringFromIndex:2];
        if (task == 10) {
            if ([payload hasPrefix:@";;"]) payload = [payload substringFromIndex:2];
            POCPerformTouchFromRawData((const unsigned char *)[payload UTF8String]);
        } else if (task == 62) {
            if (!TLinkHandleNativeTap(payload, error)) return NO;
        } else if (task == 63) {
            if (!TLinkHandleNativeSwipe(payload, error)) return NO;
        } else if (task == 64) {
            if (!TLinkHandleNativeGesture(payload, error)) return NO;
        } else {
            if (error) *error = [NSString stringWithFormat:@"Unsupported batch task: %d", task];
            return NO;
        }
    }
    return YES;
}

static CGSize TLinkScreenPixelSize(void)
{
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGSize bounds = [UIScreen mainScreen].bounds.size;
    CGFloat w = bounds.width * scale;
    CGFloat h = bounds.height * scale;
    return CGSizeMake(MIN(w, h), MAX(w, h));
}

static NSString *TLinkModelName(void)
{
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"";
}

static NSData *TLinkHandleDeviceInfo(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int subtask = parts.count > 0 ? [parts[0] intValue] : 0;
    UIDevice *device = [UIDevice currentDevice];
    if (subtask == 1) {
        CGSize size = TLinkScreenPixelSize();
        return TLinkSuccess([NSString stringWithFormat:@"%f;;%f", size.width, size.height]);
    }
    if (subtask == 2) {
        CGSize bounds = [UIScreen mainScreen].bounds.size;
        int orientation = bounds.width > bounds.height ? 4 : 1;
        return TLinkSuccess([NSString stringWithFormat:@"%d", orientation]);
    }
    if (subtask == 3) {
        return TLinkSuccess([NSString stringWithFormat:@"%f", [UIScreen mainScreen].scale]);
    }
    if (subtask == 30) {
        NSString *idfv = device.identifierForVendor.UUIDString ?: @"";
        NSString *info = [NSString stringWithFormat:@"%@;;%@;;%@;;%@;;%@",
                          device.name ?: @"",
                          device.systemName ?: @"iOS",
                          device.systemVersion ?: @"",
                          TLinkModelName(),
                          idfv];
        return TLinkSuccess(info);
    }
    if (subtask == 31) {
        device.batteryMonitoringEnabled = YES;
        int state = (int)device.batteryState;
        double level = device.batteryLevel < 0 ? -1.0 : device.batteryLevel * 100.0;
        return TLinkSuccess([NSString stringWithFormat:@"%d;;%f", state, level]);
    }
    return TLinkError([NSString stringWithFormat:@"Unknown device info task type: %d", subtask]);
}

static CaptureOutcome *TLinkRunCaptureOnMain(void)
{
    __block CaptureOutcome *outcome = nil;
    if ([NSThread isMainThread]) {
        outcome = [CaptureCore runCaptureProbe];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            outcome = [CaptureCore runCaptureProbe];
        });
    }
    return outcome;
}

static NSData *TLinkHandleScreenshot(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int action = parts.count > 0 ? [parts[0] intValue] : 0;
    if (action != 1) {
        return TLinkUnsupported(29, @"screenshot album save/clear is not ported yet");
    }
    if (parts.count < 2 || parts[1].length == 0) {
        return TLinkError(@"Screenshot task missing output path");
    }

    NSString *targetPath = parts[1];
    CaptureOutcome *outcome = TLinkRunCaptureOnMain();
    if (!outcome || !outcome.image || outcome.result == CaptureResultFail) {
        NSString *diag = outcome.diagnostics ?: @"capture failed";
        return TLinkError([NSString stringWithFormat:@"Unable to capture screenshot: %@", diag]);
    }

    UIImage *image = outcome.image;
    if (parts.count >= 6) {
        CGRect region = CGRectMake([parts[2] floatValue],
                                   [parts[3] floatValue],
                                   [parts[4] floatValue],
                                   [parts[5] floatValue]);
        CGImageRef source = image.CGImage;
        CGRect bounds = CGRectMake(0, 0, CGImageGetWidth(source), CGImageGetHeight(source));
        CGRect crop = CGRectIntersection(bounds, region);
        if (CGRectIsEmpty(crop)) {
            return TLinkError(@"Invalid screenshot region");
        }
        CGImageRef cropped = CGImageCreateWithImageInRect(source, crop);
        if (!cropped) {
            return TLinkError(@"Failed to crop screenshot");
        }
        image = [UIImage imageWithCGImage:cropped];
        CGImageRelease(cropped);
    }

    NSString *parent = [targetPath stringByDeletingLastPathComponent];
    if (parent.length > 0 && ![[NSFileManager defaultManager] fileExistsAtPath:parent]) {
        NSError *mkdirErr = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:parent
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&mkdirErr]) {
            return TLinkError([NSString stringWithFormat:@"Failed to create screenshot directory: %@",
                               mkdirErr.localizedDescription ?: parent]);
        }
    }

    NSString *ext = targetPath.pathExtension.lowercaseString;
    NSData *encoded = ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
        ? UIImageJPEGRepresentation(image, 0.75)
        : UIImagePNGRepresentation(image);
    if (!encoded || ![encoded writeToFile:targetPath atomically:NO]) {
        return TLinkError([NSString stringWithFormat:@"Failed to save screenshot: %@", targetPath]);
    }
    return TLinkSuccess(targetPath);
}

static NSData *TLinkHandleHelloStatus(void)
{
    NSDictionary *capabilities = @{
        @"touch": @(YES),
        @"touchAck": @(YES),
        @"nativeTouch": @(YES),
        @"capture": @(YES),
        @"h264": @(YES),
        @"image": @(NO),
        @"ocr": @(NO),
        @"script": @(NO),
        @"appMgmt": @(NO),
        @"hidMonitor": @(YES),
        @"privhelper": @(NO),
    };
    CGSize screen = TLinkScreenPixelSize();
    NSDictionary *payload = @{
        @"runtime": @"trollstore",
        @"service": @"streamd",
        @"phase": @"core-automation",
        @"pid": @((int)getpid()),
        @"screen": @{@"width": @((int)screen.width), @"height": @((int)screen.height), @"scale": @([UIScreen mainScreen].scale)},
        @"senderID": [NSString stringWithFormat:@"0x%llx", POCTouchCurrentSenderID()],
        @"dispatchVariant": @(POCTouchDispatchVariant()),
        @"ports": @{@"task": @6000, @"h264": @[@7001, @7002, @7003, @7004, @7005, @7006]},
        @"capabilities": capabilities,
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *b64 = [json base64EncodedStringWithOptions:0] ?: @"";
    return TLinkSuccess(b64);
}

static void TLinkEnsureRuntimeDirectories(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:@"/var/mobile/Library/TLinkauto" withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:@"/var/mobile/Library/TLinkauto/scripts" withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:@"/var/mobile/Library/TLinkauto/config" withIntermediateDirectories:YES attributes:nil error:nil];
}

static NSData *TLinkHandleTaskLine(const char *line)
{
    if (!line) return TLinkError(@"empty request");
    int taskType = POCTaskTypeFromBuffer(line);
    NSString *body = TLinkBodyFromLine(line);
    POCLogf("task-server: line='%s' task=%d", line, taskType);

    if (taskType == 18) {
        int us = [body intValue];
        if (us < 0) us = 0;
        usleep((useconds_t)us);
        return TLinkSuccess(nil);
    }

    if (taskType == 25) {
        return TLinkHandleDeviceInfo(body);
    }

    if (taskType == 29) {
        return TLinkHandleScreenshot(body);
    }

    if (taskType == 44 || taskType == 45) {
        TLinkEnsureRuntimeDirectories();
        return TLinkSuccess(@"/var/mobile/Library/TLinkauto");
    }

    if (taskType == 46) {
        TLinkEnsureRuntimeDirectories();
        return TLinkSuccess(@"/var/mobile/Library/TLinkauto/scripts");
    }

    if (taskType == 60) {
        return TLinkHandleHelloStatus();
    }

    if (taskType == 61) {
        NSRange sep = [body rangeOfString:@";;"];
        if (sep.location == NSNotFound) {
            return TLinkError(@"touch_ack_bad_payload");
        }
        NSString *seq = [body substringToIndex:sep.location];
        NSString *payload = [body substringFromIndex:sep.location + sep.length];
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        POCPerformTouchFromRawData((const unsigned char *)[payload UTF8String]);
        int dispatchUs = (int)((CFAbsoluteTimeGetCurrent() - start) * 1000000.0);
        return TLinkSuccess([NSString stringWithFormat:@"%@;;%d", seq, dispatchUs]);
    }

    if (taskType == 62) {
        NSString *err = nil;
        if (!TLinkHandleNativeTap(body, &err)) return TLinkError(err);
        return TLinkSuccess(nil);
    }

    if (taskType == 63) {
        NSString *err = nil;
        if (!TLinkHandleNativeSwipe(body, &err)) return TLinkError(err);
        return TLinkSuccess(nil);
    }

    if (taskType == 64) {
        NSString *err = nil;
        if (!TLinkHandleNativeGesture(body, &err)) return TLinkError(err);
        return TLinkSuccess(nil);
    }

    if (taskType == 65) {
        NSString *err = nil;
        if (!TLinkHandleNativeBatch(body, &err)) return TLinkError(err);
        return TLinkSuccess(nil);
    }

    if (taskType == 97) {
        NSString *cap = @"runtime=trollstore phase=core-automation ports=6000,7001,7002,7003,7004,7005,7006 tasks=10,18,25,29,44,45,46,60,61,62,63,64,65,97,98,99 capabilities=touch,capture,h264,hidMonitor,paths unsupported=image,ocr,script,appMgmt,privhelper";
        POCLogf("task-server: task97 capability report");
        return TLinkSuccess(cap);
    }

    if (taskType == 98) {
        __block NSString *summary = nil;
        if ([NSThread isMainThread]) {
            summary = SCStreamRunCaptureProbe(@"socket98");
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                summary = SCStreamRunCaptureProbe(@"socket98");
            });
        }
        NSString *response = summary ?: @"capture_socket98 result=FAIL png=<none>";
        POCLogf("task-server: task98 capture probe -> %s", [response UTF8String]);
        return TLinkSuccess(response);
    }

    if (taskType == 99) {
        POCLogf("task-server: task99 ping -> tlinkauto_alive");
        return TLinkSuccess(@"tlinkauto_alive");
    }

    return TLinkUnsupported(taskType, nil);
}

// Handle one complete line (without trailing newline). Returns nil for legacy
// fire-and-forget task 10; otherwise returns a short status line.
static NSData *POCHandleLine(const char *line)
{
    if (!line) return nil;
    int taskType = POCTaskTypeFromBuffer(line);
    POCLogf("socket: line='%s' task=%d", line, taskType);

    if (taskType == 10) {
        // Accept both legacy forms:
        //   10 + body
        //   10;; + body
        const char *body = line + 2;
        if (body[0] == ';' && body[1] == ';') body += 2;

        NSString *bodyString = [NSString stringWithUTF8String:body];
        if (!bodyString) bodyString = @"";
        POCLogf("socket: task10 received body='%s' len=%lu", body, (unsigned long)strlen(body));

        dispatch_async(dispatch_get_main_queue(), ^{
            const char *mainBody = [bodyString UTF8String];
            POCLogf("socket: task10 dispatching on main thread body='%s'", mainBody);
            POCPerformTouchFromRawData((const unsigned char *)mainBody);
        });
        return nil; // keep legacy touch fire-and-forget
    }

    return TLinkHandleTaskLine(line);
}

static void POCWriteAll(CFWriteStreamRef stream, NSData *data)
{
    if (!stream || !data || data.length == 0) return;
    const UInt8 *bytes = (const UInt8 *)data.bytes;
    CFIndex remaining = (CFIndex)data.length;
    while (remaining > 0) {
        CFIndex wrote = CFWriteStreamWrite(stream, bytes, remaining);
        if (wrote <= 0) break;
        bytes += wrote;
        remaining -= wrote;
    }
}

static void POCProcessBuffer(POCClientContext *ctx)
{
    if (!ctx || !ctx.buffer) return;

    while (true) {
        const UInt8 *bytes = (const UInt8 *)ctx.buffer.bytes;
        const NSUInteger len = ctx.buffer.length;
        if (len == 0) return;
        if (len > kMaxBuffer) {
            [ctx.buffer setLength:0];
            return;
        }

        NSUInteger nl = NSNotFound;
        for (NSUInteger i = 0; i < len; i++) {
            if (bytes[i] == '\n') { nl = i; break; }
        }
        if (nl == NSNotFound) return; // wait for more data

        NSUInteger lineLen = nl;
        if (lineLen > 0 && bytes[lineLen - 1] == '\r') lineLen -= 1;

        if (lineLen > 0) {
            char *line = (char *)malloc(lineLen + 1);
            memcpy(line, bytes, lineLen);
            line[lineLen] = 0;
            NSData *resp = POCHandleLine(line);
            if (resp) POCWriteAll(ctx.writeStream, resp);
            free(line);
        }

        NSUInteger removeLen = nl + 1;
        if (ctx.buffer.length >= removeLen) {
            [ctx.buffer replaceBytesInRange:NSMakeRange(0, removeLen) withBytes:NULL length:0];
        } else {
            [ctx.buffer setLength:0];
            return;
        }
    }
}

static void POCCleanupClient(CFReadStreamRef readStream)
{
    if (!readStream || !sClients) return;
    NSNumber *key = @((long)readStream);
    POCClientContext *ctx = [sClients objectForKey:key];
    if (!ctx) return;

    CFWriteStreamRef writeStream = ctx.writeStream;
    CFRunLoopRef runLoop = ctx.runLoop ? ctx.runLoop : CFRunLoopGetCurrent();
    [sClients removeObjectForKey:key];

    CFReadStreamSetClient(readStream, 0, NULL, NULL);
    CFReadStreamUnscheduleFromRunLoop(readStream, runLoop, kCFRunLoopCommonModes);
    CFReadStreamClose(readStream);
    CFRelease(readStream);
    if (writeStream) {
        CFWriteStreamClose(writeStream);
        CFRelease(writeStream);
    }
}

static void POCReadStreamCallback(CFReadStreamRef readStream, CFStreamEventType type, void *info)
{
    (void)info;
    dispatch_async(POCSocketQueue(), ^{
        @autoreleasepool {
            if (type == kCFStreamEventEndEncountered || type == kCFStreamEventErrorOccurred) {
                POCCleanupClient(readStream);
                return;
            }
            if (type != kCFStreamEventHasBytesAvailable) return;

            UInt8 buff[2048];
            CFIndex hasRead = CFReadStreamRead(readStream, buff, sizeof(buff));
            if (hasRead > 0) {
                POCClientContext *ctx = [sClients objectForKey:@((long)readStream)];
                if (!ctx) return;
                NSString *chunk = [[NSString alloc] initWithBytes:buff length:(NSUInteger)hasRead encoding:NSUTF8StringEncoding];
                POCLogf("socket: read %ld bytes chunk='%s'", (long)hasRead, chunk ? [chunk UTF8String] : "<non-utf8>");
                [ctx.buffer appendBytes:buff length:(NSUInteger)hasRead];
                POCProcessBuffer(ctx);
            } else {
                POCCleanupClient(readStream);
            }
        }
    });
}

static void POCAcceptCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    (void)socket; (void)address; (void)info;
    if (type != kCFSocketAcceptCallBack) return;

    CFSocketNativeHandle handle = *(CFSocketNativeHandle *)data;
    POCLogf("socket: accepted client fd=%d", handle);
    int one = 1;
    setsockopt(handle, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    CFReadStreamRef readStreamRef = NULL;
    CFWriteStreamRef writeStreamRef = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, handle, &readStreamRef, &writeStreamRef);
    if (!readStreamRef || !writeStreamRef) {
        if (readStreamRef) { CFReadStreamClose(readStreamRef); CFRelease(readStreamRef); }
        if (writeStreamRef) { CFWriteStreamClose(writeStreamRef); CFRelease(writeStreamRef); }
        close(handle);
        return;
    }

    CFReadStreamSetProperty(readStreamRef, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(writeStreamRef, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFReadStreamOpen(readStreamRef);
    CFWriteStreamOpen(writeStreamRef);

    CFStreamClientContext context = {0, NULL, NULL, NULL, NULL};
    CFOptionFlags events = kCFStreamEventHasBytesAvailable | kCFStreamEventEndEncountered | kCFStreamEventErrorOccurred;
    if (!CFReadStreamSetClient(readStreamRef, events, POCReadStreamCallback, &context)) {
        CFReadStreamClose(readStreamRef); CFRelease(readStreamRef);
        CFWriteStreamClose(writeStreamRef); CFRelease(writeStreamRef);
        return;
    }

    POCClientContext *ctx = [[POCClientContext alloc] init];
    ctx.readStream = readStreamRef;
    ctx.writeStream = writeStreamRef;
    ctx.runLoop = CFRunLoopGetCurrent();
    ctx.buffer = [NSMutableData data];
    dispatch_sync(POCSocketQueue(), ^{
        [sClients setObject:ctx forKey:@((long)readStreamRef)];
    });

    CFReadStreamScheduleWithRunLoop(readStreamRef, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
}

static void POCRunSocketServer(void)
{
    @autoreleasepool {
        CFSocketRef sock = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP,
                                          kCFSocketAcceptCallBack, POCAcceptCallback, NULL);
        if (!sock) {
            POCLogf("socket: failed to create CFSocket");
            return;
        }

        int reuse = 1;
        setsockopt(CFSocketGetNative(sock), SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = inet_addr(POC_SOCKET_ADDR);
        addr.sin_port = htons(POC_SOCKET_PORT);

        CFDataRef addrData = CFDataCreate(kCFAllocatorDefault, (UInt8 *)&addr, sizeof(addr));
        if (CFSocketSetAddress(sock, addrData) != kCFSocketSuccess) {
            POCLogf("socket: failed to bind port %d", POC_SOCKET_PORT);
            if (addrData) CFRelease(addrData);
            CFRelease(sock);
            return;
        }
        if (addrData) CFRelease(addrData);

        sClients = [[NSMutableDictionary alloc] init];
        POCLogf("socket: listening on port %d", POC_SOCKET_PORT);

        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, sock, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        CFRelease(source);
        CFRunLoopRun();
    }
}

void POCStartSocketServer(void)
{
    if (sServerStarted) return;
    sServerStarted = YES;
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        @autoreleasepool {
            POCRunSocketServer();
        }
    }];
    thread.name = @"tlink-task-server";
    [thread start];
}

void TLinkStartTaskServer(void)
{
    POCStartSocketServer();
}
