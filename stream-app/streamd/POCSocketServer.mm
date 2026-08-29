#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <CoreML/CoreML.h>
#import <ImageIO/ImageIO.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <Photos/Photos.h>
#import "H264Stream.h"
#import "../../shared/TLinkJSFileHandle.h"
#import "../../shared/TLinkEventChannel.h"
#import "../../shared/TLinkAdaptiveStreaming.h"
#import "../../shared/TLinkLicenseVerifier.h"
#import "../../shared/TLinkSmartWaitPrelude.h"
#import "../../shared/TLinkRunHistory.h"
#import "../../shared/TLinkVPNDiagnostics.h"
#include <string.h>
#include <ctype.h>
#include <dispatch/dispatch.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>
#include <dlfcn.h>
#include <signal.h>
#include <spawn.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <netinet/tcp.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <mach-o/dyld.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <sys/utsname.h>
#include <atomic>
#import <objc/message.h>
#import <objc/runtime.h>
#include <tesseract/baseapi.h>
#include <leptonica/allheaders.h>

#include "POCSocketServer.h"
#include "TouchInjector.h"
#include "HIDInjectCore.h"
#include "headers/IOHIDEvent.h"
#include "headers/IOHIDEventTypes.h"
#include "headers/IOHIDEventSystemClient.h"
#import "CaptureCore.h"
#import "StreamCaptureProbe.h"

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
extern char **environ;

static BOOL TLinkVPNInterfaceActive(void);
static NSDictionary *TLinkVPNTrollStoreDiagnosticsSnapshot(
    NSNumber *effectiveConnected,
    NSString *agentError,
    NSString *brokerError);
static CaptureOutcome *TLinkRunCaptureOnMain(void);

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
static NSString *sTLinkLaunchExecutablePath = @"";

void TLinkSetLaunchExecutablePath(const char *path)
{
    if (!path || path[0] == '\0') {
        sTLinkLaunchExecutablePath = @"";
        return;
    }
    char resolved[PATH_MAX + 1] = {0};
    const char *finalPath = realpath(path, resolved) ? resolved : path;
    NSString *value = [NSString stringWithUTF8String:finalPath] ?: @"";
    if (![value hasPrefix:@"/"]) {
        value = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:value];
    }
    sTLinkLaunchExecutablePath = [value stringByStandardizingPath] ?: @"";
}

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
@property(nonatomic, assign) BOOL eventPollPending;
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

static NSDictionary *TLinkZoomDiagnosticsDictionary(void)
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

static NSData *TLinkHandleTaskLine(const char *line);
static NSString *TLinkCleanPayload(NSString *body);
static CGSize TLinkScreenPixelSize(void);
static BOOL TLinkAppForegroundHeartbeatIsFresh(void);
static void TLinkDispatchBackgroundVisualFallback(NSDictionary *event);
static void TLinkDispatchBackgroundKeepAwake(BOOL enabled);

static NSObject *TLinkVisualFeedbackLock(void)
{
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [[NSObject alloc] init];
    });
    return lock;
}

static NSMutableArray<NSDictionary *> *sTLinkVisualEvents = nil;
static uint64_t sTLinkNextVisualEventId = 1;
static uint64_t sTLinkLastVisualEventId = 0;
static BOOL sTLinkTouchIndicatorEnabled = NO;
static BOOL sTLinkSwitchAppBeforeRunScript = YES;
static BOOL sTLinkDoubleClickVolumeShowPopup = YES;
static BOOL sTLinkShellTaskEnabled = NO;
static BOOL sTLinkKeepAwakeEnabled = NO;
static NSString *sTLinkLastDialogValue = @"";
static NSMutableDictionary<NSString *, id> *sTLinkTimerRegistry = nil;
static NSMutableDictionary<NSString *, NSMutableDictionary *> *sTLinkTimerInfoRegistry = nil;
static BOOL sTLinkAutoLaunchScheduled = NO;
static uint64_t sTLinkLastAutoLaunchRunMs = 0;
static NSInteger sTLinkLastAutoLaunchEnabledCount = 0;
static NSInteger sTLinkLastAutoLaunchStartedCount = 0;
static NSString *sTLinkLastAutoLaunchResult = @"";
static uint64_t sTLinkLicenseDropCount = 0;
static uint64_t sTLinkLicenseLastDropAtMs = 0;
static NSString *sTLinkLicenseLastDropError = @"";
static BOOL sTLinkRecordingActive = NO;
static NSString *sTLinkRecordingBundlePath = @"";
static NSString *sTLinkRecordingRawPath = @"";
static NSString *sTLinkRecordingLastError = @"";
static uint64_t sTLinkRecordingStartedAtMs = 0;
static uint64_t sTLinkRecordingStoppedAtMs = 0;
static NSInteger sTLinkRecordingEventCount = 0;
static CFAbsoluteTime sTLinkRecordingLastEventTime = 0;
static double sTLinkRecordingScreenWidth = 0;
static double sTLinkRecordingScreenHeight = 0;
static NSFileHandle *sTLinkRecordingFileHandle = nil;
static IOHIDEventSystemClientRef sTLinkRecordingClient = NULL;
static CFRunLoopRef sTLinkRecordingRunLoop = NULL;
static BOOL sTLinkTapMacroActive = NO;
static BOOL sTLinkTapMacroStopRequested = NO;
static uint64_t sTLinkNextTapMacroSessionId = 1;
static uint64_t sTLinkTapMacroSessionId = 0;
static NSInteger sTLinkTapMacroCompletedCount = 0;
static NSInteger sTLinkTapMacroTargetCount = 0;
static NSString *sTLinkTapMacroMode = @"";
static NSString *sTLinkTapMacroLastError = @"";
static uint64_t sTLinkTapMacroStartedAtMs = 0;
static uint64_t sTLinkTapMacroEndedAtMs = 0;
static NSString *const kTLinkSettingsConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/config.plist";
static NSString *const kTLinkAutoLaunchConfigPath = @"/var/mobile/Library/TLinkauto/autolaunch.plist";
static NSString *const kTLinkRecordingScriptsPath = @"/var/mobile/Library/TLinkauto/scripts/recording";
static NSString *const kTLinkAppForegroundHeartbeatPath = @"/var/mobile/Library/TLinkauto/runtime/app_foreground_heartbeat";
static NSString *const kTLinkBackgroundSchedulerDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/background_service_scheduler.plist";
static NSString *const kTLinkLicenseLifecycleDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/license_lifecycle.plist";
static NSString *const kTLinkRemoteBridgeDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/remote_bridge.plist";
static NSString *sTLinkLastTesseractInitSource = @"none";
static NSString *sTLinkLastTesseractInitAttempts = @"";
static uint64_t sTLinkLastTesseractInitAtMs = 0;

static NSString *TLinkVisualSafeText(NSString *text)
{
    NSMutableString *safe = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "] mutableCopy];
    [safe replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    return safe ?: @"";
}

static uint64_t TLinkRecordToastWithOptions(NSString *message, double duration, int type,
                                            int position, int fontSize, BOOL allowScreenshot,
                                            NSString *source)
{
    NSString *safeMessage = TLinkVisualSafeText(message);
    if (safeMessage.length == 0) return 0;
    if (duration <= 0.0) duration = 2.0;
    if (duration > 30.0) duration = 30.0;
    if (fontSize <= 0) fontSize = 15;
    if (fontSize > 50) fontSize = 50;

    uint64_t eventId = 0;
    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkVisualEvents) sTLinkVisualEvents = [NSMutableArray array];
        eventId = sTLinkNextVisualEventId++;
        sTLinkLastVisualEventId = eventId;
        [sTLinkVisualEvents addObject:@{
            @"id": @(eventId),
            @"kind": @"toast",
            @"message": safeMessage,
            @"duration": @(duration),
            @"type": @(type),
            @"position": @(position),
            @"fontSize": @(fontSize),
            @"allow_screenshot": @(allowScreenshot),
            @"delivery": @"uiservice",
            @"source": source ?: @"unknown",
            @"ts_ms": @(TLinkNowMs()),
        }];
        while (sTLinkVisualEvents.count > 50) {
            [sTLinkVisualEvents removeObjectAtIndex:0];
        }
    }
    TLinkDispatchBackgroundVisualFallback(@{
        @"action": @"visual",
        @"kind": @"toast",
        @"title": @"TLinkauto",
        @"message": safeMessage,
        @"duration": @(duration),
        @"position": @(position),
        @"fontSize": @(fontSize),
        @"allow_screenshot": @(allowScreenshot),
        @"type": @(type),
        @"event_id": @(eventId),
    });
    return eventId;
}

static uint64_t TLinkRecordToast(NSString *message, double duration, int type, int position,
                                 int fontSize, NSString *source)
{
    return TLinkRecordToastWithOptions(message, duration, type, position, fontSize, NO, source);
}

static uint64_t TLinkRecordAlert(NSString *title, NSString *message, double duration, NSString *source)
{
    NSString *safeTitle = TLinkVisualSafeText(title.length > 0 ? title : @"TLinkauto");
    NSString *safeMessage = TLinkVisualSafeText(message);
    if (safeMessage.length == 0) return 0;
    if (duration < 0.0) duration = 0.0;
    if (duration > 1000.0) duration = 1000.0;

    uint64_t eventId = 0;
    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkVisualEvents) sTLinkVisualEvents = [NSMutableArray array];
        eventId = sTLinkNextVisualEventId++;
        sTLinkLastVisualEventId = eventId;
        [sTLinkVisualEvents addObject:@{
            @"id": @(eventId),
            @"kind": @"alert",
            @"title": safeTitle,
            @"message": safeMessage,
            @"duration": @(duration),
            @"source": source ?: @"unknown",
            @"ts_ms": @(TLinkNowMs()),
        }];
        while (sTLinkVisualEvents.count > 50) {
            [sTLinkVisualEvents removeObjectAtIndex:0];
        }
    }
    TLinkDispatchBackgroundVisualFallback(@{
        @"action": @"visual",
        @"kind": @"alert",
        @"title": safeTitle,
        @"message": safeMessage,
        @"duration": @(duration),
        @"event_id": @(eventId),
    });
    return eventId;
}

static uint64_t TLinkRecordDialog(NSString *title, NSString *message, NSString *okTitle, NSString *cancelTitle, NSString *source)
{
    NSString *safeTitle = TLinkVisualSafeText(title.length > 0 ? title : @"TLinkauto");
    NSString *safeMessage = TLinkVisualSafeText(message);
    NSString *safeOK = TLinkVisualSafeText(okTitle.length > 0 ? okTitle : @"OK");
    NSString *safeCancel = TLinkVisualSafeText(cancelTitle.length > 0 ? cancelTitle : @"Cancel");
    if (safeTitle.length == 0 && safeMessage.length == 0) return 0;

    uint64_t eventId = 0;
    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkVisualEvents) sTLinkVisualEvents = [NSMutableArray array];
        eventId = sTLinkNextVisualEventId++;
        sTLinkLastVisualEventId = eventId;
        [sTLinkVisualEvents addObject:@{
            @"id": @(eventId),
            @"kind": @"dialog",
            @"title": safeTitle,
            @"message": safeMessage,
            @"ok": safeOK,
            @"cancel": safeCancel,
            @"mode": @"foreground_overlay_with_background_cfusernotification_alert",
            @"source": source ?: @"unknown",
            @"ts_ms": @(TLinkNowMs()),
        }];
        while (sTLinkVisualEvents.count > 50) {
            [sTLinkVisualEvents removeObjectAtIndex:0];
        }
    }
    TLinkDispatchBackgroundVisualFallback(@{
        @"action": @"visual",
        @"kind": @"dialog",
        @"title": safeTitle,
        @"message": safeMessage,
        @"ok": safeOK,
        @"cancel": safeCancel,
        @"duration": @30,
        @"event_id": @(eventId),
    });
    return eventId;
}

static CGSize TLinkVisualScreenPixelSize(void)
{
    UIScreen *screen = [UIScreen mainScreen];
    CGSize bounds = screen.bounds.size;
    CGFloat scale = screen.scale;
    return CGSizeMake(bounds.width * scale, bounds.height * scale);
}

static uint64_t TLinkRecordTouchIndicator(CGFloat x, CGFloat y, int touchType, NSString *source)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkTouchIndicatorEnabled) return 0;
    }
    CGSize screen = TLinkVisualScreenPixelSize();
    uint64_t eventId = 0;
    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkVisualEvents) sTLinkVisualEvents = [NSMutableArray array];
        eventId = sTLinkNextVisualEventId++;
        sTLinkLastVisualEventId = eventId;
        [sTLinkVisualEvents addObject:@{
            @"id": @(eventId),
            @"kind": @"touch",
            @"x": @(x),
            @"y": @(y),
            @"type": @(touchType),
            @"screen_width": @((int)screen.width),
            @"screen_height": @((int)screen.height),
            @"source": source ?: @"touch",
            @"ts_ms": @(TLinkNowMs()),
        }];
        while (sTLinkVisualEvents.count > 80) {
            [sTLinkVisualEvents removeObjectAtIndex:0];
        }
    }
    return eventId;
}

static void TLinkRecordLegacyTouchIndicatorEvents(NSString *body, NSString *source)
{
    if (body.length < 1) return;
    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkTouchIndicatorEnabled) return;
    }
    const char *bytes = [body UTF8String];
    if (!bytes) return;
    int count = bytes[0] - '0';
    if (count <= 0 || count > 9) return;
    NSUInteger len = strlen(bytes);
    NSUInteger offset = 1;
    for (int i = 0; i < count && offset + 13 <= len; i++, offset += 13) {
        int touchType = bytes[offset] - '0';
        char xbuf[6] = {0};
        char ybuf[6] = {0};
        memcpy(xbuf, bytes + offset + 3, 5);
        memcpy(ybuf, bytes + offset + 8, 5);
        CGFloat x = (CGFloat)atoi(xbuf) / 10.0f;
        CGFloat y = (CGFloat)atoi(ybuf) / 10.0f;
        TLinkRecordTouchIndicator(x, y, touchType, source);
    }
}

static NSDictionary *TLinkVisualFeedbackDictionary(void)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        return @{
            @"last_event_id": @(sTLinkLastVisualEventId),
            @"last_dialog_value": sTLinkLastDialogValue ?: @"",
            @"touch_indicator_enabled": @(sTLinkTouchIndicatorEnabled),
            @"foreground_app_active": @(TLinkAppForegroundHeartbeatIsFresh()),
            @"background_fallback_mode": @"toast_uiservice_always_alert_dialog_cfusernotification",
            @"toast_delivery": @"uiservice_always",
            @"events": sTLinkVisualEvents ? [sTLinkVisualEvents copy] : @[],
        };
    }
}

static NSDictionary *TLinkRuntimeSettingsDictionary(void)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        return @{
            @"config_path": kTLinkSettingsConfigPath,
            @"touch_indicator_show": @(sTLinkTouchIndicatorEnabled),
            @"switch_app_before_run_script": @(sTLinkSwitchAppBeforeRunScript),
            @"double_click_volume_show_popup": @(sTLinkDoubleClickVolumeShowPopup),
            @"shell_task_enabled": @(sTLinkShellTaskEnabled),
        };
    }
}

static NSDictionary *TLinkKeepAwakeDictionary(void)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        return @{
            @"enabled": @(sTLinkKeepAwakeEnabled),
            @"mode": @"foreground_app_plus_background_uidaemon_best_effort",
        };
    }
}

static NSDictionary *TLinkSchedulerStatusDictionary(void)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        return @{
            @"mode": @"streamd_lite",
            @"autolaunch_path": kTLinkAutoLaunchConfigPath,
            @"startup_scheduled": @(sTLinkAutoLaunchScheduled),
            @"last_autolaunch_run_ms": @(sTLinkLastAutoLaunchRunMs),
            @"last_autolaunch_enabled_count": @(sTLinkLastAutoLaunchEnabledCount),
            @"last_autolaunch_started_count": @(sTLinkLastAutoLaunchStartedCount),
            @"last_autolaunch_result": sTLinkLastAutoLaunchResult ?: @"",
            @"timer_count": @((int)(sTLinkTimerInfoRegistry ? sTLinkTimerInfoRegistry.count : 0)),
            @"timers": sTLinkTimerInfoRegistry ? [sTLinkTimerInfoRegistry copy] : @{},
        };
    }
}

static NSDictionary *TLinkRecordingStatusDictionary(void)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        return @{
            @"active": @(sTLinkRecordingActive),
            @"mode": @"iohid_monitor_raw_js_replay",
            @"bundle_path": sTLinkRecordingBundlePath ?: @"",
            @"raw_path": sTLinkRecordingRawPath ?: @"",
            @"event_count": @(sTLinkRecordingEventCount),
            @"started_at_ms": @(sTLinkRecordingStartedAtMs),
            @"stopped_at_ms": @(sTLinkRecordingStoppedAtMs),
            @"last_error": sTLinkRecordingLastError ?: @"",
        };
    }
}

static NSDictionary *TLinkTapMacroStatusDictionary(void)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        return @{
            @"active": @(sTLinkTapMacroActive),
            @"mode": sTLinkTapMacroMode ?: @"",
            @"session_id": @(sTLinkTapMacroSessionId),
            @"completed_count": @(sTLinkTapMacroCompletedCount),
            @"target_count": @(sTLinkTapMacroTargetCount),
            @"started_at_ms": @(sTLinkTapMacroStartedAtMs),
            @"ended_at_ms": @(sTLinkTapMacroEndedAtMs),
            @"last_error": sTLinkTapMacroLastError ?: @"",
        };
    }
}

@interface TLinkScriptSession : NSObject
@property(nonatomic, copy) NSString *sessionId;
@property(nonatomic, copy) NSString *bundlePath;
@property(nonatomic, copy) NSString *entryPath;
@property(nonatomic, copy) NSString *state;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, assign) uint64_t startedAtMs;
@property(nonatomic, assign) uint64_t endedAtMs;
@property(nonatomic, assign) NSInteger repeatTimes;
@property(nonatomic, assign) NSInteger totalRuns;
@property(nonatomic, assign) NSInteger currentRun;
@property(nonatomic, assign) double intervalSeconds;
@property(nonatomic, assign) double speed;
@property(nonatomic, assign) BOOL stopRequested;
@property(nonatomic, assign) BOOL licenseRevoked;
@property(nonatomic, assign) uint64_t lastLicenseCheckAtMs;
@property(nonatomic, copy) NSString *licenseRevocationError;
@property(nonatomic, copy) NSString *historyRunId;
@property(nonatomic, strong) NSMutableArray<NSString *> *logs;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, TLinkJSFileHandle *> *fileHandles;
@property(nonatomic, assign) NSUInteger nextFileHandleId;
@end

@implementation TLinkScriptSession
@end

static NSString *const kTLinkScriptsRootPath = @"/var/mobile/Library/TLinkauto/scripts";
static NSString *const kTLinkScriptPlayConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/script_play_settings.plist";
static const NSUInteger kTLinkScriptMaxOpenFiles = 32;
static const NSUInteger kTLinkScriptMaxFileTransferBytes = 512 * 1024;
static TLinkScriptSession *sTLinkScriptSession = nil;
static uint64_t sTLinkNextScriptSessionId = 1;
static NSString *sTLinkLastScriptError = @"script_runtime_not_started";
static uint64_t sTLinkLastScriptErrorTs = 0;

static NSString *TLinkNormalizePath(NSString *path)
{
    if (path.length == 0) return @"";
    NSString *standard = [path stringByStandardizingPath] ?: path;
    NSString *resolved = [standard stringByResolvingSymlinksInPath];
    return resolved.length > 0 ? resolved : standard;
}

static BOOL TLinkPathIsInside(NSString *path, NSString *basePath)
{
    NSString *normalizedPath = TLinkNormalizePath(path);
    NSString *normalizedBase = TLinkNormalizePath(basePath);
    if (normalizedPath.length == 0 || normalizedBase.length == 0) return NO;
    if ([normalizedPath isEqualToString:normalizedBase]) return YES;
    NSString *prefix = [normalizedBase hasSuffix:@"/"] ? normalizedBase : [normalizedBase stringByAppendingString:@"/"];
    return [normalizedPath hasPrefix:prefix];
}

static NSString *TLinkResponseStringFromData(NSData *data)
{
    if (data.length == 0) return @"";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

static NSDictionary *TLinkTaskResultFromResponseString(NSString *raw)
{
    NSString *text = raw ?: @"";
    BOOL ok = [text isEqualToString:@"0"] || [text hasPrefix:@"0;;"];
    NSString *payload = @"";
    if ([text hasPrefix:@"0;;"] || [text hasPrefix:@"-1;;"]) {
        payload = [text substringFromIndex:3] ?: @"";
    }
    NSMutableDictionary *result = [@{
        @"ok": @(ok),
        @"code": ok ? @0 : @-1,
        @"payload": payload ?: @"",
        @"raw": text,
    } mutableCopy];
    if (!ok) result[@"error"] = payload.length > 0 ? payload : @"unknown_error";
    return result;
}

static NSString *TLinkScriptRunTask(int taskType, NSString *body);
static BOOL TLinkScriptStopRequested(TLinkScriptSession *session);

static NSDictionary *TLinkScriptStoppedResult(void)
{
    return @{@"ok": @NO, @"code": @-1, @"payload": @"script_stop_requested", @"error": @"script_stop_requested", @"raw": @"-1;;script_stop_requested"};
}

static NSArray<NSString *> *TLinkScriptResultParts(NSDictionary *result)
{
    NSString *payload = [result[@"payload"] isKindOfClass:[NSString class]] ? result[@"payload"] : @"";
    return payload.length > 0 ? TLinkSplitBody(payload) : @[];
}

static NSDictionary *TLinkScriptResultByAdding(NSDictionary *result, NSDictionary *extra)
{
    NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:result ?: @{}];
    if (![merged[@"ok"] boolValue] && !merged[@"error"]) merged[@"error"] = merged[@"payload"] ?: @"unknown_error";
    [extra enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if (key && obj) merged[key] = obj;
    }];
    return merged;
}

static NSDictionary *TLinkScriptTaskResult(TLinkScriptSession *session, int task, NSString *body)
{
    if (TLinkScriptStopRequested(session)) return TLinkScriptStoppedResult();
    NSDictionary *result = TLinkTaskResultFromResponseString(TLinkScriptRunTask(task, body ?: @""));
    if (![result[@"ok"] boolValue]) {
        return TLinkScriptResultByAdding(result, @{@"error": result[@"payload"] ?: @"unknown_error"});
    }
    return result;
}

static NSDictionary *TLinkScriptDictionaryFromJSValue(JSValue *value)
{
    if (!value || [value isUndefined] || [value isNull]) return nil;
    id obj = [value toObject];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static NSArray *TLinkScriptArrayFromJSValue(JSValue *value)
{
    if (!value || [value isUndefined] || [value isNull]) return nil;
    id obj = [value toObject];
    return [obj isKindOfClass:[NSArray class]] ? obj : nil;
}

static NSString *TLinkScriptStringOption(NSDictionary *options, NSString *key, NSString *fallback)
{
    id value = options[key];
    if (!value || value == (id)kCFNull) return fallback ?: @"";
    if ([value isKindOfClass:[NSString class]]) return value;
    return [value description] ?: (fallback ?: @"");
}

static int TLinkScriptIntOption(NSDictionary *options, NSString *key, int fallback)
{
    id value = options[key];
    return value && value != (id)kCFNull ? [value intValue] : fallback;
}

static double TLinkScriptDoubleOption(NSDictionary *options, NSString *key, double fallback)
{
    id value = options[key];
    return value && value != (id)kCFNull ? [value doubleValue] : fallback;
}

static NSString *TLinkScriptBase64Decode(NSString *value)
{
    NSData *data = [[NSData alloc] initWithBase64EncodedString:value ?: @"" options:0];
    return data ? ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"") : @"";
}

static NSString *TLinkScriptBase64Encode(NSString *value)
{
    NSData *data = [(value ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return data ? [data base64EncodedStringWithOptions:0] : @"";
}

static BOOL TLinkScriptPointFromObject(id item, double *x, double *y, int *r, int *g, int *b, BOOL requireColor)
{
    if ([item isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)item;
        if (arr.count < (requireColor ? 5 : 2)) return NO;
        if (x) *x = [arr[0] doubleValue];
        if (y) *y = [arr[1] doubleValue];
        if (requireColor) {
            if (r) *r = [arr[2] intValue];
            if (g) *g = [arr[3] intValue];
            if (b) *b = [arr[4] intValue];
        }
        return YES;
    }
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)item;
        id xValue = dict[@"x"];
        id yValue = dict[@"y"];
        if (!xValue || !yValue) return NO;
        if (x) *x = [xValue doubleValue];
        if (y) *y = [yValue doubleValue];
        if (requireColor) {
            id rValue = dict[@"r"] ?: dict[@"red"];
            id gValue = dict[@"g"] ?: dict[@"green"];
            id bValue = dict[@"b"] ?: dict[@"blue"];
            if (!rValue || !gValue || !bValue) return NO;
            if (r) *r = [rValue intValue];
            if (g) *g = [gValue intValue];
            if (b) *b = [bValue intValue];
        }
        return YES;
    }
    return NO;
}

static NSString *TLinkScriptPointList(id points, BOOL requireColor, NSString **error)
{
    if (![points isKindOfClass:[NSArray class]] || [(NSArray *)points count] == 0) {
        if (error) *error = requireColor ? @"requires non-empty point color array" : @"requires non-empty point array";
        return nil;
    }
    NSMutableArray<NSString *> *encoded = [NSMutableArray array];
    for (id item in (NSArray *)points) {
        double x = 0, y = 0;
        int r = 0, g = 0, b = 0;
        if (!TLinkScriptPointFromObject(item, &x, &y, &r, &g, &b, requireColor)) {
            if (error) *error = requireColor ? @"point colors must be [x,y,r,g,b] or {x,y,r,g,b}" : @"points must be [x,y] or {x,y}";
            return nil;
        }
        if (requireColor) {
            [encoded addObject:[NSString stringWithFormat:@"%d,%d,%d,%d,%d", (int)llround(x), (int)llround(y), r, g, b]];
        } else {
            [encoded addObject:[NSString stringWithFormat:@"%d,%d", (int)llround(x), (int)llround(y)]];
        }
    }
    return [encoded componentsJoinedByString:@"|"];
}

static NSString *TLinkScriptDefaultScreenshotPath(TLinkScriptSession *session)
{
    NSString *base = session.bundlePath.length > 0 ? session.bundlePath : @"/var/mobile/Library/TLinkauto/scripts";
    NSString *folder = [base stringByAppendingPathComponent:@"screenshots"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"screenshot_%llu.png", (unsigned long long)TLinkNowMs()]];
}

static void TLinkScriptAppendLog(TLinkScriptSession *session, NSString *line)
{
    if (!session || line.length == 0) return;
    NSString *entry = [NSString stringWithFormat:@"%llu %@", TLinkNowMs(), line];
    @synchronized (session) {
        if (!session.logs) session.logs = [NSMutableArray array];
        [session.logs addObject:entry];
        while (session.logs.count > 200) {
            [session.logs removeObjectAtIndex:0];
        }
    }
    POCLogf("script[%s]: %s", [session.sessionId UTF8String], [line UTF8String]);
}

static BOOL TLinkScriptStopRequested(TLinkScriptSession *session)
{
    if (!session) return YES;
    @synchronized (session) {
        return session.stopRequested;
    }
}

static void TLinkScriptCloseOpenFiles(TLinkScriptSession *session)
{
    if (!session) return;
    NSArray<TLinkJSFileHandle *> *openHandles = nil;
    @synchronized (session) {
        openHandles = [session.fileHandles.allValues copy];
        [session.fileHandles removeAllObjects];
    }
    for (TLinkJSFileHandle *handle in openHandles) [handle close];
}

static BOOL TLinkScriptIsActive(TLinkScriptSession *session);

static void TLinkScriptMarkLicenseRevoked(TLinkScriptSession *session, NSString *detail)
{
    if (!session) return;
    BOOL firstRevocation = NO;
    @synchronized (session) {
        if (!session.licenseRevoked) {
            firstRevocation = YES;
            session.licenseRevoked = YES;
            session.stopRequested = YES;
            session.state = @"stopping";
            session.licenseRevocationError = detail ?: @"license_required";
            session.lastError = @"license_revoked_during_execution";
        }
    }
    if (!firstRevocation) return;
    TLinkScriptCloseOpenFiles(session);
    TLinkScriptAppendLog(session, [NSString stringWithFormat:@"license_revoked_during_execution %@",
                                   detail ?: @"license_required"]);
}

static void TLinkStartScriptLicenseHeartbeat(TLinkScriptSession *session)
{
    if (!session || !TLinkScriptIsActive(session) || TLinkScriptStopRequested(session)) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!TLinkScriptIsActive(session) || TLinkScriptStopRequested(session)) return;
        NSString *licenseError = nil;
        BOOL allowed = TLinkLicenseFeatureAllowed(@"script", &licenseError);
        @synchronized (session) {
            session.lastLicenseCheckAtMs = TLinkNowMs();
        }
        if (!allowed) {
            TLinkScriptMarkLicenseRevoked(session, licenseError);
            return;
        }
        TLinkStartScriptLicenseHeartbeat(session);
    });
}

static void TLinkScriptMarkTerminal(TLinkScriptSession *session, NSString *state, NSString *error)
{
    if (!session) return;
    TLinkScriptCloseOpenFiles(session);
    NSArray<NSString *> *logTail = nil;
    NSString *runId = nil;
    @synchronized (session) {
        if (session.licenseRevoked) {
            state = @"license_revoked";
            error = @"license_revoked_during_execution";
        }
        session.state = state ?: @"finished";
        session.endedAtMs = TLinkNowMs();
        session.lastError = error ?: @"";
        NSUInteger start = session.logs.count > 50 ? session.logs.count - 50 : 0;
        logTail = session.logs.count > 0
            ? [session.logs subarrayWithRange:NSMakeRange(start, session.logs.count - start)]
            : @[];
        runId = session.historyRunId ?: @"";
    }
    if (error.length > 0) {
        sTLinkLastScriptError = error;
        sTLinkLastScriptErrorTs = session.endedAtMs;
    }

    NSString *screenshotPath = @"";
    NSString *screenshotError = @"";
    BOOL failed = [state isEqualToString:@"failed"] || [state isEqualToString:@"license_revoked"];
    if (failed && runId.length > 0) {
        CaptureOutcome *outcome = TLinkRunCaptureOnMain();
        if (outcome && outcome.image && outcome.result != CaptureResultFail) {
            screenshotPath = [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@.png", runId]];
            NSData *png = UIImagePNGRepresentation(outcome.image);
            if (!png || ![png writeToFile:screenshotPath atomically:NO]) {
                screenshotError = @"failure_evidence_screenshot_write_failed";
                screenshotPath = @"";
            }
        } else {
            screenshotError = outcome.diagnostics ?: @"failure_evidence_capture_failed";
        }
    }
    TLinkRunHistoryFinish(runId,
                          state ?: @"finished",
                          error ?: @"",
                          logTail ?: @[],
                          @"",
                          screenshotPath,
                          screenshotError,
                          @{
                              @"current_run": @(session.currentRun),
                              @"total_runs": @(session.totalRuns),
                          });
}

static BOOL TLinkScriptIsActive(TLinkScriptSession *session)
{
    if (!session) return NO;
    @synchronized (session) {
        return [session.state isEqualToString:@"starting"] ||
               [session.state isEqualToString:@"running"] ||
               [session.state isEqualToString:@"stopping"];
    }
}

static NSString *TLinkScriptEntryFromMetadata(NSString *bundlePath)
{
    NSString *manifestPath = [bundlePath stringByAppendingPathComponent:@"manifest.json"];
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    if (manifestData.length > 0) {
        NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil];
        NSString *entry = [manifest isKindOfClass:[NSDictionary class]] ? manifest[@"entry"] : nil;
        if (entry.length > 0) return entry;
    }

    NSString *plistPath = [bundlePath stringByAppendingPathComponent:@"info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSString *entry = [info isKindOfClass:[NSDictionary class]] ? info[@"Entry"] : nil;
    return entry.length > 0 ? entry : @"main.js";
}

static BOOL TLinkResolveScriptPaths(NSString *body, NSString **outBundlePath, NSString **outEntryPath, NSString **outError)
{
    NSString *raw = TLinkCleanPayload(body);
    if (raw.length == 0) {
        if (outError) *outError = @"script_missing_path";
        return NO;
    }

    NSString *candidate = [raw hasPrefix:@"/"] ? raw : [kTLinkScriptsRootPath stringByAppendingPathComponent:raw];
    NSString *path = TLinkNormalizePath(candidate);
    if (!TLinkPathIsInside(path, kTLinkScriptsRootPath)) {
        if (outError) *outError = @"script_path_outside_scripts_root";
        return NO;
    }

    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        if (outError) *outError = [NSString stringWithFormat:@"script_not_found path=%@", path];
        return NO;
    }

    NSString *bundlePath = isDir ? path : [path stringByDeletingLastPathComponent];
    NSString *entryPath = nil;
    if (isDir) {
        NSString *entry = TLinkScriptEntryFromMetadata(bundlePath);
        if ([entry hasPrefix:@"/"]) {
            if (outError) *outError = @"script_entry_must_be_relative";
            return NO;
        }
        entryPath = TLinkNormalizePath([bundlePath stringByAppendingPathComponent:entry]);
    } else {
        entryPath = path;
    }

    if (!TLinkPathIsInside(entryPath, bundlePath)) {
        if (outError) *outError = @"script_entry_outside_bundle";
        return NO;
    }
    if (![[entryPath pathExtension].lowercaseString isEqualToString:@"js"]) {
        if (outError) *outError = @"script_entry_must_be_js";
        return NO;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:entryPath]) {
        if (outError) *outError = [NSString stringWithFormat:@"script_entry_not_found path=%@", entryPath];
        return NO;
    }

    if (outBundlePath) *outBundlePath = bundlePath;
    if (outEntryPath) *outEntryPath = entryPath;
    return YES;
}

static NSString *TLinkRequestedScriptPathFromBody(NSString *body)
{
    NSString *raw = TLinkCleanPayload(body);
    if (raw.length == 0) return @"";
    NSString *candidate = [raw hasPrefix:@"/"] ? raw : [kTLinkScriptsRootPath stringByAppendingPathComponent:raw];
    return TLinkNormalizePath(candidate);
}

static NSDictionary *TLinkScriptPlaySettingsForPath(NSString *requestedPath, NSString *bundlePath)
{
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:kTLinkScriptPlayConfigPath];
    NSDictionary *individual = [root[@"individual_configs"] isKindOfClass:[NSDictionary class]] ? root[@"individual_configs"] : nil;
    if (!individual) return @{};
    NSDictionary *settings = [individual[requestedPath ?: @""] isKindOfClass:[NSDictionary class]] ? individual[requestedPath ?: @""] : nil;
    if (!settings && bundlePath.length > 0) {
        settings = [individual[bundlePath] isKindOfClass:[NSDictionary class]] ? individual[bundlePath] : nil;
    }
    return settings ?: @{};
}

static NSInteger TLinkPlaySettingInteger(NSDictionary *settings, NSString *key, NSInteger defaultValue, NSInteger maxValue)
{
    id value = settings[key];
    NSInteger result = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : defaultValue;
    if (result < 0) result = 0;
    if (maxValue > 0 && result > maxValue) result = maxValue;
    return result;
}

static double TLinkPlaySettingDouble(NSDictionary *settings, NSString *key, double defaultValue, double maxValue)
{
    id value = settings[key];
    double result = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : defaultValue;
    if (result < 0.0) result = 0.0;
    if (maxValue > 0.0 && result > maxValue) result = maxValue;
    return result;
}

static BOOL TLinkSleepForScriptInterval(TLinkScriptSession *session, double seconds)
{
    if (seconds <= 0.0) return !TLinkScriptStopRequested(session);
    uint64_t deadline = TLinkNowMs() + (uint64_t)(seconds * 1000.0);
    while (TLinkNowMs() < deadline) {
        if (TLinkScriptStopRequested(session)) return NO;
        uint64_t now = TLinkNowMs();
        uint64_t remainingMs = deadline > now ? deadline - now : 0;
        useconds_t sleepUs = (useconds_t)MIN((uint64_t)100000, remainingMs * 1000);
        if (sleepUs == 0) break;
        usleep(sleepUs);
    }
    return !TLinkScriptStopRequested(session);
}

static double TLinkScriptEffectiveSpeed(TLinkScriptSession *session)
{
    if (!session) return 1.0;
    @synchronized (session) {
        return session.speed > 0.0 ? session.speed : 1.0;
    }
}

static NSString *TLinkScriptStoragePath(TLinkScriptSession *session, NSString *relativePath, BOOL writing, NSString **error)
{
    if (!session || relativePath.length == 0) {
        if (error) *error = @"storage_missing_path";
        return nil;
    }
    if ([relativePath hasPrefix:@"/"]) {
        if (error) *error = @"storage_path_must_be_relative";
        return nil;
    }
    if ([relativePath rangeOfString:@"\0"].location != NSNotFound) {
        if (error) *error = @"storage_path_contains_nul";
        return nil;
    }
    NSString *target = TLinkNormalizePath([session.bundlePath stringByAppendingPathComponent:relativePath]);
    if (!TLinkPathIsInside(target, session.bundlePath)) {
        if (error) *error = @"storage_path_outside_bundle";
        return nil;
    }
    if (writing) {
        NSArray<NSString *> *protectedNames = @[@"manifest.json", @"info.plist"];
        if ([protectedNames containsObject:[target lastPathComponent]] ||
            [[[target pathExtension] lowercaseString] isEqualToString:@"js"]) {
            if (error) *error = @"storage_path_is_protected";
            return nil;
        }
    }
    return target;
}

static NSString *TLinkScriptRunTask(int taskType, NSString *body)
{
    if (taskType == 10) {
        TLinkRecordLegacyTouchIndicatorEvents(body ?: @"", @"script-task10");
        POCPerformTouchFromRawData((const unsigned char *)[(body ?: @"") UTF8String]);
        return @"0";
    }
    NSString *line = [NSString stringWithFormat:@"%02d%@", taskType, body ?: @""];
    NSData *response = TLinkHandleTaskLine([line UTF8String]);
    return TLinkResponseStringFromData(response);
}

static int TLinkScriptHardwareKeyType(NSString *key)
{
    NSString *normalized = [[key ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([normalized isEqualToString:@"home"]) return HID_KEY_HOME;
    if ([normalized isEqualToString:@"volume-up"] || [normalized isEqualToString:@"vol-up"]) return HID_KEY_VOLUME_UP;
    if ([normalized isEqualToString:@"volume-down"] || [normalized isEqualToString:@"vol-down"]) return HID_KEY_VOLUME_DOWN;
    if ([normalized isEqualToString:@"lock"] || [normalized isEqualToString:@"power"]) return HID_KEY_LOCK;
    return 0;
}

static int TLinkScriptHardwareKeyAction(NSString *action)
{
    NSString *normalized = [[action ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([normalized isEqualToString:@"down"]) return HID_KEY_ACTION_DOWN;
    if ([normalized isEqualToString:@"up"]) return HID_KEY_ACTION_UP;
    return -1;
}

static void TLinkConfigureScriptContext(JSContext *context, TLinkScriptSession *session)
{
    __weak TLinkScriptSession *weakSession = session;
    JSValue *console = [JSValue valueWithNewObjectInContext:context];
    console[@"log"] = ^(JSValue *value) {
        TLinkScriptSession *strongSession = weakSession;
        TLinkScriptAppendLog(strongSession, [value toString] ?: @"");
    };
    console[@"error"] = ^(JSValue *value) {
        TLinkScriptSession *strongSession = weakSession;
        TLinkScriptAppendLog(strongSession, [NSString stringWithFormat:@"ERROR %@", [value toString] ?: @""]);
    };
    context[@"console"] = console;

    JSValue *device = [JSValue valueWithNewObjectInContext:context];
    device[@"log"] = ^(JSValue *value) {
        TLinkScriptAppendLog(weakSession, [value toString] ?: @"");
    };
    device[@"toast"] = ^NSDictionary *(JSValue *message, JSValue *options) {
        NSString *text = [message toString] ?: @"";
        TLinkScriptAppendLog(weakSession, [NSString stringWithFormat:@"toast: %@", text]);
        NSDictionary *opts = nil;
        if (options && ![options isUndefined] && ![options isNull]) {
            id obj = [options toObject];
            if ([obj isKindOfClass:[NSDictionary class]]) opts = obj;
        }
        double duration = opts[@"duration"] ? [opts[@"duration"] doubleValue] : 2.0;
        int type = opts[@"type"] ? [opts[@"type"] intValue] : 0;
        int position = opts[@"position"] ? [opts[@"position"] intValue] : 2;
        int fontSize = opts[@"fontSize"] ? [opts[@"fontSize"] intValue] : 15;
        NSNumber *allowScreenshotValue = opts[@"allow_screenshot"] ?: opts[@"allowScreenshot"];
        BOOL allowScreenshot = allowScreenshotValue ? allowScreenshotValue.boolValue : NO;
        uint64_t eventId = TLinkRecordToastWithOptions(text, duration, type, position, fontSize,
                                                       allowScreenshot, @"script");
        return @{@"ok": @YES, @"mode": @"foreground_or_background_uiservice_positioned_with_cf_fallback", @"event_id": @(eventId)};
    };
    device[@"alert"] = ^NSDictionary *(JSValue *titleValue, JSValue *messageValue, JSValue *options) {
        NSString *title = titleValue && ![titleValue isUndefined] && ![titleValue isNull] ? [titleValue toString] : @"TLinkauto";
        NSString *message = messageValue && ![messageValue isUndefined] && ![messageValue isNull] ? [messageValue toString] : @"";
        NSDictionary *opts = nil;
        if (options && ![options isUndefined] && ![options isNull]) {
            id obj = [options toObject];
            if ([obj isKindOfClass:[NSDictionary class]]) opts = obj;
        }
        double duration = 0.0;
        if (opts[@"duration"]) {
            duration = [opts[@"duration"] doubleValue];
        } else if (options && ![options isUndefined] && ![options isNull]) {
            duration = [options toDouble];
        }
        TLinkScriptAppendLog(weakSession, [NSString stringWithFormat:@"alert: %@", message]);
        uint64_t eventId = TLinkRecordAlert(title, message, duration, @"script");
        return @{@"ok": @(eventId > 0), @"mode": @"foreground_overlay_or_background_cfusernotification", @"event_id": @(eventId)};
    };
    device[@"dialog"] = ^NSDictionary *(JSValue *options) {
        NSDictionary *opts = nil;
        if (options && ![options isUndefined] && ![options isNull]) {
            id obj = [options toObject];
            if ([obj isKindOfClass:[NSDictionary class]]) opts = obj;
        }
        NSString *title = [opts[@"title"] isKindOfClass:[NSString class]] ? opts[@"title"] : @"TLinkauto";
        NSString *message = [opts[@"message"] isKindOfClass:[NSString class]] ? opts[@"message"] : @"";
        NSString *okTitle = [opts[@"ok"] isKindOfClass:[NSString class]] ? opts[@"ok"] : @"OK";
        NSString *cancelTitle = [opts[@"cancel"] isKindOfClass:[NSString class]] ? opts[@"cancel"] : @"Cancel";
        sTLinkLastDialogValue = @"0";
        TLinkScriptAppendLog(weakSession, [NSString stringWithFormat:@"dialog: %@", message]);
        uint64_t eventId = TLinkRecordDialog(title, message, okTitle, cancelTitle, @"script");
        return @{
            @"ok": @(eventId > 0),
            @"response": sTLinkLastDialogValue ?: @"0",
            @"mode": @"foreground_overlay_or_background_cfusernotification_alert",
            @"event_id": @(eventId),
        };
    };
    device[@"clearDialogValues"] = ^NSDictionary *{
        sTLinkLastDialogValue = @"";
        return @{@"ok": @YES};
    };
    device[@"shouldStop"] = ^BOOL {
        return TLinkScriptStopRequested(weakSession);
    };
    device[@"sleep"] = ^NSDictionary *(double seconds) {
        TLinkScriptSession *strongSession = weakSession;
        double speed = TLinkScriptEffectiveSpeed(strongSession);
        int requestedMs = (int)llround(MAX(0.0, seconds) * 1000.0);
        int totalMs = (int)llround((double)requestedMs / speed);
        int sleptMs = 0;
        while (sleptMs < totalMs && !TLinkScriptStopRequested(strongSession)) {
            int chunk = MIN(100, totalMs - sleptMs);
            usleep((useconds_t)chunk * 1000);
            sleptMs += chunk;
        }
        return @{@"ok": @(!TLinkScriptStopRequested(strongSession)), @"requested_ms": @(requestedMs), @"slept_ms": @(sleptMs), @"speed": @(speed)};
    };
    device[@"usleep"] = ^NSDictionary *(double microseconds) {
        TLinkScriptSession *strongSession = weakSession;
        double speed = TLinkScriptEffectiveSpeed(strongSession);
        int requestedUs = (int)llround(MAX(0.0, microseconds));
        int totalUs = (int)llround((double)requestedUs / speed);
        int sleptUs = 0;
        while (sleptUs < totalUs && !TLinkScriptStopRequested(strongSession)) {
            int chunk = MIN(100000, totalUs - sleptUs);
            usleep((useconds_t)chunk);
            sleptUs += chunk;
        }
        return @{@"ok": @(!TLinkScriptStopRequested(strongSession)), @"requested_us": @(requestedUs), @"slept_us": @(sleptUs), @"speed": @(speed)};
    };
    device[@"task"] = ^NSString *(double task, JSValue *bodyValue) {
        TLinkScriptSession *strongSession = weakSession;
        if (TLinkScriptStopRequested(strongSession)) return @"-1;;script_stop_requested";
        NSString *body = bodyValue && ![bodyValue isUndefined] && ![bodyValue isNull] ? [bodyValue toString] : @"";
        return TLinkScriptRunTask((int)task, body);
    };
    device[@"taskResult"] = ^NSDictionary *(double task, JSValue *bodyValue) {
        TLinkScriptSession *strongSession = weakSession;
        if (TLinkScriptStopRequested(strongSession)) return TLinkScriptStoppedResult();
        NSString *body = bodyValue && ![bodyValue isUndefined] && ![bodyValue isNull] ? [bodyValue toString] : @"";
        return TLinkScriptTaskResult(strongSession, (int)task, body);
    };
    device[@"runTask"] = ^NSDictionary *(double task, JSValue *bodyValue) {
        TLinkScriptSession *strongSession = weakSession;
        if (TLinkScriptStopRequested(strongSession)) return TLinkScriptStoppedResult();
        NSString *body = bodyValue && ![bodyValue isUndefined] && ![bodyValue isNull] ? [bodyValue toString] : @"";
        return TLinkScriptTaskResult(strongSession, (int)task, body);
    };
    device[@"hardwareKey"] = ^NSDictionary *(NSString *key, NSString *action) {
        TLinkScriptSession *strongSession = weakSession;
        if (TLinkScriptStopRequested(strongSession)) {
            return @{@"ok": @NO, @"code": @-1, @"payload": @"script_stop_requested", @"raw": @"-1;;script_stop_requested"};
        }
        int keyType = TLinkScriptHardwareKeyType(key);
        int keyAction = TLinkScriptHardwareKeyAction(action);
        if (keyType <= 0 || keyAction < 0) {
            return @{@"ok": @NO, @"code": @-1, @"payload": @"hardwareKey supports key home/volume-up/volume-down/lock and action down/up"};
        }
        NSString *raw = TLinkScriptRunTask(30, [NSString stringWithFormat:@"%d;;%d", keyAction, keyType]);
        return TLinkTaskResultFromResponseString(raw);
    };
    device[@"pressHardwareKey"] = ^NSDictionary *(NSString *key) {
        TLinkScriptSession *strongSession = weakSession;
        if (TLinkScriptStopRequested(strongSession)) {
            return @{@"ok": @NO, @"code": @-1, @"payload": @"script_stop_requested", @"raw": @"-1;;script_stop_requested"};
        }
        int keyType = TLinkScriptHardwareKeyType(key);
        if (keyType <= 0) {
            return @{@"ok": @NO, @"code": @-1, @"payload": @"pressHardwareKey supports key home/volume-up/volume-down/lock"};
        }
        NSString *down = TLinkScriptRunTask(30, [NSString stringWithFormat:@"%d;;%d", HID_KEY_ACTION_DOWN, keyType]);
        NSDictionary *downResult = TLinkTaskResultFromResponseString(down);
        if (![downResult[@"ok"] boolValue]) return downResult;
        usleep(80000);
        NSString *up = TLinkScriptRunTask(30, [NSString stringWithFormat:@"%d;;%d", HID_KEY_ACTION_UP, keyType]);
        NSMutableDictionary *result = [TLinkTaskResultFromResponseString(up) mutableCopy];
        result[@"down"] = downResult;
        return result;
    };
    device[@"tapMacro"] = ^NSDictionary *(double x, double y, JSValue *options) {
        TLinkScriptSession *strongSession = weakSession;
        if (TLinkScriptStopRequested(strongSession)) {
            return @{@"ok": @NO, @"code": @-1, @"payload": @"script_stop_requested", @"raw": @"-1;;script_stop_requested"};
        }
        NSDictionary *opts = nil;
        if (options && ![options isUndefined] && ![options isNull]) {
            id obj = [options toObject];
            if ([obj isKindOfClass:[NSDictionary class]]) opts = obj;
        }
        int count = opts[@"count"] ? [opts[@"count"] intValue] : 10;
        int intervalMs = opts[@"intervalMs"] ? [opts[@"intervalMs"] intValue] : 80;
        int durationMs = opts[@"durationMs"] ? [opts[@"durationMs"] intValue] : 20;
        int finger = opts[@"finger"] ? [opts[@"finger"] intValue] : 0;
        int task = opts[@"mode"] && [[opts[@"mode"] description] isEqualToString:@"crazy"] ? 16 : 17;
        NSString *body = [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d;;%d",
                          (int)x,
                          (int)y,
                          count,
                          intervalMs,
                          durationMs,
                          finger];
        return TLinkTaskResultFromResponseString(TLinkScriptRunTask(task, body));
    };
    device[@"stopTapMacro"] = ^NSDictionary *{
        return TLinkTaskResultFromResponseString(TLinkScriptRunTask(17, @"stop"));
    };
    device[@"pickColor"] = ^NSDictionary *(double x, double y) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 23, [NSString stringWithFormat:@"%d;;%d", (int)x, (int)y]);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 3) return result;
        return TLinkScriptResultByAdding(result, @{
            @"red": @([parts[0] intValue]),
            @"green": @([parts[1] intValue]),
            @"blue": @([parts[2] intValue]),
        });
    };
    device[@"tap"] = ^NSDictionary *(double x, double y) {
        return TLinkScriptTaskResult(weakSession, 62, [NSString stringWithFormat:@"%.0f;;%.0f", x, y]);
    };
    device[@"swipe"] = ^NSDictionary *(double x1, double y1, double x2, double y2, double duration) {
        int durationMs = duration > 20.0 ? (int)llround(duration) : (int)llround(MAX(0.0, duration) * 1000.0);
        return TLinkScriptTaskResult(weakSession, 63, [NSString stringWithFormat:@"%.0f;;%.0f;;%.0f;;%.0f;;%d", x1, y1, x2, y2, durationMs]);
    };
    device[@"longPress"] = ^NSDictionary *(double x, double y, double duration) {
        int durationMs = duration > 20.0 ? (int)llround(duration) : (int)llround(MAX(0.0, duration) * 1000.0);
        return TLinkScriptTaskResult(weakSession, 62, [NSString stringWithFormat:@"%.0f;;%.0f;;%d", x, y, durationMs]);
    };
    device[@"gesture"] = ^NSDictionary *(JSValue *pointsValue, JSValue *optionsValue) {
        NSArray *points = TLinkScriptArrayFromJSValue(pointsValue);
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *err = nil;
        NSString *pointList = TLinkScriptPointList(points, NO, &err);
        if (!pointList) return @{@"ok": @NO, @"code": @-1, @"error": err ?: @"invalid_gesture_points"};
        int finger = TLinkScriptIntOption(opts, @"finger", 0);
        int durationMs = TLinkScriptIntOption(opts, @"durationMs", (int)llround(TLinkScriptDoubleOption(opts, @"duration", 0.3) * 1000.0));
        return TLinkScriptTaskResult(weakSession, 64, [NSString stringWithFormat:@"%d;;%d;;%@", finger, durationMs, pointList]);
    };
    device[@"zoom"] = ^NSDictionary *(double centerX, double centerY, double startRadius, double endRadius, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        int durationMs = TLinkScriptIntOption(opts, @"durationMs", 300);
        int fingerCount = TLinkScriptIntOption(opts, @"fingerCount", 2);
        int steps = TLinkScriptIntOption(opts, @"steps", 20);
        double angleDegrees = TLinkScriptDoubleOption(opts, @"angleDegrees", 0.0);
        int baseFinger = TLinkScriptIntOption(opts, @"baseFinger", 0);
        NSString *payload = [NSString stringWithFormat:@"zoom;;%.2f;;%.2f;;%.2f;;%.2f;;%d;;%d;;%d;;%.2f;;%d",
                             centerX, centerY, startRadius, endRadius, durationMs,
                             fingerCount, steps, angleDegrees, baseFinger];
        return TLinkScriptTaskResult(weakSession, 64, payload);
    };
    device[@"batch"] = ^NSDictionary *(JSValue *commandsValue) {
        NSArray *commands = TLinkScriptArrayFromJSValue(commandsValue);
        if (![commands isKindOfClass:[NSArray class]] || commands.count == 0) {
            return @{@"ok": @NO, @"code": @-1, @"error": @"batch requires non-empty command array"};
        }
        NSMutableArray<NSString *> *wire = [NSMutableArray array];
        for (id command in commands) {
            if ([command isKindOfClass:[NSString class]]) {
                [wire addObject:command];
                continue;
            }
            if (![command isKindOfClass:[NSDictionary class]]) {
                return @{@"ok": @NO, @"code": @-1, @"error": @"batch commands must be strings or objects"};
            }
            NSDictionary *dict = (NSDictionary *)command;
            id rawType = dict[@"type"];
            if (!rawType || rawType == (id)kCFNull) rawType = dict[@"kind"];
            if (!rawType || rawType == (id)kCFNull) rawType = @"tap";
            NSString *type = [[rawType description] lowercaseString];
            if ([type isEqualToString:@"tap"]) {
                [wire addObject:[NSString stringWithFormat:@"62%.0f;;%.0f;;%d",
                                 [dict[@"x"] doubleValue],
                                 [dict[@"y"] doubleValue],
                                 TLinkScriptIntOption(dict, @"durationMs", 50)]];
            } else if ([type isEqualToString:@"swipe"]) {
                [wire addObject:[NSString stringWithFormat:@"63%.0f;;%.0f;;%.0f;;%.0f;;%d",
                                 [dict[@"x1"] doubleValue],
                                 [dict[@"y1"] doubleValue],
                                 [dict[@"x2"] doubleValue],
                                 [dict[@"y2"] doubleValue],
                                 TLinkScriptIntOption(dict, @"durationMs", 300)]];
            } else {
                return @{@"ok": @NO, @"code": @-1, @"error": [NSString stringWithFormat:@"unsupported_batch_command %@", type]};
            }
        }
        return TLinkScriptTaskResult(weakSession, 65, [wire componentsJoinedByString:@"||"]);
    };
    device[@"defaultScreenshotPath"] = ^NSString *{
        return TLinkScriptDefaultScreenshotPath(weakSession);
    };
    device[@"screenshotTo"] = ^NSDictionary *(NSString *path) {
        NSString *target = path.length > 0 ? path : TLinkScriptDefaultScreenshotPath(weakSession);
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 29, [NSString stringWithFormat:@"1;;%@", target]);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        return TLinkScriptResultByAdding(result, @{@"path": parts.count > 0 ? parts[0] : target});
    };
    device[@"screenshot"] = ^NSDictionary *{
        NSString *target = TLinkScriptDefaultScreenshotPath(weakSession);
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 29, [NSString stringWithFormat:@"1;;%@", target]);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        return TLinkScriptResultByAdding(result, @{@"path": parts.count > 0 ? parts[0] : target});
    };
    device[@"screenshotRegion"] = ^NSDictionary *(NSString *path, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *target = path.length > 0 ? path : TLinkScriptDefaultScreenshotPath(weakSession);
        NSString *body = [NSString stringWithFormat:@"1;;%@;;%.0f;;%.0f;;%.0f;;%.0f",
                          target,
                          TLinkScriptDoubleOption(opts, @"x", 0),
                          TLinkScriptDoubleOption(opts, @"y", 0),
                          TLinkScriptDoubleOption(opts, @"width", 0),
                          TLinkScriptDoubleOption(opts, @"height", 0)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 29, body);
        return TLinkScriptResultByAdding(result, @{@"path": target});
    };
    device[@"saveScreenshotToAlbum"] = ^NSDictionary *(NSString *path) {
        return TLinkScriptTaskResult(weakSession, 29, [NSString stringWithFormat:@"2;;%@", path ?: @""]);
    };
    device[@"clearScreenshotAlbum"] = ^NSDictionary *{
        return TLinkScriptTaskResult(weakSession, 29, @"3");
    };
    device[@"captureFrame"] = ^NSDictionary *(JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *body = [NSString stringWithFormat:@"%d;;%d;;%d",
                          TLinkScriptIntOption(opts, @"gray", 1),
                          TLinkScriptIntOption(opts, @"bgra", 1),
                          TLinkScriptIntOption(opts, @"ttlMs", 1000)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 66, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 14) return result;
        return TLinkScriptResultByAdding(result, @{
            @"id": @([parts[0] intValue]),
            @"width": @([parts[1] intValue]),
            @"height": @([parts[2] intValue]),
            @"bytesPerRow": @([parts[3] intValue]),
            @"scale": @([parts[4] doubleValue]),
            @"coord": parts[5] ?: @"pixel",
            @"format": parts[6] ?: @"RGBA",
            @"hasBGRA": @([parts[7] intValue] != 0),
            @"hasGray": @([parts[8] intValue] != 0),
            @"createdAtMs": @([parts[9] longLongValue]),
            @"captureMs": @([parts[10] doubleValue]),
            @"bgraMs": @([parts[11] doubleValue]),
            @"totalMs": @([parts[13] doubleValue]),
        });
    };
    device[@"releaseFrame"] = ^NSDictionary *(double frameId) {
        return TLinkScriptTaskResult(weakSession, 67, [NSString stringWithFormat:@"%d", (int)frameId]);
    };
    device[@"releaseAllFrames"] = ^NSDictionary *{
        return TLinkScriptTaskResult(weakSession, 67, @"all");
    };
    device[@"framePickColor"] = ^NSDictionary *(double frameId, double x, double y, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *body = [NSString stringWithFormat:@"%d;;pick;;%.0f;;%.0f;;%@;;%d",
                          (int)frameId,
                          x,
                          y,
                          TLinkScriptStringOption(opts, @"coord", @"pixel"),
                          TLinkScriptIntOption(opts, @"maxAgeMs", 1000)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 69, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 6) return result;
        return TLinkScriptResultByAdding(result, @{
            @"red": @([parts[0] intValue]),
            @"green": @([parts[1] intValue]),
            @"blue": @([parts[2] intValue]),
            @"ageMs": @([parts[3] longLongValue]),
            @"totalMs": @([parts[5] doubleValue]),
        });
    };
    device[@"framePickColors"] = ^NSDictionary *(double frameId, JSValue *pointsValue, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *err = nil;
        NSString *pointList = TLinkScriptPointList(TLinkScriptArrayFromJSValue(pointsValue), NO, &err);
        if (!pointList) return @{@"ok": @NO, @"code": @-1, @"error": err ?: @"invalid_points"};
        NSString *body = [NSString stringWithFormat:@"%d;;pick_many;;%@;;%@;;%d",
                          (int)frameId,
                          pointList,
                          TLinkScriptStringOption(opts, @"coord", @"pixel"),
                          TLinkScriptIntOption(opts, @"maxAgeMs", 1000)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 69, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 4) return result;
        NSMutableArray *colors = [NSMutableArray array];
        for (NSString *item in [parts[0] componentsSeparatedByString:@"|"]) {
            NSArray<NSString *> *fields = [item componentsSeparatedByString:@","];
            if (fields.count == 5) {
                [colors addObject:@{@"x": @([fields[0] intValue]), @"y": @([fields[1] intValue]), @"red": @([fields[2] intValue]), @"green": @([fields[3] intValue]), @"blue": @([fields[4] intValue])}];
            }
        }
        return TLinkScriptResultByAdding(result, @{@"colors": colors, @"ageMs": @([parts[1] longLongValue]), @"totalMs": @([parts[3] doubleValue])});
    };
    device[@"frameFindColor"] = ^NSDictionary *(double frameId, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *body = [NSString stringWithFormat:@"%d;;search_single;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d;;%@;;%d",
                          (int)frameId,
                          TLinkScriptDoubleOption(opts, @"x", 0),
                          TLinkScriptDoubleOption(opts, @"y", 0),
                          TLinkScriptDoubleOption(opts, @"width", 0),
                          TLinkScriptDoubleOption(opts, @"height", 0),
                          TLinkScriptIntOption(opts, @"redMin", TLinkScriptIntOption(opts, @"rMin", 0)),
                          TLinkScriptIntOption(opts, @"redMax", TLinkScriptIntOption(opts, @"rMax", 255)),
                          TLinkScriptIntOption(opts, @"greenMin", TLinkScriptIntOption(opts, @"gMin", 0)),
                          TLinkScriptIntOption(opts, @"greenMax", TLinkScriptIntOption(opts, @"gMax", 255)),
                          TLinkScriptIntOption(opts, @"blueMin", TLinkScriptIntOption(opts, @"bMin", 0)),
                          TLinkScriptIntOption(opts, @"blueMax", TLinkScriptIntOption(opts, @"bMax", 255)),
                          TLinkScriptIntOption(opts, @"skip", 0),
                          TLinkScriptStringOption(opts, @"coord", @"pixel"),
                          TLinkScriptIntOption(opts, @"maxAgeMs", 1000)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 69, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 8) return result;
        int foundX = [parts[0] intValue], foundY = [parts[1] intValue];
        return TLinkScriptResultByAdding(result, @{@"matched": @(foundX >= 0 && foundY >= 0), @"x": @(foundX), @"y": @(foundY), @"red": @([parts[2] intValue]), @"green": @([parts[3] intValue]), @"blue": @([parts[4] intValue]), @"ageMs": @([parts[5] longLongValue]), @"totalMs": @([parts[7] doubleValue])});
    };
    device[@"frameIsColors"] = ^NSDictionary *(double frameId, JSValue *pointsValue, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *err = nil;
        NSString *table = TLinkScriptPointList(TLinkScriptArrayFromJSValue(pointsValue), YES, &err);
        if (!table) return @{@"ok": @NO, @"code": @-1, @"error": err ?: @"invalid_point_colors"};
        NSString *body = [NSString stringWithFormat:@"%d;;is_colors;;%@;;%d;;%.4f;;%@;;%d",
                          (int)frameId,
                          table,
                          TLinkScriptIntOption(opts, @"mode", 1),
                          TLinkScriptDoubleOption(opts, @"value", TLinkScriptDoubleOption(opts, @"tolerance", 0)),
                          TLinkScriptStringOption(opts, @"coord", @"pixel"),
                          TLinkScriptIntOption(opts, @"maxAgeMs", 1000)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 69, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 4) return result;
        BOOL matched = [parts[0] intValue] != 0;
        return TLinkScriptResultByAdding(result, @{@"matched": @(matched), @"value": @(matched), @"ageMs": @([parts[1] longLongValue]), @"totalMs": @([parts[3] doubleValue])});
    };
    device[@"frameFindMultiColor"] = ^NSDictionary *(double frameId, JSValue *pointsValue, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *err = nil;
        NSString *table = TLinkScriptPointList(TLinkScriptArrayFromJSValue(pointsValue), YES, &err);
        if (!table) return @{@"ok": @NO, @"code": @-1, @"error": err ?: @"invalid_point_colors"};
        NSString *body = [NSString stringWithFormat:@"%d;;find_multi_point;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%.4f;;%d;;%@;;%d",
                          (int)frameId,
                          TLinkScriptDoubleOption(opts, @"x", 0),
                          TLinkScriptDoubleOption(opts, @"y", 0),
                          TLinkScriptDoubleOption(opts, @"width", 0),
                          TLinkScriptDoubleOption(opts, @"height", 0),
                          table,
                          TLinkScriptIntOption(opts, @"mode", 1),
                          TLinkScriptDoubleOption(opts, @"value", TLinkScriptDoubleOption(opts, @"tolerance", 0)),
                          TLinkScriptIntOption(opts, @"skip", 0),
                          TLinkScriptStringOption(opts, @"coord", @"pixel"),
                          TLinkScriptIntOption(opts, @"maxAgeMs", 1000)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 69, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 5) return result;
        int foundX = [parts[0] intValue], foundY = [parts[1] intValue];
        return TLinkScriptResultByAdding(result, @{@"matched": @(foundX >= 0 && foundY >= 0), @"x": @(foundX), @"y": @(foundY), @"ageMs": @([parts[2] longLongValue]), @"totalMs": @([parts[4] doubleValue])});
    };
    device[@"findColor"] = ^NSDictionary *(JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *body = [NSString stringWithFormat:@"1;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d",
                          TLinkScriptDoubleOption(opts, @"x", 0),
                          TLinkScriptDoubleOption(opts, @"y", 0),
                          TLinkScriptDoubleOption(opts, @"width", 0),
                          TLinkScriptDoubleOption(opts, @"height", 0),
                          TLinkScriptIntOption(opts, @"redMin", TLinkScriptIntOption(opts, @"rMin", 0)),
                          TLinkScriptIntOption(opts, @"redMax", TLinkScriptIntOption(opts, @"rMax", 255)),
                          TLinkScriptIntOption(opts, @"greenMin", TLinkScriptIntOption(opts, @"gMin", 0)),
                          TLinkScriptIntOption(opts, @"greenMax", TLinkScriptIntOption(opts, @"gMax", 255)),
                          TLinkScriptIntOption(opts, @"blueMin", TLinkScriptIntOption(opts, @"bMin", 0)),
                          TLinkScriptIntOption(opts, @"blueMax", TLinkScriptIntOption(opts, @"bMax", 255)),
                          TLinkScriptIntOption(opts, @"skip", 0)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 28, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 5) return result;
        int foundX = [parts[0] intValue], foundY = [parts[1] intValue];
        return TLinkScriptResultByAdding(result, @{@"matched": @(foundX >= 0 && foundY >= 0), @"x": @(foundX), @"y": @(foundY), @"red": @([parts[2] intValue]), @"green": @([parts[3] intValue]), @"blue": @([parts[4] intValue])});
    };
    device[@"isColors"] = ^NSDictionary *(JSValue *pointsValue, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *err = nil;
        NSString *table = TLinkScriptPointList(TLinkScriptArrayFromJSValue(pointsValue), YES, &err);
        if (!table) return @{@"ok": @NO, @"code": @-1, @"error": err ?: @"invalid_point_colors"};
        NSString *body = [NSString stringWithFormat:@"2;;%@;;%d;;%.4f", table, TLinkScriptIntOption(opts, @"mode", 1), TLinkScriptDoubleOption(opts, @"value", TLinkScriptDoubleOption(opts, @"tolerance", 0))];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 28, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        BOOL matched = [parts[0] intValue] != 0;
        return TLinkScriptResultByAdding(result, @{@"matched": @(matched), @"value": @(matched)});
    };
    device[@"findMultiColor"] = ^NSDictionary *(JSValue *pointsValue, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *err = nil;
        NSString *table = TLinkScriptPointList(TLinkScriptArrayFromJSValue(pointsValue), YES, &err);
        if (!table) return @{@"ok": @NO, @"code": @-1, @"error": err ?: @"invalid_point_colors"};
        NSString *body = [NSString stringWithFormat:@"3;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%.4f;;%d",
                          TLinkScriptDoubleOption(opts, @"x", 0),
                          TLinkScriptDoubleOption(opts, @"y", 0),
                          TLinkScriptDoubleOption(opts, @"width", 0),
                          TLinkScriptDoubleOption(opts, @"height", 0),
                          table,
                          TLinkScriptIntOption(opts, @"mode", 1),
                          TLinkScriptDoubleOption(opts, @"value", TLinkScriptDoubleOption(opts, @"tolerance", 0)),
                          TLinkScriptIntOption(opts, @"skip", 0)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 28, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 2) return result;
        int foundX = [parts[0] intValue], foundY = [parts[1] intValue];
        return TLinkScriptResultByAdding(result, @{@"matched": @(foundX >= 0 && foundY >= 0), @"x": @(foundX), @"y": @(foundY)});
    };
    device[@"openImage"] = ^NSDictionary *(NSString *path) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 48, [NSString stringWithFormat:@"2;;%@", path ?: @""]);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 3) return result;
        return TLinkScriptResultByAdding(result, @{@"id": @([parts[0] intValue]), @"width": @([parts[1] intValue]), @"height": @([parts[2] intValue])});
    };
    device[@"captureImage"] = ^NSDictionary *(double x, double y, double width, double height) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 48, [NSString stringWithFormat:@"1;;%.0f;;%.0f;;%.0f;;%.0f", x, y, width, height]);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 3) return result;
        return TLinkScriptResultByAdding(result, @{@"id": @([parts[0] intValue]), @"width": @([parts[1] intValue]), @"height": @([parts[2] intValue])});
    };
    device[@"releaseImage"] = ^NSDictionary *(double imageId) {
        return TLinkScriptTaskResult(weakSession, 48, [NSString stringWithFormat:@"3;;%d", (int)imageId]);
    };
    device[@"findImageInFrame"] = ^NSDictionary *(double frameId, double imageId, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *body = [NSString stringWithFormat:@"%d;;%d;;%.0f;;%.0f;;%.0f;;%.0f;;%.4f;;%.4f;;%.4f;;%.4f;;%d;;%@;;%d",
                          (int)frameId,
                          (int)imageId,
                          TLinkScriptDoubleOption(opts, @"x", 0),
                          TLinkScriptDoubleOption(opts, @"y", 0),
                          TLinkScriptDoubleOption(opts, @"width", 0),
                          TLinkScriptDoubleOption(opts, @"height", 0),
                          TLinkScriptDoubleOption(opts, @"acceptable", 0.95),
                          TLinkScriptDoubleOption(opts, @"scaleMin", 1.0),
                          TLinkScriptDoubleOption(opts, @"scaleMax", 1.0),
                          TLinkScriptDoubleOption(opts, @"scaleStep", 1.0),
                          TLinkScriptIntOption(opts, @"pixelSkip", 0),
                          TLinkScriptStringOption(opts, @"coord", @"pixel"),
                          TLinkScriptIntOption(opts, @"maxAgeMs", 1000)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 68, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 11) return result;
        int matchX = [parts[0] intValue], matchY = [parts[1] intValue];
        return TLinkScriptResultByAdding(result, @{@"matched": @(matchX >= 0 && matchY >= 0), @"x": @(matchX), @"y": @(matchY), @"width": @([parts[2] intValue]), @"height": @([parts[3] intValue]), @"centerX": @([parts[4] doubleValue]), @"centerY": @([parts[5] doubleValue]), @"score": @([parts[6] doubleValue]), @"ageMs": @([parts[7] longLongValue]), @"totalMs": @([parts[10] doubleValue])});
    };
    device[@"matchTemplate"] = ^NSDictionary *(NSString *path, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 21, [NSString stringWithFormat:@"%@;;0;;%.4f", path ?: @"", TLinkScriptDoubleOption(opts, @"acceptable", TLinkScriptDoubleOption(opts, @"threshold", 0.8))]);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 4) return result;
        int matchX = [parts[0] intValue], matchY = [parts[1] intValue];
        return TLinkScriptResultByAdding(result, @{@"matched": @(matchX >= 0 && matchY >= 0), @"x": @(matchX), @"y": @(matchY), @"width": @([parts[2] intValue]), @"height": @([parts[3] intValue])});
    };
    device[@"ocrLanguages"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 91, @"check_langs");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 2) return result;
        NSString *langsText = TLinkScriptBase64Decode(parts[1]);
        return TLinkScriptResultByAdding(result, @{@"languages": langsText.length > 0 ? [langsText componentsSeparatedByString:@","] : @[], @"value": langsText ?: @""});
    };
    device[@"ocrFrame"] = ^NSDictionary *(double frameId, JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSString *whitelist = TLinkScriptStringOption(opts, @"whitelist", @"");
        NSString *body = [NSString stringWithFormat:@"%d;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%d;;%@;;%d;;%d;;%@;;%d",
                          (int)frameId,
                          TLinkScriptDoubleOption(opts, @"x", 0),
                          TLinkScriptDoubleOption(opts, @"y", 0),
                          TLinkScriptDoubleOption(opts, @"width", 0),
                          TLinkScriptDoubleOption(opts, @"height", 0),
                          TLinkScriptStringOption(opts, @"lang", @"eng"),
                          TLinkScriptIntOption(opts, @"oem", 1),
                          TLinkScriptIntOption(opts, @"psm", 7),
                          TLinkScriptBase64Encode(whitelist),
                          TLinkScriptIntOption(opts, @"scaleUp", 2),
                          TLinkScriptIntOption(opts, @"thresholdMode", 0),
                          TLinkScriptStringOption(opts, @"coord", @"pixel"),
                          TLinkScriptIntOption(opts, @"maxAgeMs", 1000)];
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 91, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 6) return result;
        NSMutableDictionary *extra = [@{
            @"text": TLinkScriptBase64Decode(parts[0]),
            @"confidence": @([parts[1] doubleValue]),
            @"ageMs": @([parts[2] longLongValue]),
            @"ocrMs": @([parts[3] doubleValue]),
            @"preprocessMs": @([parts[4] doubleValue]),
            @"totalMs": @([parts[5] doubleValue]),
        } mutableCopy];
        if (parts.count >= 7) extra[@"initSource"] = parts[6];
        return TLinkScriptResultByAdding(result, extra);
    };
    device[@"ocr"] = ^NSDictionary *(JSValue *optionsValue) {
        NSDictionary *opts = TLinkScriptDictionaryFromJSValue(optionsValue) ?: @{};
        NSDictionary *frame = TLinkScriptTaskResult(weakSession, 66, [NSString stringWithFormat:@"1;;0;;%d", TLinkScriptIntOption(opts, @"ttlMs", 1000)]);
        NSArray<NSString *> *frameParts = TLinkScriptResultParts(frame);
        if (![frame[@"ok"] boolValue] || frameParts.count < 1) return frame;
        int frameId = [frameParts[0] intValue];
        NSString *whitelist = TLinkScriptStringOption(opts, @"whitelist", @"");
        NSString *body = [NSString stringWithFormat:@"%d;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%d;;%@;;%d;;%d;;%@;;%d",
                          frameId,
                          TLinkScriptDoubleOption(opts, @"x", 0),
                          TLinkScriptDoubleOption(opts, @"y", 0),
                          TLinkScriptDoubleOption(opts, @"width", 0),
                          TLinkScriptDoubleOption(opts, @"height", 0),
                          TLinkScriptStringOption(opts, @"lang", @"eng"),
                          TLinkScriptIntOption(opts, @"oem", 1),
                          TLinkScriptIntOption(opts, @"psm", 7),
                          TLinkScriptBase64Encode(whitelist),
                          TLinkScriptIntOption(opts, @"scaleUp", 2),
                          TLinkScriptIntOption(opts, @"thresholdMode", 0),
                          TLinkScriptStringOption(opts, @"coord", @"pixel"),
                          TLinkScriptIntOption(opts, @"maxAgeMs", 1000)];
        NSDictionary *ocrResult = TLinkScriptTaskResult(weakSession, 91, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(ocrResult);
        if ([ocrResult[@"ok"] boolValue] && parts.count >= 6) {
            NSMutableDictionary *extra = [@{
                @"text": TLinkScriptBase64Decode(parts[0]),
                @"confidence": @([parts[1] doubleValue]),
                @"ageMs": @([parts[2] longLongValue]),
                @"ocrMs": @([parts[3] doubleValue]),
                @"preprocessMs": @([parts[4] doubleValue]),
                @"totalMs": @([parts[5] doubleValue]),
            } mutableCopy];
            if (parts.count >= 7) extra[@"initSource"] = parts[6];
            ocrResult = TLinkScriptResultByAdding(ocrResult, extra);
        }
        TLinkScriptTaskResult(weakSession, 67, [NSString stringWithFormat:@"%d", frameId]);
        return ocrResult;
    };
    device[@"frontMostAppId"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 34, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"bundleId": parts[0] ?: @""});
    };
    device[@"orientation"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 35, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"value": @([parts[0] intValue])});
    };
    device[@"openApp"] = ^NSDictionary *(NSString *bundleId) {
        return TLinkScriptTaskResult(weakSession, 11, bundleId ?: @"");
    };
    device[@"killApp"] = ^NSDictionary *(NSString *bundleId) {
        return TLinkScriptTaskResult(weakSession, 31, bundleId ?: @"");
    };
    device[@"clearAppData"] = ^NSDictionary *(NSString *bundleId) {
        return TLinkScriptTaskResult(weakSession, 72, bundleId ?: @"");
    };
    device[@"appState"] = ^NSDictionary *(NSString *bundleId) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 32, bundleId ?: @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        int state = [parts[0] intValue];
        return TLinkScriptResultByAdding(result, @{@"state": @(state), @"running": @(state > 0)});
    };
    device[@"appInfo"] = ^NSDictionary *(NSString *bundleId) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 33, bundleId ?: @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 5) return result;
        return TLinkScriptResultByAdding(result, @{@"bundleId": parts[0] ?: @"", @"name": parts[1] ?: @"", @"shortVersion": parts[2] ?: @"", @"bundleVersion": parts[3] ?: @"", @"state": @([parts[4] intValue])});
    };
    device[@"appPid"] = ^NSDictionary *(NSString *bundleId) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 50, bundleId ?: @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"pid": @([parts[0] intValue])});
    };
    device[@"frontMostPid"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 51, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"pid": @([parts[0] intValue])});
    };
    device[@"appPaths"] = ^NSDictionary *(NSString *bundleId) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 52, bundleId ?: @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"bundlePath": parts[0] ?: @"", @"dataPath": parts.count > 1 ? parts[1] : @""});
    };
    device[@"listBundles"] = ^NSDictionary *(BOOL withInfo) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 53, withInfo ? @"1" : @"0");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        if (withInfo) {
            NSData *decoded = [[NSData alloc] initWithBase64EncodedString:parts[0] options:0];
            id json = decoded ? [NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil] : nil;
            NSDictionary *jsonDict = [json isKindOfClass:[NSDictionary class]] ? (NSDictionary *)json : nil;
            NSArray *items = [jsonDict[@"items"] isKindOfClass:[NSArray class]] ? jsonDict[@"items"] : @[];
            return TLinkScriptResultByAdding(result, @{@"items": items});
        }
        return TLinkScriptResultByAdding(result, @{@"bundleIds": parts[0].length > 0 ? [parts[0] componentsSeparatedByString:@",,"] : @[]});
    };
    device[@"openUrl"] = ^NSDictionary *(NSString *url) {
        return TLinkScriptTaskResult(weakSession, 54, url ?: @"");
    };
    device[@"keyboardTask"] = ^NSDictionary *(double kind, NSString *content) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 24, [NSString stringWithFormat:@"%d;;%@", (int)kind, content ?: @""]);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if ((int)kind == 6 && [result[@"ok"] boolValue]) {
            return TLinkScriptResultByAdding(result, @{@"text": parts.count > 0 ? parts[0] : @""});
        }
        return result;
    };
    device[@"getClipboardText"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 24, @"6");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        return TLinkScriptResultByAdding(result, @{@"text": parts.count > 0 ? parts[0] : @""});
    };
    device[@"setClipboardText"] = ^NSDictionary *(NSString *text) {
        return TLinkScriptTaskResult(weakSession, 24, [NSString stringWithFormat:@"7;;%@", text ?: @""]);
    };
    device[@"insertText"] = ^NSDictionary *(NSString *text) {
        return TLinkScriptTaskResult(weakSession, 24, [NSString stringWithFormat:@"1;;%@", text ?: @""]);
    };
    device[@"showKeyboard"] = ^NSDictionary *{
        return TLinkScriptTaskResult(weakSession, 24, @"2;;2");
    };
    device[@"hideKeyboard"] = ^NSDictionary *{
        return TLinkScriptTaskResult(weakSession, 24, @"2;;1");
    };
    device[@"pasteFromClipboard"] = ^NSDictionary *{
        return TLinkScriptTaskResult(weakSession, 24, @"5");
    };
    device[@"setClipboardImage"] = ^NSDictionary *(NSString *path) {
        return TLinkScriptTaskResult(weakSession, 24, [NSString stringWithFormat:@"8;;file;;%@", path ?: @""]);
    };
    device[@"deleteCharacters"] = ^NSDictionary *(double count) {
        int value = (int)llround(MAX(1.0, MIN(1024.0, count)));
        return TLinkScriptTaskResult(weakSession, 24, [NSString stringWithFormat:@"4;;%d", value]);
    };
    device[@"moveCursor"] = ^NSDictionary *(double offset) {
        int value = (int)llround(MAX(-1024.0, MIN(1024.0, offset)));
        return TLinkScriptTaskResult(weakSession, 24, [NSString stringWithFormat:@"3;;%d", value]);
    };
    device[@"runShell"] = ^NSDictionary *(NSString *command, double timeoutSeconds) {
        int timeout = timeoutSeconds > 0 ? (int)llround(timeoutSeconds) : 10;
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 71, [NSString stringWithFormat:@"%d;;%@", timeout, command ?: @""]);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 2) return result;
        return TLinkScriptResultByAdding(result, @{@"exitCode": @([parts[0] intValue]), @"output": TLinkScriptBase64Decode(parts[1])});
    };
    device[@"pathTask"] = ^NSDictionary *(double task, NSString *key) {
        NSDictionary *result = TLinkScriptTaskResult(weakSession, (int)task, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        NSMutableDictionary *extra = [@{@"path": parts[0] ?: @""} mutableCopy];
        extra[key.length > 0 ? key : @"value"] = parts[0] ?: @"";
        return TLinkScriptResultByAdding(result, extra);
    };
    device[@"rootDir"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 44, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        return [result[@"ok"] boolValue] && parts.count > 0 ? TLinkScriptResultByAdding(result, @{@"path": parts[0], @"rootDir": parts[0]}) : result;
    };
    device[@"currentDir"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 45, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        return [result[@"ok"] boolValue] && parts.count > 0 ? TLinkScriptResultByAdding(result, @{@"path": parts[0], @"currentDir": parts[0]}) : result;
    };
    device[@"botPath"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 46, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        return [result[@"ok"] boolValue] && parts.count > 0 ? TLinkScriptResultByAdding(result, @{@"path": parts[0], @"botPath": parts[0]}) : result;
    };
    device[@"info"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 25, @"30");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 5) return result;
        return TLinkScriptResultByAdding(result, @{@"name": parts[0] ?: @"", @"systemName": parts[1] ?: @"", @"systemVersion": parts[2] ?: @"", @"model": parts[3] ?: @"", @"identifierForVendor": parts[4] ?: @""});
    };
    device[@"batteryInfo"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 25, @"31");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 2) return result;
        return TLinkScriptResultByAdding(result, @{@"state": @([parts[0] intValue]), @"level": @([parts[1] doubleValue])});
    };
    device[@"getScreenSize"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 25, @"1");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 2) return result;
        return TLinkScriptResultByAdding(result, @{@"width": @([parts[0] doubleValue]), @"height": @([parts[1] doubleValue])});
    };
    device[@"touchIndicator"] = ^NSDictionary *(NSString *action) {
        NSString *lower = (action ?: @"toggle").lowercaseString;
        int value = [lower isEqualToString:@"on"] || [lower isEqualToString:@"show"] || [lower isEqualToString:@"1"] ? 1 :
                    ([lower isEqualToString:@"off"] || [lower isEqualToString:@"hide"] || [lower isEqualToString:@"0"] ? 0 : 2);
        return TLinkScriptTaskResult(weakSession, 26, [NSString stringWithFormat:@"%d", value]);
    };
    device[@"keepAwake"] = ^NSDictionary *(BOOL enabled) {
        return TLinkScriptTaskResult(weakSession, 40, enabled ? @"1" : @"0");
    };
    device[@"setAutoLaunch"] = ^NSDictionary *(NSString *name, NSString *script, BOOL enabled) {
        return TLinkScriptTaskResult(weakSession, 36, [NSString stringWithFormat:@"%@;;%@;;%d", name ?: @"", script ?: @"", enabled ? 1 : 0]);
    };
    device[@"listAutoLaunch"] = ^NSDictionary *{
        return TLinkScriptTaskResult(weakSession, 37, @"");
    };
    device[@"setTimer"] = ^NSDictionary *(NSString *name, double interval, BOOL repeat, NSString *script) {
        return TLinkScriptTaskResult(weakSession, 38, [NSString stringWithFormat:@"%@;;%.3f;;%d;;%@", name ?: @"", interval, repeat ? 1 : 0, script ?: @""]);
    };
    device[@"removeTimer"] = ^NSDictionary *(NSString *name) {
        return TLinkScriptTaskResult(weakSession, 39, name ?: @"");
    };
    device[@"connectivityTask"] = ^NSDictionary *(double task, NSString *enabledKey, JSValue *value) {
        NSString *body = @"";
        if (value && ![value isUndefined] && ![value isNull]) body = [value toBool] ? @"1" : @"0";
        NSDictionary *result = TLinkScriptTaskResult(weakSession, (int)task, body);
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        NSMutableDictionary *extra = [NSMutableDictionary dictionary];
        extra[enabledKey.length > 0 ? enabledKey : @"enabled"] = @([parts[0] intValue] != 0);
        return TLinkScriptResultByAdding(result, extra);
    };
    device[@"wifi"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 55, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"enabled": @([parts[0] intValue] != 0)});
    };
    device[@"setWifi"] = ^NSDictionary *(BOOL enabled) { return TLinkScriptTaskResult(weakSession, 55, enabled ? @"1" : @"0"); };
    device[@"bluetooth"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 56, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"enabled": @([parts[0] intValue] != 0)});
    };
    device[@"setBluetooth"] = ^NSDictionary *(BOOL enabled) { return TLinkScriptTaskResult(weakSession, 56, enabled ? @"1" : @"0"); };
    device[@"airplaneMode"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 57, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"enabled": @([parts[0] intValue] != 0)});
    };
    device[@"setAirplaneMode"] = ^NSDictionary *(BOOL enabled) { return TLinkScriptTaskResult(weakSession, 57, enabled ? @"1" : @"0"); };
    device[@"cellularData"] = ^NSDictionary *{
        NSDictionary *result = TLinkScriptTaskResult(weakSession, 58, @"");
        NSArray<NSString *> *parts = TLinkScriptResultParts(result);
        if (![result[@"ok"] boolValue] || parts.count < 1) return result;
        return TLinkScriptResultByAdding(result, @{@"enabled": @([parts[0] intValue] != 0)});
    };
    device[@"setCellularData"] = ^NSDictionary *(BOOL enabled) { return TLinkScriptTaskResult(weakSession, 58, enabled ? @"1" : @"0"); };
    device[@"runtimeInfo"] = ^NSDictionary *{
        TLinkScriptSession *strongSession = weakSession;
        if (!strongSession) return @{};
        @synchronized (strongSession) {
            return @{
                @"runtime": @"javascriptcore",
                @"runtimeLocation": @"streamd",
                @"fileHandleAPI": @YES,
                @"smartWaitAPI": @YES,
                @"smartWaitVersion": @1,
                @"smartWaitSchema": @"smart_wait_result_v1",
                @"fileHandleModes": @[@"r", @"rb", @"r+", @"rb+", @"w", @"wb", @"w+", @"wb+", @"a", @"ab", @"a+", @"ab+"],
                @"maxOpenFiles": @(kTLinkScriptMaxOpenFiles),
                @"maxFileTransferBytes": @(kTLinkScriptMaxFileTransferBytes),
                @"sessionId": strongSession.sessionId ?: @"",
                @"bundlePath": strongSession.bundlePath ?: @"",
                @"entryPath": strongSession.entryPath ?: @"",
                @"state": strongSession.state ?: @"",
                @"currentRun": @(strongSession.currentRun),
                @"totalRuns": @(strongSession.totalRuns),
                @"playSettings": @{
                    @"repeatTimes": @(strongSession.repeatTimes),
                    @"interval": @(strongSession.intervalSeconds),
                    @"speed": @(strongSession.speed),
                },
                @"stopRequested": @(strongSession.stopRequested),
            };
        }
    };
    device[@"readText"] = ^NSDictionary *(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, NO, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        NSError *readErr = nil;
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readErr];
        if (!text) {
            NSString *message = readErr.localizedDescription ?: @"read_failed";
            return @{@"ok": @NO, @"error": message, @"path": path};
        }
        return @{@"ok": @YES, @"path": path, @"text": text};
    };
    device[@"writeText"] = ^NSDictionary *(NSString *relativePath, NSString *text) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, YES, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        NSString *parent = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *writeErr = nil;
        NSString *safeText = text ?: @"";
        BOOL ok = [safeText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
        NSUInteger byteCount = [[safeText dataUsingEncoding:NSUTF8StringEncoding] length];
        return ok ? @{@"ok": @YES, @"path": path, @"bytes": @(byteCount)} : @{@"ok": @NO, @"path": path, @"error": writeErr.localizedDescription ?: @"write_failed"};
    };
    device[@"openFile"] = ^JSValue *(NSString *relativePath, NSString *mode) {
        JSContext *currentContext = [JSContext currentContext] ?: context;
        TLinkScriptSession *strongSession = weakSession;
        NSString *openMode = mode.length > 0 ? mode : @"r";
        if (!strongSession) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"script_session_unavailable"} inContext:currentContext];
        }
        if (!TLinkJSFileModeIsValid(openMode)) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"invalid_file_mode", @"mode": openMode} inContext:currentContext];
        }
        BOOL writing = TLinkJSFileModeWrites(openMode);
        NSString *pathError = nil;
        NSString *path = TLinkScriptStoragePath(strongSession, relativePath, writing, &pathError);
        if (!path) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": pathError ?: @"storage_path_error", @"path": relativePath ?: @""} inContext:currentContext];
        }
        if (writing) {
            NSError *mkdirError = nil;
            NSString *parent = [path stringByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] createDirectoryAtPath:parent
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&mkdirError]) {
                return [JSValue valueWithObject:@{@"ok": @NO, @"error": mkdirError.localizedDescription ?: @"create_parent_failed", @"path": path} inContext:currentContext];
            }
        }

        __block NSUInteger handleId = 0;
        @synchronized (strongSession) {
            if (!strongSession.fileHandles) strongSession.fileHandles = [NSMutableDictionary dictionary];
            if (strongSession.fileHandles.count >= kTLinkScriptMaxOpenFiles) {
                return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"too_many_open_files", @"limit": @(kTLinkScriptMaxOpenFiles)} inContext:currentContext];
            }
            handleId = strongSession.nextFileHandleId++;
        }
        NSString *openError = nil;
        TLinkJSFileHandle *handle = [TLinkJSFileHandle openPath:path
                                                          mode:openMode
                                                      handleId:handleId
                                              maxTransferBytes:kTLinkScriptMaxFileTransferBytes
                                                         error:&openError];
        if (!handle) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": openError ?: @"file_open_failed", @"path": path, @"mode": openMode} inContext:currentContext];
        }
        @synchronized (strongSession) {
            strongSession.fileHandles[@(handleId)] = handle;
        }
        __weak TLinkScriptSession *closeSession = strongSession;
        return TLinkJSFileHandleCreateJSObject(currentContext, handle, ^(NSUInteger closedId) {
            TLinkScriptSession *sessionForClose = closeSession;
            if (!sessionForClose) return;
            @synchronized (sessionForClose) {
                [sessionForClose.fileHandles removeObjectForKey:@(closedId)];
            }
        });
    };
    device[@"fileExists"] = ^NSDictionary *(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, NO, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @"", @"exists": @NO};
        BOOL isDir = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
        return @{@"ok": @YES, @"path": path, @"exists": @(exists), @"directory": @(exists && isDir)};
    };
    device[@"deleteFile"] = ^NSDictionary *(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, YES, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return @{@"ok": @YES, @"path": path, @"deleted": @NO};
        }
        NSError *deleteErr = nil;
        BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&deleteErr];
        if (ok || deleteErr.code == NSFileNoSuchFileError) return @{@"ok": @YES, @"path": path, @"deleted": @YES};
        return @{@"ok": @NO, @"path": path, @"error": deleteErr.localizedDescription ?: @"delete_failed"};
    };
    device[@"readJSON"] = ^NSDictionary *(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, NO, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length == 0) return @{@"ok": @NO, @"path": path, @"error": @"read_failed"};
        NSError *jsonErr = nil;
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (!object) return @{@"ok": @NO, @"path": path, @"error": jsonErr.localizedDescription ?: @"json_parse_failed"};
        return @{@"ok": @YES, @"path": path, @"value": object};
    };
    device[@"writeJSON"] = ^NSDictionary *(NSString *relativePath, JSValue *value) {
        id object = [value toObject];
        if (!object || ![NSJSONSerialization isValidJSONObject:object]) {
            return @{@"ok": @NO, @"error": @"invalid_json_object"};
        }
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, YES, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        NSString *parent = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *jsonErr = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&jsonErr];
        if (!data) return @{@"ok": @NO, @"path": path, @"error": jsonErr.localizedDescription ?: @"json_encode_failed"};
        BOOL ok = [data writeToFile:path atomically:YES];
        return ok ? @{@"ok": @YES, @"path": path, @"bytes": @(data.length)} : @{@"ok": @NO, @"path": path, @"error": @"write_json_failed"};
    };
    context[@"device"] = device;
    [context evaluateScript:TLinkSmartWaitPreludeSource()
              withSourceURL:[NSURL URLWithString:@"tlinkauto://smart-wait-v1.js"]];
}

static NSDictionary *TLinkScriptStatusDictionary(void)
{
    TLinkScriptSession *session = sTLinkScriptSession;
    if (!session) {
        return @{
            @"is_playing": @(NO),
            @"bundle_path": kTLinkScriptsRootPath,
            @"session_id": @"",
            @"state": @"idle",
            @"last_error": sTLinkLastScriptError ?: @"",
            @"last_error_ts": @(sTLinkLastScriptErrorTs),
            @"log_tail": @[],
        };
    }
    @synchronized (session) {
        BOOL active = TLinkScriptIsActive(session);
        NSUInteger start = session.logs.count > 20 ? session.logs.count - 20 : 0;
        NSArray *tail = session.logs.count > 0 ? [session.logs subarrayWithRange:NSMakeRange(start, session.logs.count - start)] : @[];
        return @{
            @"is_playing": @(active),
            @"bundle_path": kTLinkScriptsRootPath,
            @"session_id": session.sessionId ?: @"",
            @"state": session.state ?: @"idle",
            @"entry_path": session.entryPath ?: @"",
            @"started_at_ms": @(session.startedAtMs),
            @"ended_at_ms": @(session.endedAtMs),
            @"current_run": @(session.currentRun),
            @"total_runs": @(session.totalRuns),
            @"play_settings": @{
                @"repeat_times": @(session.repeatTimes),
                @"interval": @(session.intervalSeconds),
                @"speed": @(session.speed),
            },
            @"last_error": session.lastError.length > 0 ? session.lastError : (sTLinkLastScriptError ?: @""),
            @"license_revoked": @(session.licenseRevoked),
            @"license_revocation_error": session.licenseRevocationError ?: @"",
            @"last_license_check_at_ms": @(session.lastLicenseCheckAtMs),
            @"last_error_ts": @(sTLinkLastScriptErrorTs),
            @"log_tail": tail,
        };
    }
}

static void TLinkRunScriptSession(TLinkScriptSession *session)
{
    @autoreleasepool {
        @synchronized (session) {
            if (session.stopRequested) {
                session.state = @"stopping";
            } else {
                session.state = @"running";
            }
        }
        if (TLinkScriptStopRequested(session)) {
            TLinkScriptAppendLog(session, @"cancelled before start");
            TLinkScriptMarkTerminal(session, @"cancelled", @"");
            return;
        }
        NSInteger totalRuns = session.totalRuns > 0 ? session.totalRuns : 1;
        TLinkScriptAppendLog(session, [NSString stringWithFormat:@"start %@ repeat=%ld interval=%.3f speed=%.3f", session.entryPath, (long)session.repeatTimes, session.intervalSeconds, session.speed]);

        for (NSInteger run = 1; run <= totalRuns; run++) {
            if (TLinkScriptStopRequested(session)) {
                TLinkScriptAppendLog(session, @"cancelled");
                TLinkScriptMarkTerminal(session, @"cancelled", @"");
                return;
            }

            @synchronized (session) {
                session.currentRun = run;
                session.state = @"running";
            }
            TLinkScriptAppendLog(session, [NSString stringWithFormat:@"run %ld/%ld", (long)run, (long)totalRuns]);

            NSError *readErr = nil;
            NSString *source = [NSString stringWithContentsOfFile:session.entryPath encoding:NSUTF8StringEncoding error:&readErr];
            if (!source) {
                TLinkScriptMarkTerminal(session, @"failed", [NSString stringWithFormat:@"script_read_failed %@", readErr.localizedDescription ?: @"unknown"]);
                return;
            }

            JSContext *context = [[JSContext alloc] init];
            __block NSString *exceptionText = nil;
            context.exceptionHandler = ^(__unused JSContext *ctx, JSValue *exception) {
                exceptionText = [exception toString] ?: @"javascript_exception";
            };
            TLinkConfigureScriptContext(context, session);
            [context evaluateScript:source withSourceURL:[NSURL fileURLWithPath:session.entryPath]];
            TLinkScriptCloseOpenFiles(session);

            if (exceptionText.length > 0) {
                TLinkScriptAppendLog(session, [NSString stringWithFormat:@"exception %@", exceptionText]);
                TLinkScriptMarkTerminal(session, @"failed", exceptionText);
                return;
            }
            if (TLinkScriptStopRequested(session)) {
                TLinkScriptAppendLog(session, @"cancelled");
                TLinkScriptMarkTerminal(session, @"cancelled", @"");
                return;
            }
            TLinkScriptAppendLog(session, [NSString stringWithFormat:@"run %ld/%ld finished", (long)run, (long)totalRuns]);

            if (run < totalRuns && session.intervalSeconds > 0.0) {
                TLinkScriptAppendLog(session, [NSString stringWithFormat:@"interval %.3fs", session.intervalSeconds]);
                if (!TLinkSleepForScriptInterval(session, session.intervalSeconds)) {
                    TLinkScriptAppendLog(session, @"cancelled during interval");
                    TLinkScriptMarkTerminal(session, @"cancelled", @"");
                    return;
                }
            }
        }
        TLinkScriptAppendLog(session, @"finished");
        TLinkScriptMarkTerminal(session, @"finished", @"");
    }
}

static NSData *TLinkHandlePlayScript(NSString *body)
{
    NSString *licenseError = nil;
    if (!TLinkLicenseFeatureAllowed(@"script", &licenseError)) {
        NSDictionary *status = TLinkLicenseStatusDictionary();
        return TLinkError([NSString stringWithFormat:@"license_required component=script_runtime feature=script state=%@ error=%@",
                           status[@"state"] ?: @"invalid",
                           licenseError ?: status[@"error"] ?: @"license_required"]);
    }

    NSString *bundlePath = nil;
    NSString *entryPath = nil;
    NSString *error = nil;
    if (!TLinkResolveScriptPaths(body, &bundlePath, &entryPath, &error)) {
        sTLinkLastScriptError = error ?: @"script_resolve_failed";
        sTLinkLastScriptErrorTs = TLinkNowMs();
        return TLinkError(sTLinkLastScriptError);
    }

    if (TLinkScriptIsActive(sTLinkScriptSession)) {
        return TLinkError([NSString stringWithFormat:@"script_already_playing session=%@", sTLinkScriptSession.sessionId ?: @""]);
    }

    NSString *requestedPath = TLinkRequestedScriptPathFromBody(body);
    NSDictionary *playSettings = TLinkScriptPlaySettingsForPath(requestedPath, bundlePath);
    NSInteger repeatTimes = TLinkPlaySettingInteger(playSettings, @"repeat_times", 0, 10000);
    double intervalSeconds = TLinkPlaySettingDouble(playSettings, @"interval", 0.0, 86400.0);
    double speed = TLinkPlaySettingDouble(playSettings, @"speed", 1.0, 100.0);
    if (speed <= 0.0) speed = 1.0;

    TLinkScriptSession *session = [[TLinkScriptSession alloc] init];
    session.sessionId = [NSString stringWithFormat:@"%llu", sTLinkNextScriptSessionId++];
    session.bundlePath = bundlePath;
    session.entryPath = entryPath;
    session.state = @"starting";
    session.startedAtMs = TLinkNowMs();
    session.endedAtMs = 0;
    session.repeatTimes = repeatTimes;
    session.totalRuns = repeatTimes + 1;
    session.currentRun = 0;
    session.intervalSeconds = intervalSeconds;
    session.speed = speed;
    session.stopRequested = NO;
    session.licenseRevoked = NO;
    session.lastLicenseCheckAtMs = TLinkNowMs();
    session.licenseRevocationError = @"";
    session.logs = [NSMutableArray array];
    session.fileHandles = [NSMutableDictionary dictionary];
    session.nextFileHandleId = 1;
    NSDictionary *historyRecord = TLinkRunHistoryBegin(@"trollstore",
                                                        bundlePath,
                                                        entryPath,
                                                        @{
                                                            @"repeat_times": @(repeatTimes),
                                                            @"interval": @(intervalSeconds),
                                                            @"speed": @(speed),
                                                        });
    session.historyRunId = historyRecord[@"run_id"] ?: @"";
    sTLinkScriptSession = session;
    sTLinkLastScriptError = @"";
    sTLinkLastScriptErrorTs = 0;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        TLinkRunScriptSession(session);
    });
    TLinkStartScriptLicenseHeartbeat(session);

    return TLinkSuccess([NSString stringWithFormat:@"script_started;;%@;;%@;;repeat=%ld;;interval=%.3f", session.sessionId, entryPath, (long)repeatTimes, intervalSeconds]);
}

static NSData *TLinkHandleStopScript(NSString *body)
{
    (void)body;
    TLinkScriptSession *session = sTLinkScriptSession;
    if (!TLinkScriptIsActive(session)) {
        return TLinkSuccess(@"no_script_playing");
    }
    @synchronized (session) {
        session.stopRequested = YES;
        session.state = @"stopping";
    }
    TLinkScriptAppendLog(session, @"stop requested");
    return TLinkSuccess([NSString stringWithFormat:@"script_stopping;;%@", session.sessionId ?: @""]);
}

static NSData *TLinkHandleClearScriptLog(NSString *body)
{
    (void)body;
    TLinkScriptSession *session = sTLinkScriptSession;
    if (!session) {
        return TLinkSuccess(@"script_log_cleared;;0;;no_session");
    }
    NSUInteger cleared = 0;
    @synchronized (session) {
        cleared = session.logs.count;
        [session.logs removeAllObjects];
    }
    return TLinkSuccess([NSString stringWithFormat:@"script_log_cleared;;%lu",
                         (unsigned long)cleared]);
}

static NSData *TLinkHandleToast(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int type = parts.count >= 1 ? [parts[0] intValue] : 0;
    NSString *message = parts.count >= 2 ? parts[1] : TLinkCleanPayload(body);
    double duration = parts.count >= 3 ? [parts[2] doubleValue] : 2.0;
    int position = parts.count >= 4 ? [parts[3] intValue] : 2;
    int fontSize = parts.count >= 5 ? [parts[4] intValue] : 15;
    BOOL allowScreenshot = parts.count >= 6 ? [parts[5] boolValue] : NO;
    uint64_t eventId = TLinkRecordToastWithOptions(message, duration, type, position, fontSize,
                                                   allowScreenshot, @"task22");
    if (eventId == 0) return TLinkError(@"toast_missing_message");
    return TLinkSuccess([NSString stringWithFormat:@"toast_queued;;%llu;;foreground_or_background_uiservice_positioned_with_cf_fallback;;requested_position=%d", eventId, position]);
}

static NSData *TLinkHandleAlertBox(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    NSString *title = parts.count >= 1 ? parts[0] : @"TLinkauto";
    NSString *message = parts.count >= 2 ? parts[1] : @"";
    double duration = parts.count >= 3 ? [parts[2] doubleValue] : 0.0;
    uint64_t eventId = TLinkRecordAlert(title, message, duration, @"task12");
    if (eventId == 0) return TLinkError(@"alert_missing_message");
    return TLinkSuccess([NSString stringWithFormat:@"alert_queued;;%llu;;foreground_overlay_or_background_cfusernotification", eventId]);
}

static NSData *TLinkHandleDialog(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    NSString *title = parts.count >= 1 ? parts[0] : @"TLinkauto";
    NSString *message = parts.count >= 2 ? parts[1] : @"";
    NSString *okTitle = parts.count >= 3 ? parts[2] : @"OK";
    NSString *cancelTitle = parts.count >= 4 ? parts[3] : @"Cancel";
    sTLinkLastDialogValue = @"0";
    uint64_t eventId = TLinkRecordDialog(title, message, okTitle, cancelTitle, @"task42");
    if (eventId == 0) return TLinkError(@"dialog_missing_content");
    return TLinkSuccess([NSString stringWithFormat:@"%@;;dialog_queued;;%llu;;foreground_overlay_or_background_cfusernotification_alert", sTLinkLastDialogValue ?: @"0", eventId]);
}

static NSData *TLinkHandleClearDialog(NSString *body)
{
    (void)body;
    sTLinkLastDialogValue = @"";
    return TLinkSuccess(nil);
}

static NSData *TLinkHandleTouchIndicator(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int action = parts.count >= 1 ? [parts[0] intValue] : [TLinkCleanPayload(body) intValue];
    @synchronized (TLinkVisualFeedbackLock()) {
        if (action == 0) {
            sTLinkTouchIndicatorEnabled = NO;
        } else if (action == 1 || action == 2) {
            sTLinkTouchIndicatorEnabled = YES;
        } else {
            return TLinkError([NSString stringWithFormat:@"unknown_touch_indicator_action %d", action]);
        }
    }
    NSString *state = sTLinkTouchIndicatorEnabled ? @"enabled" : @"disabled";
    uint64_t eventId = TLinkRecordToast([NSString stringWithFormat:@"Touch indicator %@", state],
                                        1.2,
                                        0,
                                        2,
                                        14,
                                        @"task26");
    if (action == 2) {
        return TLinkSuccess([NSString stringWithFormat:@"touch_indicator_reloaded;;%@;;%llu", state, eventId]);
    }
    return TLinkSuccess([NSString stringWithFormat:@"touch_indicator_%@;;%llu", state, eventId]);
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
        // Rootfull task payloads use `,,` while the JS compatibility facade
        // historically emitted `,`. Accept both wire representations.
        NSString *separator = [item containsString:@",,"] ? @",," : @",";
        NSArray<NSString *> *parts = [item componentsSeparatedByString:separator];
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
    TLinkRecordTouchIndicator(x, y, type, @"native-touch");
    POCPerformTouchFromRawData((const unsigned char *)[payload UTF8String]);
}

static void TLinkPerformTouchFrame(int type, int baseFinger, const CGPoint *points, int count)
{
    NSMutableString *payload = [NSMutableString stringWithFormat:@"%d", count];
    for (int i = 0; i < count; i++) {
        [payload appendFormat:@"%d%02d%05d%05d",
                              type,
                              baseFinger + i,
                              TLinkClampTouchCoord(points[i].x),
                              TLinkClampTouchCoord(points[i].y)];
        TLinkRecordTouchIndicator(points[i].x, points[i].y, type, @"native-zoom");
    }
    POCPerformTouchFromRawData((const unsigned char *)[payload UTF8String]);
    sTLinkZoomFrameCount.fetch_add(1, std::memory_order_relaxed);
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

static BOOL TLinkTapMacroShouldStop(uint64_t sessionId)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        return !sTLinkTapMacroActive ||
               sTLinkTapMacroSessionId != sessionId ||
               sTLinkTapMacroStopRequested;
    }
}

static NSData *TLinkHandleTapMacro(int taskType, NSString *body)
{
    NSString *raw = [TLinkCleanPayload(body) lowercaseString];
    if ([raw isEqualToString:@"0"] || [raw isEqualToString:@"stop"] || [raw isEqualToString:@"cancel"]) {
        @synchronized (TLinkVisualFeedbackLock()) {
            sTLinkTapMacroStopRequested = YES;
            sTLinkTapMacroLastError = @"stop_requested";
        }
        return TLinkSuccess(@"tap_macro_stop_requested");
    }

    CGSize screen = TLinkScreenPixelSize();
    CGFloat defaultX = screen.width / 2.0;
    CGFloat defaultY = screen.height / 2.0;
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    CGFloat x = parts.count >= 1 && parts[0].length > 0 ? [parts[0] floatValue] : defaultX;
    CGFloat y = parts.count >= 2 && parts[1].length > 0 ? [parts[1] floatValue] : defaultY;
    int count = parts.count >= 3 ? [parts[2] intValue] : (taskType == 16 ? 50 : 10);
    int intervalMs = parts.count >= 4 ? [parts[3] intValue] : (taskType == 16 ? 40 : 80);
    int durationMs = parts.count >= 5 ? [parts[4] intValue] : 20;
    int finger = parts.count >= 6 ? [parts[5] intValue] : 0;
    if (count <= 0) return TLinkError(@"tap_macro_count_must_be_positive");
    if (count > 10000) count = 10000;
    if (intervalMs < 0) intervalMs = 0;
    if (intervalMs > 60000) intervalMs = 60000;
    if (durationMs < 0) durationMs = 0;
    if (durationMs > 5000) durationMs = 5000;

    uint64_t sessionId = 0;
    NSString *mode = taskType == 16 ? @"crazy_tap" : @"rapid_fire_tap";
    @synchronized (TLinkVisualFeedbackLock()) {
        if (sTLinkTapMacroActive) {
            return TLinkError([NSString stringWithFormat:@"tap_macro_already_running session=%llu", sTLinkTapMacroSessionId]);
        }
        sessionId = sTLinkNextTapMacroSessionId++;
        sTLinkTapMacroActive = YES;
        sTLinkTapMacroStopRequested = NO;
        sTLinkTapMacroSessionId = sessionId;
        sTLinkTapMacroCompletedCount = 0;
        sTLinkTapMacroTargetCount = count;
        sTLinkTapMacroMode = mode;
        sTLinkTapMacroLastError = @"";
        sTLinkTapMacroStartedAtMs = TLinkNowMs();
        sTLinkTapMacroEndedAtMs = 0;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSInteger completed = 0;
        for (int i = 0; i < count; i++) {
            if (TLinkTapMacroShouldStop(sessionId)) break;
            TLinkPerformSingleTouch(POC_TOUCH_DOWN, finger, x, y);
            if (durationMs > 0) usleep((useconds_t)durationMs * 1000);
            TLinkPerformSingleTouch(POC_TOUCH_UP, finger, x, y);
            completed++;
            @synchronized (TLinkVisualFeedbackLock()) {
                if (sTLinkTapMacroSessionId == sessionId) {
                    sTLinkTapMacroCompletedCount = completed;
                }
            }
            if (intervalMs > 0 && i < count - 1) {
                usleep((useconds_t)intervalMs * 1000);
            }
        }
        @synchronized (TLinkVisualFeedbackLock()) {
            if (sTLinkTapMacroSessionId == sessionId) {
                sTLinkTapMacroCompletedCount = completed;
                sTLinkTapMacroActive = NO;
                sTLinkTapMacroStopRequested = NO;
                sTLinkTapMacroEndedAtMs = TLinkNowMs();
            }
        }
        TLinkRecordToast([NSString stringWithFormat:@"%@ finished %ld/%d", mode, (long)completed, count],
                         1.5,
                         0,
                         2,
                         14,
                         @"tap-macro");
    });

    return TLinkSuccess([NSString stringWithFormat:@"tap_macro_started;;%@;;session=%llu;;x=%.1f;;y=%.1f;;count=%d;;interval_ms=%d;;duration_ms=%d",
                         mode,
                         sessionId,
                         x,
                         y,
                         count,
                         intervalMs,
                         durationMs]);
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

static BOOL TLinkParseZoomNumber(NSString *text, double *value)
{
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double parsed = 0.0;
    if (![scanner scanDouble:&parsed] || !scanner.isAtEnd || !isfinite(parsed)) return NO;
    if (value) *value = parsed;
    return YES;
}

static BOOL TLinkParseZoomInteger(NSString *text, int *value)
{
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    long long parsed = 0;
    if (![scanner scanLongLong:&parsed] || !scanner.isAtEnd || parsed < INT_MIN || parsed > INT_MAX) return NO;
    if (value) *value = (int)parsed;
    return YES;
}

static BOOL TLinkZoomError(NSString **error, NSString *message)
{
    if ([message hasPrefix:@"zoom_dispatch_exception"]) {
        sTLinkZoomDispatchExceptionCount.fetch_add(1, std::memory_order_relaxed);
        sTLinkZoomLastResult.store(3, std::memory_order_relaxed);
    } else {
        sTLinkZoomValidationRejectedCount.fetch_add(1, std::memory_order_relaxed);
        sTLinkZoomLastResult.store(2, std::memory_order_relaxed);
    }
    if (error) *error = message ?: @"zoom_failed";
    return NO;
}

static void TLinkZoomPoints(CGPoint *points,
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

static BOOL TLinkHandleNativeZoom(NSArray<NSString *> *parts, NSString **error)
{
    sTLinkZoomAttemptCount.fetch_add(1, std::memory_order_relaxed);
    sTLinkZoomLastAtMs.store((uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0), std::memory_order_relaxed);
    sTLinkZoomLastResult.store(0, std::memory_order_relaxed);
    sTLinkZoomLastDirection.store(0, std::memory_order_relaxed);
    sTLinkZoomLastFingerCount.store(0, std::memory_order_relaxed);
    sTLinkZoomLastSteps.store(0, std::memory_order_relaxed);
    sTLinkZoomLastDurationMs.store(0, std::memory_order_relaxed);
    if (parts.count < 8 || parts.count > 10) {
        return TLinkZoomError(error, @"zoom_bad_payload expected=zoom;;center_x;;center_y;;start_radius;;end_radius;;duration_ms;;finger_count;;steps[;;angle_degrees;;base_finger]");
    }

    double centerX = 0.0, centerY = 0.0, startRadius = 0.0, endRadius = 0.0, angleDegrees = 0.0;
    int durationMs = 0, fingerCount = 0, steps = 0, baseFinger = 0;
    if (!TLinkParseZoomNumber(parts[1], &centerX)) return TLinkZoomError(error, @"zoom_invalid_number field=center_x");
    if (!TLinkParseZoomNumber(parts[2], &centerY)) return TLinkZoomError(error, @"zoom_invalid_number field=center_y");
    if (!TLinkParseZoomNumber(parts[3], &startRadius)) return TLinkZoomError(error, @"zoom_invalid_number field=start_radius");
    if (!TLinkParseZoomNumber(parts[4], &endRadius)) return TLinkZoomError(error, @"zoom_invalid_number field=end_radius");
    if (!TLinkParseZoomInteger(parts[5], &durationMs)) return TLinkZoomError(error, @"zoom_invalid_number field=duration_ms");
    if (!TLinkParseZoomInteger(parts[6], &fingerCount)) return TLinkZoomError(error, @"zoom_invalid_number field=finger_count");
    if (!TLinkParseZoomInteger(parts[7], &steps)) return TLinkZoomError(error, @"zoom_invalid_number field=steps");
    if (parts.count >= 9 && !TLinkParseZoomNumber(parts[8], &angleDegrees)) return TLinkZoomError(error, @"zoom_invalid_number field=angle_degrees");
    if (parts.count >= 10 && !TLinkParseZoomInteger(parts[9], &baseFinger)) return TLinkZoomError(error, @"zoom_invalid_number field=base_finger");

    sTLinkZoomLastDirection.store(endRadius > startRadius ? 1 : (endRadius < startRadius ? -1 : 0), std::memory_order_relaxed);
    sTLinkZoomLastFingerCount.store(fingerCount, std::memory_order_relaxed);
    sTLinkZoomLastSteps.store(steps, std::memory_order_relaxed);
    sTLinkZoomLastDurationMs.store(durationMs, std::memory_order_relaxed);

    if (durationMs < 50 || durationMs > 5000) return TLinkZoomError(error, @"zoom_duration_out_of_range min=50 max=5000");
    if (fingerCount != 2 && fingerCount != 3) return TLinkZoomError(error, @"zoom_finger_count_unsupported allowed=2,3");
    if (steps < 2 || steps > 120) return TLinkZoomError(error, @"zoom_steps_out_of_range min=2 max=120");
    if (startRadius <= 0.0 || endRadius <= 0.0) return TLinkZoomError(error, @"zoom_radius_invalid positive_required=1");
    if (startRadius == endRadius) return TLinkZoomError(error, @"zoom_radius_unchanged");
    if (angleDegrees < -360.0 || angleDegrees > 360.0) return TLinkZoomError(error, @"zoom_angle_out_of_range min=-360 max=360");
    if (baseFinger < 0 || baseFinger + fingerCount > 20) return TLinkZoomError(error, @"zoom_finger_range_invalid allowed=0..19");

    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize bounds = [UIScreen mainScreen].bounds.size;
    CGFloat screenWidth = MIN(bounds.width * scale, bounds.height * scale);
    CGFloat screenHeight = MAX(bounds.width * scale, bounds.height * scale);
    if (screenWidth <= 0.0 || screenHeight <= 0.0) return TLinkZoomError(error, @"zoom_screen_unavailable");

    CGPoint points[3];
    for (int step = 0; step < steps; step++) {
        double t = (double)step / (double)(steps - 1);
        double radius = startRadius + (endRadius - startRadius) * t;
        TLinkZoomPoints(points, fingerCount, centerX, centerY, radius, angleDegrees);
        for (int finger = 0; finger < fingerCount; finger++) {
            if (points[finger].x < 0.0 || points[finger].x >= screenWidth ||
                points[finger].y < 0.0 || points[finger].y >= screenHeight) {
                return TLinkZoomError(error, [NSString stringWithFormat:@"zoom_point_out_of_bounds step=%d finger=%d screen=%.0fx%.0f",
                                               step, baseFinger + finger, screenWidth, screenHeight]);
            }
        }
    }

    BOOL fingersDown = NO;
    @try {
        TLinkZoomPoints(points, fingerCount, centerX, centerY, startRadius, angleDegrees);
        TLinkPerformTouchFrame(POC_TOUCH_DOWN, baseFinger, points, fingerCount);
        fingersDown = YES;

        int sleepPerIntervalUs = durationMs * 1000 / (steps - 1);
        for (int step = 1; step < steps; step++) {
            if (sleepPerIntervalUs > 0) usleep((useconds_t)sleepPerIntervalUs);
            double t = (double)step / (double)(steps - 1);
            double radius = startRadius + (endRadius - startRadius) * t;
            TLinkZoomPoints(points, fingerCount, centerX, centerY, radius, angleDegrees);
            TLinkPerformTouchFrame(POC_TOUCH_MOVE, baseFinger, points, fingerCount);
        }
        TLinkPerformTouchFrame(POC_TOUCH_UP, baseFinger, points, fingerCount);
        fingersDown = NO;
    } @catch (__unused NSException *exception) {
        if (fingersDown) {
            sTLinkZoomCleanupCount.fetch_add(1, std::memory_order_relaxed);
            TLinkPerformTouchFrame(POC_TOUCH_UP, baseFinger, points, fingerCount);
        }
        return TLinkZoomError(error, @"zoom_dispatch_exception");
    }
    sTLinkZoomSuccessCount.fetch_add(1, std::memory_order_relaxed);
    sTLinkZoomLastResult.store(1, std::memory_order_relaxed);
    return YES;
}

static BOOL TLinkHandleNativeGesture(NSString *body, NSString **error)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count > 0 &&
        [[parts[0] lowercaseString] isEqualToString:@"zoom"]) {
        return TLinkHandleNativeZoom(parts, error);
    }
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
            TLinkRecordLegacyTouchIndicatorEvents(payload, @"native-batch-task10");
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

static NSData *TLinkHandleHardwareKey(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 2) {
        return TLinkError(@"hardware_key_bad_payload expected=action;;keyType");
    }

    int action = [parts[0] intValue];
    int keyType = [parts[1] intValue];
    HIDInjectResult result = HIDInjectDispatchHardwareKey(action, keyType);
    if (result.errnoValue == EINVAL) {
        return TLinkError([NSString stringWithFormat:@"hardware_key_invalid action=%d keyType=%d", action, keyType]);
    }
    if (!result.clientCreated) {
        return TLinkError([NSString stringWithFormat:@"hardware_key_client_unavailable errno=%d", result.errnoValue]);
    }
    if (!result.eventCreated) {
        return TLinkError([NSString stringWithFormat:@"hardware_key_event_create_failed errno=%d", result.errnoValue]);
    }

    return TLinkSuccess([NSString stringWithFormat:@"hardware_key_dispatched;;action=%d;;keyType=%d;;client=%p;;sender=0x%llx;;errno=%d",
                         action,
                         keyType,
                         result.clientPtr,
                         result.senderID,
                         result.errnoValue]);
}

static NSString *TLinkRecordingReplaySource(NSString *rawFileName)
{
    NSString *safeRaw = TLinkVisualSafeText(rawFileName ?: @"record.raw");
    return [NSString stringWithFormat:
            @"console.log('TLinkauto recording replay started: %@');\n"
             "var rawResult = device.readText('%@');\n"
             "var raw = rawResult && rawResult.ok ? (rawResult.text || '') : '';\n"
             "var lines = raw.split(/\\r?\\n/);\n"
             "for (var i = 0; i < lines.length; i++) {\n"
             "  var line = (lines[i] || '').trim();\n"
             "  if (!line || device.shouldStop()) continue;\n"
             "  if (line.indexOf('18') === 0) {\n"
             "    var us = parseFloat(line.substring(2));\n"
             "    if (!isNaN(us) && us > 0) device.usleep(us);\n"
             "  } else if (line.indexOf('10') === 0) {\n"
             "    device.task(10, line.substring(2));\n"
             "  }\n"
             "}\n"
             "console.log('TLinkauto recording replay finished');\n",
            safeRaw, safeRaw];
}

static void TLinkRecordTouchFromHIDEvent(IOHIDEventRef event)
{
    if (!event || IOHIDEventGetType(event) != kIOHIDEventTypeDigitizer) return;

    IOHIDFloat x = IOHIDEventGetFloatValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerX);
    IOHIDFloat y = IOHIDEventGetFloatValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerY);
    int eventMask = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerEventMask);
    int touch = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerTouch);
    int index = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerIndex);
    int touchType = -1;
    if (touch == 1 && (eventMask & kIOHIDDigitizerEventTouch)) {
        touchType = 1;
    } else if (touch == 1 && (eventMask & kIOHIDDigitizerEventPosition)) {
        touchType = 2;
    } else if (!touch && (eventMask & kIOHIDDigitizerEventTouch)) {
        touchType = 0;
    }
    if (touchType < 0) return;
    if (index < 0) index = 0;
    if (index > 99) index = 99;

    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkRecordingActive || !sTLinkRecordingFileHandle) return;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        double sleepUsec = sTLinkRecordingLastEventTime > 0 ? (now - sTLinkRecordingLastEventTime) * 1000000.0 : 0.0;
        sTLinkRecordingLastEventTime = now;
        double rawX = MAX(0.0, MIN(99999.0, x * sTLinkRecordingScreenWidth * 10.0));
        double rawY = MAX(0.0, MIN(99999.0, y * sTLinkRecordingScreenHeight * 10.0));
        NSString *line = [NSString stringWithFormat:@"18%.0f\n10%d%02d%05.0f%05.0f\n",
                          sleepUsec,
                          touchType,
                          index,
                          rawX,
                          rawY];
        @try {
            [sTLinkRecordingFileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            sTLinkRecordingEventCount++;
        } @catch (NSException *exception) {
            sTLinkRecordingLastError = exception.reason ?: @"recording_write_exception";
        }
    }
}

static void TLinkRecordingHIDCallback(void *target, void *refcon, IOHIDEventQueueRef queue, IOHIDEventRef parentEvent)
{
    (void)target;
    (void)refcon;
    (void)queue;
    if (!parentEvent) return;
    if (IOHIDEventGetType(parentEvent) != kIOHIDEventTypeDigitizer) return;
    CFArrayRef childrenRef = IOHIDEventGetChildren(parentEvent);
    NSArray *children = (__bridge NSArray *)childrenRef;
    if (children.count == 0) {
        TLinkRecordTouchFromHIDEvent(parentEvent);
        return;
    }
    for (id child in children) {
        TLinkRecordTouchFromHIDEvent((__bridge IOHIDEventRef)child);
    }
}

static void TLinkStopRecordingLocked(NSString *reason)
{
    if (sTLinkRecordingClient) {
        IOHIDEventSystemClientUnregisterEventCallback(sTLinkRecordingClient);
        if (sTLinkRecordingRunLoop) {
            IOHIDEventSystemClientUnscheduleWithRunLoop(sTLinkRecordingClient, sTLinkRecordingRunLoop, kCFRunLoopDefaultMode);
        }
        CFRelease(sTLinkRecordingClient);
        sTLinkRecordingClient = NULL;
    }
    if (sTLinkRecordingFileHandle) {
        @try {
            [sTLinkRecordingFileHandle synchronizeFile];
            [sTLinkRecordingFileHandle closeFile];
        } @catch (__unused NSException *exception) {
        }
        sTLinkRecordingFileHandle = nil;
    }
    if (sTLinkRecordingRunLoop) {
        CFRunLoopStop(sTLinkRecordingRunLoop);
        CFRelease(sTLinkRecordingRunLoop);
        sTLinkRecordingRunLoop = NULL;
    }
    sTLinkRecordingActive = NO;
    sTLinkRecordingStoppedAtMs = TLinkNowMs();
    if (reason.length > 0) sTLinkRecordingLastError = reason;
}

static NSData *TLinkHandleStartRecording(NSString *body)
{
    (void)body;
    @synchronized (TLinkVisualFeedbackLock()) {
        if (sTLinkRecordingActive) {
            return TLinkError([NSString stringWithFormat:@"recording_already_started path=%@", sTLinkRecordingBundlePath ?: @""]);
        }
    }

    CGSize screen = TLinkScreenPixelSize();
    if (screen.width <= 0 || screen.height <= 0) {
        return TLinkError(@"recording_screen_size_unavailable");
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyMMddHHmmss";
    NSString *name = [formatter stringFromDate:[NSDate date]] ?: [NSString stringWithFormat:@"%llu", TLinkNowMs()];
    NSString *bundlePath = [kTLinkRecordingScriptsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.tl", name]];
    NSString *rawFileName = [NSString stringWithFormat:@"%@.raw", name];
    NSString *rawPath = [bundlePath stringByAppendingPathComponent:rawFileName];
    NSError *err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:bundlePath withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) return TLinkError([NSString stringWithFormat:@"recording_create_bundle_failed %@", err.localizedDescription ?: @""]);

    NSDictionary *info = @{@"Entry": @"main.js", @"FrontApp": @"", @"Orientation": @"1"};
    [info writeToFile:[bundlePath stringByAppendingPathComponent:@"info.plist"] atomically:YES];
    NSDictionary *manifest = @{@"entry": @"main.js", @"name": name, @"kind": @"recording", @"raw": rawFileName};
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    [manifestData writeToFile:[bundlePath stringByAppendingPathComponent:@"manifest.json"] atomically:YES];
    NSString *source = TLinkRecordingReplaySource(rawFileName);
    if (![source writeToFile:[bundlePath stringByAppendingPathComponent:@"main.js"] atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        return TLinkError([NSString stringWithFormat:@"recording_write_main_failed %@", err.localizedDescription ?: @""]);
    }
    if (![[NSFileManager defaultManager] createFileAtPath:rawPath contents:nil attributes:nil]) {
        return TLinkError(@"recording_create_raw_failed");
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:rawPath];
    if (!fh) return TLinkError(@"recording_open_raw_failed");

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) {
        [fh closeFile];
        return TLinkError(@"unsupported_on_trollstore task=14 hid_monitor_client_unavailable");
    }

    @synchronized (TLinkVisualFeedbackLock()) {
        sTLinkRecordingActive = YES;
        sTLinkRecordingBundlePath = bundlePath;
        sTLinkRecordingRawPath = rawPath;
        sTLinkRecordingLastError = @"";
        sTLinkRecordingStartedAtMs = TLinkNowMs();
        sTLinkRecordingStoppedAtMs = 0;
        sTLinkRecordingEventCount = 0;
        sTLinkRecordingLastEventTime = CFAbsoluteTimeGetCurrent();
        sTLinkRecordingScreenWidth = screen.width;
        sTLinkRecordingScreenHeight = screen.height;
        sTLinkRecordingFileHandle = fh;
        sTLinkRecordingClient = client;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            @synchronized (TLinkVisualFeedbackLock()) {
                if (!sTLinkRecordingActive || !sTLinkRecordingClient) return;
                CFRunLoopRef runLoop = CFRunLoopGetCurrent();
                CFRetain(runLoop);
                sTLinkRecordingRunLoop = runLoop;
                IOHIDEventSystemClientScheduleWithRunLoop(sTLinkRecordingClient, runLoop, kCFRunLoopDefaultMode);
                IOHIDEventSystemClientRegisterEventCallback(sTLinkRecordingClient, TLinkRecordingHIDCallback, NULL, NULL);
            }
            CFRunLoopRun();
        }
    });

    TLinkRecordToast(@"Recording started", 2.0, 0, 2, 14, @"task14");
    return TLinkSuccess([NSString stringWithFormat:@"recording_started;;%@", bundlePath]);
}

static NSData *TLinkHandleStopRecording(NSString *body)
{
    (void)body;
    NSString *bundlePath = @"";
    NSInteger count = 0;
    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkRecordingActive) {
            return TLinkSuccess(@"recording_not_active");
        }
        bundlePath = sTLinkRecordingBundlePath ?: @"";
        count = sTLinkRecordingEventCount;
        TLinkStopRecordingLocked(@"");
    }
    TLinkRecordToast([NSString stringWithFormat:@"Recording saved (%ld events)", (long)count], 2.5, 0, 2, 14, @"task15");
    return TLinkSuccess([NSString stringWithFormat:@"recording_stopped;;%@;;events=%ld", bundlePath, (long)count]);
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

static NSString *const kTLinkPhotoAlbumName = @"TLinkauto";

static NSString *TLinkPhotoAuthorizationStatusName(PHAuthorizationStatus status)
{
    switch (status) {
        case PHAuthorizationStatusNotDetermined: return @"not_determined";
        case PHAuthorizationStatusRestricted: return @"restricted";
        case PHAuthorizationStatusDenied: return @"denied";
        case PHAuthorizationStatusAuthorized: return @"authorized";
        case PHAuthorizationStatusLimited: return @"limited";
        default: return [NSString stringWithFormat:@"unknown_%ld", (long)status];
    }
}

static BOOL TLinkPhotoLibraryAuthorized(NSString **error)
{
    if (!NSClassFromString(@"PHPhotoLibrary")) {
        if (error) *error = @"photos_framework_unavailable";
        return NO;
    }

    PHAuthorizationStatus status = PHAuthorizationStatusNotDetermined;
    if (@available(iOS 14.0, *)) {
        status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    } else {
        status = [PHPhotoLibrary authorizationStatus];
    }

    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
        return YES;
    }
    if (error) {
        NSString *name = TLinkPhotoAuthorizationStatusName(status);
        if (status == PHAuthorizationStatusNotDetermined) {
            *error = [NSString stringWithFormat:@"photo_permission_not_determined status=%@ open StreamControl.app Settings > Photo Access first", name];
        } else {
            *error = [NSString stringWithFormat:@"photo_permission_unavailable status=%@ grant Photos access in iOS Settings", name];
        }
    }
    return NO;
}

static PHAssetCollection *TLinkFetchPhotoAlbum(void)
{
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"title = %@", kTLinkPhotoAlbumName];
    PHFetchResult<PHAssetCollection *> *result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                                                          subtype:PHAssetCollectionSubtypeAlbumRegular
                                                                                          options:fetchOptions];
    return result.firstObject;
}

static PHAssetCollection *TLinkEnsurePhotoAlbum(NSString **error)
{
    if (!TLinkPhotoLibraryAuthorized(error)) return nil;
    PHAssetCollection *album = TLinkFetchPhotoAlbum();
    if (album) return album;

    NSError *creationError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:kTLinkPhotoAlbumName];
    } error:&creationError];
    if (creationError) {
        if (error) *error = [NSString stringWithFormat:@"photo_album_create_failed %@", creationError.localizedDescription ?: @"unknown"];
        return nil;
    }
    album = TLinkFetchPhotoAlbum();
    if (!album && error) *error = @"photo_album_fetch_after_create_failed";
    return album;
}

static NSData *TLinkSaveImagePathToPhotoAlbum(NSString *path)
{
    if (path.length == 0) return TLinkError(@"save_album_missing_file_path");
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) return TLinkError([NSString stringWithFormat:@"save_album_image_not_found path=%@", path]);

    NSString *err = nil;
    PHAssetCollection *album = TLinkEnsurePhotoAlbum(&err);
    if (!album) return TLinkError(err ?: @"photo_album_unavailable");

    NSError *saveError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        PHObjectPlaceholder *placeholder = assetRequest.placeholderForCreatedAsset;
        if (placeholder) {
            PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
            [albumRequest addAssets:@[placeholder]];
        }
    } error:&saveError];
    if (saveError) {
        return TLinkError([NSString stringWithFormat:@"save_album_failed %@", saveError.localizedDescription ?: @"unknown"]);
    }
    return TLinkSuccess([NSString stringWithFormat:@"saved_to_album;;%@", kTLinkPhotoAlbumName]);
}

static NSData *TLinkClearPhotoAlbum(void)
{
    NSString *err = nil;
    if (!TLinkPhotoLibraryAuthorized(&err)) return TLinkError(err ?: @"photo_permission_unavailable");
    PHAssetCollection *album = TLinkFetchPhotoAlbum();
    if (!album) return TLinkSuccess(@"album_not_found;;0");
    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsInAssetCollection:album options:nil];
    NSUInteger count = assets.count;
    if (count == 0) return TLinkSuccess(@"album_empty;;0");

    NSError *removeError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
        [albumRequest removeAssets:assets];
    } error:&removeError];
    if (removeError) {
        return TLinkError([NSString stringWithFormat:@"clear_album_failed %@", removeError.localizedDescription ?: @"unknown"]);
    }
    return TLinkSuccess([NSString stringWithFormat:@"album_cleared;;%lu;;removed_from_album_only", (unsigned long)count]);
}

static NSData *TLinkHandleScreenshot(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int action = parts.count > 0 ? [parts[0] intValue] : 0;
    if (action == 2) {
        if (parts.count < 2 || parts[1].length == 0) return TLinkError(@"save_album_missing_file_path");
        return TLinkSaveImagePathToPhotoAlbum(parts[1]);
    }
    if (action == 3) {
        return TLinkClearPhotoAlbum();
    }
    if (action != 1) {
        return TLinkError([NSString stringWithFormat:@"unknown_screenshot_action action=%d", action]);
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

static NSData *TLinkRunAppSideClipboard(NSString *body);
static NSData *TLinkRunForegroundClipboardBroker(NSString *body);

static BOOL TLinkKeyboardResultSucceeded(HIDInjectResult result)
{
    return result.clientCreated && result.eventCreated && result.dispatched;
}

static BOOL TLinkDispatchKeyboardStroke(uint16_t usage, int count, NSString **error)
{
    if (count < 1) count = 1;
    for (int index = 0; index < count; index++) {
        HIDInjectResult down = HIDInjectDispatchKeyboardKey(HID_KEY_ACTION_DOWN, 0x07, usage);
        if (!TLinkKeyboardResultSucceeded(down)) {
            if (error) *error = [NSString stringWithFormat:@"keyboard_key_down_failed usage=0x%x errno=%d", usage, down.errnoValue];
            return NO;
        }
        usleep(12000);
        HIDInjectResult up = HIDInjectDispatchKeyboardKey(HID_KEY_ACTION_UP, 0x07, usage);
        if (!TLinkKeyboardResultSucceeded(up)) {
            if (error) *error = [NSString stringWithFormat:@"keyboard_key_up_failed usage=0x%x errno=%d", usage, up.errnoValue];
            return NO;
        }
        if (index + 1 < count) usleep(12000);
    }
    return YES;
}

static BOOL TLinkDispatchPasteShortcut(NSString **error)
{
    // USB HID keyboard usages: Left GUI/Command=0xE3 and V=0x19.
    HIDInjectResult commandDown = HIDInjectDispatchKeyboardKey(HID_KEY_ACTION_DOWN, 0x07, 0xE3);
    if (!TLinkKeyboardResultSucceeded(commandDown)) {
        if (error) *error = [NSString stringWithFormat:@"command_key_down_failed errno=%d", commandDown.errnoValue];
        return NO;
    }

    usleep(20000);
    HIDInjectResult vDown = HIDInjectDispatchKeyboardKey(HID_KEY_ACTION_DOWN, 0x07, 0x19);
    usleep(25000);
    HIDInjectResult vUp = HIDInjectDispatchKeyboardKey(HID_KEY_ACTION_UP, 0x07, 0x19);
    usleep(12000);
    HIDInjectResult commandUp = HIDInjectDispatchKeyboardKey(HID_KEY_ACTION_UP, 0x07, 0xE3);

    if (!TLinkKeyboardResultSucceeded(vDown) ||
        !TLinkKeyboardResultSucceeded(vUp) ||
        !TLinkKeyboardResultSucceeded(commandUp)) {
        if (error) {
            *error = [NSString stringWithFormat:@"paste_shortcut_dispatch_failed v_down=%d v_up=%d command_up=%d errno=%d/%d/%d",
                      TLinkKeyboardResultSucceeded(vDown),
                      TLinkKeyboardResultSucceeded(vUp),
                      TLinkKeyboardResultSucceeded(commandUp),
                      vDown.errnoValue, vUp.errnoValue, commandUp.errnoValue];
        }
        return NO;
    }
    return YES;
}

static NSData *TLinkHandleKeyboard(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 1) return TLinkError(@"keyboard task missing subtask");
    int subtask = [parts[0] intValue];
    if (subtask == 1) {
        if (parts.count < 2) return TLinkError(@"insert text missing content");
        NSString *text = TLinkJoinParts(parts, 1);
        NSData *saveResponse = TLinkRunAppSideClipboard([NSString stringWithFormat:@"7;;%@", text ?: @""]);
        NSString *saveText = TLinkResponseStringFromData(saveResponse);
        if (![saveText isEqualToString:@"0"] && ![saveText hasPrefix:@"0;;"]) {
            return TLinkError([NSString stringWithFormat:@"insert_text_clipboard_save_failed %@", saveText ?: @""]);
        }
        usleep(80000);
        NSString *hidError = nil;
        if (!TLinkDispatchPasteShortcut(&hidError)) {
            return TLinkError([NSString stringWithFormat:@"insert_text_hid_paste_failed %@ text_saved_to_clipboard length=%lu",
                               hidError ?: @"unknown", (unsigned long)text.length]);
        }
        return TLinkSuccess([NSString stringWithFormat:@"insert_text_via_background_clipboard_hid;;%lu", (unsigned long)text.length]);
    }
    if (subtask == 2) {
        NSString *mode = parts.count > 1 ? parts[1] : @"";
        return TLinkUnsupported(24, [NSString stringWithFormat:@"limited_on_trollstore keyboard_visibility_requires_springboard_keyboard_observer mode=%@", mode ?: @""]);
    }
    if (subtask == 3) {
        int offset = parts.count > 1 ? [parts[1] intValue] : 0;
        if (offset > 1024) offset = 1024;
        if (offset < -1024) offset = -1024;
        if (offset == 0) return TLinkSuccess(@"move_cursor_hid;;0");
        NSString *hidError = nil;
        uint16_t usage = offset < 0 ? 0x50 : 0x4F;
        if (!TLinkDispatchKeyboardStroke(usage, abs(offset), &hidError)) {
            return TLinkError([NSString stringWithFormat:@"move_cursor_hid_failed %@", hidError ?: @"unknown"]);
        }
        return TLinkSuccess([NSString stringWithFormat:@"move_cursor_hid;;%d", offset]);
    }
    if (subtask == 4) {
        int count = parts.count > 1 ? [parts[1] intValue] : 1;
        if (count <= 0) count = 1;
        if (count > 1024) count = 1024;
        NSString *hidError = nil;
        if (!TLinkDispatchKeyboardStroke(0x2A, count, &hidError)) {
            return TLinkError([NSString stringWithFormat:@"delete_characters_hid_failed %@", hidError ?: @"unknown"]);
        }
        return TLinkSuccess([NSString stringWithFormat:@"delete_characters_hid;;%d", count]);
    }
    if (subtask == 5) {
        NSString *hidError = nil;
        if (!TLinkDispatchPasteShortcut(&hidError)) {
            return TLinkError([NSString stringWithFormat:@"paste_from_clipboard_hid_failed %@", hidError ?: @"unknown"]);
        }
        return TLinkSuccess(@"paste_from_background_clipboard_hid");
    }
    if (subtask == 6) {
        return TLinkRunAppSideClipboard(@"6");
    }
    if (subtask == 7) {
        if (parts.count < 2) return TLinkError(@"clipboard save text missing content");
        return TLinkRunAppSideClipboard([NSString stringWithFormat:@"7;;%@", TLinkJoinParts(parts, 1)]);
    }
    if (subtask == 8) {
        if (parts.count < 2) return TLinkError(@"clipboard image missing file path");
        NSString *payload = TLinkJoinParts(parts, 1);
        NSString *path = [payload hasPrefix:@"file;;"] ? [payload substringFromIndex:6] : payload;
        if (path.length == 0) return TLinkError(@"clipboard image empty file path");
        return TLinkRunAppSideClipboard([NSString stringWithFormat:@"8;;file;;%@", path]);
    }
    if (subtask == 9) {
        return TLinkRunAppSideClipboard(@"9");
    }
    if (subtask == 10) {
        return TLinkRunAppSideClipboard(@"10");
    }
    if (subtask == 11) {
        return TLinkRunAppSideClipboard(@"11");
    }
    if (subtask == 12) {
        return TLinkRunAppSideClipboard(@"12");
    }
    return TLinkUnsupported(24, @"limited_on_trollstore unknown_keyboard_subtask");
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

static BOOL TLinkConfigureVisionRequestCPUOnly(VNRequest *request, NSString **error)
{
    if (!request) {
        if (error) *error = @"vision_cpu_request_missing";
        return NO;
    }

    if (@available(iOS 17.0, *)) {
        NSError *deviceError = nil;
        NSDictionary *supportedDevices = [request supportedComputeStageDevicesAndReturnError:&deviceError];
        if (supportedDevices.count == 0) {
            if (error) {
                *error = [NSString stringWithFormat:@"vision_cpu_device_query_failed %@",
                                                    deviceError.localizedDescription ?: @"no_compute_stages"];
            }
            return NO;
        }

        for (VNComputeStage stage in supportedDevices) {
            NSArray *devices = supportedDevices[stage];
            id<MLComputeDeviceProtocol> cpuDevice = nil;
            for (id<MLComputeDeviceProtocol> device in devices) {
                if ([device isKindOfClass:[MLCPUComputeDevice class]]) {
                    cpuDevice = device;
                    break;
                }
            }
            if (!cpuDevice) {
                if (error) {
                    *error = [NSString stringWithFormat:@"vision_cpu_unavailable_for_stage %@", stage];
                }
                return NO;
            }
            [request setComputeDevice:cpuDevice forComputeStage:stage];
        }
        return YES;
    }

    request.usesCPUOnly = YES;
    return YES;
}

static NSString *TLinkBase64String(NSString *value);

static BOOL TLinkWriteAllToFd(int fd, const void *bytes, size_t length)
{
    const uint8_t *cursor = (const uint8_t *)bytes;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t written = write(fd, cursor, remaining);
        if (written <= 0) return NO;
        cursor += written;
        remaining -= (size_t)written;
    }
    return YES;
}

static NSData *TLinkReadSocketResponse(int fd)
{
    NSMutableData *response = [NSMutableData data];
    char buffer[2048];
    while (response.length < 262144) {
        ssize_t n = read(fd, buffer, sizeof(buffer));
        if (n <= 0) break;
        [response appendBytes:buffer length:(NSUInteger)n];
        if (memchr(buffer, '\n', (size_t)n) != NULL) break;
    }
    return response;
}

static NSData *TLinkRunClipboardService(NSString *body, uint16_t port, int timeoutMs)
{
    NSData *bodyData = [(body ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encodedBody = bodyData ? [bodyData base64EncodedStringWithOptions:0] : @"";

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        return TLinkError([NSString stringWithFormat:@"clipboard_service_socket_failed errno=%d", errno]);
    }
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif
    struct timeval timeout;
    if (timeoutMs < 100) timeoutMs = 100;
    timeout.tv_sec = timeoutMs / 1000;
    timeout.tv_usec = (timeoutMs % 1000) * 1000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        int connectErrno = errno;
        close(sock);
        return TLinkError([NSString stringWithFormat:@"clipboard_service_unavailable port=%u errno=%d", port, connectErrno]);
    }

    NSString *line = [NSString stringWithFormat:@"1;;%@\n", encodedBody ?: @""];
    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!TLinkWriteAllToFd(sock, lineData.bytes, lineData.length)) {
        close(sock);
        return TLinkError(@"clipboard_service_request_write_failed port_6000_preserved");
    }

    NSData *response = TLinkReadSocketResponse(sock);
    close(sock);
    if (response.length == 0) return TLinkError(@"clipboard_service_timeout_or_empty_response port_6000_preserved");
    return response;
}

static BOOL TLinkAppForegroundHeartbeatIsFresh(void)
{
    NSString *value = [NSString stringWithContentsOfFile:kTLinkAppForegroundHeartbeatPath
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    uint64_t heartbeatMs = (uint64_t)[value longLongValue];
    uint64_t nowMs = TLinkNowMs();
    return heartbeatMs > 0 && nowMs >= heartbeatMs && nowMs - heartbeatMs <= 1500;
}

static void TLinkDispatchBackgroundVisualFallback(NSDictionary *event)
{
    if (![event isKindOfClass:[NSDictionary class]]) return;
    NSString *kind = [event[@"kind"] isKindOfClass:NSString.class] ? event[@"kind"] : @"";
    BOOL forceUIService = [kind isEqualToString:@"toast"];
    if (!forceUIService && TLinkAppForegroundHeartbeatIsFresh()) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:event options:0 error:&jsonError];
        if (jsonData.length == 0) {
            POCLogf("background-ui: encode failed error=%s",
                    [jsonError.localizedDescription UTF8String] ?: "unknown");
            return;
        }
        NSString *encoded = [jsonData base64EncodedStringWithOptions:0];
        NSData *response = TLinkRunClipboardService([NSString stringWithFormat:@"90;;%@", encoded ?: @""], 6012, 800);
        NSString *text = TLinkResponseStringFromData(response);
        POCLogf("background-ui: visual response=%s", [text UTF8String] ?: "<nil>");
    });
}

static void TLinkDispatchBackgroundKeepAwake(BOOL enabled)
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *payload = @{
            @"action": @"keep_awake",
            @"enabled": @(enabled),
        };
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        NSString *encoded = [jsonData base64EncodedStringWithOptions:0];
        NSData *response = TLinkRunClipboardService([NSString stringWithFormat:@"90;;%@", encoded ?: @""], 6012, 800);
        NSString *text = TLinkResponseStringFromData(response);
        POCLogf("background-ui: keep-awake response=%s", [text UTF8String] ?: "<nil>");
    });
}

static BOOL TLinkClipboardResponseSucceeded(NSData *response)
{
    NSString *value = TLinkResponseStringFromData(response);
    return [value isEqualToString:@"0"] || [value hasPrefix:@"0;;"];
}

static BOOL sTLinkClipboardDaemonWriteVerified = NO;

static void TLinkUpdateClipboardDaemonVerification(NSData *diagnosticResponse)
{
    NSString *diagnostic = TLinkResponseStringFromData(diagnosticResponse);
    sTLinkClipboardDaemonWriteVerified =
        [diagnostic containsString:@"version=16"] &&
        [diagnostic containsString:@"background_entitlement=1"] &&
        [diagnostic containsString:@"write_verified=1"];
}

static NSData *TLinkRunAppSideClipboard(NSString *body)
{
    // Task 249 reports the selected mode and preserves the daemon details as
    // base64 so nested legacy delimiters cannot corrupt the response shape.
    if ([body isEqualToString:@"9"]) {
        NSData *daemonResponse = TLinkRunClipboardService(body, 6012, 500);
        NSString *daemonText = TLinkResponseStringFromData(daemonResponse) ?: @"";
        TLinkUpdateClipboardDaemonVerification(daemonResponse);
        NSData *diagnosticData = [daemonText dataUsingEncoding:NSUTF8StringEncoding];
        NSString *diagnosticB64 = [diagnosticData base64EncodedStringWithOptions:0] ?: @"";
        return TLinkSuccess([NSString stringWithFormat:@"clipboard_backend_ready;;mode=background_entitled_uidaemon_with_ui_bridge_and_foreground_fallback;;app_port=6013;;daemon_port=6012;;daemon_direct_write=%d;;daemon_diag_b64=%@",
                             sTLinkClipboardDaemonWriteVerified ? 1 : 0, diagnosticB64]);
    }

    // UI controls do not depend on a previous Pasteboard write verification.
    // They must reach the always-on clipboardd even on a fresh installation.
    BOOL daemonControl = [body isEqualToString:@"10"] ||
                         [body isEqualToString:@"11"] ||
                         [body isEqualToString:@"12"];
    if (daemonControl) {
        return TLinkRunClipboardService(body, 6012, 1500);
    }

    BOOL writeOperation = [body hasPrefix:@"7;;"] || [body hasPrefix:@"8;;"];
    if (!writeOperation && !sTLinkClipboardDaemonWriteVerified) {
        NSData *diagnostic = TLinkRunClipboardService(@"9", 6012, 500);
        TLinkUpdateClipboardDaemonVerification(diagnostic);
    }

    if (writeOperation || sTLinkClipboardDaemonWriteVerified) {
        NSData *daemonResponse = TLinkRunClipboardService(body, 6012, 500);
        if (TLinkClipboardResponseSucceeded(daemonResponse)) {
            if (writeOperation) sTLinkClipboardDaemonWriteVerified = YES;
            return daemonResponse;
        }
        sTLinkClipboardDaemonWriteVerified = NO;
    }

    // Retain the foreground bridge for devices that ignore private entitlements.
    NSData *appResponse = TLinkRunClipboardService(body, 6013, 250);
    if (TLinkClipboardResponseSucceeded(appResponse)) return appResponse;

    return TLinkRunForegroundClipboardBroker(body);
}

static NSString *TLinkBase64UTF8String(NSString *value)
{
    NSData *data = [(value ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return [data base64EncodedStringWithOptions:0] ?: @"";
}

static NSData *TLinkRunAppSideVisionOCR(NSData *pngData,
                                        CGRect region,
                                        NSString *customWords,
                                        CGFloat minimumTextHeight,
                                        int levelValue,
                                        NSString *languages,
                                        BOOL languageCorrection,
                                        NSString *profile)
{
    if (pngData.length == 0) return TLinkError(@"app_ocr_bridge_empty_png");

    NSString *tmpDir = @"/var/mobile/Library/TLinkauto/tmp";
    NSError *mkdirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:tmpDir
                                   withIntermediateDirectories:YES
                                                    attributes:@{NSFilePosixPermissions: @0755}
                                                         error:&mkdirError]) {
        return TLinkError([NSString stringWithFormat:@"app_ocr_bridge_tmpdir_failed %@", mkdirError.localizedDescription ?: tmpDir]);
    }
    chmod([tmpDir fileSystemRepresentation], 0755);

    char imageTemplate[PATH_MAX + 1] = {0};
    snprintf(imageTemplate, sizeof(imageTemplate), "%s", [[tmpDir stringByAppendingPathComponent:@"appocr-XXXXXX"] fileSystemRepresentation]);
    int imageFd = mkstemp(imageTemplate);
    if (imageFd < 0) {
        return TLinkError([NSString stringWithFormat:@"app_ocr_bridge_temp_failed errno=%d", errno]);
    }
    BOOL wroteImage = TLinkWriteAllToFd(imageFd, pngData.bytes, pngData.length);
    fchmod(imageFd, 0644);
    close(imageFd);
    chmod(imageTemplate, 0644);
    if (!wroteImage) {
        unlink(imageTemplate);
        return TLinkError(@"app_ocr_bridge_png_write_failed");
    }

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        unlink(imageTemplate);
        return TLinkError([NSString stringWithFormat:@"app_ocr_bridge_socket_failed errno=%d", errno]);
    }
    struct timeval timeout;
    // The app has its own 15-second watchdog. Leave enough time for that
    // structured response while staying below the worker's 20-second bound.
    timeout.tv_sec = 18;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(6011);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        int connectErrno = errno;
        close(sock);
        unlink(imageTemplate);
        return TLinkError([NSString stringWithFormat:@"app_ocr_bridge_unavailable errno=%d open_StreamControl_foreground", connectErrno]);
    }

    NSString *line = [NSString stringWithFormat:@"2;;%s;;%.0f;;%.0f;;%.0f;;%.0f;;%.8f;;%d;;%@;;%@;;%d;;%@\n",
                      imageTemplate,
                      region.origin.x,
                      region.origin.y,
                      region.size.width,
                      region.size.height,
                      minimumTextHeight,
                      levelValue,
                      TLinkBase64UTF8String(customWords),
                      TLinkBase64UTF8String(languages),
                      languageCorrection ? 1 : 0,
                      profile ?: @"app_cpu"];
    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!TLinkWriteAllToFd(sock, lineData.bytes, lineData.length)) {
        close(sock);
        unlink(imageTemplate);
        return TLinkError(@"app_ocr_bridge_request_write_failed");
    }

    NSData *response = TLinkReadSocketResponse(sock);
    close(sock);
    unlink(imageTemplate);
    if (response.length == 0) return TLinkError(@"app_ocr_bridge_empty_response");
    return response;
}

static char sTLinkOCRWorkerOutputPath[PATH_MAX + 1] = {0};
static char sTLinkOCRWorkerPhase[96] = "not_started";
static NSString *const kTLinkVisionOCRDebugLogPath = @"/var/mobile/Library/TLinkauto/runtime/vision-ocr-debug.log";

static size_t TLinkSafeCStringLength(const char *value, size_t maxLen)
{
    size_t len = 0;
    if (!value) return 0;
    while (len < maxLen && value[len] != '\0') len++;
    return len;
}

static void TLinkSetOCRWorkerOutputPath(const char *path)
{
    if (!path) {
        sTLinkOCRWorkerOutputPath[0] = '\0';
        return;
    }
    snprintf(sTLinkOCRWorkerOutputPath, sizeof(sTLinkOCRWorkerOutputPath), "%s", path);
}

static void TLinkSetOCRWorkerPhase(const char *phase)
{
    if (!phase) phase = "unknown";
    snprintf(sTLinkOCRWorkerPhase, sizeof(sTLinkOCRWorkerPhase), "%s", phase);
}

static void TLinkWriteIntForSignalHandler(int fd, int value)
{
    char buf[16];
    int i = (int)sizeof(buf) - 1;
    buf[i] = '\0';
    if (value == 0) {
        buf[--i] = '0';
    } else {
        int n = value;
        while (n > 0 && i > 0) {
            buf[--i] = (char)('0' + (n % 10));
            n /= 10;
        }
    }
    write(fd, &buf[i], (size_t)((int)sizeof(buf) - 1 - i));
}

static void TLinkOCRWorkerSignalHandler(int signalNumber)
{
    if (sTLinkOCRWorkerOutputPath[0] != '\0') {
        int fd = open(sTLinkOCRWorkerOutputPath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd >= 0) {
            const char *prefix = "-1;;ocr_worker_crashed signal=";
            write(fd, prefix, TLinkSafeCStringLength(prefix, 64));
            TLinkWriteIntForSignalHandler(fd, signalNumber);
            const char *middle = " phase=";
            write(fd, middle, TLinkSafeCStringLength(middle, 16));
            write(fd, sTLinkOCRWorkerPhase, TLinkSafeCStringLength(sTLinkOCRWorkerPhase, sizeof(sTLinkOCRWorkerPhase)));
            const char *suffix = " port_6000_preserved\r\n";
            write(fd, suffix, TLinkSafeCStringLength(suffix, 32));
            close(fd);
        }
    }

    _exit(128 + signalNumber);
}

static void TLinkInstallOCRWorkerSignalHandlers(const char *outputPath)
{
    TLinkSetOCRWorkerOutputPath(outputPath);
    TLinkSetOCRWorkerPhase("worker_start");
    signal(SIGSEGV, TLinkOCRWorkerSignalHandler);
    signal(SIGBUS, TLinkOCRWorkerSignalHandler);
    signal(SIGABRT, TLinkOCRWorkerSignalHandler);
    signal(SIGILL, TLinkOCRWorkerSignalHandler);
    signal(SIGFPE, TLinkOCRWorkerSignalHandler);
}

static NSData *TLinkHandleVisionOCRInProcess(NSString *body)
{
    TLinkSetOCRWorkerPhase("vision_enter");
    BOOL visionAvailable = NO;
    if (@available(iOS 13.0, *)) {
        visionAvailable = YES;
    }
    if (!visionAvailable) {
        return TLinkUnsupported(27, @"vision_requires_ios13");
    }

    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 1) return TLinkError(@"ocr task missing subtask");
    int subtask = [parts[0] intValue];

    if (subtask == 2) {
        TLinkSetOCRWorkerPhase("vision_languages");
        int levelValue = parts.count >= 2 ? [parts[1] intValue] : 0;
        VNRequestTextRecognitionLevel level = TLinkVisionOCRLevelFromValue(levelValue);
        NSError *visionErr = nil;
        NSArray<NSString *> *languages = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:level
                                                                                                             revision:TLinkVisionOCRRevision()
                                                                                                                error:&visionErr];
        if (!languages) return TLinkError([NSString stringWithFormat:@"ocr_languages_failed %@", visionErr.localizedDescription ?: @"unknown"]);
        return TLinkSuccess([languages componentsJoinedByString:@";;"]);
    }

    if (subtask == 3) {
        NSData *logData = [NSData dataWithContentsOfFile:kTLinkVisionOCRDebugLogPath];
        if (logData.length > 65536) {
            logData = [logData subdataWithRange:NSMakeRange(logData.length - 65536, 65536)];
        }
        NSString *encoded = logData.length > 0 ? [logData base64EncodedStringWithOptions:0] : @"";
        return TLinkSuccess([NSString stringWithFormat:@"vision_debug_base64;;%@", encoded]);
    }

    if (subtask == 4) {
        NSError *removeError = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:kTLinkVisionOCRDebugLogPath] &&
            ![[NSFileManager defaultManager] removeItemAtPath:kTLinkVisionOCRDebugLogPath error:&removeError]) {
            return TLinkError([NSString stringWithFormat:@"vision_debug_clear_failed %@",
                                                        removeError.localizedDescription ?: @"unknown"]);
        }
        return TLinkSuccess(@"vision_debug_cleared");
    }

    if (subtask != 1) {
        return TLinkError([NSString stringWithFormat:@"unknown_ocr_subtask %d", subtask]);
    }

    if (parts.count < 8) {
        return TLinkError(@"ocr format: 1;;x,,y,,w,,h;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path[;;profile]");
    }

    NSString *profile = parts.count >= 9 && [parts[8] length] > 0
        ? [parts[8] lowercaseString]
        : @"app_cpu";
    if (![profile isEqualToString:@"app_cpu"] &&
        ![profile isEqualToString:@"worker_cpu"] &&
        ![profile isEqualToString:@"xxt_compat"]) {
        return TLinkError([NSString stringWithFormat:@"ocr_bad_profile %@ expected=app_cpu_or_worker_cpu_or_xxt_compat", profile]);
    }

    TLinkSetOCRWorkerPhase("vision_parse_region");
    NSArray<NSString *> *rectParts = [parts[1] componentsSeparatedByString:@",,"];
    if (rectParts.count < 4) return TLinkError(@"ocr_bad_region");
    int requestedW = [rectParts[2] intValue];
    int requestedH = [rectParts[3] intValue];
    const uint64_t maxVisionOCRPixels = 900000;
    if (requestedW > 0 && requestedH > 0 && (uint64_t)requestedW * (uint64_t)requestedH > maxVisionOCRPixels) {
        return TLinkError([NSString stringWithFormat:@"ocr_region_too_large max_pixels=%llu requested_pixels=%llu use_smaller_region",
                           (unsigned long long)maxVisionOCRPixels,
                           (unsigned long long)((uint64_t)requestedW * (uint64_t)requestedH)]);
    }

    NSString *err = nil;
    TLinkSetOCRWorkerPhase("vision_capture");
    UIImage *screen = TLinkScreenImageForVision(&err);
    if (!screen || !screen.CGImage) return TLinkError(err ?: @"ocr_capture_failed");

    TLinkSetOCRWorkerPhase("vision_crop");
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

    TLinkSetOCRWorkerPhase("vision_png_encode");
    NSData *visionImageData = UIImagePNGRepresentation(cropped);
    if (visionImageData.length == 0) {
        return TLinkError(@"ocr_png_encode_failed");
    }

    if ([profile isEqualToString:@"app_cpu"] || [profile isEqualToString:@"xxt_compat"]) {
        BOOL xxtCompat = [profile isEqualToString:@"xxt_compat"];
        TLinkSetOCRWorkerPhase(xxtCompat ? "vision_profile_xxt_compat_app" : "vision_profile_app_cpu");
        POCLogf("ocr: task27 profile=%s route=app_6011 cpu_only=%d foreground_required=1",
                [profile UTF8String],
                xxtCompat ? 0 : 1);
        return TLinkRunAppSideVisionOCR(visionImageData,
                                        region,
                                        parts[2],
                                        (CGFloat)[parts[3] doubleValue],
                                        [parts[4] intValue],
                                        parts[5],
                                        [parts[6] intValue] != 0,
                                        profile);
    }

    TLinkSetOCRWorkerPhase("vision_profile_worker_cpu");
    POCLogf("ocr: task27 profile=worker_cpu route=isolated_worker cpu_only=1");
    int levelValue = [parts[4] intValue];
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *finishedRequest, NSError *error) {
        // Results are read after performRequests returns.
        (void)finishedRequest;
        (void)error;
    }];
    request.recognitionLevel = TLinkVisionOCRLevelFromValue(levelValue);
    CGFloat minimumHeight = (CGFloat)[parts[3] doubleValue];
    if (minimumHeight > 0.0) request.minimumTextHeight = minimumHeight;
    NSArray<NSString *> *customWords = TLinkSplitNonEmpty(parts[2], @",,");
    if (customWords.count > 0) request.customWords = customWords;
    NSArray<NSString *> *languages = TLinkSplitNonEmpty(parts[5], @",,");
    if (languages.count > 0) request.recognitionLanguages = languages;
    request.usesLanguageCorrection = [parts[6] intValue] != 0;

    NSString *cpuError = nil;
    TLinkSetOCRWorkerPhase("vision_cpu_configure");
    if (!TLinkConfigureVisionRequestCPUOnly(request, &cpuError)) {
        return TLinkError([NSString stringWithFormat:@"ocr_cpu_profile_failed profile=worker_cpu %@",
                                                    cpuError ?: @"unknown"]);
    }

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithData:visionImageData
                                                                         options:@{}];
    NSError *visionErr = nil;
    TLinkSetOCRWorkerPhase("vision_perform_requests");
    if (![handler performRequests:@[request] error:&visionErr]) {
        return TLinkError([NSString stringWithFormat:@"ocr_failed %@", visionErr.localizedDescription ?: @"unknown"]);
    }

    TLinkSetOCRWorkerPhase("vision_collect_results");
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

int TLinkRunVisionOCRWorker(const char *payloadBase64, const char *outputPath)
{
    @autoreleasepool {
        if (!payloadBase64 || !outputPath || outputPath[0] == '\0') return 64;
        TLinkInstallOCRWorkerSignalHandlers(outputPath);

        TLinkSetOCRWorkerPhase("vision_worker_decode_payload");
        NSString *encoded = [NSString stringWithUTF8String:payloadBase64];
        NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:encoded ?: @"" options:0];
        NSString *payload = payloadData ? [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding] : nil;
        if (!payload) return 65;

        NSData *response = nil;
        @try {
            TLinkSetOCRWorkerPhase("vision_worker_call_handler");
            response = TLinkHandleVisionOCRInProcess(payload);
        } @catch (NSException *exception) {
            response = TLinkError([NSString stringWithFormat:@"ocr_worker_exception %@",
                                   exception.reason ?: exception.name ?: @"unknown"]);
        }
        if (response.length == 0) return 66;

        TLinkSetOCRWorkerPhase("vision_worker_write_response");
        NSString *target = [NSString stringWithUTF8String:outputPath];
        return [response writeToFile:target atomically:NO] ? 0 : 67;
    }
}

static NSString *TLinkCurrentStreamdExecutablePath(void)
{
    char procPath[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int procLen = proc_pidpath(getpid(), procPath, sizeof(procPath));
    if (procLen > 0 && procPath[0] != '\0') {
        NSString *path = [NSString stringWithUTF8String:procPath];
        if (path.length > 0 && [[NSFileManager defaultManager] isExecutableFileAtPath:path]) return path;
    }

    char dyldPath[PATH_MAX + 1] = {0};
    uint32_t dyldSize = sizeof(dyldPath);
    if (_NSGetExecutablePath(dyldPath, &dyldSize) == 0 && dyldPath[0] != '\0') {
        NSString *path = [NSString stringWithUTF8String:dyldPath];
        if (path.length > 0 && [[NSFileManager defaultManager] isExecutableFileAtPath:path]) return path;
    }

    NSString *bundleExecutable = [[NSBundle mainBundle] executablePath];
    if (bundleExecutable.length > 0 && [[NSFileManager defaultManager] isExecutableFileAtPath:bundleExecutable]) {
        return bundleExecutable;
    }

    // TrollStore can replace the application container while the previous
    // daemon is still alive. Resolve the currently installed app bundle.
    NSString *installedExecutable = TLinkBundledExecutablePath(@"streamd");
    if (installedExecutable.length > 0) return installedExecutable;

    return nil;
}

static NSData *TLinkRunOCRWorkerProcess(NSString *body, const char *workerMode)
{
    NSData *payloadData = [(body ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encodedPayload = [payloadData base64EncodedStringWithOptions:0];
    if (encodedPayload.length == 0) return TLinkError(@"ocr_worker_payload_encode_failed");

    NSString *executable = TLinkCurrentStreamdExecutablePath();
    if (executable.length == 0) {
        return TLinkError(@"ocr_worker_executable_path_failed proc_pidpath_and_dyld_empty");
    }

    char outputTemplate[] = "/tmp/tlinkauto-ocr-XXXXXX";
    int outputFd = mkstemp(outputTemplate);
    if (outputFd < 0) {
        return TLinkError([NSString stringWithFormat:@"ocr_worker_temp_failed errno=%d", errno]);
    }
    close(outputFd);

    NSString *outputPath = [NSString stringWithUTF8String:outputTemplate] ?: @"";
    char *const workerArgv[] = {
        (char *)[executable fileSystemRepresentation],
        (char *)(workerMode ?: "--vision-ocr-worker"),
        (char *)[encodedPayload UTF8String],
        (char *)[outputPath fileSystemRepresentation],
        NULL,
    };

    pid_t workerPid = -1;
    int spawnError = posix_spawn(&workerPid,
                                 [executable fileSystemRepresentation],
                                 NULL,
                                 NULL,
                                 workerArgv,
                                 environ);
    if (spawnError != 0 || workerPid <= 0) {
        unlink(outputTemplate);
        return TLinkError([NSString stringWithFormat:@"ocr_worker_spawn_failed code=%d path=%@",
                           spawnError,
                           executable]);
    }

    int status = 0;
    BOOL completed = NO;
    for (int i = 0; i < 400; i++) {
        pid_t result = waitpid(workerPid, &status, WNOHANG);
        if (result == workerPid) {
            completed = YES;
            break;
        }
        if (result < 0) {
            if (errno == EINTR) continue;
            int waitError = errno;
            unlink(outputTemplate);
            return TLinkError([NSString stringWithFormat:@"ocr_worker_wait_failed errno=%d", waitError]);
        }
        usleep(50000);
    }

    if (!completed) {
        kill(workerPid, SIGKILL);
        waitpid(workerPid, &status, 0);
        unlink(outputTemplate);
        return TLinkError(@"ocr_worker_timeout timeout_ms=20000");
    }

    if (WIFSIGNALED(status)) {
        int signalNumber = WTERMSIG(status);
        NSData *response = [NSData dataWithContentsOfFile:outputPath];
        unlink(outputTemplate);
        if (response.length > 0) return response;
        return TLinkError([NSString stringWithFormat:@"ocr_worker_crashed signal=%d port_6000_preserved", signalNumber]);
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        int exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
        NSData *response = [NSData dataWithContentsOfFile:outputPath];
        unlink(outputTemplate);
        if (response.length > 0) return response;
        return TLinkError([NSString stringWithFormat:@"ocr_worker_failed exit=%d", exitCode]);
    }

    NSData *response = [NSData dataWithContentsOfFile:outputPath];
    unlink(outputTemplate);
    if (response.length == 0) return TLinkError(@"ocr_worker_empty_response");
    return response;
}

static NSData *TLinkHandleVisionOCR(NSString *body)
{
    return TLinkRunOCRWorkerProcess(body, "--vision-ocr-worker");
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

static BOOL TLinkPidIsAlive(pid_t pid)
{
    if (pid <= 0) return NO;
    if (kill(pid, 0) == 0) return YES;
    return errno == EPERM;
}

typedef int (*TLinkSBSLaunchApplicationFn)(CFStringRef identifier, Boolean suspended);
typedef CFStringRef (*TLinkSBSCopyFrontmostFn)(void);

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

static pid_t TLinkResolvePidForBundleId(NSString *bundleId)
{
    if (bundleId.length > 0 &&
        [bundleId isEqualToString:sTLinkLastFrontmostBundleId] &&
        sTLinkLastFrontmostPid > 0) {
        uint64_t now = TLinkNowMs();
        uint64_t age = (sTLinkLastFrontmostAtMs > 0 && now >= sTLinkLastFrontmostAtMs)
            ? now - sTLinkLastFrontmostAtMs
            : 0;
        if (age <= 600000 && TLinkPidIsAlive(sTLinkLastFrontmostPid)) {
            return sTLinkLastFrontmostPid;
        }
        sTLinkLastFrontmostPid = 0;
    }

    pid_t pid = TLinkPidForBundleId(bundleId);
    if (pid > 0 && [bundleId isEqualToString:sTLinkLastFrontmostBundleId]) {
        sTLinkLastFrontmostPid = pid;
        if (sTLinkLastFrontmostAtMs == 0) sTLinkLastFrontmostAtMs = TLinkNowMs();
    }
    return pid;
}

static void TLinkRememberFrontmost(NSString *bundleId, NSString *source, pid_t pid)
{
    if (bundleId.length == 0) return;
    sTLinkLastFrontmostBundleId = bundleId;
    sTLinkLastFrontmostSource = source ?: @"unknown";
    sTLinkLastFrontmostPid = pid > 0 ? pid : (pid == 0 ? TLinkPidForBundleId(bundleId) : 0);
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

static NSString *TLinkExecutableDirectory(void)
{
    char path[PATH_MAX] = {0};
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return nil;
    char resolved[PATH_MAX] = {0};
    const char *finalPath = realpath(path, resolved) ? resolved : path;
    NSString *exePath = [NSString stringWithUTF8String:finalPath] ?: @"";
    return exePath.length > 0 ? [exePath stringByDeletingLastPathComponent] : nil;
}

static NSString *TLinkPrivhelperPath(void)
{
    NSString *installedPath = TLinkBundledExecutablePath(@"privhelper");
    if (installedPath.length > 0) return installedPath;

    NSString *dir = TLinkExecutableDirectory();
    if (dir.length == 0) return nil;
    NSString *path = [dir stringByAppendingPathComponent:@"privhelper"];
    return [[NSFileManager defaultManager] isExecutableFileAtPath:path] ? path : nil;
}

static int TLinkRunPrivhelper(NSArray<NSString *> *arguments, int timeoutMs)
{
    if (arguments.count == 0) return -100;
    NSString *path = TLinkPrivhelperPath();
    if (path.length == 0) return -101;
    const char *cpath = [path fileSystemRepresentation];

    NSUInteger argc = arguments.count + 2;
    char **argv = (char **)calloc(argc, sizeof(char *));
    if (!argv) return -102;
    argv[0] = strdup(cpath);
    BOOL allocFailed = argv[0] == NULL;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        NSString *arg = arguments[i] ?: @"";
        argv[i + 1] = strdup([arg UTF8String] ?: "");
        if (!argv[i + 1]) allocFailed = YES;
    }
    argv[argc - 1] = NULL;
    if (allocFailed) {
        for (NSUInteger i = 0; i < argc; i++) {
            if (argv[i]) free(argv[i]);
        }
        free(argv);
        return -102;
    }

    pid_t pid = -1;
    int rc = posix_spawn(&pid, cpath, NULL, NULL, argv, environ);
    for (NSUInteger i = 0; i < argc; i++) {
        if (argv[i]) free(argv[i]);
    }
    free(argv);
    if (rc != 0 || pid <= 0) return rc != 0 ? rc : -103;

    int status = 0;
    int loops = timeoutMs > 0 ? timeoutMs / 100 : 30;
    if (loops < 1) loops = 1;
    for (int i = 0; i < loops; i++) {
        pid_t w = waitpid(pid, &status, WNOHANG);
        if (w == pid) {
            if (WIFEXITED(status)) return WEXITSTATUS(status);
            if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
            return -104;
        }
        if (w < 0) return -105;
        usleep(100 * 1000);
    }
    kill(pid, SIGKILL);
    waitpid(pid, &status, 0);
    return -106;
}

static int TLinkRunPrivhelperOpenBundle(NSString *bundleId)
{
    if (bundleId.length == 0) return -100;
    return TLinkRunPrivhelper(@[@"--open-bundle", bundleId], 3000);
}

static NSData *TLinkRunForegroundClipboardBroker(NSString *body)
{
    static NSString *const streamControlBundleId = @"com.tlinkauto.streamcontrol";

    NSString *restoreBundleId = TLinkSBSCopyFrontmostBundleId();
    if (restoreBundleId.length == 0 && sTLinkLastFrontmostBundleId.length > 0) {
        uint64_t now = TLinkNowMs();
        uint64_t age = (sTLinkLastFrontmostAtMs > 0 && now >= sTLinkLastFrontmostAtMs)
            ? now - sTLinkLastFrontmostAtMs
            : UINT64_MAX;
        if (age <= 60000) restoreBundleId = sTLinkLastFrontmostBundleId;
    }
    if ([restoreBundleId isEqualToString:streamControlBundleId] ||
        [restoreBundleId isEqualToString:@"com.apple.springboard"]) {
        restoreBundleId = nil;
    }

    int launchExit = TLinkRunPrivhelper(@[@"--open-bundle", streamControlBundleId], 1500);
    if (launchExit != 0) {
        return TLinkError([NSString stringWithFormat:@"clipboard_foreground_broker_launch_failed exit=%d", launchExit]);
    }

    NSData *lastResponse = nil;
    for (int attempt = 0; attempt < 6; attempt++) {
        usleep(attempt == 0 ? 200 * 1000 : 120 * 1000);
        lastResponse = TLinkRunClipboardService(body, 6013, 300);
        if (!TLinkClipboardResponseSucceeded(lastResponse)) continue;

        NSString *bundleToRestore = [restoreBundleId copy];
        if (bundleToRestore.length > 0) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                usleep(250 * 1000);
                int restoreExit = TLinkRunPrivhelperOpenBundle(bundleToRestore);
                POCLogf("clipboard-broker: restore bundle=%s exit=%d",
                        bundleToRestore.UTF8String ?: "", restoreExit);
            });
        }
        POCLogf("clipboard-broker: app-side request succeeded restore=%s",
                restoreBundleId.UTF8String ?: "");
        return lastResponse;
    }

    NSString *lastText = TLinkResponseStringFromData(lastResponse);
    return TLinkError([NSString stringWithFormat:@"clipboard_foreground_broker_failed %@",
                       lastText.length > 0 ? lastText : @"app_bridge_no_response"]);
}

static int TLinkRunPrivhelperKillBundle(NSString *bundleId)
{
    if (bundleId.length == 0) return -100;
    return TLinkRunPrivhelper(@[@"--kill-bundle", bundleId], 4000);
}

static int TLinkRunPrivhelperOpenURL(NSString *rawURL)
{
    if (rawURL.length == 0) return -100;
    return TLinkRunPrivhelper(@[@"--open-url", rawURL], 3000);
}

static int TLinkRunPrivhelperClearData(NSString *bundleId)
{
    if (bundleId.length == 0) return -100;
    return TLinkRunPrivhelper(@[@"--clear-data", bundleId], 7000);
}

static NSData *TLinkHandleRespring(NSString *body)
{
    NSString *confirmation = [[TLinkCleanPayload(body) lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![confirmation isEqualToString:@"confirm"]) {
        return TLinkError(@"respring_requires_confirm use_task_74confirm");
    }

    TLinkScriptSession *session = sTLinkScriptSession;
    if (TLinkScriptIsActive(session)) {
        @synchronized (session) {
            session.stopRequested = YES;
            session.state = @"stopping";
        }
        TLinkScriptAppendLog(session, @"respring requested");
    }

    int helperExit = TLinkRunPrivhelper(@[@"--respring"], 5000);
    if (helperExit != 0) {
        return TLinkError([NSString stringWithFormat:@"respring_failed exit=%d see_privhelper_log", helperExit]);
    }
    return TLinkSuccess(@"respring_requested_via_privhelper");
}

static NSData *TLinkHandleOpenApplication(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"open_app_missing_bundle_id");
    TLinkRememberFrontmost(bundleId, @"task11:expected", -1);
    int helperExit = TLinkRunPrivhelperOpenBundle(bundleId);
    if (helperExit == 0) {
        TLinkRememberFrontmost(bundleId, @"task11:privhelper", 0);
        return TLinkSuccess([NSString stringWithFormat:@"frontmost_expected;;%@;;launch_via_privhelper", bundleId]);
    }
    return TLinkSuccess([NSString stringWithFormat:@"frontmost_expected;;%@;;launch_helper_failed_or_limited_on_trollstore;;exit=%d", bundleId, helperExit]);
}

static NSData *TLinkHandleAppKill(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"kill_app_missing_bundle_id");
    if ([bundleId isEqualToString:@"com.apple.springboard"]) {
        return TLinkUnsupported(31, @"refusing_to_kill_springboard");
    }
    int helperExit = TLinkRunPrivhelperKillBundle(bundleId);
    if (helperExit != 0) {
        return TLinkError([NSString stringWithFormat:@"kill_app_failed_or_limited_on_trollstore bundle=%@ exit=%d", bundleId, helperExit]);
    }
    if ([sTLinkLastFrontmostBundleId isEqualToString:bundleId]) {
        sTLinkLastFrontmostBundleId = @"";
        sTLinkLastFrontmostSource = @"task31:privhelper-killed";
        sTLinkLastFrontmostPid = 0;
        sTLinkLastFrontmostAtMs = TLinkNowMs();
    }
    return TLinkSuccess(@"kill_app_via_privhelper");
}

static NSData *TLinkHandleClearAppData(NSString *body)
{
    NSString *bundleId = TLinkCleanPayload(body);
    if (bundleId.length == 0) return TLinkError(@"clear_app_data_missing_bundle_id");
    if ([bundleId isEqualToString:@"com.apple.springboard"] ||
        [bundleId isEqualToString:@"com.tlinkauto.streamcontrol"]) {
        return TLinkUnsupported(72, @"refusing_to_clear_protected_bundle");
    }
    int helperExit = TLinkRunPrivhelperClearData(bundleId);
    if (helperExit != 0) {
        return TLinkError([NSString stringWithFormat:@"clear_app_data_failed_or_refused bundle=%@ exit=%d", bundleId, helperExit]);
    }
    if ([sTLinkLastFrontmostBundleId isEqualToString:bundleId]) {
        sTLinkLastFrontmostBundleId = @"";
        sTLinkLastFrontmostSource = @"task72:privhelper-cleared";
        sTLinkLastFrontmostPid = 0;
        sTLinkLastFrontmostAtMs = TLinkNowMs();
    }
    return TLinkSuccess(@"clear_data_via_privhelper");
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
    pid_t pid = TLinkResolvePidForBundleId(bundleId);
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
    NSString *knownBundleId = nil;
    if ([lowerRaw hasPrefix:@"prefs:"]) {
        knownBundleId = @"com.apple.Preferences";
    } else if ([lowerRaw hasPrefix:@"app-prefs:"]) {
        knownBundleId = @"com.apple.Preferences";
    }
    NSURL *url = [NSURL URLWithString:raw];
    if (!url) return TLinkError(@"open_url_invalid_url");
    int helperExit = TLinkRunPrivhelperOpenURL(raw);
    if (helperExit == 0) {
        if (knownBundleId.length > 0) TLinkRememberFrontmost(knownBundleId, @"task54:privhelper", 0);
        return TLinkSuccess(@"open_url_via_privhelper");
    }
    return TLinkError([NSString stringWithFormat:@"open_url_failed_or_limited_on_trollstore exit=%d", helperExit]);
}

static NSData *TLinkHandleHelloStatus(void)
{
    NSDictionary *licenseStatus = TLinkLicenseStatusDictionary();
    NSDictionary *backgroundService = [NSDictionary dictionaryWithContentsOfFile:kTLinkBackgroundSchedulerDiagnosticsPath];
    if (![backgroundService isKindOfClass:[NSDictionary class]]) {
        backgroundService = @{
            @"mode": @"best_effort_bgtaskscheduler_after_first_launch",
            @"state": @"not_registered_or_no_diagnostics",
            @"diagnostics_path": kTLinkBackgroundSchedulerDiagnosticsPath,
        };
    }
    NSDictionary *licenseLifecycle = [NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseLifecycleDiagnosticsPath];
    if (![licenseLifecycle isKindOfClass:[NSDictionary class]]) {
        licenseLifecycle = @{
            @"mode": @"foreground_bg_single_flight_backoff_v1",
            @"state": @"no_app_lifecycle_diagnostics",
            @"diagnostics_path": kTLinkLicenseLifecycleDiagnosticsPath,
        };
    }
    NSDictionary *remoteBridge = [NSDictionary dictionaryWithContentsOfFile:kTLinkRemoteBridgeDiagnosticsPath];
    if (![remoteBridge isKindOfClass:[NSDictionary class]]) {
        remoteBridge = @{
            @"state": @"not_started",
            @"diagnostics_path": kTLinkRemoteBridgeDiagnosticsPath,
        };
    }
    NSDictionary *capabilities = @{
        @"touch": @(YES),
        @"touchAck": @(YES),
        @"nativeTouch": @(YES),
        @"touchRecording": @(YES),
        @"touchRecordingMode": @"iohid_monitor_raw_js_replay",
        @"tapMacro": @(YES),
        @"tapMacroMode": @"bounded_async_native_tap",
        @"multiTouchRaw": @(YES),
        @"multiTouchRawMode": @"legacy_task10_parent_with_multiple_finger_children",
        @"zoom": @(YES),
        @"zoomState": @"experimental",
        @"zoomTask": @64,
        @"zoomWire": @"task64_additive_zoom_v1",
        @"zoomFingerCounts": @[@2, @3],
        @"zoomBackend": @"legacy_multitouch_parent_frames",
        @"zoomGeometry": @"radial_linear_interpolation_v1",
        @"zoomValidation": @"preflight_bounds_v1",
        @"zoomCleanup": @"all_fingers_up_on_exception_v1",
        @"zoomDeviceValidated": @(NO),
        @"zoomPhase": @2,
        @"zoomClients": @"task64_python_js_webtango_v1",
        @"zoomDiagnostics": TLinkZoomDiagnosticsDictionary(),
        @"capture": @(YES),
        @"captureMode": @"detached_iosurface_bitmap",
        @"screenshotAlbum": @(YES),
        @"screenshotAlbumMode": @"photos_framework_tlinkauto_album",
        @"h264": @(YES),
        @"remoteBridge": @(YES),
        @"remoteBridgeMode": @"outbound_wss_control_and_zxh2_video_mvp",
        @"image": @(YES),
        @"color": @(YES),
        @"frame": @(YES),
        @"keyboardClipboard": @(YES),
        @"clipboardImage": @(YES),
        @"clipboardUIDaemon": @(YES),
        @"clipboardBackgroundEntitlement": @(YES),
        @"clipboardDirectWrite": @(YES),
        @"clipboardForegroundBroker": @(YES),
        @"backgroundUIBridge": @(YES),
        @"backgroundVisualNotifications": @(YES),
        @"backgroundVisualCFUserNotification": @(YES),
        @"backgroundPositionedToastOverlay": @(YES),
        @"backgroundToastUIService": @"TLinkUIService.app_port_6017_uimain_context_v6_ephemeral_native_retry",
        @"backgroundToastFixedCenter": @(YES),
        @"clipboardMode": @"background_entitled_uidaemon_with_ui_bridge_and_foreground_fallback",
        @"keyboardHIDPaste": @(YES),
        @"keyboardHIDEditing": @(YES),
        @"keyboardMode": @"background_clipboard_hid_paste_cursor_delete",
        @"keyboardInputMode": @"clipboard_command_v_best_effort",
        @"keyboardVisibilityMode": @"limited_requires_springboard_keyboard_observer",
        @"hardwareKey": @(YES),
        @"hardwareKeyMode": @"hid_keyboard_event",
        @"ocr": @(YES),
        @"visionOCR": @(YES),
        @"ocrInputMode": @"png_data",
        @"ocrWorkerIsolation": @(YES),
        @"ocrWorkerBreadcrumbs": @(YES),
        @"ocrVisionState": @"experimental",
        @"ocrVisionProfile": @"app_cpu_default_worker_cpu_opt_in_xxt_compat_app_foreground",
        @"ocrVisionCPUOnly": @(YES),
        @"ocrVisionXXTCompat": @(YES),
        @"ocrVisionXXTCompatInput": @"png_bridge_then_compact_cgimage",
        @"ocrVisionXXTCompatPixelLayout": @"compact_bgra8888_premultiplied_first_stride_width_x4",
        @"ocrVisionXXTCompatCompute": @"automatic",
        @"ocrVisionXXTCompatHost": @"foreground_app_6011",
        @"ocrVisionXXTCompatForegroundRequired": @(YES),
        @"ocrVisionAppWatchdogMs": @15000,
        @"ocrVisionAppBridgeProtocol": @2,
        @"ocrVisionDebugLog": kTLinkVisionOCRDebugLogPath,
        @"ocrVisionFallback": @"none",
        @"ocrAppSideBridge": @(YES),
        @"ocrAppRGBBridge": @(YES),
        @"ocrAppAccurateRetry": @(YES),
        @"tesseractOCR": @(YES),
        @"tesseractOCRCompat": @(YES),
        @"tesseractOCRMode": @"true_tesseract_static_libs_memory_fallback_requires_traineddata",
        @"tesseractInitSource": sTLinkLastTesseractInitSource ?: @"none",
        @"tesseractInitAttempts": sTLinkLastTesseractInitAttempts ?: @"",
        @"tesseractInitAtMs": @(sTLinkLastTesseractInitAtMs),
        @"script": @(YES),
        @"scriptMode": @"javascriptcore_rootfull_compat_facade",
        @"scriptCompatFacade": @(YES),
        @"scriptResponseShape": @"ok_code_payload_error_fields",
        @"scriptRunTaskAlias": @(YES),
        @"scriptStorageAPI": @(YES),
        @"scriptFileHandleAPI": @(YES),
        @"scriptFileHandleMode": @"shared_rootfull_trollstore_bundle_relative",
        @"scriptFileHandleMaxOpen": @(kTLinkScriptMaxOpenFiles),
        @"scriptFileHandleMaxTransferBytes": @(kTLinkScriptMaxFileTransferBytes),
        @"scriptKeyboardAPI": @(YES),
        @"scriptColorFrameAPI": @(YES),
        @"scriptImageAPI": @(YES),
        @"scriptOCRAPI": @(YES),
        @"scriptAppAPI": @(YES),
        @"scriptPlaySettings": @(YES),
        @"scriptHardwareKey": @(YES),
        @"scriptTapMacro": @(YES),
        @"scriptLogClear": @(YES),
        @"smartWait": @(YES),
        @"smartWaitState": @"implemented",
        @"smartWaitPhase": @1,
        @"smartWaitSchema": @"smart_wait_result_v1",
        @"smartWaitClients": @"rootfull_js_trollstore_js_webtango_v1",
        @"smartWaitLocators": @[@"predicate", @"app", @"color", @"image", @"text", @"image_gone", @"tap_when_visible"],
        @"smartWaitFrameStrategy": @"fresh_frame_per_attempt_release_always_template_open_once",
        @"smartWaitTimeoutMaxMs": @300000,
        @"smartWaitIntervalMinMs": @20,
        @"smartWaitStableFramesMax": @10,
        @"smartWaitDeviceValidated": @(NO),
        @"runHistory": @(YES),
        @"runHistoryState": @"implemented",
        @"runHistoryVersion": @1,
        @"runHistorySchema": TLinkRunHistorySchemaV1,
        @"failureEvidenceSchema": TLinkFailureEvidenceSchemaV1,
        @"runHistoryTransport": @"task60_status_json_v1",
        @"runHistoryRetentionMaxRuns": @50,
        @"failureEvidenceScreenshot": @"best_effort_png_on_failure",
        @"runHistoryDeviceValidated": @(NO),
        @"securePairing": @(NO),
        @"securePairingState": @"contract_only",
        @"securePairingPhase": @0,
        @"securePairingContractVersion": @1,
        @"securePairingTransport": @"zxsp_json_v1",
        @"securePairingMode": @"observe_only",
        @"securePairingLegacyPolicy": @"unchanged_p0",
        @"securePairingCrypto": @"p256_ecdh_ecdsa_hkdf_sha256_aes256_gcm",
        @"securePairingDeviceValidated": @(NO),
        @"license": @(YES),
        @"licenseSignedLease": @(YES),
        @"licenseDeviceBound": @(YES),
        @"licenseDeviceKeyProof": licenseStatus[@"device_key_proof"] ?: @NO,
        @"licenseGenerationSync": @(YES),
        @"licensePolicyMode": @"explicit_table_fail_closed",
        @"licenseRuntimeRecheck": @(YES),
        @"h264LicenseRecheckSeconds": @5,
        @"scriptLicenseHeartbeatSeconds": @1,
        @"licenseGeneration": licenseStatus[@"license_generation"] ?: @0,
        @"licenseRecovery": @(YES),
        @"licenseCorruptLeaseQuarantine": @(YES),
        @"licenseDevicePublicKeyRepair": @(YES),
        @"licenseClockSkewToleranceSeconds": licenseStatus[@"clock_skew_tolerance_seconds"] ?: @60,
        @"licenseEnforcement": licenseStatus[@"enforcement_enabled"] ?: @NO,
        @"licenseEffectiveAccess": licenseStatus[@"effective_access"] ?: @NO,
        @"licenseMode": [licenseStatus[@"enforcement_enabled"] boolValue]
            ? @"cloudflare_worker_signed_lease_p256_enforced"
            : @"cloudflare_worker_signed_lease_p256_observe",
        @"respring": @(YES),
        @"respringMode": @"privhelper_validated_springboard_signal",
        @"scheduler": @(YES),
        @"schedulerMode": @"streamd_lite",
        @"schedulerAutoLaunch": @(YES),
        @"autoLaunchMode": @"startup_after_streamd",
        @"settingsCache": @(YES),
        @"keepAwake": @(YES),
        @"keepAwakeMode": @"foreground_app_plus_background_uidaemon_best_effort",
        @"visualFeedback": @(YES),
        @"visualFeedbackMode": @"foreground_overlay_background_uiservice_positioned_cfusernotification_fallback",
        @"toastOverlay": @(YES),
        @"alertOverlay": @(YES),
        @"dialogOverlay": @(YES),
        @"dialogOverlayMode": @"foreground_overlay_or_background_cfusernotification_alert",
        @"touchIndicator": @(YES),
        @"touchIndicatorEnabled": @(sTLinkTouchIndicatorEnabled),
        @"appMgmt": @(YES),
        @"appMgmtMode": @"limited_process_info_helper_launch_kill",
        @"appLaunchMode": @"privhelper_best_effort",
        @"appKillMode": @"privhelper_best_effort",
        @"openURLMode": @"privhelper_best_effort",
        @"connectivity": @(YES),
        @"connectivityMode": @"best_effort_private_framework",
        @"wifi": @(YES),
        @"bluetooth": @(YES),
        @"airplane": @(YES),
        @"cellularData": @(YES),
        @"vpn": @(YES),
        @"vpnMode": @"background_agent_ikev2_on_demand",
        @"vpnContractVersion": @1,
        @"vpnLegacyTask": @59,
        @"vpnState": @"background_control",
        @"vpnQuery": @"agent_6016_app_6015_interface_fallback",
        @"vpnControl": @"agent_6016_with_foreground_fallback",
        @"vpnBackend": @"nevpnmanager_ikev2_background_agent",
        @"vpnBroker": @"vpnagent_6016_then_StreamControl_6015",
        @"vpnProfileScope": @"tlink_owned_only",
        @"vpnConfigurationTransport": @"local_ui_keychain_only",
        @"vpnCredentialsOverTask59": @(NO),
        @"vpnPhase": @5,
        @"vpnBackgroundAgent": @"validated_mobile_process_v2",
        @"vpnOnDemand": @"local_ui_connect_all_networks",
        @"vpnDisconnectPolicy": @"explicit_disconnect_disables_on_demand",
        @"vpnDiagnostics": @"task59_action2_base64_json_v1",
        @"vpnEntitlementProbe": @"vpnagent_process_then_foreground_app_via_592",
        @"vpnProfileIdentifier": @"tlinkauto-managed-v1",
        @"frontmost": @(YES),
        @"clearData": @(YES),
        @"clearDataMode": @"privhelper_best_effort_data_container_only",
        @"shell": @(sTLinkShellTaskEnabled),
        @"shellMode": sTLinkShellTaskEnabled ? @"local_sh_gated_timeout_base64_json" : @"disabled_by_settings",
        @"hidMonitor": @(YES),
        @"privhelper": @(YES),
        @"privhelperMode": @"open_kill_restart_ensure_streamd_clipboardd_vpnagent_mobile_foreground_fallback_respring",
        @"installedBundlePath": TLinkInstalledApplicationBundlePath() ?: @"",
        @"resolvedStreamdPath": TLinkBundledExecutablePath(@"streamd") ?: @"",
        @"resolvedPrivhelperPath": TLinkPrivhelperPath() ?: @"",
        @"serviceMode": @"helper_ensure_streamd_best_effort",
        @"backgroundAutoStart": @(YES),
        @"backgroundAutoStartMode": @"best_effort_bgtaskscheduler_after_first_launch",
        @"trueBootAutoStart": @(NO),
    };
    CGSize screen = TLinkScreenPixelSize();
    if (sTLinkLastFrontmostBundleId.length > 0) {
        (void)TLinkResolvePidForBundleId(sTLinkLastFrontmostBundleId);
    }
    uint64_t nowMs = TLinkNowMs();
    NSDictionary *licenseEnforcement = nil;
    @synchronized (TLinkVisualFeedbackLock()) {
        licenseEnforcement = @{
            @"task10_drop_count": @(sTLinkLicenseDropCount),
            @"last_drop_at_ms": @(sTLinkLicenseLastDropAtMs),
            @"last_drop_error": sTLinkLicenseLastDropError ?: @"",
            @"policy_mode": @"explicit_table_fail_closed",
        };
    }
    uint64_t frontmostAgeMs = (sTLinkLastFrontmostAtMs > 0 && nowMs >= sTLinkLastFrontmostAtMs)
        ? nowMs - sTLinkLastFrontmostAtMs
        : 0;
    NSDictionary *payload = @{
        @"runtime": @"trollstore",
        @"service": @"streamd",
        @"service_version": @23,
        @"license_contract_version": @1,
        @"license_generation": licenseStatus[@"license_generation"] ?: @0,
        @"license_last_checked_at_ms": licenseStatus[@"last_checked_at_ms"] ?: @0,
        @"license_source": licenseStatus[@"source"] ?: @"shared_verifier_disk",
        @"launch_executable_path": sTLinkLaunchExecutablePath ?: @"",
        @"phase": @"image-color-frame-ocr-app-script-lite",
        @"pid": @((int)getpid()),
        @"tlinkauto": @{@"port": @6000, @"protocols": @[@"v0-line", @"legacy-task"]},
        @"device": @{
            @"name": [UIDevice currentDevice].name ?: @"",
            @"system_name": [UIDevice currentDevice].systemName ?: @"iOS",
            @"system_version": [UIDevice currentDevice].systemVersion ?: @"",
            @"model": TLinkModelName(),
        },
        @"script": TLinkScriptStatusDictionary(),
        @"run_history": TLinkRunHistorySnapshot(20),
        @"event_channel": TLinkEventChannelStatus(),
        @"adaptive_streaming": TLinkH264AdaptiveStreamingStatus(),
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
        @"license": licenseStatus,
        @"license_enforcement": licenseEnforcement,
        @"vpn_diagnostics": TLinkVPNTrollStoreDiagnosticsSnapshot(
            @(TLinkVPNInterfaceActive()),
            @"probe_vpnagent_via_task_592",
            @"probe_foreground_app_via_task_592"),
        @"license_lifecycle": licenseLifecycle,
        @"background_service": backgroundService,
        @"remote_bridge": remoteBridge,
        @"recording": TLinkRecordingStatusDictionary(),
        @"tap_macro": TLinkTapMacroStatusDictionary(),
        @"scheduler": TLinkSchedulerStatusDictionary(),
        @"settings": TLinkRuntimeSettingsDictionary(),
        @"keep_awake": TLinkKeepAwakeDictionary(),
        @"visual_feedback": TLinkVisualFeedbackDictionary(),
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
    NSDictionary *dirAttrs = @{NSFilePosixPermissions: @0775};
    NSArray<NSString *> *dirs = @[
        @"/var/mobile/Library/TLinkauto",
        @"/var/mobile/Library/TLinkauto/scripts",
        kTLinkRecordingScriptsPath,
        @"/var/mobile/Library/TLinkauto/config",
        @"/var/mobile/Library/TLinkauto/config/tweak",
        @"/var/mobile/Library/TLinkauto/screenshots",
        @"/var/mobile/Library/TLinkauto/tmp",
    ];
    for (NSString *dir in dirs) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:dirAttrs error:nil];
        lchown([dir fileSystemRepresentation], 501, 501);
        chmod([dir fileSystemRepresentation], 0775);
    }

    NSArray<NSString *> *repairRoots = @[
        @"/var/mobile/Library/TLinkauto/scripts",
        @"/var/mobile/Library/TLinkauto/config",
        @"/var/mobile/Library/TLinkauto/screenshots",
    ];
    for (NSString *root in repairRoots) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
        for (NSString *relative in enumerator) {
            NSString *path = [root stringByAppendingPathComponent:relative];
            BOOL isDir = NO;
            [fm fileExistsAtPath:path isDirectory:&isDir];
            const char *fsPath = [path fileSystemRepresentation];
            struct stat st;
            if (lstat(fsPath, &st) == 0 && S_ISLNK(st.st_mode)) continue;
            lchown(fsPath, 501, 501);
            chmod(fsPath, isDir ? 0775 : 0664);
        }
    }
}

static void TLinkLoadSettingsConfig(void)
{
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:kTLinkSettingsConfigPath];
    NSDictionary *touch = [config[@"touch_indicator"] isKindOfClass:[NSDictionary class]] ? config[@"touch_indicator"] : nil;
    BOOL enabled = [touch[@"show"] boolValue];
    BOOL switchApp = config[@"switch_app_before_run_script"] ? [config[@"switch_app_before_run_script"] boolValue] : YES;
    BOOL popup = config[@"double_click_volume_show_popup"] ? [config[@"double_click_volume_show_popup"] boolValue] : YES;
    NSDictionary *shell = [config[@"shell"] isKindOfClass:[NSDictionary class]] ? config[@"shell"] : nil;
    BOOL shellEnabled = [shell[@"enabled"] boolValue];
    @synchronized (TLinkVisualFeedbackLock()) {
        sTLinkTouchIndicatorEnabled = enabled;
        sTLinkSwitchAppBeforeRunScript = switchApp;
        sTLinkDoubleClickVolumeShowPopup = popup;
        sTLinkShellTaskEnabled = shellEnabled;
    }
    POCLogf("settings: loaded touch_indicator.show=%d switch_app_before_run_script=%d double_click_volume_show_popup=%d shell.enabled=%d path=%s",
            enabled ? 1 : 0,
            switchApp ? 1 : 0,
            popup ? 1 : 0,
            shellEnabled ? 1 : 0,
            [kTLinkSettingsConfigPath UTF8String]);
}

static BOOL TLinkPersistShellTaskEnabled(BOOL enabled)
{
    TLinkEnsureRuntimeDirectories();
    NSDictionary *loaded = [NSDictionary dictionaryWithContentsOfFile:kTLinkSettingsConfigPath];
    NSMutableDictionary *config = loaded ? [loaded mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *shell = [config[@"shell"] isKindOfClass:[NSDictionary class]]
        ? [config[@"shell"] mutableCopy]
        : [NSMutableDictionary dictionary];
    shell[@"enabled"] = @(enabled);
    config[@"shell"] = shell;
    return [config writeToFile:kTLinkSettingsConfigPath atomically:YES];
}

static NSData *TLinkHandleUpdateCache(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    NSString *mode = parts.count >= 1 ? [parts[0] lowercaseString] : @"";
    if ([mode isEqualToString:@"shell"]) {
        if (parts.count < 2) return TLinkError(@"shell_setting_requires_value");
        BOOL enabled = [parts[1] intValue] != 0;
        @synchronized (TLinkVisualFeedbackLock()) {
            sTLinkShellTaskEnabled = enabled;
        }
        BOOL persisted = TLinkPersistShellTaskEnabled(enabled);
        return TLinkSuccess([NSString stringWithFormat:@"shell_task_set;;%d;;persisted=%d", enabled ? 1 : 0, persisted ? 1 : 0]);
    }

    int type = parts.count >= 1 ? [parts[0] intValue] : 0;
    TLinkLoadSettingsConfig();
    NSDictionary *settings = TLinkRuntimeSettingsDictionary();
    NSString *summary = [NSString stringWithFormat:@"cache_updated;;type=%d;;touch_indicator_show=%d;;switch_app_before_run_script=%d;;double_click_volume_show_popup=%d;;shell_task_enabled=%d",
                         type,
                         [settings[@"touch_indicator_show"] boolValue] ? 1 : 0,
                         [settings[@"switch_app_before_run_script"] boolValue] ? 1 : 0,
                         [settings[@"double_click_volume_show_popup"] boolValue] ? 1 : 0,
                         [settings[@"shell_task_enabled"] boolValue] ? 1 : 0];
    return TLinkSuccess(summary);
}

static void TLinkShellAppendAvailable(int fd, NSMutableData *data, NSUInteger maxBytes, BOOL *truncated)
{
    if (fd < 0 || !data) return;
    uint8_t buffer[4096];
    while (YES) {
        ssize_t n = read(fd, buffer, sizeof(buffer));
        if (n > 0) {
            NSUInteger remaining = data.length >= maxBytes ? 0 : maxBytes - data.length;
            NSUInteger accepted = MIN((NSUInteger)n, remaining);
            if (accepted > 0) [data appendBytes:buffer length:accepted];
            if (accepted < (NSUInteger)n && truncated) *truncated = YES;
            continue;
        }
        if (n == 0) break;
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) break;
        break;
    }
}

static NSString *TLinkShellBase64Payload(NSString *output, int exitCode)
{
    NSData *data = [(output ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSString *encoded = [data base64EncodedStringWithOptions:0] ?: @"";
    return [NSString stringWithFormat:@"%d;;%@", exitCode, encoded];
}

static BOOL TLinkShellFindExecutable(NSString *name, NSString **outPath)
{
    if (name.length == 0) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([name hasPrefix:@"/"] && [fm isExecutableFileAtPath:name]) {
        if (outPath) *outPath = name;
        return YES;
    }
    NSArray<NSString *> *dirs = @[@"/bin", @"/usr/bin", @"/usr/sbin", @"/sbin", @"/var/jb/bin", @"/var/jb/usr/bin"];
    for (NSString *dir in dirs) {
        NSString *path = [dir stringByAppendingPathComponent:name];
        if ([fm isExecutableFileAtPath:path]) {
            if (outPath) *outPath = path;
            return YES;
        }
    }
    return NO;
}

static NSString *TLinkShellTrimCommand(NSString *command)
{
    return [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSArray<NSString *> *TLinkShellTokenize(NSString *command)
{
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    unichar quote = 0;
    BOOL escaped = NO;
    for (NSUInteger i = 0; i < command.length; i++) {
        unichar ch = [command characterAtIndex:i];
        if (escaped) {
            [current appendFormat:@"%C", ch];
            escaped = NO;
            continue;
        }
        if (ch == '\\' && quote != '\'') {
            escaped = YES;
            continue;
        }
        if (quote != 0) {
            if (ch == quote) quote = 0;
            else [current appendFormat:@"%C", ch];
            continue;
        }
        if (ch == '\'' || ch == '"') {
            quote = ch;
            continue;
        }
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:ch]) {
            if (current.length > 0) {
                [tokens addObject:[current copy]];
                [current setString:@""];
            }
            continue;
        }
        if (ch == '>') {
            if (current.length > 0) {
                [tokens addObject:[current copy]];
                [current setString:@""];
            }
            if (i + 1 < command.length && [command characterAtIndex:i + 1] == '>') {
                [tokens addObject:@">>"];
                i++;
            } else {
                [tokens addObject:@">"];
            }
            continue;
        }
        [current appendFormat:@"%C", ch];
    }
    if (escaped) [current appendString:@"\\"];
    if (current.length > 0) [tokens addObject:[current copy]];
    return quote == 0 ? tokens : nil;
}

static BOOL TLinkShellRunMiniFileCommand(NSArray<NSString *> *tokens, NSString **outText, int *outExitCode)
{
    if (tokens.count == 3 && [tokens[0] isEqualToString:@"cp"]) {
        NSString *source = tokens[1];
        NSString *target = tokens[2];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:source isDirectory:&isDirectory] || isDirectory) {
            if (outText) *outText = [NSString stringWithFormat:@"cp: source unavailable: %@\n", source];
            if (outExitCode) *outExitCode = 1;
            return YES;
        }
        NSError *error = nil;
        if ([fm fileExistsAtPath:target]) [fm removeItemAtPath:target error:&error];
        BOOL copied = error == nil && [fm copyItemAtPath:source toPath:target error:&error];
        if (outText) *outText = copied ? @"" : [NSString stringWithFormat:@"cp: %@\n", error.localizedDescription ?: @"copy failed"];
        if (outExitCode) *outExitCode = copied ? 0 : 1;
        return YES;
    }

    if (tokens.count >= 4 && [tokens[0] isEqualToString:@"printf"]) {
        NSUInteger redirectIndex = [tokens indexOfObject:@">"];
        BOOL append = NO;
        if (redirectIndex == NSNotFound) {
            redirectIndex = [tokens indexOfObject:@">>"];
            append = redirectIndex != NSNotFound;
        }
        if (redirectIndex == NSNotFound || redirectIndex < 2 || redirectIndex + 2 != tokens.count) return NO;
        NSString *text = [[tokens subarrayWithRange:NSMakeRange(1, redirectIndex - 1)] componentsJoinedByString:@" "];
        NSString *target = tokens[redirectIndex + 1];
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        BOOL written = NO;
        NSError *error = nil;
        if (append) {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:target];
            if (!handle) {
                [[NSFileManager defaultManager] createFileAtPath:target contents:nil attributes:nil];
                handle = [NSFileHandle fileHandleForWritingAtPath:target];
            }
            @try {
                [handle seekToEndOfFile];
                [handle writeData:data];
                [handle closeFile];
                written = handle != nil;
            } @catch (NSException *exception) {
                error = [NSError errorWithDomain:@"TLinkMiniShell" code:1 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"append failed"}];
            }
        } else {
            written = [data writeToFile:target options:NSDataWritingAtomic error:&error];
        }
        if (outText) *outText = written ? @"" : [NSString stringWithFormat:@"printf: %@\n", error.localizedDescription ?: @"write failed"];
        if (outExitCode) *outExitCode = written ? 0 : 1;
        return YES;
    }
    return NO;
}

static BOOL TLinkShellRunMiniCommand(NSString *command, NSString **outText, int *outExitCode)
{
    NSString *trimmed = TLinkShellTrimCommand(command);
    if (trimmed.length == 0) {
        if (outText) *outText = @"";
        if (outExitCode) *outExitCode = 0;
        return YES;
    }

    NSArray<NSString *> *andParts = [trimmed componentsSeparatedByString:@"&&"];
    if (andParts.count > 1) {
        NSMutableString *combined = [NSMutableString string];
        int exitCode = 0;
        for (NSString *part in andParts) {
            NSString *text = @"";
            int partExit = 0;
            if (!TLinkShellRunMiniCommand(part, &text, &partExit)) return NO;
            if (text.length > 0) [combined appendString:text];
            exitCode = partExit;
            if (partExit != 0) break;
        }
        if (outText) *outText = combined;
        if (outExitCode) *outExitCode = exitCode;
        return YES;
    }

    if ([trimmed hasPrefix:@"echo "]) {
        if (outText) *outText = [[trimmed substringFromIndex:5] stringByAppendingString:@"\n"];
        if (outExitCode) *outExitCode = 0;
        return YES;
    }
    if ([trimmed isEqualToString:@"echo"]) {
        if (outText) *outText = @"\n";
        if (outExitCode) *outExitCode = 0;
        return YES;
    }
    if ([trimmed isEqualToString:@"pwd"]) {
        if (outText) *outText = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingString:@"\n"];
        if (outExitCode) *outExitCode = 0;
        return YES;
    }
    if ([trimmed isEqualToString:@"whoami"]) {
        if (outText) *outText = [NSString stringWithFormat:@"%s\n", getuid() == 0 ? "root" : "mobile"];
        if (outExitCode) *outExitCode = 0;
        return YES;
    }
    if ([trimmed isEqualToString:@"id"]) {
        uid_t uid = getuid();
        gid_t gid = getgid();
        if (outText) *outText = [NSString stringWithFormat:@"uid=%d gid=%d euid=%d egid=%d\n", uid, gid, geteuid(), getegid()];
        if (outExitCode) *outExitCode = 0;
        return YES;
    }
    if ([trimmed isEqualToString:@"uname"] || [trimmed isEqualToString:@"uname -a"]) {
        struct utsname u;
        memset(&u, 0, sizeof(u));
        if (uname(&u) == 0) {
            if ([trimmed isEqualToString:@"uname"]) {
                if (outText) *outText = [NSString stringWithFormat:@"%s\n", u.sysname];
            } else {
                if (outText) *outText = [NSString stringWithFormat:@"%s %s %s %s %s\n", u.sysname, u.nodename, u.release, u.version, u.machine];
            }
            if (outExitCode) *outExitCode = 0;
            return YES;
        }
    }
    if ([trimmed isEqualToString:@"true"]) {
        if (outText) *outText = @"";
        if (outExitCode) *outExitCode = 0;
        return YES;
    }
    if ([trimmed isEqualToString:@"false"]) {
        if (outText) *outText = @"";
        if (outExitCode) *outExitCode = 1;
        return YES;
    }
    NSArray<NSString *> *tokens = TLinkShellTokenize(trimmed);
    if (tokens && TLinkShellRunMiniFileCommand(tokens, outText, outExitCode)) return YES;
    return NO;
}

static NSData *TLinkHandleShellTask(NSString *body, int taskType)
{
    TLinkLoadSettingsConfig();
    @synchronized (TLinkVisualFeedbackLock()) {
        if (!sTLinkShellTaskEnabled) {
            return TLinkUnsupported(taskType, @"shell_disabled_by_settings enable config shell.enabled");
        }
    }

    NSArray<NSString *> *parts = TLinkSplitBody(body);
    double timeout = 8.0;
    NSString *command = TLinkCleanPayload(body);
    if (parts.count >= 2 && parts[0].length > 0) {
        NSScanner *scanner = [NSScanner scannerWithString:parts[0]];
        double parsedTimeout = 0.0;
        if ([scanner scanDouble:&parsedTimeout] && parsedTimeout > 0.0) {
            timeout = parsedTimeout;
            command = TLinkJoinParts(parts, 1);
        }
    }
    if (timeout < 1.0) timeout = 1.0;
    if (timeout > 30.0) timeout = 30.0;
    if (command.length == 0) return TLinkError(@"shell_empty_command");
    if (command.length > 4096) return TLinkError(@"shell_command_too_long");

    NSArray<NSString *> *shellCandidates = @[@"/bin/sh", @"/usr/bin/sh", @"/var/jb/bin/sh", @"/var/jb/usr/bin/sh"];
    NSString *shellPath = nil;
    for (NSString *candidate in shellCandidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
            shellPath = candidate;
            break;
        }
    }
    if (shellPath.length == 0) {
        NSString *miniOutput = nil;
        int miniExit = 127;
        if (TLinkShellRunMiniCommand(command, &miniOutput, &miniExit)) {
            return TLinkSuccess(TLinkShellBase64Payload(miniOutput, miniExit));
        }

        NSArray<NSString *> *tokens = [command componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSMutableArray<NSString *> *cleanTokens = [NSMutableArray array];
        for (NSString *token in tokens) {
            if (token.length > 0) [cleanTokens addObject:token];
        }
        NSString *exePath = nil;
        if (cleanTokens.count > 0 && TLinkShellFindExecutable(cleanTokens[0], &exePath)) {
            return TLinkError([NSString stringWithFormat:@"shell_unavailable_no_sh direct_exec_not_supported executable=%@", exePath ?: @""]);
        }
        return TLinkError(@"shell_unavailable_no_sh mini_shell_unsupported_command");
    }

    int outPipe[2] = {-1, -1};
    int errPipe[2] = {-1, -1};
    if (pipe(outPipe) != 0 || pipe(errPipe) != 0) {
        if (outPipe[0] >= 0) close(outPipe[0]);
        if (outPipe[1] >= 0) close(outPipe[1]);
        if (errPipe[0] >= 0) close(errPipe[0]);
        if (errPipe[1] >= 0) close(errPipe[1]);
        return TLinkError(@"shell_pipe_failed");
    }

    fcntl(outPipe[0], F_SETFL, O_NONBLOCK);
    fcntl(errPipe[0], F_SETFL, O_NONBLOCK);

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
    const char *argv[] = {[shellPath UTF8String], "-c", [command UTF8String], NULL};
    int spawnErr = posix_spawn(&pid, [shellPath fileSystemRepresentation], &actions, &attr, (char *const *)argv, NULL);

    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    close(outPipe[1]);
    close(errPipe[1]);

    if (spawnErr != 0) {
        close(outPipe[0]);
        close(errPipe[0]);
        return TLinkError([NSString stringWithFormat:@"shell_spawn_failed code=%d", spawnErr]);
    }

    NSMutableData *stdoutData = [NSMutableData data];
    NSMutableData *stderrData = [NSMutableData data];
    BOOL stdoutTruncated = NO;
    BOOL stderrTruncated = NO;
    BOOL timedOut = NO;
    int exitCode = -1;
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeout;
    static const NSUInteger kShellMaxOutputBytes = 256 * 1024;

    while (YES) {
        struct pollfd fds[2] = {
            { outPipe[0], POLLIN | POLLHUP | POLLERR, 0 },
            { errPipe[0], POLLIN | POLLHUP | POLLERR, 0 },
        };
        (void)poll(fds, 2, 50);
        TLinkShellAppendAvailable(outPipe[0], stdoutData, kShellMaxOutputBytes, &stdoutTruncated);
        TLinkShellAppendAvailable(errPipe[0], stderrData, kShellMaxOutputBytes, &stderrTruncated);

        int status = 0;
        pid_t waitResult = waitpid(pid, &status, WNOHANG);
        if (waitResult == pid) {
            if (WIFEXITED(status)) exitCode = WEXITSTATUS(status);
            else if (WIFSIGNALED(status)) exitCode = 128 + WTERMSIG(status);
            break;
        }
        if (CFAbsoluteTimeGetCurrent() >= deadline) {
            timedOut = YES;
            kill(-pid, SIGTERM);
            usleep(150 * 1000);
            if (waitpid(pid, &status, WNOHANG) == 0) kill(-pid, SIGKILL);
            waitpid(pid, &status, 0);
            exitCode = 124;
            break;
        }
    }

    TLinkShellAppendAvailable(outPipe[0], stdoutData, kShellMaxOutputBytes, &stdoutTruncated);
    TLinkShellAppendAvailable(errPipe[0], stderrData, kShellMaxOutputBytes, &stderrTruncated);
    close(outPipe[0]);
    close(errPipe[0]);

    NSMutableData *combined = [NSMutableData dataWithData:stdoutData];
    if (stderrData.length > 0) {
        NSData *prefix = [@"\n[stderr]\n" dataUsingEncoding:NSUTF8StringEncoding];
        [combined appendData:prefix];
        [combined appendData:stderrData];
    }
    if (timedOut) {
        NSData *timeoutNote = [[NSString stringWithFormat:@"\n[tlinkauto] shell timed out after %.1fs\n", timeout] dataUsingEncoding:NSUTF8StringEncoding];
        [combined appendData:timeoutNote];
    }
    if (stdoutTruncated || stderrTruncated) {
        NSData *truncNote = [@"\n[tlinkauto] shell output truncated\n" dataUsingEncoding:NSUTF8StringEncoding];
        [combined appendData:truncNote];
    }
    NSString *output = [[NSString alloc] initWithData:combined encoding:NSUTF8StringEncoding] ?: @"";
    return TLinkSuccess(TLinkShellBase64Payload(output, exitCode));
}

static NSString *TLinkBase64String(NSString *value)
{
    NSData *data = [(value ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    return [data base64EncodedStringWithOptions:0] ?: @"";
}

static NSString *TLinkVisionLanguageFromTesseractLanguage(NSString *lang)
{
    NSString *lower = [[lang ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (lower.length == 0) return @"";
    NSDictionary<NSString *, NSString *> *map = @{
        @"eng": @"en-US",
        @"en": @"en-US",
        @"en-us": @"en-US",
        @"fra": @"fr-FR",
        @"fre": @"fr-FR",
        @"fr": @"fr-FR",
        @"ita": @"it-IT",
        @"it": @"it-IT",
        @"deu": @"de-DE",
        @"ger": @"de-DE",
        @"de": @"de-DE",
        @"spa": @"es-ES",
        @"es": @"es-ES",
        @"por": @"pt-BR",
        @"pt": @"pt-BR",
        @"chi_sim": @"zh-Hans",
        @"zh-hans": @"zh-Hans",
        @"chi_tra": @"zh-Hant",
        @"zh-hant": @"zh-Hant",
    };
    return map[lower] ?: @"";
}

static NSString *TLinkVisionLanguagesFromTesseractLanguage(NSString *lang)
{
    NSArray<NSString *> *rawParts = [lang componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"+,"]];
    NSMutableArray<NSString *> *mapped = [NSMutableArray array];
    for (NSString *part in rawParts) {
        NSString *visionLang = TLinkVisionLanguageFromTesseractLanguage(part);
        if (visionLang.length > 0 && ![mapped containsObject:visionLang]) {
            [mapped addObject:visionLang];
        }
    }
    return [mapped componentsJoinedByString:@",,"];
}

static NSString *TLinkTessdataRoot(void)
{
    NSArray<NSString *> *roots = @[
        @"/var/mobile/Library/TLinkauto",
        [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] ?: @"",
        [[NSBundle mainBundle] bundlePath] ?: @"",
    ];
    for (NSString *root in roots) {
        if (root.length == 0) continue;
        NSString *dir = [root stringByAppendingPathComponent:@"tessdata"];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:dir isDirectory:&isDir] && isDir) {
            return root;
        }
    }
    return @"/var/mobile/Library/TLinkauto";
}

static NSArray<NSString *> *TLinkAvailableTesseractLanguages(void)
{
    NSString *dir = [TLinkTessdataRoot() stringByAppendingPathComponent:@"tessdata"];
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray<NSString *> *langs = [NSMutableArray array];
    for (NSString *file in files ?: @[]) {
        if ([[file pathExtension] isEqualToString:@"traineddata"]) {
            [langs addObject:[file stringByDeletingPathExtension]];
        }
    }
    [langs sortUsingSelector:@selector(compare:)];
    return langs;
}

static tesseract::PageSegMode TLinkTesseractPSM(int psm)
{
    switch (psm) {
        case 3: return tesseract::PSM_AUTO;
        case 6: return tesseract::PSM_SINGLE_BLOCK;
        case 8: return tesseract::PSM_SINGLE_WORD;
        case 7:
        default: return tesseract::PSM_SINGLE_LINE;
    }
}

static tesseract::OcrEngineMode TLinkTesseractOEM(int oem)
{
    switch (oem) {
        case 0: return tesseract::OEM_TESSERACT_ONLY;
        case 2: return tesseract::OEM_TESSERACT_LSTM_COMBINED;
        case 3: return tesseract::OEM_DEFAULT;
        case 1:
        default: return tesseract::OEM_LSTM_ONLY;
    }
}

static NSString *TLinkTesseractOEMName(int oem)
{
    switch (oem) {
        case 0: return @"tesseract";
        case 1: return @"lstm";
        case 2: return @"combined";
        case 3: return @"default";
        default: return [NSString stringWithFormat:@"unknown_%d", oem];
    }
}

static NSArray<NSNumber *> *TLinkTesseractOEMAttempts(int requestedOEM)
{
    NSMutableArray<NSNumber *> *attempts = [NSMutableArray array];
    NSArray<NSNumber *> *ordered = @[@(requestedOEM), @3, @1, @2, @0];
    for (NSNumber *n in ordered) {
        if (![attempts containsObject:n]) [attempts addObject:n];
    }
    return attempts;
}

static UIImage *TLinkScaledImageForTesseract(UIImage *image, int scaleUp)
{
    if (!image || scaleUp <= 1) return image;
    if (scaleUp > 4) scaleUp = 4;
    CGSize size = CGSizeMake(image.size.width * scaleUp, image.size.height * scaleUp);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled ?: image;
}

static NSData *TLinkRunTrueTesseractOCR(UIImage *image,
                                        NSString *lang,
                                        int oem,
                                        int psm,
                                        NSString *whitelist,
                                        int scaleUp,
                                        uint64_t frameAgeMs,
                                        double captureMs)
{
    if (!image) return TLinkError(@"tesseract_capture_image_missing");
    NSString *root = TLinkTessdataRoot();
    NSString *tessdataDir = [root stringByAppendingPathComponent:@"tessdata"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:tessdataDir]) {
        return TLinkError([NSString stringWithFormat:@"tesseract_tessdata_missing path=%@", tessdataDir]);
    }

    NSString *language = lang.length > 0 ? lang : @"eng";
    NSString *trainedData = [tessdataDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.traineddata", language]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:trainedData]) {
        NSArray<NSString *> *langs = TLinkAvailableTesseractLanguages();
        return TLinkError([NSString stringWithFormat:@"tesseract_traineddata_missing lang=%@ path=%@ available=%@",
                           language,
                           trainedData,
                           [langs componentsJoinedByString:@","]]);
    }

    UIImage *workImage = TLinkScaledImageForTesseract(image, scaleUp);
    NSData *png = UIImagePNGRepresentation(workImage);
    if (png.length == 0) return TLinkError(@"tesseract_png_encode_failed");

    PIX *pix = pixReadMem((const l_uint8 *)png.bytes, (size_t)png.length);
    if (!pix) return TLinkError(@"tesseract_pix_read_failed");

    CFAbsoluteTime totalStart = CFAbsoluteTimeGetCurrent();
    tesseract::TessBaseAPI api;
    BOOL initialized = NO;
    NSString *initSource = @"none";
    NSMutableArray<NSString *> *attempts = [NSMutableArray array];
    NSMutableArray<NSString *> *dataPaths = [NSMutableArray array];
    NSArray<NSString *> *orderedDataPaths = @[
        [tessdataDir stringByAppendingString:@"/"],
        tessdataDir,
        [root stringByAppendingString:@"/"],
        root,
    ];
    for (NSString *dataPath in orderedDataPaths) {
        if (dataPath.length > 0 && ![dataPaths containsObject:dataPath]) {
            [dataPaths addObject:dataPath];
        }
    }
    for (NSString *dataPath in dataPaths) {
        if (initialized) break;
        for (NSNumber *attemptOEMNumber in TLinkTesseractOEMAttempts(oem)) {
            int attemptOEM = [attemptOEMNumber intValue];
            NSString *attemptName = TLinkTesseractOEMName(attemptOEM);
            int init = api.Init([dataPath fileSystemRepresentation],
                                [language UTF8String],
                                TLinkTesseractOEM(attemptOEM));
            if (init == 0) {
                initialized = YES;
                initSource = [NSString stringWithFormat:@"path:%@:%@", dataPath, attemptName];
                break;
            }
            [attempts addObject:[NSString stringWithFormat:@"%@:%@", dataPath, attemptName]];
            api.End();
        }
    }
    if (!initialized && [language rangeOfString:@"+"].location == NSNotFound) {
        NSData *trainedDataBytes = [NSData dataWithContentsOfFile:trainedData];
        if (trainedDataBytes.length > 0 && trainedDataBytes.length <= INT_MAX) {
            for (NSNumber *attemptOEMNumber in TLinkTesseractOEMAttempts(oem)) {
                int attemptOEM = [attemptOEMNumber intValue];
                NSString *attemptName = TLinkTesseractOEMName(attemptOEM);
                int init = api.Init((const char *)trainedDataBytes.bytes,
                                    (int)trainedDataBytes.length,
                                    [language UTF8String],
                                    TLinkTesseractOEM(attemptOEM),
                                    nullptr,
                                    0,
                                    nullptr,
                                    nullptr,
                                    false,
                                    nullptr);
                if (init == 0) {
                    initialized = YES;
                    initSource = [NSString stringWithFormat:@"memory:%@", attemptName];
                    break;
                }
                [attempts addObject:[NSString stringWithFormat:@"memory:%@", attemptName]];
                api.End();
            }
        } else {
            [attempts addObject:[NSString stringWithFormat:@"memory:unreadable_or_too_large bytes=%llu",
                                 (unsigned long long)trainedDataBytes.length]];
        }
    }
    if (!initialized) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:trainedData error:nil] ?: @{};
        unsigned long long fileSize = [attrs fileSize];
        sTLinkLastTesseractInitSource = @"failed";
        sTLinkLastTesseractInitAttempts = [attempts componentsJoinedByString:@","];
        sTLinkLastTesseractInitAtMs = TLinkNowMs();
        pixDestroy(&pix);
        return TLinkError([NSString stringWithFormat:@"tesseract_init_failed lang=%@ root=%@ tessdata=%@ size=%llu attempts=%@",
                           language,
                           root,
                           trainedData,
                           fileSize,
                           [attempts componentsJoinedByString:@","]]);
    }
    sTLinkLastTesseractInitSource = initSource ?: @"unknown";
    sTLinkLastTesseractInitAttempts = [attempts componentsJoinedByString:@","];
    sTLinkLastTesseractInitAtMs = TLinkNowMs();
    api.SetPageSegMode(TLinkTesseractPSM(psm));
    if (whitelist.length > 0) {
        api.SetVariable("tessedit_char_whitelist", [whitelist UTF8String]);
    }
    api.SetImage(pix);

    CFAbsoluteTime ocrStart = CFAbsoluteTimeGetCurrent();
    char *utf8 = api.GetUTF8Text();
    double ocrMs = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000.0;
    int confidence = api.MeanTextConf();
    NSString *text = utf8 ? [NSString stringWithUTF8String:utf8] : @"";
    if (utf8) delete [] utf8;
    api.End();
    pixDestroy(&pix);

    text = [[text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    double totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0;
    return TLinkSuccess([NSString stringWithFormat:@"%@;;%.2f;;%llu;;%.3f;;%.3f;;%.3f;;tesseract_init_source=%@",
                         TLinkBase64String(text),
                         (double)confidence,
                         (unsigned long long)frameAgeMs,
                         ocrMs,
                         captureMs,
                         totalMs,
                         initSource ?: @"unknown"]);
}

static BOOL TLinkAppendVisionOCRTextForRegion(int x,
                                              int y,
                                              int w,
                                              int h,
                                              NSString *visionLanguages,
                                              int level,
                                              NSMutableArray<NSString *> *texts,
                                              NSString **error)
{
    // Task 91 uses the safest Vision profile for headless TrollStore: fast
    // recognition, no forced language list, and no language correction.
    (void)visionLanguages;
    NSString *visionPayload = [NSString stringWithFormat:@"1;;%d,,%d,,%d,,%d;;;;0;;%d;;;;0;;",
                               x,
                               y,
                               w,
                               h,
                               level];
    NSData *response = nil;
    @try {
        response = TLinkHandleVisionOCRInProcess(visionPayload);
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSString stringWithFormat:@"tesseract_vision_fallback_exception %@",
                      exception.reason ?: exception.name ?: @"unknown"];
        }
        return NO;
    }

    NSString *rawResponse = TLinkResponseStringFromData(response);
    NSDictionary *result = TLinkTaskResultFromResponseString(rawResponse);
    if (![result[@"ok"] boolValue]) {
        if (error) {
            *error = [NSString stringWithFormat:@"tesseract_vision_fallback_failed %@",
                      result[@"payload"] ?: rawResponse ?: @"unknown"];
        }
        return NO;
    }

    NSString *payload = result[@"payload"] ?: @"";
    NSArray<NSString *> *observations = payload.length > 0 ? [payload componentsSeparatedByString:@";;"] : @[];
    for (NSString *obs in observations) {
        NSArray<NSString *> *fields = [obs componentsSeparatedByString:@",,"];
        if (fields.count > 0 && [fields[0] length] > 0) {
            [texts addObject:fields[0]];
        }
    }
    return YES;
}

static NSData *TLinkHandleTesseractOCRCompatInProcess(NSString *body)
{
    TLinkSetOCRWorkerPhase("tesseract_compat_enter");
    NSString *raw = TLinkCleanPayload(body);
    if ([[raw lowercaseString] isEqualToString:@"check_langs"]) {
        TLinkSetOCRWorkerPhase("tesseract_compat_check_langs");
        NSArray<NSString *> *languages = TLinkAvailableTesseractLanguages();
        return TLinkSuccess([NSString stringWithFormat:@"check_langs;;%@", TLinkBase64String([languages componentsJoinedByString:@","])]);
    }

    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 13) {
        return TLinkError(@"tesseract_vision_fallback_format frame_id;;x;;y;;w;;h;;lang;;oem;;psm;;whitelist_b64;;scale_up;;threshold_mode;;coord;;max_age_ms");
    }

    TLinkSetOCRWorkerPhase("tesseract_compat_parse");
    int x = [parts[1] intValue];
    int y = [parts[2] intValue];
    int w = [parts[3] intValue];
    int h = [parts[4] intValue];
    NSString *lang = parts[5].length > 0 ? parts[5] : @"eng";
    int oem = parts[6].length > 0 ? [parts[6] intValue] : 1;
    int psm = parts[7].length > 0 ? [parts[7] intValue] : 7;
    NSString *whitelist = @"";
    if (parts[8].length > 0) {
        NSData *decoded = [[NSData alloc] initWithBase64EncodedString:parts[8] options:0];
        whitelist = decoded ? [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] ?: @"" : @"";
    }
    int scaleUp = parts[9].length > 0 ? [parts[9] intValue] : 2;
    NSString *coord = parts[11].length > 0 ? parts[11] : @"pixel";
    CGSize screen = TLinkScreenPixelSize();
    int screenW = (int)llround(screen.width);
    int screenH = (int)llround(screen.height);
    if (screenW > 0 && screenH > 0) {
        if (x < 0) {
            w += x;
            x = 0;
        }
        if (y < 0) {
            h += y;
            y = 0;
        }
        if (w <= 0) w = screenW - x;
        if (h <= 0) h = screenH - y;
        if (x >= screenW || y >= screenH) return TLinkError(@"tesseract_vision_fallback_invalid_region");
        if (x + w > screenW) w = screenW - x;
        if (y + h > screenH) h = screenH - y;
    }
    if (w <= 0 || h <= 0) return TLinkError(@"tesseract_vision_fallback_invalid_region");

    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    const uint64_t maxCompatOCRPixels = 4000000;
    uint64_t totalPixels = (uint64_t)w * (uint64_t)h;
    if (totalPixels > maxCompatOCRPixels) {
        return TLinkError([NSString stringWithFormat:@"tesseract_region_too_large max_pixels=%llu requested_pixels=%llu use_smaller_region",
                           (unsigned long long)maxCompatOCRPixels,
                           (unsigned long long)totalPixels]);
    }

    NSString *captureError = nil;
    TLinkSetOCRWorkerPhase("tesseract_compat_capture");
    UIImage *workerScreen = TLinkCaptureScreenImage(&captureError);
    if (!workerScreen || !workerScreen.CGImage) {
        return TLinkError([NSString stringWithFormat:@"tesseract_vision_fallback_capture_failed %@",
                           captureError ?: @"unknown"]);
    }

    CGRect region = CGRectMake(x, y, w, h);
    if ([coord.lowercaseString isEqualToString:@"point"]) {
        CGFloat scale = [UIScreen mainScreen].scale;
        region = CGRectMake(x * scale, y * scale, w * scale, h * scale);
    }
    NSString *cropError = nil;
    TLinkSetOCRWorkerPhase("tesseract_compat_crop");
    UIImage *cropped = TLinkCropImage(workerScreen, region, &cropError);
    if (!cropped) return TLinkError(cropError ?: @"tesseract_crop_failed");

    double captureMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0;
    TLinkSetOCRWorkerPhase("tesseract_true_ocr");
    return TLinkRunTrueTesseractOCR(cropped, lang, oem, psm, whitelist, scaleUp, 0, captureMs);
}

int TLinkRunTesseractOCRWorker(const char *payloadBase64, const char *outputPath)
{
    @autoreleasepool {
        if (!payloadBase64 || !outputPath || outputPath[0] == '\0') return 64;
        TLinkInstallOCRWorkerSignalHandlers(outputPath);

        TLinkSetOCRWorkerPhase("tesseract_worker_decode_payload");
        NSString *encoded = [NSString stringWithUTF8String:payloadBase64];
        NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:encoded ?: @"" options:0];
        NSString *payload = payloadData ? [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding] : nil;
        if (!payload) return 65;

        NSData *response = nil;
        @try {
            TLinkSetOCRWorkerPhase("tesseract_worker_call_handler");
            response = TLinkHandleTesseractOCRCompatInProcess(payload);
        } @catch (NSException *exception) {
            sTLinkKeptScreenImage = nil;
            response = TLinkError([NSString stringWithFormat:@"tesseract_ocr_worker_exception %@",
                                   exception.reason ?: exception.name ?: @"unknown"]);
        }
        if (response.length == 0) return 66;

        TLinkSetOCRWorkerPhase("tesseract_worker_write_response");
        NSString *target = [NSString stringWithUTF8String:outputPath];
        return [response writeToFile:target atomically:NO] ? 0 : 67;
    }
}

static NSData *TLinkHandleTesseractOCRCompat(NSString *body)
{
    return TLinkRunOCRWorkerProcess(body, "--tesseract-ocr-worker");
}

static NSData *TLinkHandleKeepAwake(NSString *body)
{
    NSString *raw = TLinkCleanPayload(body);
    BOOL enabled = [raw intValue] != 0;
    @synchronized (TLinkVisualFeedbackLock()) {
        sTLinkKeepAwakeEnabled = enabled;
    }
    TLinkDispatchBackgroundKeepAwake(enabled);
    uint64_t eventId = TLinkRecordToast([NSString stringWithFormat:@"Keep Awake %@", enabled ? @"On" : @"Off"],
                                        1.5,
                                        0,
                                        2,
                                        14,
                                        @"task40");
    return TLinkSuccess([NSString stringWithFormat:@"keep_awake_%@;;mode=foreground_app_plus_background_uidaemon_best_effort;;event=%llu",
                         enabled ? @"enabled" : @"disabled",
                         eventId]);
}

static NSMutableDictionary *TLinkLoadAutoLaunchConfig(void)
{
    NSMutableDictionary *config = [NSMutableDictionary dictionaryWithContentsOfFile:kTLinkAutoLaunchConfigPath];
    return config ?: [NSMutableDictionary dictionary];
}

static BOOL TLinkSaveAutoLaunchConfig(NSDictionary *config)
{
    NSString *parent = [kTLinkAutoLaunchConfigPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    return [config writeToFile:kTLinkAutoLaunchConfigPath atomically:YES];
}

static NSData *TLinkHandleSetAutoLaunch(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 3) {
        return TLinkError(@"auto_launch_bad_payload expected=name;;script;;enabled");
    }
    NSString *name = parts[0] ?: @"";
    NSString *script = parts[1] ?: @"";
    BOOL enabled = [parts[2] intValue] != 0;
    if (name.length == 0 || script.length == 0) {
        return TLinkError(@"auto_launch_requires_name_and_script");
    }

    NSMutableDictionary *config = TLinkLoadAutoLaunchConfig();
    config[name] = @{@"script": script, @"enabled": @(enabled)};
    if (!TLinkSaveAutoLaunchConfig(config)) {
        return TLinkError(@"auto_launch_save_failed");
    }
    return TLinkSuccess([NSString stringWithFormat:@"auto_launch_set;;%@;;%d", name, enabled ? 1 : 0]);
}

static NSData *TLinkHandleListAutoLaunch(void)
{
    NSDictionary *config = TLinkLoadAutoLaunchConfig();
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    NSArray<NSString *> *keys = [[config allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        NSDictionary *obj = [config[key] isKindOfClass:[NSDictionary class]] ? config[key] : @{};
        NSString *script = [obj[@"script"] isKindOfClass:[NSString class]] ? obj[@"script"] : @"";
        NSString *enabled = [obj[@"enabled"] boolValue] ? @"1" : @"0";
        [entries addObject:[NSString stringWithFormat:@"%@,,%@,,%@", key ?: @"", script, enabled]];
    }
    return TLinkSuccess([entries componentsJoinedByString:@";;"]);
}

static void TLinkEnsureTimerRegistryLocked(void)
{
    if (!sTLinkTimerRegistry) sTLinkTimerRegistry = [NSMutableDictionary dictionary];
    if (!sTLinkTimerInfoRegistry) sTLinkTimerInfoRegistry = [NSMutableDictionary dictionary];
}

static void TLinkCancelTimerLocked(NSString *name)
{
    TLinkEnsureTimerRegistryLocked();
    dispatch_source_t existing = (dispatch_source_t)sTLinkTimerRegistry[name];
    if (existing) {
        dispatch_source_cancel(existing);
        [sTLinkTimerRegistry removeObjectForKey:name];
    }
    [sTLinkTimerInfoRegistry removeObjectForKey:name];
}

static void TLinkSchedulerTimerFired(NSString *name)
{
    NSMutableDictionary *info = nil;
    @synchronized (TLinkVisualFeedbackLock()) {
        info = [sTLinkTimerInfoRegistry[name] mutableCopy];
    }
    if (![info isKindOfClass:[NSDictionary class]]) return;

    NSString *script = [info[@"script"] isKindOfClass:[NSString class]] ? info[@"script"] : @"";
    BOOL repeat = [info[@"repeat"] boolValue];
    NSString *result = @"";
    if (script.length > 0) {
        NSData *response = TLinkHandlePlayScript(script);
        result = TLinkResponseStringFromData(response);
    } else {
        result = @"-1;;timer_missing_script";
    }

    @synchronized (TLinkVisualFeedbackLock()) {
        NSMutableDictionary *stored = sTLinkTimerInfoRegistry[name];
        if (stored) {
            stored[@"last_fired_ms"] = @(TLinkNowMs());
            stored[@"last_result"] = result ?: @"";
        }
        if (!repeat) {
            TLinkCancelTimerLocked(name);
        }
    }
}

static NSData *TLinkHandleSetTimer(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    if (parts.count < 4) {
        return TLinkError(@"timer_bad_payload expected=name;;interval;;repeat;;script");
    }
    NSString *name = parts[0] ?: @"";
    double interval = [parts[1] doubleValue];
    BOOL repeat = [parts[2] intValue] != 0;
    NSString *script = TLinkJoinParts(parts, 3);
    if (name.length == 0) return TLinkError(@"timer_name_required");
    if (script.length == 0) return TLinkError(@"timer_script_required");
    if (interval <= 0.0) return TLinkError(@"timer_interval_must_be_positive");
    if (interval > 86400.0) return TLinkError(@"timer_interval_too_large");

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    if (!timer) return TLinkError(@"timer_create_failed");
    uint64_t intervalNs = (uint64_t)(interval * (double)NSEC_PER_SEC);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNs), repeat ? intervalNs : DISPATCH_TIME_FOREVER, (uint64_t)(0.05 * (double)NSEC_PER_SEC));
    NSString *timerName = [name copy];
    dispatch_source_set_event_handler(timer, ^{
        TLinkSchedulerTimerFired(timerName);
    });

    @synchronized (TLinkVisualFeedbackLock()) {
        TLinkCancelTimerLocked(name);
        TLinkEnsureTimerRegistryLocked();
        sTLinkTimerRegistry[name] = timer;
        sTLinkTimerInfoRegistry[name] = [@{
            @"name": name,
            @"script": script,
            @"interval": @(interval),
            @"repeat": @(repeat),
            @"created_ms": @(TLinkNowMs()),
            @"last_fired_ms": @0,
            @"last_result": @"",
        } mutableCopy];
    }
    dispatch_resume(timer);
    return TLinkSuccess([NSString stringWithFormat:@"timer_set;;%@;;interval=%.3f;;repeat=%d", name, interval, repeat ? 1 : 0]);
}

static NSData *TLinkHandleRemoveTimer(NSString *body)
{
    NSString *name = TLinkCleanPayload(body);
    if (name.length == 0) return TLinkError(@"timer_name_required");
    @synchronized (TLinkVisualFeedbackLock()) {
        TLinkCancelTimerLocked(name);
    }
    return TLinkSuccess([NSString stringWithFormat:@"timer_removed;;%@", name]);
}

static void TLinkLoadConnectivityFrameworks(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = @[
            @"/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
            @"/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi",
            @"/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager",
            @"/System/Library/PrivateFrameworks/BluetoothManager.framework/Frameworks/BTLEAudioController.framework/BTLEAudioController",
            @"/System/Library/PrivateFrameworks/Preferences.framework/Preferences",
            @"/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport",
            @"/System/Library/PrivateFrameworks/CoreTelephony.framework/CoreTelephony",
        ];
        for (NSString *path in paths) {
            dlerror();
            void *handle = dlopen([path fileSystemRepresentation], RTLD_LAZY | RTLD_GLOBAL);
            if (!handle) {
                const char *err = dlerror();
                POCLogf("connectivity: dlopen failed path=%s err=%s",
                        [path fileSystemRepresentation],
                        err ?: "unknown");
            }
        }
    });
}

static NSString *TLinkConnectivityLoadedClassSummary(NSArray<NSString *> *tokens)
{
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return @"classes=none";
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    if (!classes) return @"classes=alloc_failed";
    count = objc_getClassList(classes, count);
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (int i = 0; i < count && matches.count < 12; i++) {
        const char *name = class_getName(classes[i]);
        if (!name) continue;
        NSString *className = [NSString stringWithUTF8String:name];
        for (NSString *token in tokens) {
            if ([className rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:className];
                break;
            }
        }
    }
    free(classes);
    return matches.count > 0
        ? [NSString stringWithFormat:@"classes=%@", [matches componentsJoinedByString:@","]]
        : @"classes=no_match";
}

static NSString *TLinkConnectivityMethodSummaryForClass(Class cls, BOOL classMethods, NSArray<NSString *> *tokens)
{
    if (!cls) return @"methods=none";
    Class target = classMethods ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    if (!methods || count == 0) {
        if (methods) free(methods);
        return @"methods=none";
    }
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count && matches.count < 16; i++) {
        SEL sel = method_getName(methods[i]);
        if (!sel) continue;
        NSString *name = NSStringFromSelector(sel);
        for (NSString *token in tokens) {
            if ([name rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:name];
                break;
            }
        }
    }
    free(methods);
    return matches.count > 0
        ? [matches componentsJoinedByString:@","]
        : @"no_match";
}

static NSString *TLinkConnectivityClassMethodSummary(NSArray<NSString *> *classNames, NSArray<NSString *> *tokens)
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        NSString *classMethods = TLinkConnectivityMethodSummaryForClass(cls, YES, tokens);
        NSString *instanceMethods = TLinkConnectivityMethodSummaryForClass(cls, NO, tokens);
        [parts addObject:[NSString stringWithFormat:@"%@ class=%@ instance=%@", className, classMethods, instanceMethods]];
    }
    return parts.count > 0 ? [parts componentsJoinedByString:@" | "] : @"method_classes=no_match";
}

static BOOL TLinkParseConnectivityAction(NSString *body, int *outAction, int *outValue, NSString **error)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int action = parts.count >= 1 && parts[0].length > 0 ? [parts[0] intValue] : 0;
    int value = 0;
    if (action != 0 && action != 1) {
        if (error) *error = @"connectivity_action_must_be_0_query_or_1_set";
        return NO;
    }
    if (action == 1) {
        if (parts.count < 2) {
            if (error) *error = @"connectivity_set_requires_value";
            return NO;
        }
        value = [parts[1] intValue] ? 1 : 0;
    }
    if (outAction) *outAction = action;
    if (outValue) *outValue = value;
    return YES;
}

static id TLinkSharedConnectivityObjectWithAlloc(NSArray<NSString *> *classNames, BOOL allowAlloc)
{
    TLinkLoadConnectivityFrameworks();
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        SEL queueSel = NSSelectorFromString(@"setSharedInstanceQueue:");
        if ([cls respondsToSelector:queueSel]) {
            @try {
                ((void (*)(Class, SEL, dispatch_queue_t))objc_msgSend)(cls, queueSel, POCSocketQueue());
            } @catch (__unused NSException *exception) {
            }
        }
        NSArray<NSString *> *selectors = @[
            @"sharedInstance",
            @"sharedManager",
            @"sharedController",
            @"sharedBluetoothManager",
            @"defaultManager",
            @"sharedLocalDevice",
            @"localDevice",
            @"defaultLocalDevice",
            @"sharedDevice"
        ];
        for (NSString *selectorName in selectors) {
            SEL sel = NSSelectorFromString(selectorName);
            if ([cls respondsToSelector:sel]) {
                @try {
                    id obj = ((id (*)(Class, SEL))objc_msgSend)(cls, sel);
                    if (obj) return obj;
                } @catch (__unused NSException *exception) {
                }
            }
        }
        if (!allowAlloc) continue;
        @try {
            id allocated = ((id (*)(Class, SEL))objc_msgSend)(cls, @selector(alloc));
            id obj = allocated ? ((id (*)(id, SEL))objc_msgSend)(allocated, @selector(init)) : nil;
            if (obj) return obj;
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static id TLinkSharedConnectivityObject(NSArray<NSString *> *classNames)
{
    return TLinkSharedConnectivityObjectWithAlloc(classNames, YES);
}

static BOOL TLinkConnectivityGetBool(id obj, NSArray<NSString *> *selectorNames, BOOL *outValue)
{
    if (!obj) return NO;
    for (NSString *selectorName in selectorNames) {
        SEL sel = NSSelectorFromString(selectorName);
        if (![obj respondsToSelector:sel]) continue;
        @try {
            BOOL value = ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
            if (outValue) *outValue = value;
            return YES;
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

static BOOL TLinkConnectivityGetInt(id obj, NSArray<NSString *> *selectorNames, int *outValue)
{
    if (!obj) return NO;
    for (NSString *selectorName in selectorNames) {
        SEL sel = NSSelectorFromString(selectorName);
        if (![obj respondsToSelector:sel]) continue;
        @try {
            int value = ((int (*)(id, SEL))objc_msgSend)(obj, sel);
            if (outValue) *outValue = value;
            return YES;
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

static BOOL TLinkConnectivityGetBoolOutParam(id obj, NSArray<NSString *> *selectorNames, BOOL *outValue)
{
    if (!obj) return NO;
    for (NSString *selectorName in selectorNames) {
        SEL sel = NSSelectorFromString(selectorName);
        if (![obj respondsToSelector:sel]) continue;
        @try {
            BOOL value = NO;
            ((void (*)(id, SEL, BOOL *))objc_msgSend)(obj, sel, &value);
            if (outValue) *outValue = value;
            return YES;
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

static BOOL TLinkConnectivitySetBool(id obj, NSArray<NSString *> *selectorNames, BOOL value)
{
    if (!obj) return NO;
    for (NSString *selectorName in selectorNames) {
        SEL sel = NSSelectorFromString(selectorName);
        if (![obj respondsToSelector:sel]) continue;
        @try {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, sel, value);
            return YES;
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

static BOOL TLinkMobileWiFiState(BOOL setState, BOOL requestedValue, BOOL *outValue)
{
    TLinkLoadConnectivityFrameworks();
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY | RTLD_GLOBAL);
    if (!handle) return NO;

    typedef void *(*WiFiManagerClientCreateFn)(CFAllocatorRef, int);
    typedef CFArrayRef (*WiFiManagerClientCopyDevicesFn)(void *);
    typedef int (*WiFiDeviceClientGetPowerFn)(void *);
    typedef int (*WiFiDeviceClientSetPowerFn)(void *, int);
    typedef int (*WiFiManagerClientGetPowerFn)(void *);
    typedef int (*WiFiManagerClientSetPowerFn)(void *, int);

    WiFiManagerClientCreateFn createFn = (WiFiManagerClientCreateFn)dlsym(handle, "WiFiManagerClientCreate");
    WiFiManagerClientCopyDevicesFn copyDevicesFn = (WiFiManagerClientCopyDevicesFn)dlsym(handle, "WiFiManagerClientCopyDevices");
    WiFiDeviceClientGetPowerFn deviceGetFn = (WiFiDeviceClientGetPowerFn)dlsym(handle, "WiFiDeviceClientGetPower");
    WiFiDeviceClientSetPowerFn deviceSetFn = (WiFiDeviceClientSetPowerFn)dlsym(handle, "WiFiDeviceClientSetPower");
    WiFiManagerClientGetPowerFn managerGetFn = (WiFiManagerClientGetPowerFn)dlsym(handle, "WiFiManagerClientGetPower");
    WiFiManagerClientSetPowerFn managerSetFn = (WiFiManagerClientSetPowerFn)dlsym(handle, "WiFiManagerClientSetPower");
    if (!createFn) return NO;

    void *manager = createFn(kCFAllocatorDefault, 0);
    if (!manager) return NO;

    BOOL success = NO;
    void *device = NULL;
    CFArrayRef devices = copyDevicesFn ? copyDevicesFn(manager) : NULL;
    if (devices && CFArrayGetCount(devices) > 0) {
        device = (void *)CFArrayGetValueAtIndex(devices, 0);
    }

    if (setState) {
        if (device && deviceSetFn) {
            deviceSetFn(device, requestedValue ? 1 : 0);
            success = YES;
        } else if (managerSetFn) {
            managerSetFn(manager, requestedValue ? 1 : 0);
            success = YES;
        }
    }

    if (device && deviceGetFn) {
        int value = deviceGetFn(device);
        if (outValue) *outValue = value != 0;
        success = YES;
    } else if (managerGetFn) {
        int value = managerGetFn(manager);
        if (outValue) *outValue = value != 0;
        success = YES;
    } else if (setState) {
        if (outValue) *outValue = requestedValue;
        success = YES;
    }

    if (devices) CFRelease(devices);
    return success;
}

static BOOL TLinkNetworkInterfaceActive(const char *name, const char *prefix)
{
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0 || !interfaces) return NO;
    BOOL active = NO;
    for (struct ifaddrs *ifa = interfaces; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_name || !ifa->ifa_addr) continue;
        if (name && strcmp(ifa->ifa_name, name) != 0) continue;
        if (prefix && strncmp(ifa->ifa_name, prefix, strlen(prefix)) != 0) continue;
        int family = ifa->ifa_addr->sa_family;
        if ((family == AF_INET || family == AF_INET6) &&
            (ifa->ifa_flags & IFF_UP) &&
            (ifa->ifa_flags & IFF_RUNNING)) {
            active = YES;
            break;
        }
    }
    freeifaddrs(interfaces);
    return active;
}

static BOOL TLinkWiFiInterfaceActive(void)
{
    return TLinkNetworkInterfaceActive("en0", NULL);
}

static BOOL TLinkCellularInterfaceActive(void)
{
    return TLinkNetworkInterfaceActive(NULL, "pdp_ip");
}

static BOOL TLinkVPNInterfaceActive(void)
{
    return TLinkNetworkInterfaceActive(NULL, "utun") ||
           TLinkNetworkInterfaceActive(NULL, "ipsec") ||
           TLinkNetworkInterfaceActive(NULL, "ppp");
}

static NSDictionary *TLinkVPNTrollStoreDiagnosticsSnapshot(
    NSNumber *effectiveConnected,
    NSString *agentError,
    NSString *brokerError)
{
    NSMutableDictionary *diagnostics = [TLinkVPNDiagnosticsSnapshot(
        @"trollstore",
        @"background_control",
        @"agent_6016_app_6015_interface_fallback",
        @"agent_6016_with_foreground_fallback",
        @"nevpnmanager_ikev2_background_agent",
        @"vpnagent_6016_then_StreamControl_6015",
        effectiveConnected) mutableCopy];
    diagnostics[@"phase"] = @5;
    diagnostics[@"broker_ready"] = @0;
    diagnostics[@"broker_target"] = @"vpnagent_mobile_then_StreamControl_foreground_app";
    diagnostics[@"entitlement_probe_scope"] = @"streamd_process_fallback";
    diagnostics[@"control_preflight"] = @"requires_vpnagent_or_foreground_app_probe";
    diagnostics[@"profile_state"] = @"not_probed";
    diagnostics[@"on_demand_policy"] =
        @"local_ui_connect_all_networks_explicit_disconnect_disables";
    diagnostics[@"diagnostics_source"] = @"streamd_interface_fallback";
    diagnostics[@"background_agent_expected"] = @1;
    diagnostics[@"background_agent_port"] = @6016;
    diagnostics[@"background_agent_last_error"] = agentError ?: @"";
    diagnostics[@"foreground_heartbeat_fresh"] =
        @(TLinkAppForegroundHeartbeatIsFresh());
    diagnostics[@"broker_last_error"] = brokerError ?: @"";
    return diagnostics;
}

static NSData *TLinkRunVPNBackgroundAgentWithTimeout(
    NSString *command,
    NSString **failure,
    int timeoutSeconds)
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        if (failure) *failure = @"vpnagent_socket_failed";
        return nil;
    }
    struct timeval timeout = {MAX(2, MIN(timeoutSeconds, 30)), 0};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6016);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (connect(sock, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(sock);
        if (failure) *failure = @"vpnagent_unavailable";
        return nil;
    }

    NSString *line = [NSString stringWithFormat:@"%@\n", command ?: @""];
    NSData *request = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!TLinkWriteAllToFd(sock, request.bytes, request.length)) {
        close(sock);
        if (failure) *failure = @"vpnagent_request_write_failed";
        return nil;
    }
    NSData *response = TLinkReadSocketResponse(sock);
    close(sock);
    if (response.length == 0) {
        if (failure) *failure = @"vpnagent_timeout_or_empty_response";
        return nil;
    }
    return response;
}

static NSData *TLinkRunVPNBackgroundAgentWithRecovery(
    NSString *command,
    NSString **failure,
    int timeoutSeconds)
{
    NSData *response = TLinkRunVPNBackgroundAgentWithTimeout(
        command, failure, timeoutSeconds);
    if (response.length > 0) return response;

    NSString *streamdPath = TLinkCurrentStreamdExecutablePath();
    if (streamdPath.length == 0) {
        if (failure) *failure = @"vpnagent_recovery_streamd_path_unavailable";
        return nil;
    }
    int ensureExit = TLinkRunPrivhelper(
        @[@"--ensure-vpnagent", streamdPath], 6000);
    if (ensureExit != 0) {
        if (failure) {
            *failure = [NSString stringWithFormat:
                @"vpnagent_recovery_failed_exit_%d", ensureExit];
        }
        return nil;
    }
    return TLinkRunVPNBackgroundAgentWithTimeout(
        command, failure, timeoutSeconds);
}

static NSData *TLinkRunVPNBackgroundAgent(
    NSString *command,
    NSString **failure)
{
    return TLinkRunVPNBackgroundAgentWithRecovery(command, failure, 30);
}

static NSData *TLinkRunVPNForegroundBrokerWithTimeout(
    NSString *command,
    NSString **failure,
    int timeoutSeconds)
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        if (failure) *failure = @"vpn_app_broker_socket_failed";
        return nil;
    }
    struct timeval timeout = {MAX(2, MIN(timeoutSeconds, 30)), 0};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6015);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (connect(sock, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(sock);
        if (failure) *failure = @"vpn_foreground_app_required";
        return nil;
    }

    NSString *line = [NSString stringWithFormat:@"%@\n", command ?: @""];
    NSData *request = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!TLinkWriteAllToFd(sock, request.bytes, request.length)) {
        close(sock);
        if (failure) *failure = @"vpn_app_broker_request_write_failed";
        return nil;
    }
    NSData *response = TLinkReadSocketResponse(sock);
    close(sock);
    if (response.length == 0) {
        if (failure) *failure = @"vpn_app_broker_timeout_or_empty_response";
        return nil;
    }
    return response;
}

static NSData *TLinkRunVPNForegroundBroker(
    NSString *command,
    NSString **failure)
{
    return TLinkRunVPNForegroundBrokerWithTimeout(command, failure, 30);
}

static NSData *TLinkHandleConnectivity(NSString *body,
                                       int taskType,
                                       NSString *label,
                                       NSArray<NSString *> *classNames,
                                       NSArray<NSString *> *getters,
                                       NSArray<NSString *> *setters);

static NSData *TLinkHandleWiFiConnectivity(NSString *body, int taskType)
{
    int action = 0;
    int requestedValue = 0;
    NSString *parseError = nil;
    if (!TLinkParseConnectivityAction(body, &action, &requestedValue, &parseError)) {
        return TLinkError(parseError ?: @"connectivity_bad_payload");
    }

    BOOL enabled = NO;
    if (TLinkMobileWiFiState(action == 1, requestedValue != 0, &enabled)) {
        if (action == 0 && !enabled && TLinkWiFiInterfaceActive()) {
            enabled = YES;
        }
        return TLinkSuccess(enabled ? @"1" : @"0");
    }
    if (action == 0 && TLinkWiFiInterfaceActive()) {
        return TLinkSuccess(@"1");
    }

    NSData *fallback = TLinkHandleConnectivity(body,
                                               taskType,
                                               @"wifi",
                                               @[@"SBWiFiManager", @"WiFiManager", @"WiFiManagerClient"],
                                               @[@"wiFiEnabled", @"wifiEnabled", @"isWiFiEnabled", @"enabled", @"power"],
                                               @[@"setWiFiEnabled:", @"setWifiEnabled:", @"setEnabled:", @"setPower:"]);
    return fallback;
}

static NSData *TLinkHandleConnectivity(NSString *body,
                                       int taskType,
                                       NSString *label,
                                       NSArray<NSString *> *classNames,
                                       NSArray<NSString *> *getters,
                                       NSArray<NSString *> *setters)
{
    int action = 0;
    int requestedValue = 0;
    NSString *parseError = nil;
    if (!TLinkParseConnectivityAction(body, &action, &requestedValue, &parseError)) {
        return TLinkError(parseError ?: @"connectivity_bad_payload");
    }

    id controller = TLinkSharedConnectivityObject(classNames);
    if (!controller) {
        NSArray<NSString *> *methodTokens = @[@"shared", @"default", @"local", @"manager", @"device", @"bluetooth"];
        return TLinkUnsupported(taskType, [NSString stringWithFormat:@"%@_controller_unavailable %@ %@", label, TLinkConnectivityLoadedClassSummary(classNames), TLinkConnectivityClassMethodSummary(classNames, methodTokens)]);
    }

    if (action == 1) {
        if (!TLinkConnectivitySetBool(controller, setters, requestedValue != 0)) {
            return TLinkUnsupported(taskType, [NSString stringWithFormat:@"%@_set_selector_unavailable", label]);
        }
    }

    BOOL enabled = NO;
    if (!(TLinkConnectivityGetBool(controller, getters, &enabled) ||
          TLinkConnectivityGetBoolOutParam(controller, @[@"getCellularDataEnabled:", @"getAirplaneMode:", @"getEnabled:"], &enabled))) {
        if (action == 1) {
            enabled = requestedValue != 0;
        } else {
            NSArray<NSString *> *methodTokens = @[@"enabled", @"cellular", @"data", @"radio", @"airplane", @"power", @"bluetooth"];
            return TLinkUnsupported(taskType, [NSString stringWithFormat:@"%@_get_selector_unavailable controller=%@ instance=%@", label, NSStringFromClass([controller class]), TLinkConnectivityMethodSummaryForClass([controller class], NO, methodTokens)]);
        }
    }
    return TLinkSuccess(enabled ? @"1" : @"0");
}

static NSData *TLinkHandleBluetoothConnectivity(NSString *body, int taskType)
{
    int action = 0;
    int requestedValue = 0;
    NSString *parseError = nil;
    if (!TLinkParseConnectivityAction(body, &action, &requestedValue, &parseError)) {
        return TLinkError(parseError ?: @"connectivity_bad_payload");
    }

    NSArray<NSString *> *classNames = @[@"BluetoothManager", @"BTLocalDevice"];
    id controller = TLinkSharedConnectivityObjectWithAlloc(classNames, YES);
    if (!controller) {
        NSArray<NSString *> *methodTokens = @[@"shared", @"default", @"local", @"manager", @"device", @"bluetooth"];
        return TLinkUnsupported(taskType, [NSString stringWithFormat:@"bluetooth_controller_unavailable %@ %@", TLinkConnectivityLoadedClassSummary(classNames), TLinkConnectivityClassMethodSummary(classNames, methodTokens)]);
    }

    if (action == 1) {
        if (!TLinkConnectivitySetBool(controller, @[@"setPowered:", @"setEnabled:", @"setPowerState:", @"setPower:"], requestedValue != 0)) {
            return TLinkUnsupported(taskType, [NSString stringWithFormat:@"bluetooth_set_selector_unavailable controller=%@", NSStringFromClass([controller class])]);
        }
    }

    BOOL enabled = NO;
    int state = 0;
    if (TLinkConnectivityGetInt(controller, @[@"bluetoothState", @"powerState"], &state)) {
        enabled = state == 5;
    } else if (!(TLinkConnectivityGetBool(controller, @[@"powered", @"enabled", @"isEnabled", @"isPowered"], &enabled) ||
                 TLinkConnectivityGetBoolOutParam(controller, @[@"getEnabled:", @"getPowered:"], &enabled))) {
        NSArray<NSString *> *methodTokens = @[@"enabled", @"power", @"bluetooth", @"state"];
        return TLinkUnsupported(taskType, [NSString stringWithFormat:@"bluetooth_get_selector_unavailable controller=%@ instance=%@", NSStringFromClass([controller class]), TLinkConnectivityMethodSummaryForClass([controller class], NO, methodTokens)]);
    }
    return TLinkSuccess(enabled ? @"1" : @"0");
}

static NSData *TLinkHandleCellularConnectivity(NSString *body, int taskType)
{
    int action = 0;
    int requestedValue = 0;
    NSString *parseError = nil;
    if (!TLinkParseConnectivityAction(body, &action, &requestedValue, &parseError)) {
        return TLinkError(parseError ?: @"connectivity_bad_payload");
    }

    if (action == 0) {
        id controller = TLinkSharedConnectivityObject(@[@"RadiosPreferences"]);
        BOOL enabled = NO;
        if (controller &&
            (TLinkConnectivityGetBool(controller, @[@"cellularDataEnabled", @"isCellularDataEnabled", @"dataEnabled", @"getCellularDataEnabled"], &enabled) ||
             TLinkConnectivityGetBoolOutParam(controller, @[@"getCellularDataEnabled:"], &enabled))) {
            return TLinkSuccess(enabled ? @"1" : @"0");
        }
        return TLinkSuccess(TLinkCellularInterfaceActive() ? @"1" : @"0");
    }

    return TLinkHandleConnectivity(body,
                                   taskType,
                                   @"cellular_data",
                                   @[@"RadiosPreferences"],
                                   @[@"cellularDataEnabled", @"isCellularDataEnabled", @"dataEnabled", @"getCellularDataEnabled"],
                                   @[@"setCellularDataEnabled:", @"setDataEnabled:"]);
}

static NSData *TLinkHandleVPNConnectivity(NSString *body, int taskType)
{
    (void)taskType;
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int requestedAction =
        parts.count >= 1 && parts[0].length > 0 ? [parts[0] intValue] : 0;
    if (requestedAction == 2) {
        if (parts.count != 1) {
            return TLinkError(@"vpn_diagnostics_takes_no_arguments");
        }
        NSString *agentError = nil;
        NSData *agentResponse = TLinkRunVPNBackgroundAgentWithRecovery(
            @"diagnostics",
            &agentError,
            5);
        NSString *agentText = TLinkResponseStringFromData(agentResponse);
        if ([agentText hasPrefix:@"0;;"]) return agentResponse;

        NSString *brokerError = nil;
        NSData *brokerResponse = TLinkRunVPNForegroundBrokerWithTimeout(
            @"diagnostics",
            &brokerError,
            5);
        if (!brokerResponse && !brokerError) {
            brokerError = @"vpn_foreground_app_required";
        }
        NSString *brokerText = TLinkResponseStringFromData(brokerResponse);
        if ([brokerText hasPrefix:@"0;;"]) return brokerResponse;

        NSDictionary *diagnostics = TLinkVPNTrollStoreDiagnosticsSnapshot(
            @(TLinkVPNInterfaceActive()),
            agentError ?: agentText ?: @"vpnagent_unavailable",
            brokerError ?: brokerText ?: @"vpn_foreground_app_required");
        NSError *jsonError = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:diagnostics
                                                       options:0
                                                         error:&jsonError];
        if (!json || jsonError) return TLinkError(@"vpn_diagnostics_encode_failed");
        return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @"");
    }

    int action = 0;
    int requestedValue = 0;
    NSString *parseError = nil;
    if (!TLinkParseConnectivityAction(body, &action, &requestedValue, &parseError)) {
        return TLinkError(parseError ?: @"connectivity_bad_payload");
    }
    if (action == 0) {
        NSString *agentError = nil;
        NSData *agentResponse = TLinkRunVPNBackgroundAgent(
            @"query", &agentError);
        NSString *agentText = TLinkResponseStringFromData(agentResponse);
        if ([agentText hasPrefix:@"0;;"]) return agentResponse;

        NSString *brokerError = nil;
        NSData *brokerResponse = TLinkAppForegroundHeartbeatIsFresh()
            ? TLinkRunVPNForegroundBroker(@"query", &brokerError)
            : nil;
        NSString *brokerText = TLinkResponseStringFromData(brokerResponse);
        if ([brokerText hasPrefix:@"0;;"]) return brokerResponse;
        return TLinkSuccess(TLinkVPNInterfaceActive() ? @"1" : @"0");
    }
    NSString *agentError = nil;
    NSData *agentResponse = TLinkRunVPNBackgroundAgent(
        requestedValue ? @"connect" : @"disconnect",
        &agentError);
    NSString *agentText = TLinkResponseStringFromData(agentResponse);
    if ([agentText hasPrefix:@"0;;"]) return agentResponse;

    if (!TLinkAppForegroundHeartbeatIsFresh()) {
        if (agentResponse.length > 0) return agentResponse;
        return TLinkError(agentError ?: @"vpnagent_unavailable");
    }
    NSString *brokerError = nil;
    NSData *brokerResponse = TLinkRunVPNForegroundBroker(
        requestedValue ? @"connect" : @"disconnect",
        &brokerError);
    if (brokerResponse.length > 0) return brokerResponse;
    if (agentResponse.length > 0) return agentResponse;
    return TLinkError(brokerError ?: agentError ?: @"vpnagent_unavailable");
}

static NSData *TLinkHandleConnectivityTask(int taskType, NSString *body)
{
    if (taskType == 55) {
        return TLinkHandleWiFiConnectivity(body, taskType);
    }
    if (taskType == 56) {
        return TLinkHandleBluetoothConnectivity(body, taskType);
    }
    if (taskType == 57) {
        return TLinkHandleConnectivity(body,
                                       taskType,
                                       @"airplane",
                                       @[@"RadiosPreferences", @"SBAirplaneModeController"],
                                       @[@"airplaneMode", @"airplaneModeEnabled", @"isAirplaneModeEnabled"],
                                       @[@"setAirplaneMode:", @"setAirplaneModeEnabled:"]);
    }
    if (taskType == 58) {
        return TLinkHandleCellularConnectivity(body, taskType);
    }
    return TLinkHandleVPNConnectivity(body, taskType);
}

static BOOL TLinkAutoLaunchEntryEnabled(id obj, NSString **scriptOut)
{
    if (![obj isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *entry = (NSDictionary *)obj;
    NSString *script = [entry[@"script"] isKindOfClass:[NSString class]] ? entry[@"script"] : @"";
    if (scriptOut) *scriptOut = script ?: @"";
    return script.length > 0 && [entry[@"enabled"] boolValue];
}

static void TLinkRunAutoLaunchEntries(void)
{
    NSDictionary *config = TLinkLoadAutoLaunchConfig();
    NSArray<NSString *> *keys = [[config allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    NSInteger enabledCount = 0;
    NSInteger startedCount = 0;

    for (NSString *key in keys) {
        NSString *script = @"";
        if (!TLinkAutoLaunchEntryEnabled(config[key], &script)) continue;
        enabledCount++;
        NSData *response = TLinkHandlePlayScript(script);
        NSString *result = TLinkResponseStringFromData(response);
        if ([result hasPrefix:@"0;;"] || [result isEqualToString:@"0"]) startedCount++;
        NSString *safeResult = TLinkVisualSafeText(result ?: @"");
        [results addObject:[NSString stringWithFormat:@"%@=%@", key ?: @"", safeResult]];
    }

    NSString *summary = [results componentsJoinedByString:@" | "];
    @synchronized (TLinkVisualFeedbackLock()) {
        sTLinkLastAutoLaunchRunMs = TLinkNowMs();
        sTLinkLastAutoLaunchEnabledCount = enabledCount;
        sTLinkLastAutoLaunchStartedCount = startedCount;
        sTLinkLastAutoLaunchResult = summary ?: @"";
    }

    if (enabledCount > 0) {
        TLinkRecordToast([NSString stringWithFormat:@"Auto launch %ld/%ld", (long)startedCount, (long)enabledCount],
                         2.0,
                         0,
                         2,
                         14,
                         @"scheduler");
    }
}

static void TLinkScheduleAutoLaunchStartup(void)
{
    @synchronized (TLinkVisualFeedbackLock()) {
        if (sTLinkAutoLaunchScheduled) return;
        sTLinkAutoLaunchScheduled = YES;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * (double)NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        TLinkRunAutoLaunchEntries();
    });
}

static BOOL TLinkLicenseTaskIsExempt(int taskType)
{
    return taskType == 60 ||
           taskType == 75 ||
           taskType == 76 ||
           taskType == 96 ||
           taskType == 97 ||
           taskType == 99;
}

typedef struct {
    int taskType;
    const char *feature;
} TLinkLicenseTaskPolicyEntry;

static const TLinkLicenseTaskPolicyEntry kTLinkLicenseTaskPolicy[] = {
    {11, "automation"}, {12, "automation"}, {13, "shell"},
    {14, "automation"}, {15, "automation"}, {16, "automation"},
    {17, "automation"}, {18, "automation"}, {19, "script"},
    {20, "script"}, {21, "automation"}, {22, "automation"},
    {23, "automation"}, {24, "automation"}, {25, "automation"},
    {26, "automation"}, {27, "automation"}, {28, "automation"},
    {29, "automation"}, {30, "automation"}, {31, "admin"},
    {32, "automation"}, {33, "automation"}, {34, "automation"},
    {35, "automation"}, {36, "script"}, {37, "script"},
    {38, "script"}, {39, "script"}, {40, "automation"},
    {41, "script"}, {42, "automation"}, {43, "automation"},
    {44, "automation"}, {45, "automation"}, {46, "automation"},
    {47, "automation"}, {48, "automation"}, {49, "automation"},
    {50, "automation"}, {51, "automation"}, {52, "automation"},
    {53, "automation"}, {54, "automation"}, {55, "automation"},
    {56, "automation"}, {57, "automation"}, {58, "automation"},
    {59, "automation"}, {61, "automation"}, {62, "automation"},
    {63, "automation"}, {64, "automation"}, {65, "automation"},
    {66, "automation"}, {67, "automation"}, {68, "automation"},
    {69, "automation"}, {70, "automation"}, {71, "shell"},
    {72, "admin"}, {73, "script"}, {74, "admin"},
    {90, "automation"}, {91, "automation"}, {94, "stream"}, {95, "automation"}, {98, "automation"},
};

static NSString *TLinkLicenseFeatureForTask(int taskType)
{
    const size_t count = sizeof(kTLinkLicenseTaskPolicy) / sizeof(kTLinkLicenseTaskPolicy[0]);
    for (size_t index = 0; index < count; index++) {
        const TLinkLicenseTaskPolicyEntry *entry = &kTLinkLicenseTaskPolicy[index];
        if (entry->taskType == taskType) {
            return [NSString stringWithUTF8String:entry->feature];
        }
    }
    return nil;
}

static NSData *TLinkLicenseDeniedResponse(int taskType, NSString *feature, NSString *detail)
{
    NSDictionary *status = TLinkLicenseStatusDictionary();
    NSString *state = [status[@"state"] isKindOfClass:[NSString class]] ? status[@"state"] : @"invalid";
    NSString *reason = detail.length > 0
        ? detail
        : ([status[@"error"] isKindOfClass:[NSString class]] ? status[@"error"] : @"license_required");
    return TLinkError([NSString stringWithFormat:@"license_required task=%d feature=%@ state=%@ error=%@",
                       taskType,
                       feature ?: @"automation",
                       state,
                       reason]);
}

static NSData *TLinkHandleLicenseStatus(BOOL invalidate, NSString *body)
{
    uint64_t generationBefore = TLinkLicenseGeneration();
    NSString *action = @"status";
    if (invalidate) {
        NSString *rawMode = body ? body : @"";
        NSString *trimmedMode = [rawMode stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *mode = [trimmedMode lowercaseString];
        if ([mode isEqualToString:@"reload"]) {
            TLinkLicenseInvalidateCache();
            action = @"reload";
        } else {
            TLinkLicenseAdvanceGeneration();
            action = @"advance";
        }
    }
    uint64_t generationAfter = TLinkLicenseGeneration();
    NSMutableDictionary *status = [TLinkLicenseStatusDictionary() mutableCopy];
    status[@"license_contract_version"] = @1;
    status[@"checked_at_ms"] = @((uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0));
    status[@"cache_invalidated"] = @(invalidate);
    status[@"generation_before"] = @(generationBefore);
    status[@"license_generation"] = @(generationAfter);
    status[@"generation_action"] = action;
    status[@"source"] = @"streamd_shared_verifier";
    NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
    if (json.length == 0) return TLinkError(@"license_status_json_failed");
    return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @"");
}

static NSData *TLinkHandleTaskLine(const char *line)
{
    if (!line) return TLinkError(@"empty request");
    int taskType = POCTaskTypeFromBuffer(line);
    NSString *body = TLinkBodyFromLine(line);
    POCLogf("task-server: line='%s' task=%d", line, taskType);

    if (!TLinkLicenseTaskIsExempt(taskType)) {
        NSString *feature = TLinkLicenseFeatureForTask(taskType);
        if (feature.length == 0) {
            POCLogf("task-server: license policy missing task=%d", taskType);
            return TLinkError([NSString stringWithFormat:@"license_policy_missing task=%d", taskType]);
        }
        NSString *licenseError = nil;
        if (!TLinkLicenseFeatureAllowed(feature, &licenseError)) {
            POCLogf("task-server: license denied task=%d feature=%s error=%s",
                    taskType,
                    [feature UTF8String],
                    [(licenseError ?: @"license_required") UTF8String]);
            return TLinkLicenseDeniedResponse(taskType, feature, licenseError);
        }
    }

    if (taskType == 11) {
        return TLinkHandleOpenApplication(body);
    }

    if (taskType == 12) {
        return TLinkHandleAlertBox(body);
    }

    if (taskType == 13) {
        return TLinkHandleShellTask(body, taskType);
    }

    if (taskType == 14) {
        return TLinkHandleStartRecording(body);
    }

    if (taskType == 15) {
        return TLinkHandleStopRecording(body);
    }

    if (taskType == 16 || taskType == 17) {
        return TLinkHandleTapMacro(taskType, body);
    }

    if (taskType == 18) {
        int us = [body intValue];
        if (us < 0) us = 0;
        usleep((useconds_t)us);
        return TLinkSuccess(nil);
    }

    if (taskType == 19) {
        return TLinkHandlePlayScript(body);
    }

    if (taskType == 20) {
        return TLinkHandleStopScript(body);
    }

    if (taskType == 21) {
        return TLinkHandleTemplateMatch(body);
    }

    if (taskType == 22) {
        return TLinkHandleToast(body);
    }

    if (taskType == 25) {
        return TLinkHandleDeviceInfo(body);
    }

    if (taskType == 26) {
        return TLinkHandleTouchIndicator(body);
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

    if (taskType == 30) {
        return TLinkHandleHardwareKey(body);
    }

    if (taskType == 36) {
        return TLinkHandleSetAutoLaunch(body);
    }

    if (taskType == 37) {
        return TLinkHandleListAutoLaunch();
    }

    if (taskType == 38) {
        return TLinkHandleSetTimer(body);
    }

    if (taskType == 39) {
        return TLinkHandleRemoveTimer(body);
    }

    if (taskType == 40) {
        return TLinkHandleKeepAwake(body);
    }

    if (taskType == 41) {
        return TLinkHandleStopScript(body);
    }

    if (taskType == 42) {
        return TLinkHandleDialog(body);
    }

    if (taskType == 43) {
        return TLinkHandleClearDialog(body);
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

    if (taskType >= 55 && taskType <= 59) {
        return TLinkHandleConnectivityTask(taskType, body);
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

    if (taskType == 71) {
        return TLinkHandleShellTask(body, taskType);
    }

    if (taskType == 72) {
        return TLinkHandleClearAppData(body);
    }

    if (taskType == 73) {
        return TLinkHandleClearScriptLog(body);
    }

    if (taskType == 74) {
        return TLinkHandleRespring(body);
    }

    if (taskType == 75) {
        return TLinkHandleLicenseStatus(NO, body);
    }

    if (taskType == 76) {
        return TLinkHandleLicenseStatus(YES, body);
    }

    if (taskType == 90) {
        return TLinkHandleUpdateCache(body);
    }

    if (taskType == 91) {
        return TLinkHandleTesseractOCRCompat(body);
    }

    if (taskType == 94) {
        NSString *feedbackError = nil;
        NSDictionary *accepted = TLinkAdaptiveStreamingSubmitFeedback(@"trollstore", body, &feedbackError);
        if (feedbackError.length > 0) return TLinkError(feedbackError);
        NSData *json = [NSJSONSerialization dataWithJSONObject:accepted options:0 error:nil];
        return json.length > 0 ? TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @"") : TLinkError(@"adaptive_feedback_json_failed");
    }

    if (taskType == 95) {
        NSString *eventError = nil;
        NSDictionary *batch = TLinkEventChannelPollBody(body, &eventError);
        if (eventError.length > 0) return TLinkError(eventError);
        NSData *json = [NSJSONSerialization dataWithJSONObject:batch options:0 error:nil];
        if (json.length == 0) return TLinkError(@"event_channel_json_failed");
        return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @"");
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
        NSString *cap = @"runtime=trollstore serviceVersion=14 phase=image-color-frame-ocr-app-script-lite ports=6000,7001,7002,7003,7004,7005,7006 tasks=10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,90,91,96,97,98,99 capabilities=touch,touchRecording,tapMacro,capture,captureDetached,screenshotAlbum,h264,hidMonitor,paths,color,image,frame,ocr,visionOCR,ocrPNGInput,ocrWorkerIsolation,ocrWorkerBreadcrumbs,ocrAppSideBridge,ocrAppRGBBridge,ocrAppAccurateRetry,tesseractOCR,tesseractOCRCompat,scriptJS,scriptStorage,scriptTaskBridge,scriptCompatFacade,scriptRunTaskAlias,scriptStorageAPI,scriptFileHandleAPI,scriptKeyboardAPI,scriptColorFrameAPI,scriptImageAPI,scriptOCRAPI,scriptAppAPI,scriptPlaySettings,scriptHardwareKey,scriptTapMacro,scriptLogClear,scheduler,schedulerAutoLaunch,settingsCache,keepAwake,visualFeedback,remoteBridgeWSS,remoteBridgeControl,remoteBridgeVideo,remoteBridgeReconnect,backgroundAutoStartBestEffort,backgroundUIBridge,backgroundVisualNotifications,backgroundVisualCFUserNotification,backgroundToastUIService,backgroundToastFixedCenter,backgroundPositionedToastOverlay,toastOverlay,alertOverlay,dialogOverlay,touchIndicator,appInfo,appLaunchPrivhelper,appKillPrivhelper,openURLPrivhelper,listBundles,keyboardClipboard,clipboardImage,clipboardUIDaemon,clipboardBackgroundEntitlement,clipboardForegroundFallback,keyboardHIDPaste,keyboardHIDEditing,hardwareKey,connectivity,wifi,bluetooth,airplane,cellularData,vpnQuery,shellTaskGated,clearDataPrivhelper,gracefulShutdown,privhelperRestart,privhelperEnsureStreamd unsupported=keychain,vpnControl,keyboardVisibilityControl,globalTouchIndicator,trueBootAutoStart unsupportedTasks=none remoteBridge=outbound_wss_control_and_zxh2_video_mvp keyboard=background_clipboard_hid_paste_cursor_delete clipboard=background_entitled_uidaemon_with_ui_bridge_and_foreground_fallback keyboardInput=clipboard_command_v_best_effort keyboardVisibility=limited_requires_springboard_keyboard_observer hardwareKey=hid_keyboard_event touchRecording=iohid_monitor_raw_js_replay tapMacro=bounded_async_native_tap scheduler=streamd_lite autolaunch=startup_after_streamd backgroundAutoStart=best_effort_bgtaskscheduler_after_first_launch keepAwake=foreground_app_plus_background_uidaemon_best_effort visualFeedback=foreground_overlay_background_uiservice_positioned_cfusernotification_fallback toast=foreground_or_background_uiservice_positioned_with_cf_fallback dialog=foreground_overlay_or_background_cfusernotification_alert touchIndicator=foreground_only_requires_springboard_injection_for_global connectivity=best_effort_private_framework vpn=query_only_interface_probe shell=local_sh_or_mini_shell_gated_disabled_by_default screenshotAlbum=photos_framework_tlinkauto_album clearData=privhelper_best_effort_data_container_only ocr=tesseract_true_static_libs_memory_fallback tessdata=/var/mobile/Library/TLinkauto/tessdata tesseractOCR=true_tesseract_static_libs_memory_fallback_requires_traineddata serviceMode=helper_ensure_streamd_clipboardd_uiservice_best_effort imageMatch=naive_rgba appMgmt=limited_process_info_helper_launch_kill script=javascriptcore_rootfull_compat_facade fileHandle=bundle_relative_shared_rootfull_trollstore_max32_transfer512KiB";
        NSDictionary *licenseStatus = TLinkLicenseStatusDictionary();
        cap = [cap stringByReplacingOccurrencesOfString:@"serviceVersion=14" withString:@"serviceVersion=23"];
        cap = [cap stringByAppendingFormat:@" licenseBuildMode=%@", TLinkLicenseBuildMode()];
        cap = [cap stringByReplacingOccurrencesOfString:@"71,72,73,90" withString:@"71,72,73,74,75,76,90"];
        cap = [cap stringByReplacingOccurrencesOfString:@"90,91,96" withString:@"90,91,94,95,96"];
        cap = [cap stringByReplacingOccurrencesOfString:@"clearDataPrivhelper,gracefulShutdown"
                                             withString:@"clearDataPrivhelper,respringPrivhelper,licenseSignedLease,licenseDeviceBound,gracefulShutdown"];
        cap = [cap stringByAppendingString:@" respring=privhelper_validated_springboard_signal"];
        cap = [cap stringByAppendingString:@" multiTouchRaw=legacy_task10_parent_frames"];
        cap = [cap stringByAppendingString:@" zoomState=experimental zoomTask=64 zoomWire=task64_additive_zoom_v1"];
        cap = [cap stringByAppendingString:@" zoomFingerCounts=2,3 zoomBackend=legacy_multitouch_parent_frames zoomPhase=2"];
        cap = [cap stringByAppendingString:@" zoomGeometry=radial_linear_interpolation_v1 zoomValidation=preflight_bounds_v1"];
        cap = [cap stringByAppendingString:@" zoomCleanup=all_fingers_up_on_exception_v1 zoomDeviceValidated=0"];
        cap = [cap stringByAppendingString:@" zoomDiagnostics=zoom_runtime_diagnostics_v1 zoomClients=task64_python_js_webtango_v1"];
        cap = [cap stringByAppendingString:@" smartWaitState=implemented smartWaitPhase=1 smartWaitSchema=smart_wait_result_v1 smartWaitClients=rootfull_js_trollstore_js_webtango_v1 smartWaitLocators=predicate,app,color,image,text,image_gone,tap_when_visible smartWaitFrameStrategy=fresh_frame_per_attempt_release_always_template_open_once smartWaitDeviceValidated=0"];
        cap = [cap stringByAppendingString:@" runHistoryState=implemented runHistoryVersion=1 runHistorySchema=run_history_v1 failureEvidenceSchema=failure_evidence_v1 runHistoryTransport=task60_status_json_v1 runHistoryRetentionMaxRuns=50 failureEvidenceScreenshot=best_effort_png_on_failure runHistoryDeviceValidated=0"];
        cap = [cap stringByAppendingString:@" eventChannelState=implemented eventChannelVersion=1 eventChannelSchema=event_channel_v1 eventChannelTransport=task95_long_poll_v1 eventChannelResume=cursor_v1 eventChannelJournalMaxEvents=256 eventChannelPollMaxEvents=32 eventChannelPollTimeoutMaxMs=25000 eventChannelDeviceValidated=0"];
        cap = [cap stringByAppendingString:@" adaptiveStreamingState=implemented adaptiveStreamingVersion=1 adaptiveStreamingSchema=adaptive_streaming_v1 adaptiveStreamingFeedback=task94_base64_json_v1 adaptiveStreamingLevels=high,balanced,survival adaptiveStreamingSelfHealing=encoder_restart_3_client_reconnect_6 adaptiveStreamingDeviceValidated=0"];
        cap = [cap stringByAppendingString:@" securePairingState=contract_only securePairingPhase=0 securePairingContractVersion=1 securePairingTransport=zxsp_json_v1 securePairingMode=observe_only securePairingLegacyPolicy=unchanged_p0 securePairingCrypto=p256_ecdh_ecdsa_hkdf_sha256_aes256_gcm securePairingDeviceValidated=0"];
        cap = [cap stringByAppendingString:@" vpnContractVersion=1 vpnLegacyTask=59"];
        cap = [cap stringByAppendingString:@" vpnProfileScope=tlink_owned_only"];
        cap = [cap stringByAppendingString:@" vpnConfigurationTransport=local_ui_keychain_only"];
        cap = [cap stringByAppendingString:@" vpnCredentialsOverTask59=forbidden"];
        cap = [cap stringByReplacingOccurrencesOfString:@"vpn=query_only_interface_probe"
                                             withString:@"vpn=background_agent_ikev2_on_demand"];
        cap = [cap stringByReplacingOccurrencesOfString:@"unsupported=keychain,vpnControl,"
                                             withString:@"unsupported=keychain,"];
        cap = [cap stringByReplacingOccurrencesOfString:@"vpnQuery,shellTaskGated"
                                             withString:@"vpnQuery,vpnControl,vpnOnDemand,shellTaskGated"];
        cap = [cap stringByAppendingString:@" vpnState=background_control vpnQuery=agent_6016_app_6015_interface_fallback"];
        cap = [cap stringByAppendingString:@" vpnControl=agent_6016_with_foreground_fallback vpnBackend=nevpnmanager_ikev2_background_agent"];
        cap = [cap stringByAppendingString:@" vpnBroker=vpnagent_6016_then_StreamControl_6015"];
        cap = [cap stringByAppendingString:@" vpnPhase=5 vpnBackgroundAgent=validated_mobile_process_v2"];
        cap = [cap stringByAppendingString:@" vpnOnDemand=local_ui_connect_all_networks"];
        cap = [cap stringByAppendingString:@" vpnDisconnectPolicy=explicit_disconnect_disables_on_demand"];
        cap = [cap stringByAppendingString:@" vpnDiagnostics=task59_action2_base64_json_v1"];
        cap = [cap stringByAppendingString:@" vpnEntitlementProbe=vpnagent_process_then_foreground_app_via_592"];
        cap = [cap stringByAppendingString:@" vpnProfileIdentifier=tlinkauto-managed-v1"];
        cap = [cap stringByAppendingString:@" licenseContractVersion=1 licensePolicyVersion=1"];
        cap = [cap stringByAppendingString:@" licenseLifecycle=foreground_bg_single_flight_backoff_v1"];
        cap = [cap stringByAppendingFormat:@" licenseGeneration=%llu licenseGenerationSync=darwin_plus_request_check",
            (unsigned long long)TLinkLicenseGeneration()];
        @synchronized (TLinkVisualFeedbackLock()) {
            cap = [cap stringByAppendingFormat:@" licensePolicy=explicit_table_fail_closed licenseRuntimeRecheck=h264_5s_script_1s task10LicenseDropCount=%llu",
                (unsigned long long)sTLinkLicenseDropCount];
        }
        cap = [cap stringByAppendingFormat:@" license=%@ licenseState=%@ licenseAccess=%@",
            [licenseStatus[@"enforcement_enabled"] boolValue] ? @"signed_lease_p256_enforced" : @"signed_lease_p256_observe",
            licenseStatus[@"state"] ?: @"unknown",
            [licenseStatus[@"effective_access"] boolValue] ? @"allowed" : @"denied"];
        NSDictionary *licenseRecovery = [licenseStatus[@"recovery"] isKindOfClass:[NSDictionary class]]
            ? licenseStatus[@"recovery"]
            : @{};
        cap = [cap stringByAppendingFormat:@" licenseRecovery=%@ licenseDeviceRepair=public_key_from_keychain serviceRecovery=replace_old_daemon_v21",
            licenseRecovery.count > 0 ? (licenseRecovery[@"state"] ?: @"required") : @"ready"];
        cap = [cap stringByAppendingFormat:@" tesseractInitSource=%@", sTLinkLastTesseractInitSource ?: @"none"];
        // Keep the stable Tesseract default while exposing CPU-only and
        // app-hosted XXTouch-compatible Vision canaries without changing task 27 bytes.
        cap = [cap stringByAppendingString:@" visionOCRState=experimental"
                                               @" visionOCRProfiles=app_cpu_default,worker_cpu_opt_in,xxt_compat_app_foreground"
                                               @" visionOCRRoute=profile_selected_worker_or_app_6011"
                                               @" visionOCRFallback=none"
                                               @" visionOCRCPUOnly=1"
                                               @" visionOCRXXTCompat=1"
                                               @" visionOCRXXTCompatInput=png_bridge_then_compact_cgimage"
                                               @" visionOCRXXTCompatPixelLayout=compact_bgra8888_premultiplied_first_stride_width_x4"
                                               @" visionOCRXXTCompatCompute=automatic"
                                               @" visionOCRXXTCompatHost=foreground_app_6011"
                                               @" visionOCRXXTCompatForegroundRequired=1"
                                               @" visionOCRAppWatchdogMs=15000"
                                               @" visionOCRAppBridgeProtocol=2"
                                               @" visionOCRDefaultProfile=app_cpu"
                                               @" ocrDefaultEngine=tesseract"
                                               @" ocrEngineSelector=none"
                                               @" ocrProtocolVersion=legacy_v1"
                                               @" ocrLegacyTasks=27,91"];
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
        NSString *licenseError = nil;
        if (!TLinkLicenseFeatureAllowed(@"automation", &licenseError)) {
            @synchronized (TLinkVisualFeedbackLock()) {
                sTLinkLicenseDropCount++;
                sTLinkLicenseLastDropAtMs = TLinkNowMs();
                sTLinkLicenseLastDropError = licenseError ?: @"license_required";
            }
            POCLogf("socket: task10 dropped by license enforcement error=%s",
                    [(licenseError ?: @"license_required") UTF8String]);
            return nil;
        }
        // Accept both legacy forms:
        //   10 + body
        //   10;; + body
        const char *body = line + 2;
        if (body[0] == ';' && body[1] == ';') body += 2;

        NSString *bodyString = [NSString stringWithUTF8String:body];
        if (!bodyString) bodyString = @"";
        POCLogf("socket: task10 received body='%s' len=%lu", body, (unsigned long)strlen(body));
        TLinkRecordLegacyTouchIndicatorEvents(bodyString, @"socket-task10");

        dispatch_async(dispatch_get_main_queue(), ^{
            const char *mainBody = [bodyString UTF8String];
            POCLogf("socket: task10 dispatching on main thread body='%s'", mainBody);
            POCPerformTouchFromRawData((const unsigned char *)mainBody);
        });
        return nil; // keep legacy touch fire-and-forget
    }

    return TLinkHandleTaskLine(line);
}

NSData *TLinkDispatchTaskLineData(NSData *lineData)
{
    if (![lineData isKindOfClass:[NSData class]] || lineData.length == 0) {
        return TLinkError(@"empty_task_line");
    }

    const UInt8 *bytes = (const UInt8 *)lineData.bytes;
    NSUInteger lineLen = lineData.length;
    while (lineLen > 0 &&
           (bytes[lineLen - 1] == '\r' || bytes[lineLen - 1] == '\n' || bytes[lineLen - 1] == 0)) {
        lineLen--;
    }
    if (lineLen == 0 || lineLen > kMaxBuffer) {
        return TLinkError(lineLen == 0 ? @"empty_task_line" : @"task_line_too_large");
    }

    char *line = (char *)malloc(lineLen + 1);
    if (!line) return TLinkError(@"task_line_allocation_failed");
    memcpy(line, bytes, lineLen);
    line[lineLen] = 0;
    __block NSData *response = nil;
    if (POCTaskTypeFromBuffer(line) == 95) {
        // The shared dispatcher is also used by the remote bridge.  Long-poll
        // directly so it never monopolizes the serial socket queue.
        response = POCHandleLine(line);
    } else {
        dispatch_sync(POCSocketQueue(), ^{
            response = POCHandleLine(line);
        });
    }
    free(line);
    return response;
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

static void POCDeferEventPoll(POCClientContext *ctx, NSString *body)
{
    if (!ctx || !ctx.writeStream) return;
    NSString *licenseError = nil;
    if (!TLinkLicenseFeatureAllowed(@"automation", &licenseError)) {
        POCWriteAll(ctx.writeStream, TLinkLicenseDeniedResponse(95, @"automation", licenseError));
        return;
    }
    __block CFWriteStreamRef stream = NULL;
    @synchronized (ctx) {
        if (ctx.eventPollPending) {
            POCWriteAll(ctx.writeStream, TLinkError(@"event_poll_already_pending"));
            return;
        }
        ctx.eventPollPending = YES;
        stream = ctx.writeStream;
        CFRetain(stream);
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *eventError = nil;
        NSDictionary *batch = TLinkEventChannelPollBody(body, &eventError);
        NSData *response = nil;
        if (eventError.length > 0) {
            response = TLinkError(eventError);
        } else {
            NSData *json = [NSJSONSerialization dataWithJSONObject:batch options:0 error:nil];
            response = json.length > 0
                ? TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @"")
                : TLinkError(@"event_channel_json_failed");
        }
        dispatch_async(POCSocketQueue(), ^{
            @synchronized (ctx) {
                if (ctx.writeStream == stream) POCWriteAll(stream, response);
                ctx.eventPollPending = NO;
            }
            CFRelease(stream);
        });
    });
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
            int taskType = POCTaskTypeFromBuffer(line);
            if (taskType == 95) {
                POCDeferEventPoll(ctx, TLinkBodyFromLine(line));
            } else {
                NSData *resp = POCHandleLine(line);
                if (resp) POCWriteAll(ctx.writeStream, resp);
            }
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

    CFWriteStreamRef writeStream = NULL;
    @synchronized (ctx) {
        writeStream = ctx.writeStream;
        ctx.writeStream = NULL;
        ctx.readStream = NULL;
        ctx.eventPollPending = NO;
    }
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
    TLinkEnsureRuntimeDirectories();
    TLinkLoadSettingsConfig();
    POCStartSocketServer();
    TLinkScheduleAutoLaunchStartup();
}
