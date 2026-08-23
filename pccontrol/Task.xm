#include "Task.h"
#import "TLinkDiagnostic.h"
#include "../shared/TLinkRootfullLicenseBuild.h"
#include "../shared/TLinkLicenseVerifier.h"
#include "../shared/TLinkRootfullLicensePolicy.h"
#include "../shared/TLinkVPNDiagnostics.h"
#include "../shared/TLinkRunHistory.h"
#include "../shared/TLinkEventChannel.h"
#include "../shared/TLinkAdaptiveStreaming.h"
#import <Foundation/Foundation.h>
#ifndef YES
#define YES true
#endif
#ifndef NO
#define NO false
#endif

#include <spawn.h>
#include <poll.h>
#include "Touch.h"
#include "Process.h"
#include "AlertBox.h"
#include "Record.h"
#include "Play.h"
#include "SocketServer.h"
#include "ScreenMatch.h"
#include "Toast.h"
#include "ColorPicker.h"
#include "Image.h"
#include "Connectivity.h"
#include "UIKeyboard.h"
#include "DeviceInfo.h"
#include "TouchIndicator/TouchIndicatorWindow.h"
#include "HardwareKey.h"
#include "Scheduler.h"
#include "RuntimeUtils.h"
#import "ScriptPlayer.h"
#import <mach/mach.h>
#include <Foundation/NSDistributedNotificationCenter.h>
#include <TextRecognization/TextRecognizer.h>
#include "UpdateCache.h"
#include "TesseractOCRTask.h"
#include "Screen.h"
#include "H264Stream.h"
#include "NSTask.h"
#include <signal.h>
#include <os/lock.h>
#include <atomic>
#include <math.h>
#include <limits.h>

extern CFRunLoopRef recordRunLoop;
extern ScriptPlayer *scriptPlayer;
static std::atomic<uint64_t> sTLinkSpringBoardLicenseTask10DropCount(0);
static std::atomic<uint64_t> sTLinkZoomAttemptCount(0);
static std::atomic<uint64_t> sTLinkZoomSuccessCount(0);
static std::atomic<uint64_t> sTLinkZoomValidationRejectedCount(0);
static std::atomic<uint64_t> sTLinkZoomDispatchExceptionCount(0);
static std::atomic<uint64_t> sTLinkZoomCleanupCount(0);
static std::atomic<uint64_t> sTLinkZoomFrameCount(0);
static std::atomic<uint64_t> sTLinkZoomLastAtMs(0);
static std::atomic<int> sTLinkZoomLastResult(0);
static std::atomic<int> sTLinkZoomLastDirection(0);
static std::atomic<int> sTLinkZoomLastFingerCount(0);
static std::atomic<int> sTLinkZoomLastSteps(0);
static std::atomic<int> sTLinkZoomLastDurationMs(0);

static uint64_t zx_zoomNowMs(void)
{
    return (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

static NSDictionary *zx_zoomDiagnostics(void)
{
    uint64_t attempts = sTLinkZoomAttemptCount.load(std::memory_order_relaxed);
    uint64_t successes = sTLinkZoomSuccessCount.load(std::memory_order_relaxed);
    uint64_t validationRejected = sTLinkZoomValidationRejectedCount.load(std::memory_order_relaxed);
    uint64_t dispatchExceptions = sTLinkZoomDispatchExceptionCount.load(std::memory_order_relaxed);
    uint64_t completed = successes + validationRejected + dispatchExceptions;
    int result = sTLinkZoomLastResult.load(std::memory_order_relaxed);
    int direction = sTLinkZoomLastDirection.load(std::memory_order_relaxed);
    return @{
        @"schema": @"zoom_runtime_diagnostics_v1",
        @"attempt_count": @(attempts),
        @"success_count": @(successes),
        @"validation_rejected_count": @(validationRejected),
        @"dispatch_exception_count": @(dispatchExceptions),
        @"cleanup_count": @(sTLinkZoomCleanupCount.load(std::memory_order_relaxed)),
        @"frame_count": @(sTLinkZoomFrameCount.load(std::memory_order_relaxed)),
        @"in_flight": @(attempts > completed ? attempts - completed : 0),
        @"last_at_ms": @(sTLinkZoomLastAtMs.load(std::memory_order_relaxed)),
        @"last_result": result == 1 ? @"success" : (result == 2 ? @"validation_rejected" : (result == 3 ? @"dispatch_exception" : @"none")),
        @"last_direction": direction > 0 ? @"spread" : (direction < 0 ? @"pinch" : @"unknown"),
        @"last_finger_count": @(sTLinkZoomLastFingerCount.load(std::memory_order_relaxed)),
        @"last_steps": @(sTLinkZoomLastSteps.load(std::memory_order_relaxed)),
        @"last_duration_ms": @(sTLinkZoomLastDurationMs.load(std::memory_order_relaxed)),
    };
}

/*
get task type
*/
static int getTaskType(UInt8* dataArray)
{
    return (dataArray[0] - '0') * 10 + (dataArray[1] - '0');
}

static int zx_clampTouchCoord(CGFloat value)
{
    if (value < 0) value = 0;
    int fixed = (int)(value * 10.0f + 0.5f);
    if (fixed > 99999) fixed = 99999;
    return fixed;
}

static NSString *zx_touchPayload(int type, int finger, CGFloat x, CGFloat y)
{
    if (finger < 0) finger = 0;
    if (finger > 99) finger = 99;
    return [NSString stringWithFormat:@"1%d%02d%05d%05d", type, finger, zx_clampTouchCoord(x), zx_clampTouchCoord(y)];
}

static void zx_performSingleTouch(int type, int finger, CGFloat x, CGFloat y)
{
    NSString *payload = zx_touchPayload(type, finger, x, y);
    performTouchFromRawData((UInt8 *)[payload UTF8String]);
}

static void zx_performTouchFrame(int type, int baseFinger, const CGPoint *points, int count)
{
    NSMutableString *payload = [NSMutableString stringWithFormat:@"%d", count];
    for (int i = 0; i < count; i++) {
        [payload appendFormat:@"%d%02d%05d%05d",
                              type,
                              baseFinger + i,
                              zx_clampTouchCoord(points[i].x),
                              zx_clampTouchCoord(points[i].y)];
    }
    performTouchFromRawData((UInt8 *)[payload UTF8String]);
    sTLinkZoomFrameCount.fetch_add(1, std::memory_order_relaxed);
}

static NSArray<NSString *> *zx_splitTaskParts(UInt8 *eventData)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw) return @[];
    return [raw componentsSeparatedByString:@";;"];
}

static bool zx_handleNativeTap(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 2) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native tap format: x;;y[;;duration_ms;;finger]\r\n"}];
        return false;
    }
    CGFloat x = [parts[0] floatValue];
    CGFloat y = [parts[1] floatValue];
    int durationMs = parts.count >= 3 ? [parts[2] intValue] : 50;
    int finger = parts.count >= 4 ? [parts[3] intValue] : 0;
    if (durationMs < 0) durationMs = 0;
    zx_performSingleTouch(TOUCH_DOWN, finger, x, y);
    if (durationMs > 0) usleep((useconds_t)durationMs * 1000);
    zx_performSingleTouch(TOUCH_UP, finger, x, y);
    return true;
}

static bool zx_handleNativeSwipe(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 5) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native swipe format: x1;;y1;;x2;;y2;;duration_ms[;;finger;;steps]\r\n"}];
        return false;
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

    zx_performSingleTouch(TOUCH_DOWN, finger, x1, y1);
    int sleepPerStep = steps > 0 ? durationMs * 1000 / steps : 0;
    for (int i = 1; i < steps; i++) {
        if (sleepPerStep > 0) usleep((useconds_t)sleepPerStep);
        CGFloat t = (CGFloat)i / (CGFloat)steps;
        zx_performSingleTouch(TOUCH_MOVE, finger, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
    if (sleepPerStep > 0) usleep((useconds_t)sleepPerStep);
    zx_performSingleTouch(TOUCH_UP, finger, x2, y2);
    return true;
}

static bool zx_parseGesturePoint(NSString *text, CGFloat *x, CGFloat *y)
{
    NSArray<NSString *> *xy = [text componentsSeparatedByString:@","];
    if (xy.count != 2) return false;
    if (x) *x = [xy[0] floatValue];
    if (y) *y = [xy[1] floatValue];
    return true;
}

static bool zx_parseZoomNumber(NSString *text, double *value)
{
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return false;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double parsed = 0.0;
    if (![scanner scanDouble:&parsed] || !scanner.isAtEnd || !isfinite(parsed)) return false;
    if (value) *value = parsed;
    return true;
}

static bool zx_parseZoomInteger(NSString *text, int *value)
{
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return false;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    long long parsed = 0;
    if (![scanner scanLongLong:&parsed] || !scanner.isAtEnd || parsed < INT_MIN || parsed > INT_MAX) return false;
    if (value) *value = (int)parsed;
    return true;
}

static bool zx_zoomError(NSError **err, NSString *message)
{
    if ([message hasPrefix:@"zoom_dispatch_exception"]) {
        sTLinkZoomDispatchExceptionCount.fetch_add(1, std::memory_order_relaxed);
        sTLinkZoomLastResult.store(3, std::memory_order_relaxed);
    } else {
        sTLinkZoomValidationRejectedCount.fetch_add(1, std::memory_order_relaxed);
        sTLinkZoomLastResult.store(2, std::memory_order_relaxed);
    }
    if (err) {
        NSString *response = [NSString stringWithFormat:@"-1;;%@\r\n", message ?: @"zoom_failed"];
        *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                   code:999
                               userInfo:@{NSLocalizedDescriptionKey: response}];
    }
    return false;
}

static void zx_zoomPoints(CGPoint *points,
                          int fingerCount,
                          double centerX,
                          double centerY,
                          double radius,
                          double angleDegrees)
{
    const double degreesToRadians = 3.14159265358979323846 / 180.0;
    double baseAngle = angleDegrees * degreesToRadians;
    for (int finger = 0; finger < fingerCount; finger++) {
        double angle = baseAngle + (2.0 * 3.14159265358979323846 * (double)finger / (double)fingerCount);
        points[finger] = CGPointMake((CGFloat)(centerX + cos(angle) * radius),
                                    (CGFloat)(centerY + sin(angle) * radius));
    }
}

static bool zx_handleNativeZoom(NSArray<NSString *> *parts, NSError **err)
{
    sTLinkZoomAttemptCount.fetch_add(1, std::memory_order_relaxed);
    sTLinkZoomLastAtMs.store(zx_zoomNowMs(), std::memory_order_relaxed);
    sTLinkZoomLastResult.store(0, std::memory_order_relaxed);
    sTLinkZoomLastDirection.store(0, std::memory_order_relaxed);
    sTLinkZoomLastFingerCount.store(0, std::memory_order_relaxed);
    sTLinkZoomLastSteps.store(0, std::memory_order_relaxed);
    sTLinkZoomLastDurationMs.store(0, std::memory_order_relaxed);
    if (parts.count < 8 || parts.count > 10) {
        return zx_zoomError(err, @"zoom_bad_payload expected=zoom;;center_x;;center_y;;start_radius;;end_radius;;duration_ms;;finger_count;;steps[;;angle_degrees;;base_finger]");
    }

    double centerX = 0.0, centerY = 0.0, startRadius = 0.0, endRadius = 0.0, angleDegrees = 0.0;
    int durationMs = 0, fingerCount = 0, steps = 0, baseFinger = 0;
    if (!zx_parseZoomNumber(parts[1], &centerX)) return zx_zoomError(err, @"zoom_invalid_number field=center_x");
    if (!zx_parseZoomNumber(parts[2], &centerY)) return zx_zoomError(err, @"zoom_invalid_number field=center_y");
    if (!zx_parseZoomNumber(parts[3], &startRadius)) return zx_zoomError(err, @"zoom_invalid_number field=start_radius");
    if (!zx_parseZoomNumber(parts[4], &endRadius)) return zx_zoomError(err, @"zoom_invalid_number field=end_radius");
    if (!zx_parseZoomInteger(parts[5], &durationMs)) return zx_zoomError(err, @"zoom_invalid_number field=duration_ms");
    if (!zx_parseZoomInteger(parts[6], &fingerCount)) return zx_zoomError(err, @"zoom_invalid_number field=finger_count");
    if (!zx_parseZoomInteger(parts[7], &steps)) return zx_zoomError(err, @"zoom_invalid_number field=steps");
    if (parts.count >= 9 && !zx_parseZoomNumber(parts[8], &angleDegrees)) return zx_zoomError(err, @"zoom_invalid_number field=angle_degrees");
    if (parts.count >= 10 && !zx_parseZoomInteger(parts[9], &baseFinger)) return zx_zoomError(err, @"zoom_invalid_number field=base_finger");

    sTLinkZoomLastDirection.store(endRadius > startRadius ? 1 : (endRadius < startRadius ? -1 : 0), std::memory_order_relaxed);
    sTLinkZoomLastFingerCount.store(fingerCount, std::memory_order_relaxed);
    sTLinkZoomLastSteps.store(steps, std::memory_order_relaxed);
    sTLinkZoomLastDurationMs.store(durationMs, std::memory_order_relaxed);

    if (durationMs < 50 || durationMs > 5000) return zx_zoomError(err, @"zoom_duration_out_of_range min=50 max=5000");
    if (fingerCount != 2 && fingerCount != 3) return zx_zoomError(err, @"zoom_finger_count_unsupported allowed=2,3");
    if (steps < 2 || steps > 120) return zx_zoomError(err, @"zoom_steps_out_of_range min=2 max=120");
    if (startRadius <= 0.0 || endRadius <= 0.0) return zx_zoomError(err, @"zoom_radius_invalid positive_required=1");
    if (startRadius == endRadius) return zx_zoomError(err, @"zoom_radius_unchanged");
    if (angleDegrees < -360.0 || angleDegrees > 360.0) return zx_zoomError(err, @"zoom_angle_out_of_range min=-360 max=360");
    if (baseFinger < 0 || baseFinger + fingerCount > 20) return zx_zoomError(err, @"zoom_finger_range_invalid allowed=0..19");

    CGFloat screenWidth = [Screen getScreenWidth];
    CGFloat screenHeight = [Screen getScreenHeight];
    if (screenWidth <= 0.0 || screenHeight <= 0.0) return zx_zoomError(err, @"zoom_screen_unavailable");

    CGPoint points[3];
    for (int step = 0; step < steps; step++) {
        double t = (double)step / (double)(steps - 1);
        double radius = startRadius + (endRadius - startRadius) * t;
        zx_zoomPoints(points, fingerCount, centerX, centerY, radius, angleDegrees);
        for (int finger = 0; finger < fingerCount; finger++) {
            if (points[finger].x < 0.0 || points[finger].x >= screenWidth ||
                points[finger].y < 0.0 || points[finger].y >= screenHeight) {
                return zx_zoomError(err, [NSString stringWithFormat:@"zoom_point_out_of_bounds step=%d finger=%d screen=%.0fx%.0f",
                                          step, baseFinger + finger, screenWidth, screenHeight]);
            }
        }
    }

    bool fingersDown = false;
    @try {
        zx_zoomPoints(points, fingerCount, centerX, centerY, startRadius, angleDegrees);
        zx_performTouchFrame(TOUCH_DOWN, baseFinger, points, fingerCount);
        fingersDown = true;

        int sleepPerIntervalUs = durationMs * 1000 / (steps - 1);
        for (int step = 1; step < steps; step++) {
            if (sleepPerIntervalUs > 0) usleep((useconds_t)sleepPerIntervalUs);
            double t = (double)step / (double)(steps - 1);
            double radius = startRadius + (endRadius - startRadius) * t;
            zx_zoomPoints(points, fingerCount, centerX, centerY, radius, angleDegrees);
            zx_performTouchFrame(TOUCH_MOVE, baseFinger, points, fingerCount);
        }
        zx_performTouchFrame(TOUCH_UP, baseFinger, points, fingerCount);
        fingersDown = false;
    } @catch (__unused NSException *exception) {
        if (fingersDown) {
            sTLinkZoomCleanupCount.fetch_add(1, std::memory_order_relaxed);
            zx_performTouchFrame(TOUCH_UP, baseFinger, points, fingerCount);
        }
        return zx_zoomError(err, @"zoom_dispatch_exception");
    }
    sTLinkZoomSuccessCount.fetch_add(1, std::memory_order_relaxed);
    sTLinkZoomLastResult.store(1, std::memory_order_relaxed);
    return true;
}

static bool zx_handleNativeGesture(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count > 0 &&
        [[parts[0] lowercaseString] isEqualToString:@"zoom"]) {
        return zx_handleNativeZoom(parts, err);
    }
    if (parts.count < 3) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native gesture format: finger;;duration_ms;;x,y|x,y|...\r\n"}];
        return false;
    }
    int finger = [parts[0] intValue];
    int durationMs = [parts[1] intValue];
    NSArray<NSString *> *pointTexts = [parts[2] componentsSeparatedByString:@"|"];
    if (pointTexts.count < 2) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native gesture requires at least two points.\r\n"}];
        return false;
    }
    if (durationMs < 0) durationMs = 0;

    CGFloat x = 0, y = 0;
    if (!zx_parseGesturePoint(pointTexts[0], &x, &y)) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid first gesture point.\r\n"}];
        return false;
    }
    zx_performSingleTouch(TOUCH_DOWN, finger, x, y);

    int intervals = (int)pointTexts.count - 1;
    int sleepPerInterval = intervals > 0 ? durationMs * 1000 / intervals : 0;
    for (NSUInteger i = 1; i < pointTexts.count; i++) {
        if (!zx_parseGesturePoint(pointTexts[i], &x, &y)) {
            zx_performSingleTouch(TOUCH_UP, finger, x, y);
            if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid gesture point.\r\n"}];
            return false;
        }
        zx_performSingleTouch(TOUCH_MOVE, finger, x, y);
        if (sleepPerInterval > 0) usleep((useconds_t)sleepPerInterval);
    }
    zx_performSingleTouch(TOUCH_UP, finger, x, y);
    return true;
}

static bool zx_handleNativeBatch(UInt8 *eventData, NSError **err)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw || raw.length == 0) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native batch format: command||command, command starts with 10/62/63/64.\r\n"}];
        return false;
    }

    NSArray<NSString *> *commands = [raw componentsSeparatedByString:@"||"];
    for (NSString *cmd in commands) {
        if (cmd.length < 2) continue;
        int task = [[cmd substringToIndex:2] intValue];
        NSString *payload = [cmd substringFromIndex:2];
        UInt8 *payloadBytes = (UInt8 *)[payload UTF8String];
        if (task == TASK_PERFORM_TOUCH) {
            performTouchFromRawData(payloadBytes);
        } else if (task == TASK_NATIVE_TAP) {
            if (!zx_handleNativeTap(payloadBytes, err)) return false;
        } else if (task == TASK_NATIVE_SWIPE) {
            if (!zx_handleNativeSwipe(payloadBytes, err)) return false;
        } else if (task == TASK_NATIVE_GESTURE) {
            if (!zx_handleNativeGesture(payloadBytes, err)) return false;
        } else {
            if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Unsupported batch task: %d\r\n", task]}];
            return false;
        }
    }
    return true;
}

// === runShell drain/timeout support (Group A) ===

static const NSUInteger kShellMaxCapturedOutputBytes = 768 * 1024;
static const NSUInteger kTLinkautoJSMaxResponseBytes = 1024 * 1024;
static const NSUInteger kShellReadChunkBytes = 16 * 1024;
static const double kShellDefaultTimeout = 30.0;
static const double kShellMinTimeout = 1.0;
static const double kShellMaxTimeout = 300.0;
static const double kShellTerminateGrace = 1.5;

@interface TLinkShellDrainContext : NSObject {
@private
    os_unfair_lock _lock;
    BOOL _forceCloseReaders;
}
@property (nonatomic, strong) NSMutableData *outData;
@property (nonatomic, strong) NSMutableData *errData;
@property (nonatomic, assign) NSUInteger capturedBytes;
@property (nonatomic, assign) BOOL outTruncated;
@property (nonatomic, assign) BOOL errTruncated;
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr;
- (void)requestForceCloseReaders;
- (BOOL)shouldForceCloseReaders;
@end

@implementation TLinkShellDrainContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _forceCloseReaders = false;
        _outData = [NSMutableData data];
        _errData = [NSMutableData data];
    }
    return self;
}
- (void)requestForceCloseReaders {
    os_unfair_lock_lock(&_lock);
    _forceCloseReaders = true;
    os_unfair_lock_unlock(&_lock);
}
- (BOOL)shouldForceCloseReaders {
    os_unfair_lock_lock(&_lock);
    BOOL value = _forceCloseReaders;
    os_unfair_lock_unlock(&_lock);
    return value;
}
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr {
    if (!chunk || chunk.length == 0) return;
    os_unfair_lock_lock(&_lock);
    NSUInteger remaining = (self.capturedBytes >= kShellMaxCapturedOutputBytes) ? 0 : (kShellMaxCapturedOutputBytes - self.capturedBytes);
    NSUInteger accepted = MIN(remaining, chunk.length);
    if (accepted > 0) {
        self.capturedBytes += accepted;
        if (isStderr) {
            [self.errData appendBytes:chunk.bytes length:accepted];
        } else {
            [self.outData appendBytes:chunk.bytes length:accepted];
        }
    }
    if (accepted < chunk.length) {
        if (isStderr) self.errTruncated = true;
        else self.outTruncated = true;
    }
    os_unfair_lock_unlock(&_lock);
}
@end

@interface TLinkShellResult : NSObject
@property (nonatomic, assign) int exitCode;
@property (nonatomic, assign) int terminationSignal;
@property (nonatomic, assign) BOOL timedOut;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL drainForcedClosed;
@property (nonatomic, strong) NSString *stdoutStr;
@property (nonatomic, strong) NSString *stderrStr;
@property (nonatomic, assign) BOOL stdoutTruncated;
@property (nonatomic, assign) BOOL stderrTruncated;
@end

@implementation TLinkShellResult
@end

static TLinkShellResult *RunShellCore(NSString *command, TLinkTaskExecutionContext *context, double timeoutSeconds, NSUInteger maxOutputBytes) {
    TLinkShellResult *result = [[TLinkShellResult alloc] init];
    result.exitCode = -1;
    result.stdoutStr = @"";
    result.stderrStr = @"";

    double actualTimeout = timeoutSeconds;
    if (actualTimeout <= 0) actualTimeout = (context && context.defaultTimeoutSeconds > 0) ? context.defaultTimeoutSeconds : kShellDefaultTimeout;
    if (actualTimeout < kShellMinTimeout) actualTimeout = kShellMinTimeout;
    if (actualTimeout > kShellMaxTimeout) actualTimeout = kShellMaxTimeout;

    int outPipe[2] = {-1, -1};
    int errPipe[2] = {-1, -1};
    
    if (pipe(outPipe) != 0 || pipe(errPipe) != 0) {
        result.stderrStr = @"Failed to create pipes";
        return result;
    }
    
    fcntl(outPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(outPipe[1], F_SETFD, FD_CLOEXEC);
    fcntl(errPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(errPipe[1], F_SETFD, FD_CLOEXEC);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, errPipe[0]);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);

    pid_t pid = -1;
    const char *cmdArgs[] = {"/usr/bin/sudo", "/usr/bin/tlinkautob", "-e", [command UTF8String], NULL};
    int spawnErr = posix_spawn(&pid, "/usr/bin/sudo", &actions, &attr, (char *const *)cmdArgs, NULL);

    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);

    close(outPipe[1]);
    close(errPipe[1]);

    if (spawnErr != 0) {
        close(outPipe[0]);
        close(errPipe[0]);
        result.stderrStr = [NSString stringWithFormat:@"posix_spawn failed: %d", spawnErr];
        return result;
    }

    TLinkShellDrainContext *drainCtx = [[TLinkShellDrainContext alloc] init];

    dispatch_queue_t ioQueue = dispatch_queue_create("com.tlinkauto.shell.io", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t drainGroup = dispatch_group_create();

    void (^drainBlock)(int, BOOL) = ^(int fd, BOOL isStderr) {
        fcntl(fd, F_SETFL, O_NONBLOCK);
        while (![drainCtx shouldForceCloseReaders]) {
            struct pollfd pfd = { fd, POLLIN, 0 };
            int ret = poll(&pfd, 1, 100);
            if (ret > 0) {
                if (pfd.revents & POLLIN) {
                    uint8_t buf[kShellReadChunkBytes];
                    ssize_t bytesRead = read(fd, buf, sizeof(buf));
                    if (bytesRead > 0) {
                        NSData *chunk = [NSData dataWithBytes:buf length:bytesRead];
                        [drainCtx appendChunk:chunk toStderr:isStderr];
                    } else if (bytesRead == 0) {
                        break;
                    }
                } else if (pfd.revents & (POLLHUP | POLLERR)) {
                    break;
                }
            } else if (ret < 0 && errno != EINTR) {
                break;
            }
        }
        close(fd);
    };

    int outFd = outPipe[0];
    int errFd = errPipe[0];
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(outFd, false); });
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(errFd, true); });

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:actualTimeout];
    BOOL timedOut = false;
    BOOL cancelled = false;

    while (true) {
        int status;
        pid_t wpid = waitpid(pid, &status, WNOHANG);
        if (wpid == pid) {
            if (WIFEXITED(status)) {
                result.exitCode = WEXITSTATUS(status);
            } else if (WIFSIGNALED(status)) {
                result.exitCode = -1;
                result.terminationSignal = WTERMSIG(status);
            }
            break;
        }

        if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
            timedOut = true;
            break;
        }
        if (context && context.cancellationToken && [context.cancellationToken isCancelled]) {
            cancelled = true;
            break;
        }
        usleep(20 * 1000);
    }

    if (timedOut || cancelled) {
        result.timedOut = timedOut;
        result.cancelled = cancelled;
        kill(-pid, SIGTERM);
        
        NSDate *graceDeadline = [NSDate dateWithTimeIntervalSinceNow:kShellTerminateGrace];
        while (true) {
            int status;
            pid_t wpid = waitpid(pid, &status, WNOHANG);
            if (wpid == pid) {
                if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
                else if (WIFSIGNALED(status)) { result.exitCode = -1; result.terminationSignal = WTERMSIG(status); }
                break;
            }
            if ([[NSDate date] compare:graceDeadline] != NSOrderedAscending) {
                kill(-pid, SIGKILL);
                break;
            }
            usleep(20 * 1000);
        }
        
        if (result.exitCode == -1 && result.terminationSignal == 0) {
            int status;
            waitpid(pid, &status, 0);
            if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
            else if (WIFSIGNALED(status)) { result.exitCode = -1; result.terminationSignal = WTERMSIG(status); }
        }

        NSDate *drainDeadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while (dispatch_group_wait(drainGroup, DISPATCH_TIME_NOW) != 0) {
            if ([[NSDate date] compare:drainDeadline] != NSOrderedAscending) {
                [drainCtx requestForceCloseReaders];
                result.drainForcedClosed = true;
                break;
            }
            usleep(20 * 1000);
        }
    }

    dispatch_group_wait(drainGroup, DISPATCH_TIME_FOREVER);

    NSString *outStr = [[NSString alloc] initWithData:drainCtx.outData encoding:NSUTF8StringEncoding];
    if (!outStr && drainCtx.outData.length > 0) outStr = [[NSString alloc] initWithData:drainCtx.outData encoding:NSASCIIStringEncoding];
    
    NSString *errStr = [[NSString alloc] initWithData:drainCtx.errData encoding:NSUTF8StringEncoding];
    if (!errStr && drainCtx.errData.length > 0) errStr = [[NSString alloc] initWithData:drainCtx.errData encoding:NSASCIIStringEncoding];

    result.stdoutStr = outStr ?: @"";
    result.stderrStr = errStr ?: @"";
    result.stdoutTruncated = drainCtx.outTruncated;
    result.stderrTruncated = drainCtx.errTruncated;

    return result;
}

void processTaskLegacy(UInt8 *buff, CFWriteStreamRef writeStreamRef)
{
    processTaskWithContext(buff, SIZE_MAX, writeStreamRef, nil);
}

void processTask(UInt8 *buff, CFWriteStreamRef writeStreamRef)
{
    processTaskLegacy(buff, writeStreamRef);
}

/**
Process Task
*/
void processTaskWithContext(UInt8 *buff, size_t actualLength, CFWriteStreamRef writeStreamRef, TLinkTaskExecutionContext *context)
{
    if (!buff) return;
    
    //NSLog(@"### com.tlinkauto.springboard: task type: %d. Data: %s", getTaskType(buff), buff);
    UInt8 *eventData = buff + 0x2;
    int taskType = getTaskType(buff);

    NSString *licenseDenial = nil;
    if (!TLinkRootfullLicenseTaskAllowed(taskType, &licenseDenial)) {
        if (taskType == TASK_PERFORM_TOUCH) {
            sTLinkSpringBoardLicenseTask10DropCount.fetch_add(1, std::memory_order_relaxed);
            return;
        }
        notifyClient((UInt8 *)[(licenseDenial ?: @"-1;;license_required\r\n") UTF8String],
                     writeStreamRef);
        return;
    }

    //for touching
    if (taskType == TASK_PERFORM_TOUCH)
    {
        @autoreleasepool{
            performTouchFromRawData(eventData);
        }
    }
    else if (taskType == TASK_PERFORM_TOUCH_ACK)
    {
        @autoreleasepool{
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            char *sep = strstr((char *)eventData, ";;");
            if (!sep) {
                notifyClient((UInt8*)"1;;touch_ack_bad_payload\r\n", writeStreamRef);
                return;
            }

            *sep = '\0';
            char *seq = (char *)eventData;
            UInt8 *touchData = (UInt8 *)(sep + 2);
            performTouchFromRawData(touchData);
            int dispatchUs = (int)((CFAbsoluteTimeGetCurrent() - start) * 1000000.0);
            NSString *response = [NSString stringWithFormat:@"0;;%s;;%d\r\n", seq, dispatchUs];
            notifyClient((UInt8*)[response UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_TAP)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeTap(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_SWIPE)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeSwipe(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_GESTURE)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeGesture(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_BATCH)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeBatch(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_PROCESS_BRING_FOREGROUND) //bring to foreground
    {
        @autoreleasepool{   
            switchProcessForegroundFromRawData(eventData);
            notifyClient((UInt8*)"0\r\n", writeStreamRef); 
        }
    }
    else if (taskType == TASK_SHOW_ALERT_BOX)
    {
        @autoreleasepool{   
            NSError *err = nil;
            showAlertBoxFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_USLEEP)
    {
        if (writeStreamRef)
        {
            int usleepTime = 0;
            @try{
                usleepTime = atoi((char*)eventData);
            }
            @catch (NSException *exception) {
                NSLog(@"com.tlinkauto.springboard: Debug: %@", exception.reason);
                return;
            }
            //NSLog(@"com.tlinkauto.springboard: sleep %d microseconds", usleepTime);
            usleep(usleepTime);
            notifyClient((UInt8*)"0;;Sleep ends\r\n", writeStreamRef); 
        }
        else
        {
            int usleepTime = 0;

            @try{
                usleepTime = atoi((char*)eventData);
            }
            @catch (NSException *exception) {
                NSLog(@"com.tlinkauto.springboard: Debug: %@", exception.reason);
                return;
            }
            //NSLog(@"com.tlinkauto.springboard: sleep %d microseconds", usleepTime);
            usleep(usleepTime);
        }

    }
    else if (taskType == TASK_RUN_SHELL)
    {
        @autoreleasepool{
            NSString *rawPayload = [NSString stringWithUTF8String:(const char *)eventData] ?: @"";
            double timeout = kShellDefaultTimeout;
            NSString *command = rawPayload;
            NSRange sepRange = [rawPayload rangeOfString:@";;"];
            if (sepRange.location != NSNotFound) {
                NSString *maybeTimeout = [rawPayload substringToIndex:sepRange.location];
                NSScanner *scanner = [NSScanner scannerWithString:maybeTimeout];
                double parsed = 0;
                if ([scanner scanDouble:&parsed] && [scanner isAtEnd] && parsed > 0) {
                    timeout = parsed;
                    command = [rawPayload substringFromIndex:sepRange.location + 2];
                }
            }
            
            TLinkShellResult *result = RunShellCore(command, context, timeout, SIZE_MAX);
            
            NSString *combined = result.stderrStr.length > 0 ? [result.stdoutStr stringByAppendingString:result.stderrStr] : result.stdoutStr;
            NSString *safeOutput = [[combined stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
            if (result.stdoutTruncated || result.stderrTruncated) {
                safeOutput = [safeOutput stringByAppendingFormat:@"\\n[output truncated: exceeded %lu bytes]", (unsigned long)kShellMaxCapturedOutputBytes];
            }
            
            if (result.timedOut) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command timed out after %.0fs: %@\r\n", timeout, safeOutput] UTF8String], writeStreamRef);
            } else if (result.cancelled) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command cancelled: %@\r\n", safeOutput] UTF8String], writeStreamRef);
            } else if (result.exitCode == 0) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", safeOutput] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command failed (%d): %@\r\n", result.exitCode, safeOutput] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_RUN_SHELL_V2)
    {
        @autoreleasepool{
            NSError *jsonErr = nil;
            NSData *payloadData = [NSData dataWithBytes:eventData length:actualLength - 2];
            NSDictionary *req = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&jsonErr];
            
            NSString *command = @"";
            double timeout = kShellDefaultTimeout;
            NSUInteger maxOutput = kTLinkautoJSMaxResponseBytes;
            
            if (!jsonErr && [req isKindOfClass:[NSDictionary class]]) {
                command = req[@"command"] ?: @"";
                if (req[@"timeoutSeconds"]) timeout = [req[@"timeoutSeconds"] doubleValue];
                if (req[@"maxOutputBytes"]) maxOutput = [req[@"maxOutputBytes"] unsignedIntegerValue];
            }
            
            TLinkShellResult *result = RunShellCore(command, context, timeout, maxOutput);
            
            NSMutableDictionary *resp = [NSMutableDictionary dictionary];
            resp[@"exitCode"] = result.exitCode == -1 ? [NSNull null] : @(result.exitCode);
            resp[@"terminationSignal"] = @(result.terminationSignal);
            resp[@"timedOut"] = @(result.timedOut);
            resp[@"cancelled"] = @(result.cancelled);
            resp[@"drainForcedClosed"] = @(result.drainForcedClosed);
            resp[@"stdout"] = result.stdoutStr;
            resp[@"stderr"] = result.stderrStr;
            resp[@"stdoutTruncated"] = @(result.stdoutTruncated);
            resp[@"stderrTruncated"] = @(result.stderrTruncated);
            
            NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            if (respData.length > kTLinkautoJSMaxResponseBytes) {
                resp[@"stdout"] = @"[Truncated due to JSON size limit]";
                resp[@"stderr"] = @"[Truncated due to JSON size limit]";
                resp[@"stdoutTruncated"] = @(true);
                resp[@"stderrTruncated"] = @(true);
                respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            }
            
            NSString *respJson = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", respJson] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_START)
    {
        @autoreleasepool {
            NSError *err = nil;
            startRecording(writeStreamRef, &err);    
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_STOP)
    {
        @autoreleasepool {
            stopRecording(); 
            notifyClient((UInt8*)"0\r\n", writeStreamRef); 
        }
    }
    else if (taskType == TASK_PLAY_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            playScript((UInt8*)eventData, &err);
            if (err)
            {
                setLastScriptError([err localizedDescription]);
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_PLAY_SCRIPT_FORCE_STOP)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopScriptPlaying(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEMPLATE_MATCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            CGRect result = screenMatchFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%.2f;;%.2f;;%.2f;;%.2f\r\n", 
                result.origin.x, result.origin.y, result.size.width, result.size.height] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_SHOW_TOAST)
    {
        @autoreleasepool {
            NSError *err = nil;
            showToastFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_PICKER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSDictionary *rgb = getRGBFromRawData(eventData, &err); 
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%d;;%d;;%d\r\n", [rgb[@"red"] intValue], [rgb[@"green"] intValue], [rgb[@"blue"] intValue]] UTF8String], writeStreamRef);
            }
            rgb = nil;
        }
    }
    else if (taskType == TASK_TEXT_INPUT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = inputTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_GET_DEVICE_INFO)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *deviceInfo = getDeviceInfoFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", deviceInfo] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_INDICATOR)
    {
        @autoreleasepool {
            NSError *err = nil;
            handleTouchIndicatorTaskWithRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEXT_RECOGNIZER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *text = performTextRecognizerTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", text] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_SEARCHER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *returndata = searchRGBFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", returndata] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_HARDWARE_KEY)
    {
        @autoreleasepool {
            NSError *err = nil;
            sendHardwareKeyEventFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_KILL)
    {
        @autoreleasepool {
            NSError *err = nil;
            killAppFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_STATE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = appStateFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_INFO)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *info = appInfoFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", info] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRONTMOST_APP_ID)
    {
        @autoreleasepool {
            NSString *frontApp = frontMostAppId();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", frontApp] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_FRONTMOST_APP_ORIENTATION)
    {
        @autoreleasepool {
            NSString *orientation = frontMostAppOrientation();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", orientation] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SET_AUTO_LAUNCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            setAutoLaunchFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_LIST_AUTO_LAUNCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *list = listAutoLaunch(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", list ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_SET_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            setTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_REMOVE_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            removeTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_KEEP_AWAKE)
    {
        @autoreleasepool {
            NSError *err = nil;
            keepAwakeFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = appPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRONTMOST_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = frontMostPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_PATHS)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *paths = appPathsFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", paths ?: @";;"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_LIST_BUNDLES)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = listBundlesFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_OPEN_URL)
    {
        @autoreleasepool {
            NSError *err = nil;
            (void)openUrlFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_WIFI)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = wifiTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_BLUETOOTH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = bluetoothTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_AIRPLANE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = airplaneTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_CELLULAR_DATA)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = cellularDataTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_VPN)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = vpnTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_HELLO_STATUS)
    {
        @autoreleasepool {
            UIDevice *dev = [UIDevice currentDevice];
            NSString *name = dev.name ?: @"";
            NSString *systemName = dev.systemName ?: @"iOS";
            NSString *systemVersion = dev.systemVersion ?: @"";
            NSString *model = dev.model ?: @"";

            BOOL playing = false;
            NSString *bundlePath = @"";
            if (scriptPlayer) {
                playing = [scriptPlayer isPlaying];
                bundlePath = [scriptPlayer getCurrentBundlePath] ?: @"";
            }
            NSString *licenseBuildMode =
                [NSString stringWithUTF8String:TLinkRootfullLicenseBuildMode()] ?: @"";
            NSMutableDictionary *licenseStatus =
                [TLinkLicenseStatusDictionary() mutableCopy];
            licenseStatus[@"phase"] = @6;
            licenseStatus[@"runtime"] = @"rootfull";
            licenseStatus[@"runtime_gate_active"] = @1;
            licenseStatus[@"activation_lifecycle_active"] = @1;
            licenseStatus[@"enforcement_scope"] = @"task_and_long_running_component_gate";
            licenseStatus[@"task_policy"] = @"rootfull_explicit_v1";
            licenseStatus[@"h264_gate_active"] = @1;
            licenseStatus[@"h264_heartbeat_interval_ms"] = @5000;
            licenseStatus[@"h264_client_active"] = @(TLinkH264LicenseHeartbeatActive());
            licenseStatus[@"h264_denied_accept_count"] =
                @(TLinkH264LicenseDeniedAcceptCount());
            licenseStatus[@"h264_revoked_client_count"] =
                @(TLinkH264LicenseRevokedClientCount());
            licenseStatus[@"script_heartbeat_active"] = @1;
            licenseStatus[@"scheduler_launch_gate_active"] = @1;
            licenseStatus[@"helper_runtime_gate_active"] = @1;
            licenseStatus[@"ui_feature_snapshot_active"] = @1;
            licenseStatus[@"release_integrity_active"] = @1;
            licenseStatus[@"anti_rollback_active"] = @1;
            licenseStatus[@"verifier_performance"] = TLinkLicensePerformanceDictionary();
            licenseStatus[@"task10_license_drop_count"] =
                @(sTLinkSpringBoardLicenseTask10DropCount.load(std::memory_order_relaxed));
            licenseStatus[@"rootfull_build_mode"] = licenseBuildMode;
            licenseStatus[@"verifier_build_mode"] = TLinkLicenseBuildMode() ?: @"";
            NSMutableDictionary *vpnStatus = [
                TLinkVPNDiagnosticsSnapshot(
                    @"rootfull",
                    @"full_control",
                    @"broker_localhost_6014",
                    @"broker_localhost_6014",
                    @"nevpnmanager_ikev2",
                    @"tlinkauto_vpnd_6014",
                    nil)
                mutableCopy];
            vpnStatus[@"phase"] = @4;
            vpnStatus[@"broker_target"] = @"tlinkauto_vpnd";
            vpnStatus[@"on_demand_policy"] =
                @"local_ui_connect_all_networks_explicit_disconnect_disables";
            vpnStatus[@"entitlement_probe_scope"] =
                @"springboard_process_fallback_use_task592_for_broker";

            NSDictionary *payload = @{
                @"tlinkauto": @{
                    @"protocols": @[@"v0", @"v1"],
                    @"port": @6000,
                    @"license_contract_version": @1,
                },
                @"device": @{
                    @"name": name,
                    @"system_name": systemName,
                    @"system_version": systemVersion,
                    @"model": model,
                },
                @"script": @{
                    @"is_playing": @(playing),
                    @"bundle_path": bundlePath,
                    @"last_error": getLastScriptError() ?: @"",
                    @"last_error_ts": @(getLastScriptErrorTs()),
                    @"license_runtime": scriptPlayer
                        ? [scriptPlayer licenseRuntimeDiagnostics]
                        : @{},
                    @"scheduler_license": TLinkSchedulerLicenseDiagnostics(),
                },
                @"run_history": TLinkRunHistorySnapshot(20),
                @"event_channel": TLinkEventChannelStatus(),
                @"adaptive_streaming": TLinkH264AdaptiveStreamingStatus(),
                @"zoom": @{
                    @"phase": @2,
                    @"state": @"experimental",
                    @"implemented": @1,
                    @"task": @64,
                    @"wire": @"task64_additive_zoom_v1",
                    @"finger_counts": @[@2, @3],
                    @"backend": @"legacy_multitouch_parent_frames",
                    @"geometry": @"radial_linear_interpolation_v1",
                    @"validation": @"preflight_bounds_v1",
                    @"cleanup": @"all_fingers_up_on_exception_v1",
                    @"device_validated": @0,
                    @"legacy_task64_unchanged": @1,
                    @"clients": @"task64_python_js_webtango_v1",
                    @"diagnostics": zx_zoomDiagnostics(),
                },
                @"smart_wait": @{
                    @"phase": @1,
                    @"state": @"implemented",
                    @"schema": @"smart_wait_result_v1",
                    @"api_version": @1,
                    @"clients": @"rootfull_js_trollstore_js_webtango_v1",
                    @"locators": @[@"predicate", @"app", @"color", @"image", @"text", @"image_gone", @"tap_when_visible"],
                    @"frame_strategy": @"fresh_frame_per_attempt_release_always_template_open_once",
                    @"timeout_max_ms": @300000,
                    @"interval_min_ms": @20,
                    @"stable_frames_max": @10,
                    @"device_validated": @0,
                },
                @"secure_pairing": @{
                    @"phase": @0,
                    @"state": @"contract_only",
                    @"contract_version": @1,
                    @"transport": @"zxsp_json_v1",
                    @"mode": @"observe_only",
                    @"legacy_policy": @"unchanged_p0",
                    @"crypto": @"p256_ecdh_ecdsa_hkdf_sha256_aes256_gcm",
                    @"device_validated": @0,
                },
                @"vpn": vpnStatus,
                @"license": licenseStatus,
            };

            NSError *jsonErr = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonErr];
            if (!jsonData || jsonErr) {
                notifyClient((UInt8*)"1;;Failed to encode hello status.\r\n", writeStreamRef);
                return;
            }
            NSString *b64 = [jsonData base64EncodedStringWithOptions:0];
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", b64 ?: @""] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SCREEN_KEEP)
    {
        @autoreleasepool {
            NSError *err = nil;
            handleScreenKeepTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_IMAGE_OBJECT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleImageObjectTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (ret && [ret length] > 0)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_CAPTURE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameCaptureTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_RELEASE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameReleaseTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FIND_IMAGE_IN_FRAME)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFindImageInFrameTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @"-1;;-1;;0;;0;;-1;;-1;;0;;0;;0;;0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_IN_FRAME)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleColorInFrameTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_BATCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameBatchTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_OCR_TESSERACT_REGION)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleTesseractOCRTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FIND_IMAGE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFindImageTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @"-1;;-1;;0;;0;;-1;;-1;;0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_STOP_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopScriptFromRawData(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_DIALOG)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *response = dialogFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", response ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_CLEAR_DIALOG)
    {
        @autoreleasepool {
            NSError *err = nil;
            clearDialogValues(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_ROOT_DIR)
    {
        @autoreleasepool {
            NSString *path = rootDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_CURRENT_DIR)
    {
        @autoreleasepool {
            NSString *path = currentDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_BOT_PATH)
    {
        @autoreleasepool {
            NSString *path = botPathValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SCREENSHOT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *resultPath = handleScreenshotTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (resultPath)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", resultPath] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_UPDATE_CACHE)
    {
        @autoreleasepool{
            NSError *err = nil;
            updateCacheFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[@"0\r\n" UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEST)
    {

    }
}
