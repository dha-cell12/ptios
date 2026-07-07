#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#include <string.h>
#include <ctype.h>
#include <dispatch/dispatch.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <signal.h>
#include <unistd.h>
#include <netinet/tcp.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#import <objc/message.h>

#include "POCSocketServer.h"
#include "TouchInjector.h"
#import "CaptureCore.h"
#import "StreamCaptureProbe.h"

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

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

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property(nonatomic, readonly) NSString *localizedName;
@property(nonatomic, readonly) NSString *shortVersionString;
@property(nonatomic, readonly) NSString *bundleVersion;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
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

static NSString *TLinkJoinParts(NSArray<NSString *> *parts, NSUInteger start)
{
    if (!parts || start >= parts.count) return @"";
    return [[parts subarrayWithRange:NSMakeRange(start, parts.count - start)] componentsJoinedByString:@";;"];
}

static uint64_t TLinkNowMs(void)
{
    return (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000.0);
}

@interface TLinkImageObject : NSObject
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, assign) int width;
@property(nonatomic, assign) int height;
@property(nonatomic, assign) uint64_t createdAtMs;
@end

@implementation TLinkImageObject
@end

@interface TLinkFrameObject : NSObject
@property(nonatomic, assign) uint32_t frameId;
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, strong) NSData *rgbaData;
@property(nonatomic, assign) int width;
@property(nonatomic, assign) int height;
@property(nonatomic, assign) int bytesPerRow;
@property(nonatomic, assign) CGFloat scale;
@property(nonatomic, assign) BOOL hasBGRA;
@property(nonatomic, assign) BOOL hasGray;
@property(nonatomic, assign) uint64_t createdAtMs;
@property(nonatomic, assign) uint64_t expiresAtMs;
@end

@implementation TLinkFrameObject
@end

typedef struct {
    int x;
    int y;
    int r;
    int g;
    int b;
} TLinkPointColor;

static UIImage *sTLinkKeptScreenImage = nil;
static NSMutableDictionary<NSNumber *, TLinkImageObject *> *sTLinkImageStore = nil;
static NSMutableDictionary<NSNumber *, TLinkFrameObject *> *sTLinkFrameStore = nil;
static uint32_t sTLinkNextImageId = 1;
static uint32_t sTLinkNextFrameId = 1;
static const NSUInteger kTLinkMaxImageObjects = 64;
static const NSUInteger kTLinkMaxFrameObjects = 4;
static const uint64_t kTLinkDefaultFrameTtlMs = 1000;
static const uint64_t kTLinkHardFrameTtlMs = 5000;

static void TLinkEnsureVisionStores(void)
{
    if (!sTLinkImageStore) sTLinkImageStore = [[NSMutableDictionary alloc] init];
    if (!sTLinkFrameStore) sTLinkFrameStore = [[NSMutableDictionary alloc] init];
}

static CGSize TLinkImagePixelSize(UIImage *image)
{
    CGImageRef cg = image.CGImage;
    if (!cg) return CGSizeZero;
    return CGSizeMake((CGFloat)CGImageGetWidth(cg), (CGFloat)CGImageGetHeight(cg));
}

static CGRect TLinkClampRectToImage(CGRect rect, int width, int height)
{
    if (width <= 0 || height <= 0) return CGRectZero;
    int x = (int)rect.origin.x;
    int y = (int)rect.origin.y;
    int w = (int)rect.size.width;
    int h = (int)rect.size.height;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= width) x = width - 1;
    if (y >= height) y = height - 1;
    if (w <= 0 || x + w > width) w = width - x;
    if (h <= 0 || y + h > height) h = height - y;
    if (w <= 0 || h <= 0) return CGRectZero;
    return CGRectMake(x, y, w, h);
}

static UIImage *TLinkCropImage(UIImage *image, CGRect rect, NSString **error)
{
    CGImageRef source = image.CGImage;
    if (!source) {
        if (error) *error = @"image_missing_cgimage";
        return nil;
    }
    CGRect crop = TLinkClampRectToImage(rect, (int)CGImageGetWidth(source), (int)CGImageGetHeight(source));
    if (CGRectIsEmpty(crop)) {
        if (error) *error = @"invalid_crop_rect";
        return nil;
    }
    CGImageRef cropped = CGImageCreateWithImageInRect(source, crop);
    if (!cropped) {
        if (error) *error = @"crop_failed";
        return nil;
    }
    UIImage *result = [UIImage imageWithCGImage:cropped scale:image.scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return result;
}

static NSData *TLinkRGBADataFromCGImage(CGImageRef cgImage, int *outW, int *outH, int *outBpr)
{
    if (!cgImage) return nil;
    int width = (int)CGImageGetWidth(cgImage);
    int height = (int)CGImageGetHeight(cgImage);
    if (width <= 0 || height <= 0 || width > 20000 || height > 20000) return nil;

    int bytesPerRow = width * 4;
    size_t totalBytes = (size_t)bytesPerRow * (size_t)height;
    uint8_t *buffer = (uint8_t *)calloc(1, totalBytes);
    if (!buffer) return nil;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(buffer,
                                                 (size_t)width,
                                                 (size_t)height,
                                                 8,
                                                 (size_t)bytesPerRow,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        free(buffer);
        return nil;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);
    if (outW) *outW = width;
    if (outH) *outH = height;
    if (outBpr) *outBpr = bytesPerRow;
    return [NSData dataWithBytesNoCopy:buffer length:totalBytes freeWhenDone:YES];
}

static NSData *TLinkRGBADataFromImage(UIImage *image, int *outW, int *outH, int *outBpr)
{
    return TLinkRGBADataFromCGImage(image.CGImage, outW, outH, outBpr);
}

static BOOL TLinkReadRGBA(NSData *data, int width, int height, int bytesPerRow, int x, int y, int *r, int *g, int *b)
{
    if (!data || width <= 0 || height <= 0 || bytesPerRow <= 0) return NO;
    if (x < 0 || y < 0 || x >= width || y >= height) return NO;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger offset = (NSUInteger)y * (NSUInteger)bytesPerRow + (NSUInteger)x * 4;
    if (offset + 2 >= data.length) return NO;
    if (r) *r = bytes[offset];
    if (g) *g = bytes[offset + 1];
    if (b) *b = bytes[offset + 2];
    return YES;
}

static BOOL TLinkColorMatches(int r, int g, int b, int tr, int tg, int tb, int mode, double value)
{
    int dr = abs(r - tr);
    int dg = abs(g - tg);
    int db = abs(b - tb);
    if (mode == 1) {
        int dev = (int)value;
        return dr <= dev && dg <= dev && db <= dev;
    }
    double similarity = 1.0 - ((double)dr + (double)dg + (double)db) / (3.0 * 255.0);
    return similarity >= value;
}

static BOOL TLinkParsePointTable(NSString *table, NSMutableArray<NSValue *> *points, NSString **error)
{
    if (table.length == 0) {
        if (error) *error = @"point_table_empty";
        return NO;
    }
    NSArray<NSString *> *items = [table componentsSeparatedByString:@"|"];
    for (NSString *item in items) {
        if (item.length == 0) continue;
        NSArray<NSString *> *parts = [item componentsSeparatedByString:@",,"];
        if (parts.count != 5) {
            if (error) *error = @"invalid_point_table_format";
            return NO;
        }
        TLinkPointColor pc;
        pc.x = [parts[0] intValue];
        pc.y = [parts[1] intValue];
        pc.r = [parts[2] intValue];
        pc.g = [parts[3] intValue];
        pc.b = [parts[4] intValue];
        [points addObject:[NSValue valueWithBytes:&pc objCType:@encode(TLinkPointColor)]];
    }
    if (points.count == 0) {
        if (error) *error = @"point_table_empty";
        return NO;
    }
    return YES;
}

static BOOL TLinkFindTemplateInRGBA(NSData *hayData,
                                    int hayW,
                                    int hayH,
                                    int hayBpr,
                                    NSData *needleData,
                                    int needleW,
                                    int needleH,
                                    int needleBpr,
                                    CGRect searchRegion,
                                    double acceptable,
                                    int pixelSkip,
                                    int *outX,
                                    int *outY,
                                    double *outScore)
{
    if (!hayData || !needleData || hayW <= 0 || hayH <= 0 || needleW <= 0 || needleH <= 0) return NO;
    if (needleW > hayW || needleH > hayH) return NO;
    if (acceptable <= 0.0 || acceptable > 1.0) acceptable = 0.9;

    CGRect region = TLinkClampRectToImage(searchRegion, hayW, hayH);
    if (CGRectIsEmpty(region)) return NO;
    int rx = (int)region.origin.x;
    int ry = (int)region.origin.y;
    int rw = (int)region.size.width;
    int rh = (int)region.size.height;
    if (needleW > rw || needleH > rh) return NO;

    int anchorStep = pixelSkip + 1;
    if (anchorStep <= 0) anchorStep = 1;
    int sampleStep = 1;
    long samplePixels = (long)needleW * (long)needleH;
    if (samplePixels > 160000) sampleStep = 4;
    else if (samplePixels > 40000) sampleStep = 2;

    const uint8_t *hay = (const uint8_t *)hayData.bytes;
    const uint8_t *needle = (const uint8_t *)needleData.bytes;
    long long bestSad = LLONG_MAX;
    int bestX = -1;
    int bestY = -1;
    int sampleCount = 0;
    for (int ty = 0; ty < needleH; ty += sampleStep) {
        for (int tx = 0; tx < needleW; tx += sampleStep) {
            sampleCount++;
        }
    }
    if (sampleCount <= 0) return NO;

    int maxX = rx + rw - needleW;
    int maxY = ry + rh - needleH;
    for (int y = ry; y <= maxY; y += anchorStep) {
        for (int x = rx; x <= maxX; x += anchorStep) {
            long long sad = 0;
            for (int ty = 0; ty < needleH; ty += sampleStep) {
                const uint8_t *hayRow = hay + (NSUInteger)(y + ty) * (NSUInteger)hayBpr + (NSUInteger)x * 4;
                const uint8_t *needleRow = needle + (NSUInteger)ty * (NSUInteger)needleBpr;
                for (int tx = 0; tx < needleW; tx += sampleStep) {
                    const uint8_t *hp = hayRow + (NSUInteger)tx * 4;
                    const uint8_t *np = needleRow + (NSUInteger)tx * 4;
                    sad += llabs((long long)hp[0] - (long long)np[0]);
                    sad += llabs((long long)hp[1] - (long long)np[1]);
                    sad += llabs((long long)hp[2] - (long long)np[2]);
                    if (sad >= bestSad) break;
                }
                if (sad >= bestSad) break;
            }
            if (sad < bestSad) {
                bestSad = sad;
                bestX = x;
                bestY = y;
            }
        }
    }

    double score = 0.0;
    if (bestSad != LLONG_MAX) {
        double maxSad = (double)sampleCount * 3.0 * 255.0;
        score = 1.0 - ((double)bestSad / maxSad);
        if (score < 0.0) score = 0.0;
        if (score > 1.0) score = 1.0;
    }
    if (outX) *outX = bestX;
    if (outY) *outY = bestY;
    if (outScore) *outScore = score;
    return bestX >= 0 && bestY >= 0 && score >= acceptable;
}

static uint32_t TLinkStoreImageObject(UIImage *image)
{
    if (!image || !image.CGImage) return 0;
    TLinkEnsureVisionStores();
    while (sTLinkImageStore.count >= kTLinkMaxImageObjects) {
        NSNumber *key = sTLinkImageStore.allKeys.firstObject;
        if (!key) break;
        [sTLinkImageStore removeObjectForKey:key];
    }
    uint32_t imageId = sTLinkNextImageId++;
    if (imageId == 0) imageId = sTLinkNextImageId++;
    CGSize size = TLinkImagePixelSize(image);
    TLinkImageObject *obj = [[TLinkImageObject alloc] init];
    obj.image = image;
    obj.width = (int)size.width;
    obj.height = (int)size.height;
    obj.createdAtMs = TLinkNowMs();
    sTLinkImageStore[@(imageId)] = obj;
    return imageId;
}

static TLinkFrameObject *TLinkFrameForId(uint32_t frameId)
{
    TLinkEnsureVisionStores();
    return sTLinkFrameStore[@(frameId)];
}

static BOOL TLinkEnsureFrameRGBA(TLinkFrameObject *frame, NSString **error)
{
    if (!frame) {
        if (error) *error = @"frame_not_found";
        return NO;
    }
    if (frame.rgbaData.length > 0) return YES;
    int w = 0, h = 0, bpr = 0;
    NSData *data = TLinkRGBADataFromImage(frame.image, &w, &h, &bpr);
    if (!data) {
        if (error) *error = @"frame_bgra_render_failed";
        return NO;
    }
    frame.rgbaData = data;
    frame.width = w;
    frame.height = h;
    frame.bytesPerRow = bpr;
    frame.hasBGRA = YES;
    return YES;
}

static uint32_t TLinkStoreFrameObject(TLinkFrameObject *frame)
{
    if (!frame || !frame.image) return 0;
    TLinkEnsureVisionStores();
    while (sTLinkFrameStore.count >= kTLinkMaxFrameObjects) {
        NSNumber *key = sTLinkFrameStore.allKeys.firstObject;
        if (!key) break;
        [sTLinkFrameStore removeObjectForKey:key];
    }
    uint32_t frameId = sTLinkNextFrameId++;
    if (frameId == 0) frameId = sTLinkNextFrameId++;
    frame.frameId = frameId;
    sTLinkFrameStore[@(frameId)] = frame;
    return frameId;
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

static UIImage *TLinkCaptureScreenImage(NSString **error)
{
    CaptureOutcome *outcome = TLinkRunCaptureOnMain();
    if (!outcome || !outcome.image || outcome.result == CaptureResultFail) {
        NSString *diag = outcome.diagnostics ?: @"capture_failed";
        if (error) *error = [NSString stringWithFormat:@"capture_failed %@", diag];
        return nil;
    }
    return outcome.image;
}

static UIImage *TLinkScreenImageForVision(NSString **error)
{
    if (sTLinkKeptScreenImage) return sTLinkKeptScreenImage;
    return TLinkCaptureScreenImage(error);
}

static NSData *TLinkHandleScreenKeep(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int enabled = parts.count > 0 ? [parts[0] intValue] : 0;
    if (enabled) {
        NSString *err = nil;
        UIImage *image = TLinkCaptureScreenImage(&err);
        if (!image) return TLinkError(err);
        sTLinkKeptScreenImage = image;
        return TLinkSuccess(nil);
    }
    sTLinkKeptScreenImage = nil;
    return TLinkSuccess(nil);
}

static NSData *TLinkHandleColorPicker(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 2) return TLinkError(@"color_picker format: x;;y");
    int x = [parts[0] intValue];
    int y = [parts[1] intValue];
    NSString *err = nil;
    UIImage *image = TLinkScreenImageForVision(&err);
    if (!image) return TLinkError(err);
    int w = 0, h = 0, bpr = 0;
    NSData *rgba = TLinkRGBADataFromImage(image, &w, &h, &bpr);
    if (!rgba) return TLinkError(@"color_picker_rgba_failed");
    int r = 0, g = 0, b = 0;
    if (!TLinkReadRGBA(rgba, w, h, bpr, x, y, &r, &g, &b)) {
        return TLinkError(@"color_picker_point_out_of_bounds");
    }
    return TLinkSuccess([NSString stringWithFormat:@"%d;;%d;;%d", r, g, b]);
}

static NSData *TLinkHandleColorSearch(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 1) return TLinkError(@"color_search missing search type");
    int searchType = [parts[0] intValue];
    NSString *err = nil;
    UIImage *image = TLinkScreenImageForVision(&err);
    if (!image) return TLinkError(err);
    int screenW = 0, screenH = 0, bpr = 0;
    NSData *rgba = TLinkRGBADataFromImage(image, &screenW, &screenH, &bpr);
    if (!rgba) return TLinkError(@"color_search_rgba_failed");

    if (searchType == 1) {
        if (parts.count < 12) {
            return TLinkError(@"color_search single format: 1;;x;;y;;width;;height;;rmin;;rmax;;gmin;;gmax;;bmin;;bmax;;skip");
        }
        int x = [parts[1] intValue];
        int y = [parts[2] intValue];
        int width = [parts[3] intValue];
        int height = [parts[4] intValue];
        int rMin = [parts[5] intValue], rMax = [parts[6] intValue];
        int gMin = [parts[7] intValue], gMax = [parts[8] intValue];
        int bMin = [parts[9] intValue], bMax = [parts[10] intValue];
        int step = [parts[11] intValue] + 1;
        if (step <= 0) step = 1;
        CGRect region = TLinkClampRectToImage(CGRectMake(x, y, width, height), screenW, screenH);
        if (CGRectIsEmpty(region)) return TLinkError(@"color_search_invalid_region");
        int rx = (int)region.origin.x, ry = (int)region.origin.y;
        int rw = (int)region.size.width, rh = (int)region.size.height;
        for (int cy = 0; cy < rh; cy += step) {
            for (int cx = 0; cx < rw; cx += step) {
                int r = 0, g = 0, b = 0;
                if (!TLinkReadRGBA(rgba, screenW, screenH, bpr, rx + cx, ry + cy, &r, &g, &b)) continue;
                if (r >= rMin && r <= rMax && g >= gMin && g <= gMax && b >= bMin && b <= bMax) {
                    return TLinkSuccess([NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d", rx + cx, ry + cy, r, g, b]);
                }
            }
        }
        return TLinkSuccess(@"-1;;-1;;-1;;-1;;-1");
    }

    if (searchType == 2) {
        if (parts.count < 4) return TLinkError(@"color_search is_colors format: 2;;table;;mode;;value");
        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        if (!TLinkParsePointTable(parts[1], points, &err)) return TLinkError(err);
        int mode = [parts[2] intValue];
        double value = [parts[3] doubleValue];
        BOOL matched = YES;
        for (NSValue *valueObj in points) {
            TLinkPointColor pc;
            [valueObj getValue:&pc];
            int r = 0, g = 0, b = 0;
            if (!TLinkReadRGBA(rgba, screenW, screenH, bpr, pc.x, pc.y, &r, &g, &b) ||
                !TLinkColorMatches(r, g, b, pc.r, pc.g, pc.b, mode, value)) {
                matched = NO;
                break;
            }
        }
        return TLinkSuccess(matched ? @"1" : @"0");
    }

    if (searchType == 3) {
        if (parts.count < 9) return TLinkError(@"color_search find_multi format: 3;;x;;y;;w;;h;;table;;mode;;value;;skip");
        int regionX = [parts[1] intValue];
        int regionY = [parts[2] intValue];
        int regionW = [parts[3] intValue];
        int regionH = [parts[4] intValue];
        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        if (!TLinkParsePointTable(parts[5], points, &err)) return TLinkError(err);
        int mode = [parts[6] intValue];
        double value = [parts[7] doubleValue];
        int step = [parts[8] intValue] + 1;
        if (step <= 0) step = 1;

        CGRect region = TLinkClampRectToImage(CGRectMake(regionX, regionY, regionW, regionH), screenW, screenH);
        if (CGRectIsEmpty(region)) return TLinkSuccess(@"-1;;-1");

        int minDx = INT_MAX, minDy = INT_MAX, maxDx = INT_MIN, maxDy = INT_MIN;
        for (NSValue *valueObj in points) {
            TLinkPointColor pc;
            [valueObj getValue:&pc];
            if (pc.x < minDx) minDx = pc.x;
            if (pc.y < minDy) minDy = pc.y;
            if (pc.x > maxDx) maxDx = pc.x;
            if (pc.y > maxDy) maxDy = pc.y;
        }
        int axStart = MAX((int)region.origin.x, -minDx);
        int ayStart = MAX((int)region.origin.y, -minDy);
        int axEnd = MIN((int)(region.origin.x + region.size.width - 1), screenW - 1 - maxDx);
        int ayEnd = MIN((int)(region.origin.y + region.size.height - 1), screenH - 1 - maxDy);
        for (int ay = ayStart; ay <= ayEnd; ay += step) {
            for (int ax = axStart; ax <= axEnd; ax += step) {
                BOOL ok = YES;
                for (NSValue *valueObj in points) {
                    TLinkPointColor pc;
                    [valueObj getValue:&pc];
                    int r = 0, g = 0, b = 0;
                    if (!TLinkReadRGBA(rgba, screenW, screenH, bpr, ax + pc.x, ay + pc.y, &r, &g, &b) ||
                        !TLinkColorMatches(r, g, b, pc.r, pc.g, pc.b, mode, value)) {
                        ok = NO;
                        break;
                    }
                }
                if (ok) return TLinkSuccess([NSString stringWithFormat:@"%d;;%d", ax, ay]);
            }
        }
        return TLinkSuccess(@"-1;;-1");
    }

    return TLinkError([NSString stringWithFormat:@"unknown_color_search_type %d", searchType]);
}

static NSString *TLinkResolveImagePath(NSString *path)
{
    if (path.length == 0) return nil;
    if ([path hasPrefix:@"/"]) return path;
    return [@"/var/mobile/Library/TLinkauto/scripts" stringByAppendingPathComponent:path];
}

static NSString *TLinkFindImageResponse(UIImage *haystack,
                                        UIImage *needle,
                                        CGRect region,
                                        double acceptable,
                                        int pixelSkip,
                                        NSString **error)
{
    int hayW = 0, hayH = 0, hayBpr = 0;
    NSData *hayRGBA = TLinkRGBADataFromImage(haystack, &hayW, &hayH, &hayBpr);
    int needleW = 0, needleH = 0, needleBpr = 0;
    NSData *needleRGBA = TLinkRGBADataFromImage(needle, &needleW, &needleH, &needleBpr);
    if (!hayRGBA || !needleRGBA) {
        if (error) *error = @"image_match_rgba_failed";
        return nil;
    }
    int matchX = -1, matchY = -1;
    double score = 0.0;
    BOOL matched = TLinkFindTemplateInRGBA(hayRGBA, hayW, hayH, hayBpr,
                                           needleRGBA, needleW, needleH, needleBpr,
                                           region, acceptable, pixelSkip,
                                           &matchX, &matchY, &score);
    if (!matched) {
        return [NSString stringWithFormat:@"-1;;-1;;0;;0;;-1;;-1;;%.4f", score];
    }
    double centerX = matchX + needleW / 2.0;
    double centerY = matchY + needleH / 2.0;
    return [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%.2f;;%.2f;;%.4f",
            matchX, matchY, needleW, needleH, centerX, centerY, score];
}

static NSData *TLinkHandleImageObject(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 1) return TLinkError(@"image_object missing action");
    int action = [parts[0] intValue];
    if (action == 1) {
        if (parts.count < 5) return TLinkError(@"image capture format: 1;;x;;y;;w;;h");
        NSString *err = nil;
        UIImage *screen = TLinkScreenImageForVision(&err);
        if (!screen) return TLinkError(err);
        UIImage *cropped = TLinkCropImage(screen,
                                          CGRectMake([parts[1] intValue], [parts[2] intValue], [parts[3] intValue], [parts[4] intValue]),
                                          &err);
        if (!cropped) return TLinkError(err);
        uint32_t imageId = TLinkStoreImageObject(cropped);
        if (imageId == 0) return TLinkError(@"image_object_store_failed");
        CGSize size = TLinkImagePixelSize(cropped);
        return TLinkSuccess([NSString stringWithFormat:@"%u;;%d;;%d", imageId, (int)size.width, (int)size.height]);
    }
    if (action == 2) {
        if (parts.count < 2) return TLinkError(@"image open format: 2;;path");
        NSString *path = TLinkResolveImagePath(parts[1]);
        UIImage *image = path.length > 0 ? [UIImage imageWithContentsOfFile:path] : nil;
        if (!image || !image.CGImage) {
            return TLinkError([NSString stringWithFormat:@"image_not_found path=%@", path ?: parts[1]]);
        }
        uint32_t imageId = TLinkStoreImageObject(image);
        if (imageId == 0) return TLinkError(@"image_object_store_failed");
        CGSize size = TLinkImagePixelSize(image);
        return TLinkSuccess([NSString stringWithFormat:@"%u;;%d;;%d", imageId, (int)size.width, (int)size.height]);
    }
    if (action == 3) {
        if (parts.count < 2) return TLinkSuccess(@"0");
        TLinkEnsureVisionStores();
        NSString *target = parts[1];
        NSUInteger removed = 0;
        if ([[target lowercaseString] isEqualToString:@"all"] || [[target lowercaseString] isEqualToString:@"scoped"]) {
            removed = sTLinkImageStore.count;
            [sTLinkImageStore removeAllObjects];
        } else {
            NSNumber *key = @((uint32_t)[target intValue]);
            if (sTLinkImageStore[key]) {
                [sTLinkImageStore removeObjectForKey:key];
                removed = 1;
            }
        }
        return TLinkSuccess([NSString stringWithFormat:@"%lu", (unsigned long)removed]);
    }
    return TLinkError(@"unknown_image_object_action");
}

static NSData *TLinkHandleFindImage(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 10) {
        return TLinkError(@"find_image format: image_id;;x;;y;;w;;h;;acceptable;;scale_min;;scale_max;;scale_step;;pixel_skip");
    }
    TLinkEnsureVisionStores();
    uint32_t imageId = (uint32_t)[parts[0] intValue];
    TLinkImageObject *templ = sTLinkImageStore[@(imageId)];
    if (!templ || !templ.image) return TLinkError(@"image_not_found");
    NSString *err = nil;
    UIImage *screen = TLinkScreenImageForVision(&err);
    if (!screen) return TLinkError(err);
    NSString *ret = TLinkFindImageResponse(screen,
                                           templ.image,
                                           CGRectMake([parts[1] intValue], [parts[2] intValue], [parts[3] intValue], [parts[4] intValue]),
                                           [parts[5] doubleValue],
                                           [parts[9] intValue],
                                           &err);
    if (!ret) return TLinkError(err);
    return TLinkSuccess(ret);
}

static NSData *TLinkHandleTemplateMatch(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 1 || parts[0].length == 0) return TLinkError(@"template_match missing path");
    NSString *path = TLinkResolveImagePath(parts[0]);
    UIImage *templ = path.length > 0 ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!templ || !templ.CGImage) return TLinkError([NSString stringWithFormat:@"template_not_found path=%@", path ?: parts[0]]);
    NSString *err = nil;
    UIImage *screen = TLinkScreenImageForVision(&err);
    if (!screen) return TLinkError(err);
    double acceptable = parts.count >= 3 ? [parts[2] doubleValue] : 0.8;
    NSString *ret = TLinkFindImageResponse(screen, templ, CGRectMake(0, 0, 0, 0), acceptable, 0, &err);
    if (!ret) return TLinkError(err);
    NSArray<NSString *> *retParts = TLinkSplitBody(ret);
    if (retParts.count >= 4) {
        return TLinkSuccess([[retParts subarrayWithRange:NSMakeRange(0, 4)] componentsJoinedByString:@";;"]);
    }
    return TLinkSuccess(ret);
}

static NSData *TLinkHandleFrameCapture(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    BOOL needGray = YES;
    BOOL needBGRA = YES;
    uint64_t ttlMs = kTLinkDefaultFrameTtlMs;
    if (parts.count >= 1 && parts[0].length > 0) needGray = [parts[0] intValue] != 0;
    if (parts.count >= 2 && parts[1].length > 0) needBGRA = [parts[1] intValue] != 0;
    if (parts.count >= 3 && parts[2].length > 0) ttlMs = (uint64_t)MAX(0, [parts[2] longLongValue]);
    if (!needGray && !needBGRA) {
        needGray = YES;
        needBGRA = YES;
    }
    if (ttlMs == 0) ttlMs = kTLinkDefaultFrameTtlMs;
    if (ttlMs > kTLinkHardFrameTtlMs) ttlMs = kTLinkHardFrameTtlMs;

    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    NSString *err = nil;
    UIImage *image = TLinkCaptureScreenImage(&err);
    if (!image) return TLinkError(err);
    CGSize size = TLinkImagePixelSize(image);
    TLinkFrameObject *frame = [[TLinkFrameObject alloc] init];
    frame.image = image;
    frame.width = (int)size.width;
    frame.height = (int)size.height;
    frame.bytesPerRow = frame.width * 4;
    frame.scale = [UIScreen mainScreen].scale;
    frame.createdAtMs = TLinkNowMs();
    frame.expiresAtMs = frame.createdAtMs + ttlMs;
    frame.hasGray = needGray;
    frame.hasBGRA = NO;
    double captureMs = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
    double bgraMs = 0.0;
    if (needBGRA) {
        CFAbsoluteTime bgraStart = CFAbsoluteTimeGetCurrent();
        if (!TLinkEnsureFrameRGBA(frame, &err)) return TLinkError(err);
        bgraMs = (CFAbsoluteTimeGetCurrent() - bgraStart) * 1000.0;
    }
    uint32_t frameId = TLinkStoreFrameObject(frame);
    if (frameId == 0) return TLinkError(@"frame_store_failed");
    double totalMs = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
    NSString *ret = [NSString stringWithFormat:@"%u;;%d;;%d;;%d;;%.3f;;pixel;;RGBA;;%d;;%d;;%llu;;%.3f;;%.3f;;0.000;;%.3f",
                     frameId, frame.width, frame.height, frame.bytesPerRow, frame.scale,
                     frame.hasBGRA ? 1 : 0, frame.hasGray ? 1 : 0,
                     (unsigned long long)frame.createdAtMs,
                     captureMs, bgraMs, totalMs];
    return TLinkSuccess(ret);
}

static NSData *TLinkHandleFrameRelease(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    TLinkEnsureVisionStores();
    if (parts.count < 1 || parts[0].length == 0) return TLinkSuccess(@"0");
    NSString *target = [parts[0] lowercaseString];
    NSUInteger removed = 0;
    if ([target isEqualToString:@"all"] || [target isEqualToString:@"scoped"]) {
        removed = sTLinkFrameStore.count;
        [sTLinkFrameStore removeAllObjects];
    } else {
        NSNumber *key = @((uint32_t)[parts[0] intValue]);
        if (sTLinkFrameStore[key]) {
            [sTLinkFrameStore removeObjectForKey:key];
            removed = 1;
        }
    }
    return TLinkSuccess([NSString stringWithFormat:@"%lu", (unsigned long)removed]);
}

static BOOL TLinkStringIsPointCoord(NSString *coord)
{
    return coord && [[coord lowercaseString] isEqualToString:@"point"];
}

static int TLinkCoordToPixel(double value, CGFloat scale, BOOL pointCoord)
{
    return (int)llround(pointCoord ? value * scale : value);
}

static BOOL TLinkFrameTooOld(TLinkFrameObject *frame, uint64_t maxAgeMs, NSString **error)
{
    if (!frame) {
        if (error) *error = @"frame_not_found";
        return YES;
    }
    if (maxAgeMs == 0) return NO;
    uint64_t now = TLinkNowMs();
    uint64_t age = now >= frame.createdAtMs ? now - frame.createdAtMs : 0;
    if (age > maxAgeMs) {
        if (error) *error = @"frame_too_old";
        return YES;
    }
    return NO;
}

static NSData *TLinkHandleColorInFrame(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 2) return TLinkError(@"color_in_frame format: frame_id;;mode;;...");
    TLinkFrameObject *frame = TLinkFrameForId((uint32_t)[parts[0] intValue]);
    if (!frame) return TLinkError(@"frame_not_found");
    NSString *err = nil;
    if (!TLinkEnsureFrameRGBA(frame, &err)) return TLinkError(err);
    NSString *mode = [parts[1] lowercaseString];
    uint64_t ageMs = TLinkNowMs() >= frame.createdAtMs ? TLinkNowMs() - frame.createdAtMs : 0;
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();

    if ([mode isEqualToString:@"pick"]) {
        if (parts.count < 4) return TLinkError(@"color pick format: frame_id;;pick;;x;;y[;;coord;;max_age_ms]");
        BOOL pointCoord = parts.count >= 5 ? TLinkStringIsPointCoord(parts[4]) : NO;
        uint64_t maxAge = parts.count >= 6 ? (uint64_t)MAX(0, [parts[5] longLongValue]) : kTLinkDefaultFrameTtlMs;
        if (TLinkFrameTooOld(frame, maxAge, &err)) return TLinkError(err);
        int x = TLinkCoordToPixel([parts[2] doubleValue], frame.scale, pointCoord);
        int y = TLinkCoordToPixel([parts[3] doubleValue], frame.scale, pointCoord);
        int r = 0, g = 0, b = 0;
        if (!TLinkReadRGBA(frame.rgbaData, frame.width, frame.height, frame.bytesPerRow, x, y, &r, &g, &b)) {
            return TLinkError(@"point_out_of_bounds");
        }
        double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
        return TLinkSuccess([NSString stringWithFormat:@"%d;;%d;;%d;;%llu;;%.3f;;%.3f", r, g, b, (unsigned long long)ageMs, ms, ms]);
    }

    if ([mode isEqualToString:@"pick_many"]) {
        if (parts.count < 3) return TLinkError(@"pick_many format: frame_id;;pick_many;;x,y|x,y|...");
        BOOL pointCoord = parts.count >= 4 ? TLinkStringIsPointCoord(parts[3]) : NO;
        uint64_t maxAge = parts.count >= 5 ? (uint64_t)MAX(0, [parts[4] longLongValue]) : kTLinkDefaultFrameTtlMs;
        if (TLinkFrameTooOld(frame, maxAge, &err)) return TLinkError(err);
        NSMutableArray<NSString *> *result = [NSMutableArray array];
        for (NSString *item in [parts[2] componentsSeparatedByString:@"|"]) {
            NSArray<NSString *> *xy = [item componentsSeparatedByString:@","];
            if (xy.count != 2) return TLinkError(@"invalid_pick_many_point");
            int x = TLinkCoordToPixel([xy[0] doubleValue], frame.scale, pointCoord);
            int y = TLinkCoordToPixel([xy[1] doubleValue], frame.scale, pointCoord);
            int r = 0, g = 0, b = 0;
            if (!TLinkReadRGBA(frame.rgbaData, frame.width, frame.height, frame.bytesPerRow, x, y, &r, &g, &b)) {
                return TLinkError(@"point_out_of_bounds");
            }
            [result addObject:[NSString stringWithFormat:@"%d,%d,%d,%d,%d", x, y, r, g, b]];
        }
        double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
        return TLinkSuccess([NSString stringWithFormat:@"%@;;%llu;;%.3f;;%.3f", [result componentsJoinedByString:@"|"], (unsigned long long)ageMs, ms, ms]);
    }

    if ([mode isEqualToString:@"search_single"]) {
        if (parts.count < 13) return TLinkError(@"search_single format: frame_id;;search_single;;x;;y;;w;;h;;rmin;;rmax;;gmin;;gmax;;bmin;;bmax;;skip");
        BOOL pointCoord = parts.count >= 14 ? TLinkStringIsPointCoord(parts[13]) : NO;
        uint64_t maxAge = parts.count >= 15 ? (uint64_t)MAX(0, [parts[14] longLongValue]) : kTLinkDefaultFrameTtlMs;
        if (TLinkFrameTooOld(frame, maxAge, &err)) return TLinkError(err);
        int x = TLinkCoordToPixel([parts[2] doubleValue], frame.scale, pointCoord);
        int y = TLinkCoordToPixel([parts[3] doubleValue], frame.scale, pointCoord);
        int width = TLinkCoordToPixel([parts[4] doubleValue], frame.scale, pointCoord);
        int height = TLinkCoordToPixel([parts[5] doubleValue], frame.scale, pointCoord);
        int rMin = [parts[6] intValue], rMax = [parts[7] intValue];
        int gMin = [parts[8] intValue], gMax = [parts[9] intValue];
        int bMin = [parts[10] intValue], bMax = [parts[11] intValue];
        int step = [parts[12] intValue] + 1;
        if (step <= 0) step = 1;
        CGRect region = TLinkClampRectToImage(CGRectMake(x, y, width, height), frame.width, frame.height);
        if (CGRectIsEmpty(region)) return TLinkError(@"invalid_search_region");
        int rx = (int)region.origin.x, ry = (int)region.origin.y;
        int rw = (int)region.size.width, rh = (int)region.size.height;
        for (int cy = 0; cy < rh; cy += step) {
            for (int cx = 0; cx < rw; cx += step) {
                int r = 0, g = 0, b = 0;
                if (!TLinkReadRGBA(frame.rgbaData, frame.width, frame.height, frame.bytesPerRow, rx + cx, ry + cy, &r, &g, &b)) continue;
                if (r >= rMin && r <= rMax && g >= gMin && g <= gMax && b >= bMin && b <= bMax) {
                    double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
                    return TLinkSuccess([NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d;;%llu;;%.3f;;%.3f",
                                         rx + cx, ry + cy, r, g, b, (unsigned long long)ageMs, ms, ms]);
                }
            }
        }
        double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
        return TLinkSuccess([NSString stringWithFormat:@"-1;;-1;;-1;;-1;;-1;;%llu;;%.3f;;%.3f",
                             (unsigned long long)ageMs, ms, ms]);
    }

    if ([mode isEqualToString:@"is_colors"]) {
        if (parts.count < 5) return TLinkError(@"is_colors format: frame_id;;is_colors;;table;;mode;;value");
        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        if (!TLinkParsePointTable(parts[2], points, &err)) return TLinkError(err);
        int colorMode = [parts[3] intValue];
        double value = [parts[4] doubleValue];
        BOOL pointCoord = parts.count >= 6 ? TLinkStringIsPointCoord(parts[5]) : NO;
        uint64_t maxAge = parts.count >= 7 ? (uint64_t)MAX(0, [parts[6] longLongValue]) : kTLinkDefaultFrameTtlMs;
        if (TLinkFrameTooOld(frame, maxAge, &err)) return TLinkError(err);
        BOOL matched = YES;
        for (NSValue *valueObj in points) {
            TLinkPointColor pc;
            [valueObj getValue:&pc];
            int x = TLinkCoordToPixel(pc.x, frame.scale, pointCoord);
            int y = TLinkCoordToPixel(pc.y, frame.scale, pointCoord);
            int r = 0, g = 0, b = 0;
            if (!TLinkReadRGBA(frame.rgbaData, frame.width, frame.height, frame.bytesPerRow, x, y, &r, &g, &b) ||
                !TLinkColorMatches(r, g, b, pc.r, pc.g, pc.b, colorMode, value)) {
                matched = NO;
                break;
            }
        }
        double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
        return TLinkSuccess([NSString stringWithFormat:@"%d;;%llu;;%.3f;;%.3f", matched ? 1 : 0, (unsigned long long)ageMs, ms, ms]);
    }

    if ([mode isEqualToString:@"find_multi_point"]) {
        if (parts.count < 10) return TLinkError(@"find_multi_point format: frame_id;;find_multi_point;;x;;y;;w;;h;;table;;mode;;value;;skip");
        BOOL pointCoord = parts.count >= 11 ? TLinkStringIsPointCoord(parts[10]) : NO;
        uint64_t maxAge = parts.count >= 12 ? (uint64_t)MAX(0, [parts[11] longLongValue]) : kTLinkDefaultFrameTtlMs;
        if (TLinkFrameTooOld(frame, maxAge, &err)) return TLinkError(err);
        int regionX = TLinkCoordToPixel([parts[2] doubleValue], frame.scale, pointCoord);
        int regionY = TLinkCoordToPixel([parts[3] doubleValue], frame.scale, pointCoord);
        int regionW = TLinkCoordToPixel([parts[4] doubleValue], frame.scale, pointCoord);
        int regionH = TLinkCoordToPixel([parts[5] doubleValue], frame.scale, pointCoord);
        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        if (!TLinkParsePointTable(parts[6], points, &err)) return TLinkError(err);
        int colorMode = [parts[7] intValue];
        double value = [parts[8] doubleValue];
        int step = [parts[9] intValue] + 1;
        if (step <= 0) step = 1;
        CGRect region = TLinkClampRectToImage(CGRectMake(regionX, regionY, regionW, regionH), frame.width, frame.height);
        if (CGRectIsEmpty(region)) return TLinkSuccess([NSString stringWithFormat:@"-1;;-1;;%llu;;0.000;;0.000", (unsigned long long)ageMs]);
        int minDx = INT_MAX, minDy = INT_MAX, maxDx = INT_MIN, maxDy = INT_MIN;
        for (NSValue *valueObj in points) {
            TLinkPointColor pc;
            [valueObj getValue:&pc];
            int dx = TLinkCoordToPixel(pc.x, frame.scale, pointCoord);
            int dy = TLinkCoordToPixel(pc.y, frame.scale, pointCoord);
            if (dx < minDx) minDx = dx;
            if (dy < minDy) minDy = dy;
            if (dx > maxDx) maxDx = dx;
            if (dy > maxDy) maxDy = dy;
        }
        int axStart = MAX((int)region.origin.x, -minDx);
        int ayStart = MAX((int)region.origin.y, -minDy);
        int axEnd = MIN((int)(region.origin.x + region.size.width - 1), frame.width - 1 - maxDx);
        int ayEnd = MIN((int)(region.origin.y + region.size.height - 1), frame.height - 1 - maxDy);
        for (int ay = ayStart; ay <= ayEnd; ay += step) {
            for (int ax = axStart; ax <= axEnd; ax += step) {
                BOOL ok = YES;
                for (NSValue *valueObj in points) {
                    TLinkPointColor pc;
                    [valueObj getValue:&pc];
                    int dx = TLinkCoordToPixel(pc.x, frame.scale, pointCoord);
                    int dy = TLinkCoordToPixel(pc.y, frame.scale, pointCoord);
                    int r = 0, g = 0, b = 0;
                    if (!TLinkReadRGBA(frame.rgbaData, frame.width, frame.height, frame.bytesPerRow, ax + dx, ay + dy, &r, &g, &b) ||
                        !TLinkColorMatches(r, g, b, pc.r, pc.g, pc.b, colorMode, value)) {
                        ok = NO;
                        break;
                    }
                }
                if (ok) {
                    double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
                    return TLinkSuccess([NSString stringWithFormat:@"%d;;%d;;%llu;;%.3f;;%.3f",
                                         ax, ay, (unsigned long long)ageMs, ms, ms]);
                }
            }
        }
        double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
        return TLinkSuccess([NSString stringWithFormat:@"-1;;-1;;%llu;;%.3f;;%.3f",
                             (unsigned long long)ageMs, ms, ms]);
    }

    return TLinkError(@"unknown_color_frame_mode");
}

static NSData *TLinkHandleFindImageInFrame(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 11) {
        return TLinkError(@"find_image_in_frame format: frame_id;;image_id;;x;;y;;w;;h;;acceptable;;scale_min;;scale_max;;scale_step;;pixel_skip");
    }
    TLinkFrameObject *frame = TLinkFrameForId((uint32_t)[parts[0] intValue]);
    if (!frame) return TLinkError(@"frame_not_found");
    uint64_t maxAge = parts.count >= 13 ? (uint64_t)MAX(0, [parts[12] longLongValue]) : kTLinkDefaultFrameTtlMs;
    NSString *err = nil;
    if (TLinkFrameTooOld(frame, maxAge, &err)) return TLinkError(err);
    TLinkEnsureVisionStores();
    TLinkImageObject *templ = sTLinkImageStore[@((uint32_t)[parts[1] intValue])];
    if (!templ || !templ.image) return TLinkError(@"image_not_found");
    NSString *ret = TLinkFindImageResponse(frame.image,
                                           templ.image,
                                           CGRectMake([parts[2] intValue], [parts[3] intValue], [parts[4] intValue], [parts[5] intValue]),
                                           [parts[6] doubleValue],
                                           [parts[10] intValue],
                                           &err);
    if (!ret) return TLinkError(err);
    uint64_t ageMs = TLinkNowMs() >= frame.createdAtMs ? TLinkNowMs() - frame.createdAtMs : 0;
    return TLinkSuccess([NSString stringWithFormat:@"%@;;%llu;;0.000;;0.000", ret, (unsigned long long)ageMs]);
}

static NSData *TLinkHandleFrameBatch(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 2) return TLinkError(@"frame_batch format: frame_id;;op@@op...[;;coord;;max_age_ms;;auto_release]");
    uint32_t frameId = (uint32_t)[parts[0] intValue];
    TLinkFrameObject *frame = TLinkFrameForId(frameId);
    if (!frame) return TLinkError(@"frame_not_found");
    NSString *err = nil;
    uint64_t maxAge = parts.count >= 4 ? (uint64_t)MAX(0, [parts[3] longLongValue]) : kTLinkDefaultFrameTtlMs;
    if (TLinkFrameTooOld(frame, maxAge, &err)) return TLinkError(err);
    BOOL pointCoord = parts.count >= 3 ? TLinkStringIsPointCoord(parts[2]) : NO;
    BOOL autoRelease = parts.count >= 5 ? ([parts[4] intValue] != 0) : NO;
    uint64_t ageMs = TLinkNowMs() >= frame.createdAtMs ? TLinkNowMs() - frame.createdAtMs : 0;
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    NSMutableArray<NSString *> *results = [NSMutableArray array];

    for (NSString *opRaw in [parts[1] componentsSeparatedByString:@"@@"]) {
        if (opRaw.length == 0) continue;
        NSArray<NSString *> *fields = [opRaw componentsSeparatedByString:@","];
        NSString *kind = fields.count > 0 ? [fields[0] lowercaseString] : @"";
        CFAbsoluteTime opStarted = CFAbsoluteTimeGetCurrent();
        if ([kind isEqualToString:@"pick_many"]) {
            if (fields.count < 2) return TLinkError(@"batch pick_many format: pick_many,x:y|x:y");
            if (!TLinkEnsureFrameRGBA(frame, &err)) return TLinkError(err);
            NSMutableArray<NSString *> *picked = [NSMutableArray array];
            for (NSString *item in [fields[1] componentsSeparatedByString:@"|"]) {
                NSArray<NSString *> *xy = [item componentsSeparatedByString:@":"];
                if (xy.count != 2) xy = [item componentsSeparatedByString:@"/"];
                if (xy.count != 2) return TLinkError(@"invalid_batch_pick_many_point");
                int x = TLinkCoordToPixel([xy[0] doubleValue], frame.scale, pointCoord);
                int y = TLinkCoordToPixel([xy[1] doubleValue], frame.scale, pointCoord);
                int r = 0, g = 0, b = 0;
                if (!TLinkReadRGBA(frame.rgbaData, frame.width, frame.height, frame.bytesPerRow, x, y, &r, &g, &b)) {
                    return TLinkError(@"point_out_of_bounds");
                }
                [picked addObject:[NSString stringWithFormat:@"%d,%d,%d,%d,%d", x, y, r, g, b]];
            }
            double opMs = (CFAbsoluteTimeGetCurrent() - opStarted) * 1000.0;
            [results addObject:[NSString stringWithFormat:@"pick_many:%@,%.3f", [picked componentsJoinedByString:@"|"], opMs]];
            continue;
        }
        if ([kind isEqualToString:@"img"]) {
            if (fields.count < 9) return TLinkError(@"batch img format: img,image_id,x,y,w,h,acceptable,scale,pixel_skip");
            TLinkEnsureVisionStores();
            TLinkImageObject *templ = sTLinkImageStore[@((uint32_t)[fields[1] intValue])];
            if (!templ || !templ.image) return TLinkError(@"image_not_found");
            NSString *ret = TLinkFindImageResponse(frame.image,
                                                   templ.image,
                                                   CGRectMake(TLinkCoordToPixel([fields[2] doubleValue], frame.scale, pointCoord),
                                                              TLinkCoordToPixel([fields[3] doubleValue], frame.scale, pointCoord),
                                                              TLinkCoordToPixel([fields[4] doubleValue], frame.scale, pointCoord),
                                                              TLinkCoordToPixel([fields[5] doubleValue], frame.scale, pointCoord)),
                                                   [fields[6] doubleValue],
                                                   [fields[8] intValue],
                                                   &err);
            if (!ret) return TLinkError(err);
            NSArray<NSString *> *retParts = TLinkSplitBody(ret);
            double opMs = (CFAbsoluteTimeGetCurrent() - opStarted) * 1000.0;
            [results addObject:[NSString stringWithFormat:@"img:%@,%.3f", [retParts componentsJoinedByString:@","], opMs]];
            continue;
        }
        return TLinkError(@"unknown_batch_op");
    }
    if (autoRelease) {
        [sTLinkFrameStore removeObjectForKey:@(frameId)];
    }
    double totalMs = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
    return TLinkSuccess([NSString stringWithFormat:@"%@;;%llu;;%.3f", [results componentsJoinedByString:@"@@"], (unsigned long long)ageMs, totalMs]);
}

static NSData *TLinkHandleKeyboard(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 1) return TLinkError(@"keyboard task missing subtask");
    int subtask = [parts[0] intValue];
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (subtask == 6) {
        return TLinkSuccess(pasteboard.string ?: @"");
    }
    if (subtask == 7) {
        if (parts.count < 2) return TLinkError(@"clipboard save text missing content");
        pasteboard.string = TLinkJoinParts(parts, 1);
        return TLinkSuccess(nil);
    }
    return TLinkUnsupported(24, @"limited_on_trollstore pasteboard get/set only");
}

static NSArray<NSString *> *TLinkSplitNonEmpty(NSString *value, NSString *separator)
{
    if (value.length == 0) return @[];
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSString *raw in [value componentsSeparatedByString:separator]) {
        NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [items addObject:trimmed];
    }
    return items;
}

static NSString *TLinkSanitizeOCRText(NSString *text)
{
    NSMutableString *safe = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "] mutableCopy];
    [safe replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@";;" withString:@"; " options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@",," withString:@", " options:0 range:NSMakeRange(0, safe.length)];
    return safe ?: @"";
}

static BOOL TLinkWriteDebugImage(UIImage *image, NSString *path, NSString **error)
{
    if (!image || path.length == 0) return YES;
    NSString *target = [path hasPrefix:@"/"] ? path : [@"/var/mobile/Library/TLinkauto/scripts" stringByAppendingPathComponent:path];
    NSString *parent = [target stringByDeletingLastPathComponent];
    if (parent.length > 0 && ![[NSFileManager defaultManager] fileExistsAtPath:parent]) {
        NSError *mkdirErr = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:parent
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&mkdirErr]) {
            if (error) *error = [NSString stringWithFormat:@"ocr_debug_mkdir_failed %@", mkdirErr.localizedDescription ?: parent];
            return NO;
        }
    }
    NSData *png = UIImagePNGRepresentation(image);
    if (!png || ![png writeToFile:target atomically:NO]) {
        if (error) *error = [NSString stringWithFormat:@"ocr_debug_write_failed %@", target];
        return NO;
    }
    return YES;
}

static NSUInteger TLinkVisionOCRRevision(void)
{
    if (@available(iOS 14.0, *)) return 2;
    return 1;
}

static VNRequestTextRecognitionLevel TLinkVisionOCRLevelFromValue(int value)
{
    return value == 1 ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
}

static NSData *TLinkHandleVisionOCR(NSString *body)
{
    if (!@available(iOS 13.0, *)) {
        return TLinkUnsupported(27, @"vision_requires_ios13");
    }

    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 1) return TLinkError(@"ocr task missing subtask");
    int subtask = [parts[0] intValue];

    if (subtask == 2) {
        int levelValue = parts.count >= 2 ? [parts[1] intValue] : 0;
        VNRequestTextRecognitionLevel level = TLinkVisionOCRLevelFromValue(levelValue);
        NSError *visionErr = nil;
        NSArray<NSString *> *languages = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:level
                                                                                                             revision:TLinkVisionOCRRevision()
                                                                                                                error:&visionErr];
        if (!languages) return TLinkError([NSString stringWithFormat:@"ocr_languages_failed %@", visionErr.localizedDescription ?: @"unknown"]);
        return TLinkSuccess([languages componentsJoinedByString:@";;"]);
    }

    if (subtask != 1) {
        return TLinkError([NSString stringWithFormat:@"unknown_ocr_subtask %d", subtask]);
    }

    if (parts.count < 8) {
        return TLinkError(@"ocr format: 1;;x,,y,,w,,h;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path");
    }

    NSArray<NSString *> *rectParts = [parts[1] componentsSeparatedByString:@",,"];
    if (rectParts.count < 4) return TLinkError(@"ocr_bad_region");

    NSString *err = nil;
    UIImage *screen = TLinkScreenImageForVision(&err);
    if (!screen || !screen.CGImage) return TLinkError(err ?: @"ocr_capture_failed");

    int screenW = (int)CGImageGetWidth(screen.CGImage);
    int screenH = (int)CGImageGetHeight(screen.CGImage);
    CGRect region = TLinkClampRectToImage(CGRectMake([rectParts[0] intValue],
                                                     [rectParts[1] intValue],
                                                     [rectParts[2] intValue],
                                                     [rectParts[3] intValue]),
                                          screenW,
                                          screenH);
    if (CGRectIsEmpty(region)) return TLinkError(@"ocr_invalid_region");

    UIImage *cropped = TLinkCropImage(screen, region, &err);
    if (!cropped || !cropped.CGImage) return TLinkError(err ?: @"ocr_crop_failed");

    if (parts[7].length > 0 && !TLinkWriteDebugImage(cropped, parts[7], &err)) {
        return TLinkError(err);
    }

    int levelValue = [parts[4] intValue];
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *finishedRequest, NSError *error) {
        // Results are read after performRequests returns.
        (void)finishedRequest;
        (void)error;
    }];
    request.recognitionLevel = TLinkVisionOCRLevelFromValue(levelValue);
    request.revision = TLinkVisionOCRRevision();
    CGFloat minimumHeight = (CGFloat)[parts[3] doubleValue];
    if (minimumHeight > 0.0) request.minimumTextHeight = minimumHeight;
    NSArray<NSString *> *customWords = TLinkSplitNonEmpty(parts[2], @",,");
    if (customWords.count > 0) request.customWords = customWords;
    NSArray<NSString *> *languages = TLinkSplitNonEmpty(parts[5], @",,");
    if (languages.count > 0) request.recognitionLanguages = languages;
    request.usesLanguageCorrection = [parts[6] intValue] != 0;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cropped.CGImage
                                                                        orientation:kCGImagePropertyOrientationUp
                                                                            options:@{}];
    NSError *visionErr = nil;
    if (![handler performRequests:@[request] error:&visionErr]) {
        return TLinkError([NSString stringWithFormat:@"ocr_failed %@", visionErr.localizedDescription ?: @"unknown"]);
    }

    CGSize regionSize = region.size;
    NSMutableArray<NSString *> *output = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in request.results) {
        if (![observation isKindOfClass:[VNRecognizedTextObservation class]]) continue;
        VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
        if (!candidate.string.length) continue;
        CGRect bb = observation.boundingBox;
        int x = (int)llround(region.origin.x + bb.origin.x * regionSize.width);
        int y = (int)llround(region.origin.y + (1.0 - bb.origin.y - bb.size.height) * regionSize.height);
        int w = (int)llround(bb.size.width * regionSize.width);
        int h = (int)llround(bb.size.height * regionSize.height);
        [output addObject:[NSString stringWithFormat:@"%@,,%d,,%d,,%d,,%d",
                           TLinkSanitizeOCRText(candidate.string), x, y, w, h]];
    }

    return TLinkSuccess([output componentsJoinedByString:@";;"]);
}

static NSString *TLinkProtocolSafeField(NSString *value)
{
    NSMutableString *safe = [[value ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "] mutableCopy];
    [safe replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@";;" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    return safe ?: @"";
}

static NSString *TLinkCleanPayload(NSString *body)
{
    return [[body ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@""]
        stringByReplacingOccurrencesOfString:@"\n" withString:@""];
}

static id TLinkObjectForSelectorOrKey(id object, NSString *selectorName, NSString *key)
{
    if (!object || selectorName.length == 0) return nil;
    id value = nil;
    SEL sel = NSSelectorFromString(selectorName);
    @try {
        if ([object respondsToSelector:sel]) {
            value = ((id (*)(id, SEL))objc_msgSend)(object, sel);
        } else if (key.length > 0) {
            value = [object valueForKey:key];
        }
    } @catch (__unused NSException *exception) {
        value = nil;
    }
    return value;
}

static NSString *TLinkStringForSelectorOrKey(id object, NSString *selectorName, NSString *key)
{
    id value = TLinkObjectForSelectorOrKey(object, selectorName, key);
    if (!value || value == (id)kCFNull) return @"";
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    return [value description] ?: @"";
}

static NSString *TLinkPathFromURLLike(id urlLike)
{
    if (!urlLike || urlLike == (id)kCFNull) return @"";
    if ([urlLike isKindOfClass:[NSURL class]]) return [(NSURL *)urlLike path] ?: @"";
    if ([urlLike respondsToSelector:@selector(path)]) {
        NSString *path = ((NSString *(*)(id, SEL))objc_msgSend)(urlLike, @selector(path));
        return path ?: @"";
    }
    return @"";
}

static NSString *TLinkNormalizedPath(NSString *path)
{
    if (path.length == 0) return @"";
    NSString *resolved = [path stringByResolvingSymlinksInPath];
    return (resolved.length > 0 ? resolved : path).stringByStandardizingPath;
}

static void TLinkLoadLaunchServices(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/LaunchServices.framework/LaunchServices", RTLD_LAZY);
        dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
    });
}

static id TLinkApplicationProxyForBundleId(NSString *bundleId)
{
    if (bundleId.length == 0) return nil;
    TLinkLoadLaunchServices();
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:sel]) return nil;
    @try {
        return ((id (*)(Class, SEL, NSString *))objc_msgSend)(proxyClass, sel, bundleId);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id TLinkApplicationWorkspace(void)
{
    TLinkLoadLaunchServices();
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL sel = NSSelectorFromString(@"defaultWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:sel]) return nil;
    @try {
        return ((id (*)(Class, SEL))objc_msgSend)(workspaceClass, sel);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *TLinkBundlePathForProxy(id proxy)
{
    return TLinkPathFromURLLike(TLinkObjectForSelectorOrKey(proxy, @"bundleURL", @"bundleURL"));
}

static NSString *TLinkDataPathForProxy(id proxy)
{
    id dataURL = TLinkObjectForSelectorOrKey(proxy, @"dataContainerURL", @"dataContainerURL");
    if (!dataURL) dataURL = TLinkObjectForSelectorOrKey(proxy, @"containerURL", @"containerURL");
    return TLinkPathFromURLLike(dataURL);
}

static pid_t TLinkPidForBundleId(NSString *bundleId)
{
    id proxy = TLinkApplicationProxyForBundleId(bundleId);
    NSString *bundlePath = TLinkNormalizedPath(TLinkBundlePathForProxy(proxy));
    if (bundlePath.length == 0) return 0;

    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) return 0;
    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(len);
    if (!procs) return 0;
    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) {
        free(procs);
        return 0;
    }

    int count = (int)(len / sizeof(struct kinfo_proc));
    pid_t found = 0;
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 0) continue;
        char pathBuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
        if (proc_pidpath(pid, pathBuf, sizeof(pathBuf)) <= 0) continue;
        NSString *procPath = TLinkNormalizedPath([NSString stringWithUTF8String:pathBuf] ?: @"");
        if (procPath.length > 0 && [procPath hasPrefix:bundlePath]) {
            found = pid;
            break;
        }
    }
    free(procs);
    return found;
}

typedef int (*TLinkSBSLaunchApplicationFn)(CFStringRef identifier, Boolean suspended);
typedef CFStringRef (*TLinkSBSCopyFrontmostFn)(void);
typedef int (*TLinkSBSProcessIDFn)(CFStringRef identifier);

static NSString *sTLinkLastFrontmostBundleId = nil;
static NSString *sTLinkLastFrontmostSource = nil;
static pid_t sTLinkLastFrontmostPid = 0;
static uint64_t sTLinkLastFrontmostAtMs = 0;
static id sTLinkFBSDisplayLayoutMonitor = nil;
static id sTLinkFBSDisplayLayoutBlock = nil;
static NSString *sTLinkFrontmostDiag = nil;

static pid_t TLinkResolvePidForBundleId(NSString *bundleId);
static void TLinkRememberFrontmost(NSString *bundleId, NSString *source, pid_t pid);

static void *TLinkSpringBoardServicesHandle(void)
{
    static void *handle = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlerror();
        handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_GLOBAL);
        if (!handle) {
            const char *err = dlerror();
            sTLinkFrontmostDiag = [NSString stringWithFormat:@"sbs_dlopen_failed:%s", err ?: "unknown"];
        }
    });
    return handle;
}

static BOOL TLinkSBSLaunchApplication(NSString *bundleId, int *outRc)
{
    void *handle = TLinkSpringBoardServicesHandle();
    if (!handle) return NO;
    TLinkSBSLaunchApplicationFn fn = (TLinkSBSLaunchApplicationFn)dlsym(handle, "SBSLaunchApplicationWithIdentifier");
    if (!fn) return NO;
    int rc = fn((__bridge CFStringRef)bundleId, false);
    if (outRc) *outRc = rc;
    return rc == 0;
}

static NSString *TLinkSBSCopyFrontmostBundleId(void)
{
    void *handle = TLinkSpringBoardServicesHandle();
    if (!handle) {
        sTLinkFrontmostDiag = @"sbs_dlopen_failed";
        return nil;
    }
    BOOL sawSymbol = NO;
    const char *symbols[] = {
        "SBSCopyFrontmostApplicationDisplayIdentifier",
        "SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay",
        "SBSGetMostElevatedApplicationBundleIdentifier",
        "SBSGetMostElevatedApplicationDisplayIdentifier",
        NULL,
    };
    for (int i = 0; symbols[i] != NULL; i++) {
        TLinkSBSCopyFrontmostFn fn = (TLinkSBSCopyFrontmostFn)dlsym(handle, symbols[i]);
        if (!fn) continue;
        sawSymbol = YES;
        CFStringRef front = fn();
        if (!front) continue;
        NSString *bundleId = [(__bridge NSString *)front copy];
        if (strncmp(symbols[i], "SBSCopy", 7) == 0) CFRelease(front);
        if (bundleId.length > 0) {
            TLinkRememberFrontmost(bundleId, [NSString stringWithFormat:@"sbs:%s", symbols[i]], 0);
            return bundleId;
        }
    }
    sTLinkFrontmostDiag = sawSymbol ? @"sbs_symbols_returned_nil" : @"sbs_symbols_missing";
    return nil;
}

static pid_t TLinkSBSProcessIDForBundleId(NSString *bundleId)
{
    if (bundleId.length == 0) return 0;
    void *handle = TLinkSpringBoardServicesHandle();
    if (!handle) return 0;
    const char *symbols[] = {
        "SBSProcessIDForDisplayIdentifier",
        NULL,
    };
    for (int i = 0; symbols[i] != NULL; i++) {
        TLinkSBSProcessIDFn fn = (TLinkSBSProcessIDFn)dlsym(handle, symbols[i]);
        if (!fn) continue;
        int pid = fn((__bridge CFStringRef)bundleId);
        if (pid > 0) return (pid_t)pid;
    }
    return 0;
}

static pid_t TLinkResolvePidForBundleId(NSString *bundleId)
{
    pid_t pid = TLinkSBSProcessIDForBundleId(bundleId);
    if (pid <= 0) pid = TLinkPidForBundleId(bundleId);
    return pid;
}

static void TLinkRememberFrontmost(NSString *bundleId, NSString *source, pid_t pid)
{
    if (bundleId.length == 0) return;
    sTLinkLastFrontmostBundleId = bundleId;
    sTLinkLastFrontmostSource = source ?: @"unknown";
    sTLinkLastFrontmostPid = pid > 0 ? pid : (pid == 0 ? TLinkResolvePidForBundleId(bundleId) : 0);
    sTLinkLastFrontmostAtMs = TLinkNowMs();
}

static BOOL TLinkLooksLikeBundleId(NSString *candidate)
{
    if (candidate.length < 3 || [candidate rangeOfString:@"."].location == NSNotFound) return NO;
    static NSCharacterSet *bad = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
    });
    return [candidate rangeOfCharacterFromSet:bad].location == NSNotFound;
}

static void TLinkCollectBundleIdsFromObject(id object, NSMutableOrderedSet<NSString *> *bundleIds, NSInteger depth)
{
    if (!object || object == (id)kCFNull || depth <= 0) return;
    if ([object isKindOfClass:[NSString class]]) {
        NSString *candidate = (NSString *)object;
        if (TLinkLooksLikeBundleId(candidate)) [bundleIds addObject:candidate];
        return;
    }
    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]]) {
        for (id item in object) TLinkCollectBundleIdsFromObject(item, bundleIds, depth - 1);
        return;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        for (id value in [(NSDictionary *)object allValues]) TLinkCollectBundleIdsFromObject(value, bundleIds, depth - 1);
        return;
    }

    NSArray<NSString *> *selectorNames = @[
        @"bundleIdentifier",
        @"displayIdentifier",
        @"applicationIdentifier",
        @"applicationBundleIdentifier",
        @"owningBundleIdentifier",
        @"elements",
        @"displayItems",
        @"transitioningItems",
        @"toLayout",
        @"layout",
        @"currentLayout",
        @"activeApplication",
        @"frontmostApplication",
    ];
    for (NSString *selName in selectorNames) {
        SEL sel = NSSelectorFromString(selName);
        if (![object respondsToSelector:sel]) continue;
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(object, sel);
            TLinkCollectBundleIdsFromObject(value, bundleIds, depth - 1);
        } @catch (__unused NSException *exception) {
        }
    }
}

static NSString *TLinkPreferredBundleIdFromSet(NSOrderedSet<NSString *> *bundleIds)
{
    NSString *springboard = nil;
    for (NSString *bundleId in bundleIds) {
        if ([bundleId isEqualToString:@"com.apple.springboard"]) {
            springboard = bundleId;
            continue;
        }
        if ([bundleId hasPrefix:@"com.apple."] &&
            ([bundleId containsString:@"ControlCenter"] || [bundleId containsString:@"NotificationCenter"])) {
            continue;
        }
        return bundleId;
    }
    return springboard ?: (bundleIds.count > 0 ? [bundleIds objectAtIndex:0] : nil);
}

static NSString *TLinkBundleIdFromFBSObject(id object)
{
    NSMutableOrderedSet<NSString *> *bundleIds = [[NSMutableOrderedSet alloc] init];
    TLinkCollectBundleIdsFromObject(object, bundleIds, 4);
    return TLinkPreferredBundleIdFromSet(bundleIds);
}

static void *TLinkFrontBoardServicesHandle(void)
{
    static void *handle = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlerror();
        handle = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY | RTLD_GLOBAL);
        if (!handle) {
            const char *err = dlerror();
            sTLinkFrontmostDiag = [NSString stringWithFormat:@"%@ fbs_dlopen_failed:%s", sTLinkFrontmostDiag ?: @"", err ?: "unknown"];
        }
    });
    return handle;
}

static NSString *TLinkFBSCurrentFrontmostBundleId(void)
{
    if (!TLinkFrontBoardServicesHandle()) {
        sTLinkFrontmostDiag = [NSString stringWithFormat:@"%@ fbs_dlopen_failed", sTLinkFrontmostDiag ?: @""];
        return nil;
    }

    if (!sTLinkFBSDisplayLayoutMonitor) {
        Class configClass = NSClassFromString(@"FBSDisplayLayoutMonitorConfiguration");
        Class monitorClass = NSClassFromString(@"FBSDisplayLayoutMonitor");
        if (!configClass || !monitorClass) {
            sTLinkFrontmostDiag = [NSString stringWithFormat:@"%@ fbs_classes_missing", sTLinkFrontmostDiag ?: @""];
            return nil;
        }

        id config = nil;
        SEL defaultConfigSel = NSSelectorFromString(@"configurationForDefaultMainDisplayMonitor");
        @try {
            if ([configClass respondsToSelector:defaultConfigSel]) {
                config = ((id (*)(Class, SEL))objc_msgSend)(configClass, defaultConfigSel);
            } else {
                config = [[configClass alloc] init];
            }
        } @catch (__unused NSException *exception) {
            config = nil;
        }
        if (!config) {
            sTLinkFrontmostDiag = [NSString stringWithFormat:@"%@ fbs_config_failed", sTLinkFrontmostDiag ?: @""];
            return nil;
        }

        SEL prioritySel = NSSelectorFromString(@"setNeedsUserInteractivePriority:");
        if ([config respondsToSelector:prioritySel]) {
            @try {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(config, prioritySel, YES);
            } @catch (__unused NSException *exception) {
            }
        }

        sTLinkFBSDisplayLayoutBlock = [^(id transition) {
            NSString *bundleId = TLinkBundleIdFromFBSObject(transition);
            if (bundleId.length > 0) TLinkRememberFrontmost(bundleId, @"fbs:transition", 0);
        } copy];
        SEL transitionHandlerSel = NSSelectorFromString(@"setTransitionHandler:");
        if ([config respondsToSelector:transitionHandlerSel]) {
            @try {
                ((void (*)(id, SEL, id))objc_msgSend)(config, transitionHandlerSel, sTLinkFBSDisplayLayoutBlock);
            } @catch (__unused NSException *exception) {
            }
        }

        SEL monitorSel = NSSelectorFromString(@"monitorWithConfiguration:");
        @try {
            if ([monitorClass respondsToSelector:monitorSel]) {
                sTLinkFBSDisplayLayoutMonitor = ((id (*)(Class, SEL, id))objc_msgSend)(monitorClass, monitorSel, config);
            } else {
                SEL initSel = NSSelectorFromString(@"initWithConfiguration:");
                id allocated = [monitorClass alloc];
                if ([allocated respondsToSelector:initSel]) {
                    sTLinkFBSDisplayLayoutMonitor = ((id (*)(id, SEL, id))objc_msgSend)(allocated, initSel, config);
                } else {
                    sTLinkFBSDisplayLayoutMonitor = [allocated init];
                }
            }
        } @catch (__unused NSException *exception) {
            sTLinkFBSDisplayLayoutMonitor = nil;
        }
        if (!sTLinkFBSDisplayLayoutMonitor) {
            sTLinkFrontmostDiag = [NSString stringWithFormat:@"%@ fbs_monitor_failed", sTLinkFrontmostDiag ?: @""];
            return nil;
        }
    }

    id layout = TLinkObjectForSelectorOrKey(sTLinkFBSDisplayLayoutMonitor, @"currentLayout", nil);
    NSString *bundleId = TLinkBundleIdFromFBSObject(layout);
    if (bundleId.length > 0) {
        TLinkRememberFrontmost(bundleId, @"fbs:currentLayout", 0);
        return bundleId;
    }

    bundleId = TLinkBundleIdFromFBSObject(sTLinkFBSDisplayLayoutMonitor);
    if (bundleId.length > 0) {
        TLinkRememberFrontmost(bundleId, @"fbs:monitor", 0);
        return bundleId;
    }

    __block NSString *asyncBundleId = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        asyncBundleId = sTLinkLastFrontmostBundleId;
        dispatch_semaphore_signal(sema);
    });
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(350 * NSEC_PER_MSEC)));
    if (asyncBundleId.length == 0) {
        sTLinkFrontmostDiag = [NSString stringWithFormat:@"%@ fbs_no_layout_bundle", sTLinkFrontmostDiag ?: @""];
    }
    return asyncBundleId;
}

static BOOL TLinkWorkspaceOpenBundleId(NSString *bundleId)
{
    id workspace = TLinkApplicationWorkspace();
    if (!workspace) return NO;
    __block BOOL started = NO;
    void (^openBlock)(void) = ^{
        NSArray<NSString *> *selectors = @[@"openApplicationWithBundleID:", @"openApplicationWithBundleIdentifier:"];
        for (NSString *selName in selectors) {
            SEL sel = NSSelectorFromString(selName);
            if (![workspace respondsToSelector:sel]) continue;
            @try {
                BOOL ok = ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(workspace, sel, bundleId);
                if (ok) {
                    started = YES;
                    return;
                }
            } @catch (__unused NSException *exception) {
            }
        }
    };
    if ([NSThread isMainThread]) openBlock();
    else dispatch_sync(dispatch_get_main_queue(), openBlock);
    return started;
}

static BOOL TLinkWorkspaceOpenURL(NSURL *url)
{
    id workspace = TLinkApplicationWorkspace();
    SEL openSel = NSSelectorFromString(@"openURL:");
    if (workspace && [workspace respondsToSelector:openSel]) {
        @try {
            BOOL ok = ((BOOL (*)(id, SEL, NSURL *))objc_msgSend)(workspace, openSel, url);
            if (ok) return YES;
        } @catch (__unused NSException *exception) {
        }
    }

    __block BOOL started = NO;
    void (^openBlock)(void) = ^{
        @try {
            UIApplication *app = [UIApplication sharedApplication];
            if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
                started = YES;
                [app openURL:url options:@{} completionHandler:^(__unused BOOL success) {}];
            } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                started = [app openURL:url];
#pragma clang diagnostic pop
            }
        } @catch (__unused NSException *exception) {
            started = NO;
        }
    };
    if ([NSThread isMainThread]) openBlock();
    else dispatch_sync(dispatch_get_main_queue(), openBlock);
    return started;
}

static NSData *TLinkHandleOpenApplication(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"open_app_missing_bundle_id");
    TLinkRememberFrontmost(bundleId, @"task11:expected", -1);
    return TLinkSuccess([NSString stringWithFormat:@"frontmost_expected;;%@;;launch_disabled_on_trollstore", bundleId]);
}

static NSData *TLinkHandleAppKill(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"kill_app_missing_bundle_id");
    if ([bundleId isEqualToString:@"com.apple.springboard"]) {
        return TLinkUnsupported(31, @"refusing_to_kill_springboard");
    }
    pid_t pid = TLinkPidForBundleId(bundleId);
    if (pid <= 0) return TLinkError([NSString stringWithFormat:@"app_not_running bundle=%@", bundleId]);
    if (kill(pid, SIGTERM) != 0) {
        return TLinkError([NSString stringWithFormat:@"kill_app_sigterm_failed pid=%d errno=%d", pid, errno]);
    }
    usleep(500 * 1000);
    if (kill(pid, 0) == 0) {
        int rc = kill(pid, SIGKILL);
        if (rc != 0) {
            return TLinkError([NSString stringWithFormat:@"kill_app_sigkill_failed pid=%d errno=%d", pid, errno]);
        }
    }
    return TLinkSuccess(nil);
}

static NSData *TLinkHandleAppState(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"app_state_missing_bundle_id");
    return TLinkSuccess(TLinkResolvePidForBundleId(bundleId) > 0 ? @"1" : @"0");
}

static NSData *TLinkHandleAppInfo(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"app_info_missing_bundle_id");
    id proxy = TLinkApplicationProxyForBundleId(bundleId);
    if (!proxy) return TLinkError([NSString stringWithFormat:@"app_info_not_found bundle=%@", bundleId]);
    NSString *name = TLinkProtocolSafeField(TLinkStringForSelectorOrKey(proxy, @"localizedName", @"localizedName"));
    NSString *shortVersion = TLinkProtocolSafeField(TLinkStringForSelectorOrKey(proxy, @"shortVersionString", @"shortVersionString"));
    NSString *bundleVersion = TLinkProtocolSafeField(TLinkStringForSelectorOrKey(proxy, @"bundleVersion", @"bundleVersion"));
    NSString *state = TLinkResolvePidForBundleId(bundleId) > 0 ? @"1" : @"0";
    return TLinkSuccess([NSString stringWithFormat:@"%@;;%@;;%@;;%@;;%@", bundleId, name, shortVersion, bundleVersion, state]);
}

static NSData *TLinkHandleFrontmostAppId(void)
{
    NSString *bundleId = TLinkSBSCopyFrontmostBundleId();
    if (bundleId.length == 0) bundleId = TLinkFBSCurrentFrontmostBundleId();
    if (bundleId.length == 0 && sTLinkLastFrontmostBundleId.length > 0) bundleId = sTLinkLastFrontmostBundleId;
    if (bundleId.length == 0) {
        return TLinkUnsupported(34, [NSString stringWithFormat:@"frontmost_requires_springboard_or_frontboard_access %@", sTLinkFrontmostDiag ?: @""]);
    }
    return TLinkSuccess(bundleId);
}

static NSData *TLinkHandleFrontmostOrientation(void)
{
    CGSize bounds = [UIScreen mainScreen].bounds.size;
    int orientation = bounds.width > bounds.height ? 4 : 1;
    return TLinkSuccess([NSString stringWithFormat:@"%d", orientation]);
}

static NSData *TLinkHandleAppPid(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"app_pid_missing_bundle_id");
    pid_t pid = TLinkResolvePidForBundleId(bundleId);
    return TLinkSuccess([NSString stringWithFormat:@"%d", pid]);
}

static NSData *TLinkHandleFrontmostPid(void)
{
    NSString *bundleId = TLinkSBSCopyFrontmostBundleId();
    if (bundleId.length == 0) bundleId = TLinkFBSCurrentFrontmostBundleId();
    if (bundleId.length == 0 && sTLinkLastFrontmostBundleId.length > 0) bundleId = sTLinkLastFrontmostBundleId;
    if (bundleId.length == 0) {
        return TLinkUnsupported(51, [NSString stringWithFormat:@"frontmost_pid_requires_springboard_or_frontboard_access %@", sTLinkFrontmostDiag ?: @""]);
    }
    pid_t pid = 0;
    if ([bundleId isEqualToString:sTLinkLastFrontmostBundleId] && sTLinkLastFrontmostPid > 0) {
        pid = sTLinkLastFrontmostPid;
    }
    if (pid <= 0) pid = TLinkResolvePidForBundleId(bundleId);
    return TLinkSuccess([NSString stringWithFormat:@"%d", pid]);
}

static NSData *TLinkHandleAppPaths(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"app_paths_missing_bundle_id");
    id proxy = TLinkApplicationProxyForBundleId(bundleId);
    if (!proxy) return TLinkSuccess(@";;");
    NSString *bundlePath = TLinkProtocolSafeField(TLinkBundlePathForProxy(proxy));
    NSString *dataPath = TLinkProtocolSafeField(TLinkDataPathForProxy(proxy));
    return TLinkSuccess([NSString stringWithFormat:@"%@;;%@", bundlePath ?: @"", dataPath ?: @""]);
}

static NSData *TLinkHandleListBundles(NSString *body)
{
    BOOL withInfo = [TLinkCleanPayload(body) intValue] == 1;
    id workspace = TLinkApplicationWorkspace();
    if (!workspace) return TLinkError(@"list_bundles_workspace_unavailable");

    NSArray *apps = nil;
    SEL allInstalledSel = NSSelectorFromString(@"allInstalledApplications");
    SEL allSel = NSSelectorFromString(@"allApplications");
    @try {
        if ([workspace respondsToSelector:allInstalledSel]) {
            apps = ((NSArray *(*)(id, SEL))objc_msgSend)(workspace, allInstalledSel);
        } else if ([workspace respondsToSelector:allSel]) {
            apps = ((NSArray *(*)(id, SEL))objc_msgSend)(workspace, allSel);
        }
    } @catch (__unused NSException *exception) {
        apps = nil;
    }
    if (![apps isKindOfClass:[NSArray class]]) apps = @[];

    if (!withInfo) {
        NSMutableArray<NSString *> *bundleIds = [NSMutableArray array];
        for (id proxy in apps) {
            NSString *bid = TLinkStringForSelectorOrKey(proxy, @"bundleIdentifier", @"bundleIdentifier");
            if (bid.length > 0) [bundleIds addObject:bid];
        }
        return TLinkSuccess([bundleIds componentsJoinedByString:@",,"]);
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (id proxy in apps) {
        NSString *bid = TLinkStringForSelectorOrKey(proxy, @"bundleIdentifier", @"bundleIdentifier");
        if (bid.length == 0) continue;
        [items addObject:@{
            @"bundle_id": bid,
            @"name": TLinkStringForSelectorOrKey(proxy, @"localizedName", @"localizedName") ?: @"",
            @"short_version": TLinkStringForSelectorOrKey(proxy, @"shortVersionString", @"shortVersionString") ?: @"",
            @"bundle_version": TLinkStringForSelectorOrKey(proxy, @"bundleVersion", @"bundleVersion") ?: @"",
        }];
    }
    NSDictionary *obj = @{@"items": items};
    NSError *jsonErr = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&jsonErr];
    if (!json || jsonErr) return TLinkError(@"list_bundles_json_failed");
    return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @"");
}

static NSData *TLinkHandleOpenURL(NSString *body)
{
    NSString *raw = TLinkCleanPayload(body);
    if (raw.length == 0) return TLinkError(@"open_url_missing_url");
    NSString *lowerRaw = [raw lowercaseString];
    NSString *fallback = nil;
    NSString *knownBundleId = nil;
    if ([lowerRaw hasPrefix:@"prefs:"]) {
        fallback = [@"App-Prefs:" stringByAppendingString:[raw substringFromIndex:6]];
        knownBundleId = @"com.apple.Preferences";
    } else if ([lowerRaw hasPrefix:@"app-prefs:"]) {
        knownBundleId = @"com.apple.Preferences";
    }
    NSURL *url = [NSURL URLWithString:raw];
    if (!url) return TLinkError(@"open_url_invalid_url");
    if (TLinkWorkspaceOpenURL(url)) {
        if (knownBundleId.length > 0) TLinkRememberFrontmost(knownBundleId, @"task54", 0);
        return TLinkSuccess(nil);
    }
    NSURL *fallbackURL = fallback.length > 0 ? [NSURL URLWithString:fallback] : nil;
    if (fallbackURL && TLinkWorkspaceOpenURL(fallbackURL)) {
        if (knownBundleId.length > 0) TLinkRememberFrontmost(knownBundleId, @"task54:fallback", 0);
        return TLinkSuccess(nil);
    }
    return TLinkError(@"open_url_failed_or_limited_on_trollstore");
}

static NSData *TLinkHandleHelloStatus(void)
{
    NSDictionary *capabilities = @{
        @"touch": @(YES),
        @"touchAck": @(YES),
        @"nativeTouch": @(YES),
        @"capture": @(YES),
        @"h264": @(YES),
        @"image": @(YES),
        @"color": @(YES),
        @"frame": @(YES),
        @"keyboardClipboard": @(YES),
        @"ocr": @(YES),
        @"visionOCR": @(YES),
        @"tesseractOCR": @(NO),
        @"script": @(NO),
        @"appMgmt": @(YES),
        @"appMgmtMode": @"limited_process_info_cache_launch_kill",
        @"appLaunchMode": @"cache_only",
        @"frontmost": @(YES),
        @"clearData": @(NO),
        @"hidMonitor": @(YES),
        @"privhelper": @(YES),
        @"privhelperMode": @"restart_streamd_only",
    };
    CGSize screen = TLinkScreenPixelSize();
    uint64_t nowMs = TLinkNowMs();
    uint64_t frontmostAgeMs = (sTLinkLastFrontmostAtMs > 0 && nowMs >= sTLinkLastFrontmostAtMs)
        ? nowMs - sTLinkLastFrontmostAtMs
        : 0;
    NSDictionary *payload = @{
        @"runtime": @"trollstore",
        @"service": @"streamd",
        @"phase": @"image-color-frame-ocr-app-lite",
        @"pid": @((int)getpid()),
        @"tlinkauto": @{@"port": @6000, @"protocols": @[@"v0-line", @"legacy-task"]},
        @"device": @{
            @"name": [UIDevice currentDevice].name ?: @"",
            @"system_name": [UIDevice currentDevice].systemName ?: @"iOS",
            @"system_version": [UIDevice currentDevice].systemVersion ?: @"",
            @"model": TLinkModelName(),
        },
        @"script": @{
            @"is_playing": @(NO),
            @"bundle_path": @"/var/mobile/Library/TLinkauto/scripts",
            @"last_error": @"script_runtime_unsupported_on_trollstore",
            @"last_error_ts": @(0),
        },
        @"screen": @{@"width": @((int)screen.width), @"height": @((int)screen.height), @"scale": @([UIScreen mainScreen].scale)},
        @"frontmost_cache": @{
            @"bundle_id": sTLinkLastFrontmostBundleId ?: @"",
            @"pid": @((int)sTLinkLastFrontmostPid),
            @"source": sTLinkLastFrontmostSource ?: @"",
            @"age_ms": @(frontmostAgeMs),
            @"diag": sTLinkFrontmostDiag ?: @"",
        },
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

    if (taskType == 11) {
        return TLinkHandleOpenApplication(body);
    }

    if (taskType == 18) {
        int us = [body intValue];
        if (us < 0) us = 0;
        usleep((useconds_t)us);
        return TLinkSuccess(nil);
    }

    if (taskType == 21) {
        return TLinkHandleTemplateMatch(body);
    }

    if (taskType == 25) {
        return TLinkHandleDeviceInfo(body);
    }

    if (taskType == 27) {
        return TLinkHandleVisionOCR(body);
    }

    if (taskType == 23) {
        return TLinkHandleColorPicker(body);
    }

    if (taskType == 24) {
        return TLinkHandleKeyboard(body);
    }

    if (taskType == 28) {
        return TLinkHandleColorSearch(body);
    }

    if (taskType == 29) {
        return TLinkHandleScreenshot(body);
    }

    if (taskType == 31) {
        return TLinkHandleAppKill(body);
    }

    if (taskType == 32) {
        return TLinkHandleAppState(body);
    }

    if (taskType == 33) {
        return TLinkHandleAppInfo(body);
    }

    if (taskType == 34) {
        return TLinkHandleFrontmostAppId();
    }

    if (taskType == 35) {
        return TLinkHandleFrontmostOrientation();
    }

    if (taskType == 44 || taskType == 45) {
        TLinkEnsureRuntimeDirectories();
        return TLinkSuccess(@"/var/mobile/Library/TLinkauto");
    }

    if (taskType == 46) {
        TLinkEnsureRuntimeDirectories();
        return TLinkSuccess(@"/var/mobile/Library/TLinkauto/scripts");
    }

    if (taskType == 47) {
        return TLinkHandleScreenKeep(body);
    }

    if (taskType == 48) {
        return TLinkHandleImageObject(body);
    }

    if (taskType == 49) {
        return TLinkHandleFindImage(body);
    }

    if (taskType == 50) {
        return TLinkHandleAppPid(body);
    }

    if (taskType == 51) {
        return TLinkHandleFrontmostPid();
    }

    if (taskType == 52) {
        return TLinkHandleAppPaths(body);
    }

    if (taskType == 53) {
        return TLinkHandleListBundles(body);
    }

    if (taskType == 54) {
        return TLinkHandleOpenURL(body);
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

    if (taskType == 66) {
        return TLinkHandleFrameCapture(body);
    }

    if (taskType == 67) {
        return TLinkHandleFrameRelease(body);
    }

    if (taskType == 68) {
        return TLinkHandleFindImageInFrame(body);
    }

    if (taskType == 69) {
        return TLinkHandleColorInFrame(body);
    }

    if (taskType == 70) {
        return TLinkHandleFrameBatch(body);
    }

    if (taskType == 96) {
        POCLogf("task-server: task96 shutdown requested");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(150 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            POCLogf("task-server: exiting for supervisor restart");
            exit(0);
        });
        return TLinkSuccess(@"streamd_exiting");
    }

    if (taskType == 97) {
        NSString *cap = @"runtime=trollstore phase=image-color-frame-ocr-app-lite ports=6000,7001,7002,7003,7004,7005,7006 tasks=10,11,18,21,23,24,25,27,28,29,31,32,33,34,35,44,45,46,47,48,49,50,51,52,53,54,60,61,62,63,64,65,66,67,68,69,70,96,97,98,99 capabilities=touch,capture,h264,hidMonitor,paths,color,image,frame,ocr,visionOCR,appInfo,appLaunchCacheOnly,appKillLimited,openURL,listBundles,keyboardClipboard,gracefulShutdown,privhelperRestart unsupported=tesseractOCR,script,clearData,keychain,connectivity keyboard=limited_on_trollstore imageMatch=naive_rgba appMgmt=limited_process_info_cache_launch_kill";
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
