#include "../shared/TLinkGestureTiming.h"
#include "../shared/TLinkC01Ingress.h"
#include "Task.h"
#import "../shared/TLinkAccessibilityTree.h"
#import "TLinkDiagnostic.h"
#include "../shared/TLinkRootfullLicenseBuild.h"
#include "../shared/TLinkLicenseVerifier.h"
#include "../shared/TLinkRootfullLicensePolicy.h"
#include "../shared/TLinkVPNDiagnostics.h"
#include "../shared/TLinkRunHistory.h"
#include "../shared/TLinkEventChannel.h"
#include "../shared/TLinkAdaptiveStreaming.h"
#include "../shared/TLinkJailbreakPath.h"
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
#include "../shared/TLinkRawPlayback.h"
#include "Process.h"
#include "AlertBox.h"
#include "Record.h"
#include "Play.h"
#include "SocketServer.h"
#include "ScreenMatch.h"
#include "Toast.h"
#include "ColorPicker.h"
#include "Image.h"
#include "../shared/TLinkNativeFrameCaptureResult.h"
#include "../shared/TLinkNativeImageResult.h"
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

extern ScriptPlayer *scriptPlayer;
static std::atomic<uint64_t> sTLinkSpringBoardLicenseTask10DropCount(0);
static std::atomic<uint64_t> sTLinkZoomAttemptCount(0);
static std::atomic<uint64_t> sTLinkZoomSuccessCount(0);
static std::atomic<uint64_t> sTLinkZoomValidationRejectedCount(0);
static std::atomic<uint64_t> sTLinkZoomDispatchExceptionCount(0);
static std::atomic<uint64_t> sTLinkZoomCleanupCount(0);
static std::atomic<uint64_t> sTLinkZoomCancelledCount(0);
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
    uint64_t completed = successes + validationRejected + dispatchExceptions + sTLinkZoomCancelledCount.load(std::memory_order_relaxed);
    int result = sTLinkZoomLastResult.load(std::memory_order_relaxed);
    int direction = sTLinkZoomLastDirection.load(std::memory_order_relaxed);
    return @{
        @"schema": @"zoom_runtime_diagnostics_v1",
        @"attempt_count": @(attempts),
        @"success_count": @(successes),
        @"validation_rejected_count": @(validationRejected),
        @"dispatch_exception_count": @(dispatchExceptions),
        @"cleanup_count": @(sTLinkZoomCleanupCount.load(std::memory_order_relaxed)),
        @"cancelled_count": @(sTLinkZoomCancelledCount.load(std::memory_order_relaxed)),
        @"frame_count": @(sTLinkZoomFrameCount.load(std::memory_order_relaxed)),
        @"in_flight": @(attempts > completed ? attempts - completed : 0),
        @"last_at_ms": @(sTLinkZoomLastAtMs.load(std::memory_order_relaxed)),
        @"last_result": result == 1 ? @"success" : (result == 2 ? @"validation_rejected" : (result == 3 ? @"dispatch_exception" : (result == 4 ? @"cancelled" : @"none"))),
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
    if (value >= 9999.9) return 99999;
    int fixed = (int)(value * 10.0f + 0.5f);
    if (fixed > 99999) fixed = 99999;
    return fixed;
}

// Internal numeric frames preserve legacy fixed-point rounding then integer-pixel
// truncation, without NSString formatting/UTF-8 conversion and wire reparsing.
static void zx_performSingleTouch(int type, int finger, CGFloat x, CGFloat y)
{
    const TLinkTouchPoint point = {type, finger, zx_clampTouchCoord(x) / 10, zx_clampTouchCoord(y) / 10};
    performTouchFrame(&point, 1);
}

static void zx_performTouchFrame(int type, int baseFinger, const CGPoint *points, int count)
{
    if (!points || count < 1 || count > kTLinkTouchMaxCount) return;
    TLinkTouchPoint frame[kTLinkTouchMaxCount];
    for (int i = 0; i < count; i++) {
        frame[i] = {type, baseFinger + i, zx_clampTouchCoord(points[i].x) / 10, zx_clampTouchCoord(points[i].y) / 10};
    }
    performTouchFrame(frame, count);
    sTLinkZoomFrameCount.fetch_add(1, std::memory_order_relaxed);
}

static NSArray<NSString *> *zx_splitTaskParts(UInt8 *eventData)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw) return @[];
    return [raw componentsSeparatedByString:@";;"];
}

static bool zx_nativeContinue(NSError **error)
{
    if (!TLinkNativeStopped()) return true;
    auto budget = TLinkCurrentNativeBudget();
    NSString *code = budget && budget->reason() == TLinkNativeStop::Deadline ? @"TimeoutError" : @"AbortError";
    if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"-1;;%@\r\n", code]}];
    return false;
}
static bool zx_nativeTouchArguments(CGFloat x, CGFloat y, int finger, int duration, NSError **error)
{
    if (isfinite(x) && isfinite(y) && finger >= 0 && finger < kTLinkTouchMaxFingerCount && duration >= 0 && duration <= 60000) return true;
    if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid native touch coordinates, finger or duration.\r\n"}];
    return false;
}
static bool zx_executeNativeTap(CGFloat x, CGFloat y, int durationMs, int finger, NSError **err)
{
    if (!zx_nativeTouchArguments(x, y, finger, durationMs, err) || !zx_nativeContinue(err)) return false;
    const TLinkGestureTimeline timeline(TLinkNativeNowNs(), uint64_t(durationMs) * 1000000);
    @try {
        zx_performSingleTouch(TOUCH_DOWN, finger, x, y);
        if (!timeline.wait(1, 1)) return zx_nativeContinue(err);
        return true;
    } @finally { zx_performSingleTouch(TOUCH_UP, finger, x, y); }
}
static bool zx_handleNativeTap(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 2) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native tap format: x;;y[;;duration_ms;;finger]\r\n"}];
        return false;
    }
    CGFloat x = [parts[0] floatValue], y = [parts[1] floatValue];
    int durationMs = parts.count >= 3 ? [parts[2] intValue] : 50;
    int finger = parts.count >= 4 ? [parts[3] intValue] : 0;
    return zx_executeNativeTap(x, y, durationMs, finger, err);
}

static bool zx_executeNativeSwipe(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, int durationMs, int finger, int steps, NSError **err)
{
    if (!zx_nativeTouchArguments(x1, y1, finger, durationMs, err) ||
        !zx_nativeTouchArguments(x2, y2, finger, durationMs, err) || !zx_nativeContinue(err)) return false;
    steps = MAX(2, MIN(steps, 120));
    CGFloat x = x1, y = y1;
    const TLinkGestureTimeline timeline(TLinkNativeNowNs(), uint64_t(durationMs) * 1000000);
    @try {
        zx_performSingleTouch(TOUCH_DOWN, finger, x, y);
        for (int i = 1; i < steps; ++i) {
            if (!timeline.wait(unsigned(i), unsigned(steps))) return zx_nativeContinue(err);
            CGFloat t = (CGFloat)i / steps;
            x = x1 + (x2 - x1) * t; y = y1 + (y2 - y1) * t;
            if (!zx_nativeContinue(err)) return false;
            zx_performSingleTouch(TOUCH_MOVE, finger, x, y);
        }
        if (!timeline.wait(unsigned(steps), unsigned(steps))) return zx_nativeContinue(err);
        x = x2; y = y2;
        return true;
    } @finally { zx_performSingleTouch(TOUCH_UP, finger, x, y); }
}
static bool zx_handleNativeSwipe(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 5) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native swipe format: x1;;y1;;x2;;y2;;duration_ms[;;finger;;steps]\r\n"}];
        return false;
    }
    CGFloat x1 = [parts[0] floatValue], y1 = [parts[1] floatValue];
    CGFloat x2 = [parts[2] floatValue], y2 = [parts[3] floatValue];
    int durationMs = [parts[4] intValue];
    int finger = parts.count >= 6 ? [parts[5] intValue] : 0;
    int steps = parts.count >= 7 ? [parts[6] intValue] : durationMs / 16;
    return zx_executeNativeSwipe(x1, y1, x2, y2, durationMs, finger, steps, err);
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

static void zx_zoomBegin()
{
    sTLinkZoomAttemptCount.fetch_add(1, std::memory_order_relaxed);
    sTLinkZoomLastAtMs.store(zx_zoomNowMs(), std::memory_order_relaxed);
    sTLinkZoomLastResult.store(0, std::memory_order_relaxed);
    sTLinkZoomLastDirection.store(0, std::memory_order_relaxed);
    sTLinkZoomLastFingerCount.store(0, std::memory_order_relaxed);
    sTLinkZoomLastSteps.store(0, std::memory_order_relaxed);
    sTLinkZoomLastDurationMs.store(0, std::memory_order_relaxed);
}
static bool zx_executeNativeZoom(const TLinkNativeTouchRequest &request,NSError **err)
{
    const double centerX=request.x1,centerY=request.y1,startRadius=request.startRadius,endRadius=request.endRadius,angleDegrees=request.angleDegrees;
    const int durationMs=request.durationMs,fingerCount=request.fingerCount,steps=request.steps,baseFinger=request.finger;
    if(!isfinite(centerX))return zx_zoomError(err,@"zoom_invalid_number field=center_x");
    if(!isfinite(centerY))return zx_zoomError(err,@"zoom_invalid_number field=center_y");
    if(!isfinite(startRadius))return zx_zoomError(err,@"zoom_invalid_number field=start_radius");
    if(!isfinite(endRadius))return zx_zoomError(err,@"zoom_invalid_number field=end_radius");
    if(!isfinite(angleDegrees))return zx_zoomError(err,@"zoom_invalid_number field=angle_degrees");
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
    if (baseFinger < 0 || baseFinger > 20 - fingerCount) return zx_zoomError(err, @"zoom_finger_range_invalid allowed=0..19");

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
    const TLinkGestureTimeline timeline(TLinkNativeNowNs(), uint64_t(durationMs) * 1000000);
    @try {
        zx_zoomPoints(points, fingerCount, centerX, centerY, startRadius, angleDegrees);
        if (!zx_nativeContinue(err)) { sTLinkZoomCancelledCount.fetch_add(1); sTLinkZoomLastResult.store(4); return false; }
        zx_performTouchFrame(TOUCH_DOWN, baseFinger, points, fingerCount);
        fingersDown = true;

        for (int step = 1; step < steps; step++) {
            if (!timeline.wait(unsigned(step), unsigned(steps - 1))) { sTLinkZoomCancelledCount.fetch_add(1); sTLinkZoomLastResult.store(4); return zx_nativeContinue(err); }
            double t = (double)step / (double)(steps - 1);
            double radius = startRadius + (endRadius - startRadius) * t;
            zx_zoomPoints(points, fingerCount, centerX, centerY, radius, angleDegrees);
            zx_performTouchFrame(TOUCH_MOVE, baseFinger, points, fingerCount);
            if (!zx_nativeContinue(err)) { sTLinkZoomCancelledCount.fetch_add(1); sTLinkZoomLastResult.store(4); return false; }
        }
        zx_performTouchFrame(TOUCH_UP, baseFinger, points, fingerCount);
        fingersDown = false;
    } @catch (__unused NSException *exception) {
        if (fingersDown) {
            sTLinkZoomCleanupCount.fetch_add(1, std::memory_order_relaxed);
            zx_performTouchFrame(TOUCH_UP, baseFinger, points, fingerCount);
            fingersDown = false;
        }
        return zx_zoomError(err, @"zoom_dispatch_exception");
    } @finally {
        if (fingersDown) {
            sTLinkZoomCleanupCount.fetch_add(1, std::memory_order_relaxed);
            zx_performTouchFrame(TOUCH_UP, baseFinger, points, fingerCount);
        }
    }
    sTLinkZoomSuccessCount.fetch_add(1, std::memory_order_relaxed);
    sTLinkZoomLastResult.store(1, std::memory_order_relaxed);
    return true;
}

static bool zx_handleNativeZoom(NSArray<NSString *> *parts, NSError **err)
{
    zx_zoomBegin();
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

    TLinkNativeTouchRequest request;request.kind=TLinkNativeTouchKind::Zoom;
    request.x1=centerX;request.y1=centerY;request.startRadius=startRadius;request.endRadius=endRadius;
    request.durationMs=durationMs;request.fingerCount=fingerCount;request.steps=steps;request.angleDegrees=angleDegrees;request.finger=baseFinger;
    return zx_executeNativeZoom(request,err);
}

static bool zx_executeNativeGesture(const std::vector<TLinkNativeGesturePoint> &points,int durationMs,int finger,NSError **err)
{
    if (points.size() < 2) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native gesture requires at least two points.\r\n"}];
        return false;
    }
    if (!zx_nativeContinue(err)) return false;
    if (points.size() > 512) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Gesture requires at most 512 points.\r\n"}];
        return false;
    }
    for(const auto &point:points)if(!zx_nativeTouchArguments(point.x,point.y,finger,durationMs,err))return false;
    CGFloat x=points[0].x,y=points[0].y;
    const TLinkGestureTimeline timeline(TLinkNativeNowNs(), uint64_t(durationMs) * 1000000);
    @try {
        zx_performSingleTouch(TOUCH_DOWN, finger, x, y);
        for(size_t i=1;i<points.size();++i){
            if(!timeline.wait(unsigned(i),unsigned(points.size()-1)))return zx_nativeContinue(err);
            x=points[i].x;y=points[i].y;
            zx_performSingleTouch(TOUCH_MOVE,finger,x,y);
            if(!zx_nativeContinue(err))return false;
        }
        return true;
    } @finally { zx_performSingleTouch(TOUCH_UP, finger, x, y); }
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
    if (!zx_nativeContinue(err)) return false;
    if (pointTexts.count > 512) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Gesture requires at most 512 points.\r\n"}];
        return false;
    }
    std::vector<TLinkNativeGesturePoint> points;points.reserve(pointTexts.count);
    CGFloat x = 0, y = 0;
    for (NSString *text in pointTexts) {
        if (!zx_parseGesturePoint(text, &x, &y)) {
            if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid gesture point.\r\n"}];
            return false;
        }
        if (!zx_nativeTouchArguments(x, y, finger, durationMs, err)) return false;
        points.push_back({x,y});
    }
    return zx_executeNativeGesture(points,durationMs,finger,err);
}

static bool zx_handleNativeBatch(UInt8 *eventData, NSError **err)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw || raw.length == 0) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native batch format: command||command, command starts with 10/62/63/64.\r\n"}];
        return false;
    }

    NSArray<NSString *> *commands = [raw componentsSeparatedByString:@"||"];
    TLinkRawTouches ownedTouches;
    bool completed = false;
    @try {
    for (NSString *cmd in commands) {
        if (!zx_nativeContinue(err)) return false;
        if (cmd.length < 2) continue;
        int task = [[cmd substringToIndex:2] intValue];
        NSString *payload = [cmd substringFromIndex:2];
        UInt8 *payloadBytes = (UInt8 *)[payload UTF8String];
        if (task == TASK_PERFORM_TOUCH) {
            if (!performTouchFromRawData(payloadBytes, [payload lengthOfBytesUsingEncoding:NSUTF8StringEncoding])) {
                if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"1;;touch_bad_payload\r\n"}];
                return false;
            }
            ownedTouches.observe(payloadBytes, [payload lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
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
    if (!zx_nativeContinue(err)) return false;
    completed = true;
    return true;
    } @finally {
        if (!completed) ownedTouches.release([](const uint8_t *bytes, size_t length) { return performTouchFromRawData(bytes, length); });
    }
}

// BEGIN typed touch task entry.
static NSDictionary *zx_typedTouchFailure(NSString *code)
{
    return @{@"ok":@(false),@"raw":[NSString stringWithFormat:@"1;;%@\r\n",code],@"parts":@[@"1",code]};
}
static NSDictionary *zx_typedTouchStopped(const TLinkNativeBudgetPtr &budget)
{
    switch(budget->reason()) {
        case TLinkNativeStop::Cancelled:return zx_typedTouchFailure(@"AbortError");
        case TLinkNativeStop::Deadline:return zx_typedTouchFailure(@"TimeoutError");
        case TLinkNativeStop::OutputLimit:return zx_typedTouchFailure(@"response_too_large");
        default:return zx_typedTouchFailure(@"native_failed");
    }
}
static NSDictionary *zx_typedTouchReply(NSString *raw,const TLinkNativeBudgetPtr &budget)
{
    if(!budget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||budget->stopped())return zx_typedTouchStopped(budget);
    if([raw isEqualToString:@"0\r\n"])return @{@"ok":@(true),@"raw":@"0\r\n",@"parts":@[@"0"]};
    // Compatibility fields are parsed only on the error/denial path.
    NSArray *parts=[[raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"];
    return @{@"ok":@(false),@"raw":raw,@"parts":parts};
}
NSDictionary *TLinkExecuteNativeTouch(const TLinkNativeTouchRequest &request,TLinkTaskExecutionContext *context)
{
    const int taskType=TLinkNativeTouchTask(request.kind);
    if(!taskType)return zx_typedTouchFailure(@"invalid_touch_request");
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try {
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(taskType,&denial))
            return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        // License refresh may wait for IPC; recheck before committing an action.
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSError *error=nil;
        if(request.kind==TLinkNativeTouchKind::Tap)
            zx_executeNativeTap(request.x1,request.y1,request.durationMs,request.finger,&error);
        else if(request.kind==TLinkNativeTouchKind::Swipe)zx_executeNativeSwipe(request.x1,request.y1,request.x2,request.y2,request.durationMs,request.finger,
            request.steps?request.steps:request.durationMs/16,&error);
        else if(request.kind==TLinkNativeTouchKind::Gesture)zx_executeNativeGesture(request.points,request.durationMs,request.finger,&error);
        else {zx_zoomBegin();zx_executeNativeZoom(request,&error);}
        return zx_typedTouchReply(error.localizedDescription?:@"0\r\n",budget);
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
NSDictionary *TLinkExecuteNativeTouchBatch(const std::vector<TLinkNativeTouchRequest> &requests,TLinkTaskExecutionContext *context)
{
    if(requests.size()>256)return zx_typedTouchFailure(@"invalid_touch_request");
    for(const auto &request:requests)if(request.kind!=TLinkNativeTouchKind::Tap&&request.kind!=TLinkNativeTouchKind::Swipe&&
        request.kind!=TLinkNativeTouchKind::Gesture)return zx_typedTouchFailure(@"invalid_touch_request");
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try {
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *denial=nil;
        // Task 65 owns the authorization boundary; individual batch commands
        // execute in order under this one budget, with no retry after effects.
        if(!TLinkRootfullLicenseTaskAllowed(TASK_NATIVE_BATCH,&denial))
            return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        if(requests.empty())return zx_typedTouchReply(@"-1;;Native batch format: command||command, command starts with 10/62/63/64.\r\n",budget);
        NSError *error=nil;
        for(const auto &request:requests) {
            if(!zx_nativeContinue(&error))break;
            bool ok=false;
            if(request.kind==TLinkNativeTouchKind::Tap)
                ok=zx_executeNativeTap(request.x1,request.y1,request.durationMs,request.finger,&error);
            else if(request.kind==TLinkNativeTouchKind::Swipe)
                ok=zx_executeNativeSwipe(request.x1,request.y1,request.x2,request.y2,request.durationMs,request.finger,
                    request.steps?request.steps:request.durationMs/16,&error);
            else ok=zx_executeNativeGesture(request.points,request.durationMs,request.finger,&error);
            // Each executor releases its owned DOWN in finally, including throws.
            if(!ok)return zx_typedTouchReply(error.localizedDescription?:@"1;;native_failed\r\n",budget);
        }
        if(!error)zx_nativeContinue(&error);
        return zx_typedTouchReply(error.localizedDescription?:@"0\r\n",budget);
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed touch task entry.

// BEGIN typed frontmost task entry.
// Shared scalar reply formatting for frontmost and path queries.
static NSDictionary *zx_nativeStringQueryResult(NSString *value,NSString *key,bool numeric,NSString *alias,const TLinkNativeBudgetPtr &budget)
{
    NSString *body=[value copy]?:@"(null)";
    NSString *raw=[NSString stringWithFormat:@"0;;%@\r\n",body];
    const char *wire=raw.UTF8String;
    size_t length=0;
    // Match notifyClient's NUL boundary, admitting the complete response chunk.
    while(wire&&length<=budget->outputLimit()&&wire[length])++length;
    if(!budget->outputAllowed(length))return zx_typedTouchStopped(budget);
    NSCharacterSet *newlines=[NSCharacterSet newlineCharacterSet];
    const bool compatibility=!wire||![body canBeConvertedToEncoding:NSUTF8StringEncoding]||length<[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding]||
        [body rangeOfString:@";;"].location!=NSNotFound||
        (body.length&&[newlines characterIsMember:[body characterAtIndex:body.length-1]]);
    NSArray *parts=nil;
    if(compatibility){
        // Unusual backend strings retain the old C-string/trim/split behavior.
        raw=wire?[[NSString alloc] initWithBytes:wire length:length encoding:NSUTF8StringEncoding]:@"0\r\n";
        if(!raw)return zx_typedTouchFailure(@"invalid_response_encoding");
        parts=[[raw stringByTrimmingCharactersInSet:newlines] componentsSeparatedByString:@";;"];
    }else parts=@[@"0",body];
    NSMutableDictionary *result=[@{@"ok":@(true),@"raw":raw,@"parts":parts} mutableCopy];
    if(parts.count>1){
        result[key]=numeric?@([parts[1] intValue]):parts[1];
        if(alias)result[alias]=parts[1];
    }
    return result;
}
static NSDictionary *zx_nativeFrontmostExecute(int taskType,TLinkTaskExecutionContext *context)
{
    static_assert(TASK_FRONTMOST_APP_ID==34&&TASK_FRONTMOST_APP_ORIENTATION==35,"frontmost task classification changed");
    if(taskType!=TASK_FRONTMOST_APP_ID&&taskType!=TASK_FRONTMOST_APP_ORIENTATION)return zx_typedTouchFailure(@"invalid_payload");
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try{
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(taskType,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *value=taskType==TASK_FRONTMOST_APP_ID?frontMostAppId():frontMostAppOrientation();
        if(budget->stopped())return zx_typedTouchStopped(budget);
        const bool orientation=taskType==TASK_FRONTMOST_APP_ORIENTATION;
        NSDictionary *result=zx_nativeStringQueryResult(value,orientation?@"value":@"bundleId",orientation,nil,budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        return result;
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
NSDictionary *TLinkExecuteNativeFrontmost(int taskType,TLinkTaskExecutionContext *context)
{
    // Keep the result strongly owned outside the per-query temporary pool.
    NSDictionary *result=nil;
    @autoreleasepool{result=zx_nativeFrontmostExecute(taskType,context);}
    return result;
}
// END typed frontmost task entry.

// BEGIN typed frontmost PID task entry.
static NSDictionary *zx_nativeFrontmostPidExecute(TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try{
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_FRONTMOST_PID,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *value=frontMostPidValue()?:@"0";
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSDictionary *result=zx_nativeStringQueryResult(value,@"pid",true,nil,budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        return result;
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
NSDictionary *TLinkExecuteNativeFrontmostPid(TLinkTaskExecutionContext *context)
{
    NSDictionary *result=nil;
    @autoreleasepool{result=zx_nativeFrontmostPidExecute(context);}
    return result;
}
// END typed frontmost PID task entry.

// BEGIN typed path task entry.
static NSDictionary *zx_nativePathExecute(int taskType,TLinkTaskExecutionContext *context)
{
    static_assert(TASK_ROOT_DIR==44&&TASK_CURRENT_DIR==45&&TASK_BOT_PATH==46,"path task classification changed");
    if(taskType!=TASK_ROOT_DIR&&taskType!=TASK_CURRENT_DIR&&taskType!=TASK_BOT_PATH)return zx_typedTouchFailure(@"invalid_payload");
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try{
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(taskType,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *value=taskType==TASK_ROOT_DIR?rootDirValue():(taskType==TASK_CURRENT_DIR?currentDirValue():botPathValue());
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *key=taskType==TASK_ROOT_DIR?@"rootDir":(taskType==TASK_CURRENT_DIR?@"currentDir":@"botPath");
        NSDictionary *result=zx_nativeStringQueryResult(value,key,false,@"path",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        return result;
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
NSDictionary *TLinkExecuteNativePath(int taskType,TLinkTaskExecutionContext *context)
{
    NSDictionary *result=nil;
    @autoreleasepool{result=zx_nativePathExecute(taskType,context);}
    return result;
}
// END typed path task entry.

// BEGIN typed hardware key task entry.
static NSDictionary *zx_nativeHardwareKeyExecute(int action,int keyType,TLinkTaskExecutionContext *context)
{
    if(action<0||keyType<=0)return zx_typedTouchFailure(@"invalid_payload");
    // Only canonical action zero is an exempt release, matching the RAW 0;; prefix.
    const bool cleanup=action==HARDWARE_KEY_ACTION_UP;
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,cleanup,false);
    auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try{
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *denial=nil;
        if(!cleanup&&!TLinkRootfullLicenseTaskAllowed(TASK_HARDWARE_KEY,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSError *error=nil;sendHardwareKeyEvent(action,keyType,&error);
        return zx_typedTouchReply(error.localizedDescription?:@"0\r\n",budget);
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
NSDictionary *TLinkExecuteNativeHardwareKey(int action,int keyType,TLinkTaskExecutionContext *context)
{
    NSDictionary *result=nil;
    @autoreleasepool{result=zx_nativeHardwareKeyExecute(action,keyType,context);}
    return result;
}
// END typed hardware key task entry.

// BEGIN typed keep awake task entry.
static NSDictionary *zx_nativeKeepAwakeExecute(BOOL enabled,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try{
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_KEEP_AWAKE,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        TLinkSetKeepAwakeEnabled(enabled);
        return zx_typedTouchReply(@"0\r\n",budget);
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
NSDictionary *TLinkExecuteNativeKeepAwake(BOOL enabled,TLinkTaskExecutionContext *context)
{
    NSDictionary *result=nil;
    @autoreleasepool{result=zx_nativeKeepAwakeExecute(enabled,context);}
    return result;
}
// END typed keep awake task entry.

// BEGIN typed indicator task entry.
static NSDictionary *zx_nativeIndicatorExecute(int action,TLinkTaskExecutionContext *context)
{
    if(action<0)return zx_typedTouchFailure(@"invalid_payload");
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try{
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_TOUCH_INDICATOR,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSError *error=nil;handleTouchIndicatorAction(action,&error);
        return zx_typedTouchReply(error.localizedDescription?:@"0\r\n",budget);
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
NSDictionary *TLinkExecuteNativeIndicator(int action,TLinkTaskExecutionContext *context)
{
    NSDictionary *result=nil;
    @autoreleasepool{result=zx_nativeIndicatorExecute(action,context);}
    return result;
}
// END typed indicator task entry.

// BEGIN typed color task entry.
NSDictionary *TLinkExecuteNativeColorPick(const TLinkNativeColorPickRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    // Match the RAW entry's task-local deadline, including license latency.
    static_assert(TASK_COLOR_PICKER==23,"color task classification changed");
    const uint8_t task[]={'2','3'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_PICKER,&denial))
            return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;NSDictionary *rgb=getRGBAtPosition(request.x,request.y,&error);
        if(error)return zx_typedTouchReply(error.localizedDescription,replyBudget);
        // Keep compatibility text/parts, but never parse a successful RGB reply.
        int red=[rgb[@"red"] intValue],green=[rgb[@"green"] intValue],blue=[rgb[@"blue"] intValue];
        NSString *r=[NSString stringWithFormat:@"%d",red],*g=[NSString stringWithFormat:@"%d",green],*b=[NSString stringWithFormat:@"%d",blue];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@;;%@\r\n",r,g,b];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",r,g,b],@"red":@(red),@"green":@(green),@"blue":@(blue)};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed color task entry.

// BEGIN typed color range task entry.
NSDictionary *TLinkExecuteNativeColorRange(const TLinkNativeColorRangeRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_COLOR_SEARCHER==28,"color search task classification changed");const uint8_t task[]={'2','8'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_SEARCHER,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkColorResult value;
        if(!searchRGBRange(request,value,&error))return zx_typedTouchReply(error.localizedDescription?:@"-1;;color_operation_failed\r\n",replyBudget);
        NSString *x=[NSString stringWithFormat:@"%d",value.x],*y=[NSString stringWithFormat:@"%d",value.y];
        NSString *r=[NSString stringWithFormat:@"%d",value.r],*g=[NSString stringWithFormat:@"%d",value.g],*b=[NSString stringWithFormat:@"%d",value.b];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@;;%@;;%@;;%@\r\n",x,y,r,g,b];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",x,y,r,g,b],@"matched":@(value.x>=0&&value.y>=0),@"x":@(value.x),@"y":@(value.y),@"red":@(value.r),@"green":@(value.g),@"blue":@(value.b)};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed color range task entry.

// BEGIN typed color multi task entry.
NSDictionary *TLinkExecuteNativeColorMulti(const TLinkNativeColorMultiRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_COLOR_SEARCHER==28,"color search task classification changed");const uint8_t task[]={'2','8'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_SEARCHER,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkColorResult value;
        if(!searchRGBMulti(request,value,&error))return zx_typedTouchReply(error.localizedDescription?:@"-1;;color_operation_failed\r\n",replyBudget);
        NSString *x=[NSString stringWithFormat:@"%d",value.x],*y=[NSString stringWithFormat:@"%d",value.y];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@\r\n",x,y];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",x,y],@"matched":@(value.x>=0&&value.y>=0),@"x":@(value.x),@"y":@(value.y)};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed color multi task entry.

// BEGIN typed color points task entry.
NSDictionary *TLinkExecuteNativeColorPoints(const TLinkNativeColorPointsRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_COLOR_SEARCHER==28,"color search task classification changed");const uint8_t task[]={'2','8'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_SEARCHER,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;bool matched=false;
        if(!testRGBPoints(request,matched,&error))return zx_typedTouchReply(error.localizedDescription?:@"-1;;color_operation_failed\r\n",replyBudget);
        NSString *flag=matched?@"1":@"0",*raw=[NSString stringWithFormat:@"0;;%@\r\n",flag];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",flag],@"matched":@(matched),@"value":@(matched)};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed color points task entry.

// BEGIN typed image capture task entry.
NSDictionary *TLinkExecuteNativeImageCapture(const TLinkNativeImageCaptureRequest &request,TLinkTaskExecutionContext *context){
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    uint32_t publishedId=0;bool committed=false;
    @try {try {
        if(budget->stopped())return zx_typedTouchStopped(budget);
        if(budget->outputLimit()<1024)return zx_typedTouchFailure(@"response_too_large");
        NSString *denial=nil;if(!TLinkRootfullLicenseTaskAllowed(TASK_IMAGE_OBJECT,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSError *error=nil;TLinkNativeImageValue value;
        if(!captureStoredImage(request,publishedId,value,&error))return error?zx_typedTouchReply(error.localizedDescription,budget):zx_typedTouchFailure(@"image_capture_failed");
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSDictionary *result=TLinkNativeImageResult(value);NSString *raw=result[@"raw"];
        if(!budget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||budget->stopped())return zx_typedTouchStopped(budget);
        committed=true;return result;
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}@catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
    @finally {
        if(!committed&&publishedId){
            TLinkTaskExecutionContext *cleanup=TLinkNativeCallContext(call,true,false);TLinkNativeBudgetScope cleanupScope([cleanup nativeBudget]);
            TLinkNativeImageReleaseRequest rollback;rollback.imageId=publishedId;
            @try{try{releaseStoredImages(rollback);}catch(...){}}@catch(__unused NSException *exception){}
        }
    }
}
// END typed image capture task entry.

// BEGIN typed image open task entry.
NSDictionary *TLinkExecuteNativeImageOpen(const TLinkNativeImageOpenRequest &request,TLinkTaskExecutionContext *context){
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    uint32_t publishedId=0;bool committed=false;
    @try {try {
        if(budget->stopped())return zx_typedTouchStopped(budget);
        if(budget->outputLimit()<1024)return zx_typedTouchFailure(@"response_too_large");
        NSString *denial=nil;if(!TLinkRootfullLicenseTaskAllowed(TASK_IMAGE_OBJECT,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSError *error=nil;TLinkNativeImageValue value;
        if(!openStoredImage(request,publishedId,value,&error))return error?zx_typedTouchReply(error.localizedDescription,budget):zx_typedTouchFailure(@"image_open_failed");
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSDictionary *result=TLinkNativeImageResult(value);NSString *raw=result[@"raw"];
        if(!budget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||budget->stopped())return zx_typedTouchStopped(budget);
        committed=true;return result;
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}@catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
    @finally {
        if(!committed&&publishedId){
            TLinkTaskExecutionContext *cleanup=TLinkNativeCallContext(call,true,false);TLinkNativeBudgetScope cleanupScope([cleanup nativeBudget]);
            TLinkNativeImageReleaseRequest rollback;rollback.imageId=publishedId;
            @try{try{releaseStoredImages(rollback);}catch(...){}}@catch(__unused NSException *exception){}
        }
    }
}
// END typed image open task entry.

// BEGIN typed frame capture task entry.
NSDictionary *TLinkExecuteNativeFrameCapture(const TLinkNativeFrameCaptureRequest &request,TLinkTaskExecutionContext *context){
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    uint32_t publishedId=0;bool committed=false;
    @try {try {
        if(budget->stopped())return zx_typedTouchStopped(budget);
        if(budget->outputLimit()<1024)return zx_typedTouchFailure(@"response_too_large");
        NSString *denial=nil;if(!TLinkRootfullLicenseTaskAllowed(TASK_FRAME_CAPTURE,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",budget);
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSError *error=nil;TLinkNativeFrameCaptureValue value;
        if(!captureStoredFrame(request,publishedId,value,&error))return error?zx_typedTouchReply(error.localizedDescription,budget):zx_typedTouchFailure(@"capture_failed");
        if(budget->stopped())return zx_typedTouchStopped(budget);
        NSDictionary *result=TLinkNativeFrameCaptureResult(value);NSString *raw=result[@"raw"];
        if(!budget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||budget->stopped())return zx_typedTouchStopped(budget);
        committed=true;return result;
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}@catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
    @finally {
        if(!committed&&publishedId){
            TLinkTaskExecutionContext *cleanup=TLinkNativeCallContext(call,true,false);TLinkNativeBudgetScope cleanupScope([cleanup nativeBudget]);
            TLinkNativeFrameReleaseRequest rollback;rollback.frameId=publishedId;
            @try{try{releaseStoredFrames(rollback);}catch(...){}}@catch(__unused NSException *exception){}
        }
    }
}
// END typed frame capture task entry.

// BEGIN typed image release task entry.
NSDictionary *TLinkExecuteNativeImageRelease(const TLinkNativeImageReleaseRequest &request,TLinkTaskExecutionContext *context){
    // Match task 48/action 3's cleanup exemption; capture/open retain their ordinary gates.
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,true,false);auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try {
        const size_t removed=releaseStoredImages(request);
        NSString *count=[NSString stringWithFormat:@"%lu",(unsigned long)removed],*raw=[NSString stringWithFormat:@"0;;%@\r\n",count];
        if(!budget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||budget->stopped())return zx_typedTouchStopped(budget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",count]};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}@catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed image release task entry.

// BEGIN typed frame release task entry.
NSDictionary *TLinkExecuteNativeFrameRelease(const TLinkNativeFrameReleaseRequest &request,TLinkTaskExecutionContext *context){
    // Match task 67's existing cleanup admission: no license/stop gate can strand owned frames.
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,true,false);auto budget=[call nativeBudget];TLinkNativeBudgetScope scope(budget);
    @try {try {
        const size_t removed=releaseStoredFrames(request);
        NSString *count=[NSString stringWithFormat:@"%lu",(unsigned long)removed],*raw=[NSString stringWithFormat:@"0;;%@\r\n",count];
        if(!budget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||budget->stopped())return zx_typedTouchStopped(budget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",count]};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}@catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed frame release task entry.

// BEGIN typed frame OCR task entry.
static NSDictionary *zx_typedFrameOCRReply(NSString *raw,const TLinkNativeBudgetPtr &budget){
    if(!budget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||budget->stopped())return zx_typedTouchStopped(budget);
    NSArray *parts=[[raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"];
    NSString *status=parts.count?parts[0]:@"1";
    return @{@"ok":@([status isEqualToString:@"0"]),@"raw":raw,@"parts":parts};
}
NSDictionary *TLinkExecuteNativeFrameOCR(const TLinkNativeFrameOCRRequest &request,TLinkTaskExecutionContext *context){
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_OCR_TESSERACT_REGION==91,"frame OCR task classification changed");const uint8_t task[]={'9','1'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;if(!TLinkRootfullLicenseTaskAllowed(TASK_OCR_TESSERACT_REGION,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkNativeFrameOCRValue value;
        if(!recognizeFrameWithTesseract(request,value,&error))return zx_typedFrameOCRReply(error.localizedDescription?:@"0;;\r\n",replyBudget);
        NSString *raw=[NSString stringWithFormat:@"0;;%@\r\n",value.body];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        NSArray *c=value.columns;
        return @{@"ok":@(true),@"raw":raw,@"parts":[@[@"0"] arrayByAddingObjectsFromArray:c],@"text":value.text,
            @"confidence":@([c[1] doubleValue]),@"ageMs":@([c[2] longLongValue]),@"ocrMs":@([c[3] doubleValue]),
            @"preprocessMs":@([c[4] doubleValue]),@"totalMs":@([c[5] doubleValue])};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}@catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed frame OCR task entry.

// BEGIN typed frame image task entry.
NSDictionary *TLinkExecuteNativeFrameImage(const TLinkNativeFrameImageRequest &request,TLinkTaskExecutionContext *context){
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_FIND_IMAGE_IN_FRAME==68,"frame image task classification changed");const uint8_t task[]={'6','8'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;if(!TLinkRootfullLicenseTaskAllowed(TASK_FIND_IMAGE_IN_FRAME,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkNativeFrameImageValue value;if(!matchImageInFrame(request,value,&error))return zx_typedTouchReply(error.localizedDescription?:@"-1;;image_error\r\n",replyBudget);
        const bool matched=value.x>=0&&value.y>=0;
        NSString *x=[NSString stringWithFormat:@"%d",value.x],*y=[NSString stringWithFormat:@"%d",value.y],*w=[NSString stringWithFormat:@"%d",value.width],*h=[NSString stringWithFormat:@"%d",value.height];
        NSString *cx=matched?[NSString stringWithFormat:@"%.2f",value.centerX]:@"-1",*cy=matched?[NSString stringWithFormat:@"%.2f",value.centerY]:@"-1";
        NSString *score=[NSString stringWithFormat:@"%.4f",value.score],*age=[NSString stringWithFormat:@"%llu",(unsigned long long)value.ageMs],*ms=[NSString stringWithFormat:@"%.3f",value.totalMs];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@;;%@;;%@;;%@;;%@;;%@;;%@;;%@;;%@\r\n",x,y,w,h,cx,cy,score,age,ms,ms];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",x,y,w,h,cx,cy,score,age,ms,ms],@"matched":@(matched),@"x":@(value.x),@"y":@(value.y),@"width":@(value.width),@"height":@(value.height),@"centerX":@([cx doubleValue]),@"centerY":@([cy doubleValue]),@"score":@([score doubleValue]),@"ageMs":@(value.ageMs),@"totalMs":@([ms doubleValue])};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}@catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed frame image task entry.

// BEGIN typed frame pick task entry.
NSDictionary *TLinkExecuteNativeFramePick(const TLinkNativeFramePickRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_COLOR_IN_FRAME==69,"frame color task classification changed");
    const uint8_t task[]={'6','9'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_IN_FRAME,&denial))
            return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkNativeFramePickValue value;
        if(!readFramePixel(request,value,&error))return zx_typedTouchReply(error.localizedDescription?:@"1;;frame_error\r\n",replyBudget);
        NSString *r=[NSString stringWithFormat:@"%d",value.red],*g=[NSString stringWithFormat:@"%d",value.green],*b=[NSString stringWithFormat:@"%d",value.blue];
        NSString *age=[NSString stringWithFormat:@"%llu",(unsigned long long)value.ageMs],*ms=[NSString stringWithFormat:@"%.3f",value.totalMs];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@;;%@;;%@;;%@;;%@\r\n",r,g,b,age,ms,ms];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",r,g,b,age,ms,ms],@"red":@(value.red),@"green":@(value.green),@"blue":@(value.blue),@"ageMs":@(value.ageMs),@"totalMs":@([ms doubleValue])};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed frame pick task entry.

// BEGIN typed frame pick-many task entry.
NSDictionary *TLinkExecuteNativeFramePickMany(const TLinkNativeFramePickManyRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_COLOR_IN_FRAME==69,"frame color task classification changed");
    const uint8_t task[]={'6','9'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_IN_FRAME,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkNativeFramePickManyValue value;
        if(!readFramePixels(request,value,&error))return zx_typedTouchReply(error.localizedDescription?:@"1;;frame_error\r\n",replyBudget);
        NSMutableArray *colors=[NSMutableArray arrayWithCapacity:value.colors.size()];NSMutableString *table=[NSMutableString string];
        for(const auto &pixel:value.colors){
            if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
            if(table.length)[table appendString:@"|"];
            [table appendFormat:@"%d,%d,%d,%d,%d",pixel.x,pixel.y,pixel.red,pixel.green,pixel.blue];
            [colors addObject:@{@"x":@(pixel.x),@"y":@(pixel.y),@"red":@(pixel.red),@"green":@(pixel.green),@"blue":@(pixel.blue)}];
        }
        NSString *encoded=[table copy],*age=[NSString stringWithFormat:@"%llu",(unsigned long long)value.ageMs],*ms=[NSString stringWithFormat:@"%.3f",value.totalMs];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@;;%@;;%@\r\n",encoded,age,ms,ms];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",encoded,age,ms,ms],@"colors":colors,@"ageMs":@(value.ageMs),@"totalMs":@([ms doubleValue])};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed frame pick-many task entry.

// BEGIN typed frame search task entry.
NSDictionary *TLinkExecuteNativeFrameSearch(const TLinkNativeFrameSearchRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_COLOR_IN_FRAME==69,"frame color task classification changed");const uint8_t task[]={'6','9'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_IN_FRAME,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkNativeFrameSearchValue value;
        if(!searchFrameColor(request,value,&error))return zx_typedTouchReply(error.localizedDescription?:@"1;;frame_error\r\n",replyBudget);
        NSString *x=[NSString stringWithFormat:@"%d",value.x],*y=[NSString stringWithFormat:@"%d",value.y];
        NSString *r=[NSString stringWithFormat:@"%d",value.red],*g=[NSString stringWithFormat:@"%d",value.green],*b=[NSString stringWithFormat:@"%d",value.blue];
        NSString *age=[NSString stringWithFormat:@"%llu",(unsigned long long)value.ageMs],*ms=[NSString stringWithFormat:@"%.3f",value.totalMs];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@;;%@;;%@;;%@;;%@;;%@;;%@\r\n",x,y,r,g,b,age,ms,ms];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",x,y,r,g,b,age,ms,ms],@"matched":@(value.x>=0&&value.y>=0),@"x":@(value.x),@"y":@(value.y),@"red":@(value.red),@"green":@(value.green),@"blue":@(value.blue),@"ageMs":@(value.ageMs),@"totalMs":@([ms doubleValue])};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed frame search task entry.

// BEGIN typed frame colors task entry.
NSDictionary *TLinkExecuteNativeFrameColors(const TLinkNativeFrameColorsRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_COLOR_IN_FRAME==69,"frame color task classification changed");const uint8_t task[]={'6','9'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_IN_FRAME,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkNativeFrameColorsValue value;
        if(!testFrameColors(request,value,&error))return zx_typedTouchReply(error.localizedDescription?:@"1;;frame_error\r\n",replyBudget);
        NSString *flag=value.matched?@"1":@"0",*age=[NSString stringWithFormat:@"%llu",(unsigned long long)value.ageMs],*ms=[NSString stringWithFormat:@"%.3f",value.totalMs];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@;;%@;;%@\r\n",flag,age,ms,ms];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",flag,age,ms,ms],@"matched":@(value.matched),@"value":@(value.matched),@"ageMs":@(value.ageMs),@"totalMs":@([ms doubleValue])};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed frame colors task entry.

// BEGIN typed frame multi task entry.
NSDictionary *TLinkExecuteNativeFrameMulti(const TLinkNativeFrameMultiRequest &request,TLinkTaskExecutionContext *context)
{
    TLinkTaskExecutionContext *call=TLinkNativeCallContext(context,false,false);
    auto replyBudget=[call nativeBudget];TLinkNativeBudgetScope callScope(replyBudget);
    static_assert(TASK_COLOR_IN_FRAME==69,"frame color task classification changed");const uint8_t task[]={'6','9'};
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(task,sizeof(task),replyBudget));
    @try {try {
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSString *denial=nil;
        if(!TLinkRootfullLicenseTaskAllowed(TASK_COLOR_IN_FRAME,&denial))return zx_typedTouchReply(denial?:@"-1;;license_required\r\n",replyBudget);
        if(TLinkNativeStopped())return zx_typedTouchReply(@"1;;native_cancelled_or_timed_out\r\n",replyBudget);
        NSError *error=nil;TLinkNativeFrameMultiValue value;
        if(!findFrameColors(request,value,&error))return zx_typedTouchReply(error.localizedDescription?:@"1;;frame_error\r\n",replyBudget);
        NSString *x=[NSString stringWithFormat:@"%d",value.x],*y=[NSString stringWithFormat:@"%d",value.y];
        NSString *age=[NSString stringWithFormat:@"%llu",(unsigned long long)value.ageMs],*ms=[NSString stringWithFormat:@"%.3f",value.totalMs];
        NSString *raw=[NSString stringWithFormat:@"0;;%@;;%@;;%@;;%@;;%@\r\n",x,y,age,ms,ms];
        if(!replyBudget->outputAllowed([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding])||replyBudget->stopped())return zx_typedTouchStopped(replyBudget);
        return @{@"ok":@(true),@"raw":raw,@"parts":@[@"0",x,y,age,ms,ms],@"matched":@(value.x>=0&&value.y>=0),@"x":@(value.x),@"y":@(value.y),@"ageMs":@(value.ageMs),@"totalMs":@([ms doubleValue])};
    }catch(...){return zx_typedTouchFailure(@"native_exception");}}
    @catch(__unused NSException *exception){return zx_typedTouchFailure(@"native_exception");}
}
// END typed frame multi task entry.

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
    NSString *sudoPath = TLinkJailbreakPath(@"/usr/bin/sudo");
    NSString *helperPath = TLinkJailbreakPath(@"/usr/bin/tlinkautob");
    const char *sudoFileSystemPath = [sudoPath fileSystemRepresentation];
    const char *helperFileSystemPath = [helperPath fileSystemRepresentation];
    const char *cmdArgs[] = {sudoFileSystemPath, helperFileSystemPath, "-e", [command UTF8String], NULL};
    int spawnErr = posix_spawn(&pid, sudoFileSystemPath, &actions, &attr, (char *const *)cmdArgs, NULL);

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
        if (TLinkNativeStopped() || (context && context.cancellationToken && [context.cancellationToken isCancelled])) {
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
    // Legacy callers own a complete NUL-terminated string; bounded ingress uses the explicit-length API.
    processTaskWithContext(buff, buff ? strlen((const char *)buff) : 0, writeStreamRef, nil);
}

void processTask(UInt8 *buff, CFWriteStreamRef writeStreamRef)
{
    processTaskLegacy(buff, writeStreamRef);
}

static NSDictionary *zx_uiTreeRequest(UInt8 *eventData, BOOL allowEmpty, NSString **error)
{
    NSString *body = eventData ? [NSString stringWithUTF8String:(char *)eventData] : @"";
    body = [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (body.length == 0 && allowEmpty) return @{};
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:body
                                                         options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (decoded.length == 0) {
        if (error) *error = @"ui_request_base64_invalid";
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error) *error = @"ui_request_json_object_required";
        return nil;
    }
    return object;
}

static void zx_uiTreeNotifyResult(NSDictionary *result, CFWriteStreamRef stream)
{
    if (!TLinkAXResultSucceeded(result)) {
        NSString *code = [result[@"error"] isKindOfClass:[NSString class]]
            ? result[@"error"] : @"ui_operation_failed";
        notifyClient((UInt8 *)[[NSString stringWithFormat:@"-1;;%@\r\n", code] UTF8String], stream);
        return;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if (json.length == 0) {
        notifyClient((UInt8 *)"-1;;ui_result_json_failed\r\n", stream);
        return;
    }
    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @"";
    notifyClient((UInt8 *)[[NSString stringWithFormat:@"0;;%@\r\n", base64] UTF8String], stream);
}

static BOOL zx_uiTreeContextChanged(NSDictionary *before)
{
    NSDictionary *after = TLinkAXCopyFrontmostContext();
    if (!TLinkAXResultSucceeded(after)) return true;
    return ![before[@"bundle_id"] isEqual:after[@"bundle_id"]] ||
           [before[@"pid"] intValue] != [after[@"pid"] intValue];
}

static void zx_handleUITreeTask(int taskType, UInt8 *eventData, CFWriteStreamRef stream)
{
    if (taskType == TASK_UI_TREE_CAPABILITY) {
        NSMutableDictionary *capability = [TLinkAXCapabilitySnapshot() mutableCopy];
        capability[@"runtime"] = @"rootfull";
        capability[@"service"] = @"springboard_script_bridge";
        capability[@"tasks"] = @[@77, @78, @79, @80, @81];
        NSData *json = [NSJSONSerialization dataWithJSONObject:capability options:0 error:nil];
        if (json.length == 0) {
            notifyClient((UInt8 *)"-1;;ui_capability_json_failed\r\n", stream);
        } else {
            NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @"";
            notifyClient((UInt8 *)[[NSString stringWithFormat:@"0;;%@\r\n", base64] UTF8String], stream);
        }
        return;
    }

    NSString *decodeError = nil;
    NSDictionary *request = zx_uiTreeRequest(eventData, taskType == TASK_UI_TREE_SNAPSHOT, &decodeError);
    if (!request) {
        notifyClient((UInt8 *)[[NSString stringWithFormat:@"-1;;%@\r\n", decodeError] UTF8String], stream);
        return;
    }
    NSDictionary *context = TLinkAXCopyFrontmostContext();
    if (!TLinkAXResultSucceeded(context)) {
        zx_uiTreeNotifyResult(context, stream);
        return;
    }
    NSString *bundleID = context[@"bundle_id"];
    pid_t pid = [context[@"pid"] intValue];
    NSDictionary *result = nil;
    if (taskType == TASK_UI_TREE_SNAPSHOT) {
        result = TLinkAXCopySnapshot(pid, bundleID, request);
    } else if (taskType == TASK_UI_TREE_FIND || taskType == TASK_UI_TREE_TAP) {
        result = TLinkAXFindElement(pid, bundleID, request);
    } else if (taskType == TASK_UI_TREE_AT) {
        id x = request[@"x"], y = request[@"y"];
        if (![x respondsToSelector:@selector(doubleValue)] || ![y respondsToSelector:@selector(doubleValue)]) {
            notifyClient((UInt8 *)"-1;;ui_hit_test_coordinates_required\r\n", stream);
            return;
        }
        result = TLinkAXElementAtPoint(pid, bundleID, CGPointMake([x doubleValue], [y doubleValue]));
    }
    if (!TLinkAXResultSucceeded(result)) {
        zx_uiTreeNotifyResult(result, stream);
        return;
    }
    if (taskType == TASK_UI_TREE_TAP && !TLinkAXResultCompleteForAction(result)) {
        notifyClient((UInt8 *)"-1;;ui_snapshot_incomplete\r\n", stream);
        return;
    }
    if (zx_uiTreeContextChanged(context)) {
        notifyClient((UInt8 *)"-1;;ui_context_changed\r\n", stream);
        return;
    }
    NSMutableDictionary *finalResult = [result mutableCopy];
    finalResult[@"runtime"] = @"rootfull";
    finalResult[@"context_changed"] = @(false);
    if (taskType == TASK_UI_TREE_TAP) {
        NSDictionary *element = [finalResult[@"element"] isKindOfClass:[NSDictionary class]]
            ? finalResult[@"element"] : @{};
        if (![finalResult[@"found"] boolValue] || element.count == 0) {
            notifyClient((UInt8 *)"-1;;ui_element_not_found\r\n", stream);
            return;
        }
        if (![element[@"enabled"] boolValue] || ![element[@"clickable"] boolValue]) {
            notifyClient((UInt8 *)"-1;;ui_element_not_clickable\r\n", stream);
            return;
        }
        if (![element[@"activation_point_valid"] boolValue]) {
            notifyClient((UInt8 *)"-1;;ui_activation_point_invalid\r\n", stream);
            return;
        }
        NSDictionary *point = element[@"activation_point"];
        CGFloat pointScale = [UIScreen mainScreen].scale > 0.0 ? [UIScreen mainScreen].scale : 1.0;
        NSString *tap = [NSString stringWithFormat:@"%.3f;;%.3f;;50;;0",
                         [point[@"x"] doubleValue] * pointScale,
                         [point[@"y"] doubleValue] * pointScale];
        NSError *tapError = nil;
        if (!zx_handleNativeTap((UInt8 *)[tap UTF8String], &tapError)) {
            notifyClient((UInt8 *)"-1;;ui_tap_dispatch_failed\r\n", stream);
            return;
        }
        finalResult[@"schema"] = @"ui_tap_v1";
        finalResult[@"tapped"] = @(true);
    }
    zx_uiTreeNotifyResult(finalResult, stream);
}

/**
Process Task
*/
void processTaskWithContext(UInt8 *buff, size_t actualLength, CFWriteStreamRef writeStreamRef, TLinkTaskExecutionContext *context)
{
    if (!buff || actualLength < 2 || actualLength == SIZE_MAX ||
        buff[0] < '0' || buff[0] > '9' || buff[1] < '0' || buff[1] > '9') {
        notifyClient((UInt8 *)"1;;task_bad_payload\r\n", writeStreamRef);
        return;
    }
    TLinkNativeBudgetScope taskScope(TLinkTaskBudget(context));
    TLinkNativeBudgetScope c01Scope(TLinkC01TaskBudget(buff,actualLength,TLinkCurrentNativeBudget()));
    const size_t eventDataLength = actualLength - 2;
    
    //NSLog(@"### com.tlinkauto.springboard: task type: %d. Data: %s", getTaskType(buff), buff);
    UInt8 *eventData = buff + 0x2;
    int taskType = getTaskType(buff);

    auto nativeBudget = TLinkCurrentNativeBudget();
    const bool cleanup = nativeBudget && nativeBudget->cleanup() &&
        (taskType == TASK_FRAME_RELEASE ||
         (taskType == TASK_IMAGE_OBJECT && eventDataLength >= 3 && memcmp(eventData, "3;;", 3) == 0) ||
         (taskType == TASK_HARDWARE_KEY && eventDataLength >= 3 && memcmp(eventData, "0;;", 3) == 0));
    if (TLinkNativeStopped() && !cleanup) {
        notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n", writeStreamRef);
        return;
    }
    NSString *licenseDenial = nil;
    const BOOL sessionAutomation = (taskType == TASK_PERFORM_TOUCH || taskType == TASK_USLEEP) &&
        context.allowsAutomationForOwner && context.allowsAutomationForOwner(context.ownerSessionId);
    if (!cleanup && !sessionAutomation && !TLinkRootfullLicenseTaskAllowed(taskType, &licenseDenial)) {
        if (taskType == TASK_PERFORM_TOUCH) {
            sTLinkSpringBoardLicenseTask10DropCount.fetch_add(1, std::memory_order_relaxed);
            return;
        }
        notifyClient((UInt8 *)[(licenseDenial ?: @"-1;;license_required\r\n") UTF8String],
                     writeStreamRef);
        return;
    }

    // License refresh may wait for IPC; recheck before committing an action.
    if (TLinkNativeStopped() && !cleanup) {
        notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n", writeStreamRef);
        return;
    }

    //for touching
    if (taskType == TASK_PERFORM_TOUCH)
    {
        @autoreleasepool{
            if (!performTouchFromRawData(eventData, eventDataLength)) {
                notifyClient((UInt8 *)"1;;touch_bad_payload\r\n", writeStreamRef);
            } else if (context.didInjectTouchPayload) {
                context.didInjectTouchPayload(eventData, eventDataLength);
            }
        }
    }
    else if (taskType >= TASK_UI_TREE_CAPABILITY && taskType <= TASK_UI_TREE_TAP)
    {
        @autoreleasepool {
            zx_handleUITreeTask(taskType, eventData, writeStreamRef);
        }
    }
    else if (taskType == TASK_PERFORM_TOUCH_ACK)
    {
        @autoreleasepool{
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            size_t separator = 0;
            while (separator + 1 < eventDataLength &&
                   (eventData[separator] != ';' || eventData[separator + 1] != ';')) separator++;
            if (separator == 0 || separator + 1 >= eventDataLength ||
                memchr(eventData, '\0', separator) != NULL) {
                notifyClient((UInt8*)"1;;touch_ack_bad_payload\r\n", writeStreamRef);
                return;
            }
            NSString *seq = [[NSString alloc] initWithBytes:eventData length:separator encoding:NSUTF8StringEncoding];
            const size_t touchOffset = separator + 2;
            if (!seq || !performTouchFromRawData(eventData + touchOffset, eventDataLength - touchOffset)) {
                notifyClient((UInt8*)"1;;touch_ack_bad_payload\r\n", writeStreamRef);
                return;
            }
            if (context.didInjectTouchPayload) context.didInjectTouchPayload(eventData + touchOffset, eventDataLength - touchOffset);
            int dispatchUs = (int)((CFAbsoluteTimeGetCurrent() - start) * 1000000.0);
            NSString *response = [NSString stringWithFormat:@"0;;%@;;%d\r\n", seq, dispatchUs];
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
        long long micros = atoll((const char *)eventData);
        if (micros < 0 || micros > INT_MAX) {
            notifyClient((UInt8 *)"1;;invalid_sleep\r\n", writeStreamRef);
        } else if (!TLinkNativeWaitNs((uint64_t)micros * 1000)) {
            notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n", writeStreamRef);
        } else if (writeStreamRef) notifyClient((UInt8 *)"0;;Sleep ends\r\n", writeStreamRef);
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
            NSString *path = startRecordingWithError(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8 *)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_STOP)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopRecordingWithError(&err);
            notifyClient((UInt8 *)(err ? err.localizedDescription.UTF8String : "0\r\n"), writeStreamRef);
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
            NSString *licenseDiagnosticMode = [[NSString alloc] initWithBytes:eventData length:eventDataLength encoding:NSUTF8StringEncoding];
            NSMutableDictionary *licenseStatus =
                [(TLinkLicenseDiagnosticUsesCache(licenseDiagnosticMode) ? TLinkLicenseDiagnosticStatus(licenseDiagnosticMode) : TLinkLicenseStatusDictionary()) mutableCopy];
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
                @"tesseract_ocr": TLinkTesseractOCRPerformance(),
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
