#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#import <JavaScriptCore/JavaScriptCore.h>
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
#include <mach-o/dyld.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <sys/utsname.h>
#import <objc/message.h>
#import <objc/runtime.h>

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

static NSData *TLinkHandleTaskLine(const char *line);
static NSString *TLinkCleanPayload(NSString *body);
static CGSize TLinkScreenPixelSize(void);

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

static NSString *TLinkVisualSafeText(NSString *text)
{
    NSMutableString *safe = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "] mutableCopy];
    [safe replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    return safe ?: @"";
}

static uint64_t TLinkRecordToast(NSString *message, double duration, int type, int position, int fontSize, NSString *source)
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
            @"source": source ?: @"unknown",
            @"ts_ms": @(TLinkNowMs()),
        }];
        while (sTLinkVisualEvents.count > 50) {
            [sTLinkVisualEvents removeObjectAtIndex:0];
        }
    }
    return eventId;
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
            @"mode": @"nonblocking_foreground_overlay",
            @"source": source ?: @"unknown",
            @"ts_ms": @(TLinkNowMs()),
        }];
        while (sTLinkVisualEvents.count > 50) {
            [sTLinkVisualEvents removeObjectAtIndex:0];
        }
    }
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
            @"mode": @"app_foreground_idle_timer",
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
@property(nonatomic, strong) NSMutableArray<NSString *> *logs;
@end

@implementation TLinkScriptSession
@end

static NSString *const kTLinkScriptsRootPath = @"/var/mobile/Library/TLinkauto/scripts";
static NSString *const kTLinkScriptPlayConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/script_play_settings.plist";
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
    return @{
        @"ok": @(ok),
        @"code": ok ? @0 : @-1,
        @"payload": payload ?: @"",
        @"raw": text,
    };
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

static void TLinkScriptMarkTerminal(TLinkScriptSession *session, NSString *state, NSString *error)
{
    if (!session) return;
    @synchronized (session) {
        session.state = state ?: @"finished";
        session.endedAtMs = TLinkNowMs();
        session.lastError = error ?: @"";
    }
    if (error.length > 0) {
        sTLinkLastScriptError = error;
        sTLinkLastScriptErrorTs = session.endedAtMs;
    }
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
    NSString *target = TLinkNormalizePath([session.bundlePath stringByAppendingPathComponent:relativePath]);
    if (!TLinkPathIsInside(target, session.bundlePath)) {
        if (error) *error = @"storage_path_outside_bundle";
        return nil;
    }
    if (writing) {
        NSArray<NSString *> *protectedNames = @[@"main.js", @"manifest.json", @"info.plist"];
        if ([protectedNames containsObject:[target lastPathComponent]]) {
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
        uint64_t eventId = TLinkRecordToast(text, duration, type, position, fontSize, @"script");
        return @{@"ok": @YES, @"mode": @"app_foreground_overlay", @"event_id": @(eventId)};
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
        return @{@"ok": @(eventId > 0), @"mode": @"app_foreground_overlay", @"event_id": @(eventId)};
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
            @"mode": @"limited_nonblocking_foreground_overlay",
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
        if (TLinkScriptStopRequested(strongSession)) {
            return @{@"ok": @NO, @"code": @-1, @"payload": @"script_stop_requested", @"raw": @"-1;;script_stop_requested"};
        }
        NSString *body = bodyValue && ![bodyValue isUndefined] && ![bodyValue isNull] ? [bodyValue toString] : @"";
        return TLinkTaskResultFromResponseString(TLinkScriptRunTask((int)task, body));
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
        NSString *raw = TLinkScriptRunTask(23, [NSString stringWithFormat:@"%d;;%d", (int)x, (int)y]);
        return TLinkTaskResultFromResponseString(raw);
    };
    device[@"ocrLanguages"] = ^NSDictionary *{
        NSString *raw = TLinkScriptRunTask(27, @"2;;0");
        return TLinkTaskResultFromResponseString(raw);
    };
    device[@"runtimeInfo"] = ^NSDictionary *{
        TLinkScriptSession *strongSession = weakSession;
        if (!strongSession) return @{};
        @synchronized (strongSession) {
            return @{
                @"runtime": @"javascriptcore",
                @"runtimeLocation": @"streamd",
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
    device[@"readText"] = ^NSString *(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, NO, &err);
        if (!path) return nil;
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        return text;
    };
    device[@"writeText"] = ^NSDictionary *(NSString *relativePath, NSString *text) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, YES, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error"};
        NSString *parent = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *writeErr = nil;
        BOOL ok = [text ?: @"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
        return ok ? @{@"ok": @YES, @"path": path} : @{@"ok": @NO, @"error": writeErr.localizedDescription ?: @"write_failed"};
    };
    device[@"fileExists"] = ^BOOL(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, NO, &err);
        return path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path];
    };
    device[@"deleteFile"] = ^NSDictionary *(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, YES, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error"};
        NSError *deleteErr = nil;
        BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&deleteErr];
        if (ok || deleteErr.code == NSFileNoSuchFileError) return @{@"ok": @YES};
        return @{@"ok": @NO, @"error": deleteErr.localizedDescription ?: @"delete_failed"};
    };
    device[@"readJSON"] = ^id(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, NO, &err);
        if (!path) return nil;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length == 0) return nil;
        return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    };
    device[@"writeJSON"] = ^NSDictionary *(NSString *relativePath, JSValue *value) {
        id object = [value toObject];
        if (!object || ![NSJSONSerialization isValidJSONObject:object]) {
            return @{@"ok": @NO, @"error": @"invalid_json_object"};
        }
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, YES, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error"};
        NSString *parent = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
        BOOL ok = [data writeToFile:path atomically:YES];
        return ok ? @{@"ok": @YES, @"path": path} : @{@"ok": @NO, @"error": @"write_json_failed"};
    };
    context[@"device"] = device;
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
    session.logs = [NSMutableArray array];
    sTLinkScriptSession = session;
    sTLinkLastScriptError = @"";
    sTLinkLastScriptErrorTs = 0;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        TLinkRunScriptSession(session);
    });

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

static NSData *TLinkHandleToast(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    int type = parts.count >= 1 ? [parts[0] intValue] : 0;
    NSString *message = parts.count >= 2 ? parts[1] : TLinkCleanPayload(body);
    double duration = parts.count >= 3 ? [parts[2] doubleValue] : 2.0;
    int position = parts.count >= 4 ? [parts[3] intValue] : 2;
    int fontSize = parts.count >= 5 ? [parts[4] intValue] : 15;
    uint64_t eventId = TLinkRecordToast(message, duration, type, position, fontSize, @"task22");
    if (eventId == 0) return TLinkError(@"toast_missing_message");
    return TLinkSuccess([NSString stringWithFormat:@"toast_queued;;%llu", eventId]);
}

static NSData *TLinkHandleAlertBox(NSString *body)
{
    NSArray<NSString *> *parts = TLinkSplitBody(body);
    NSString *title = parts.count >= 1 ? parts[0] : @"TLinkauto";
    NSString *message = parts.count >= 2 ? parts[1] : @"";
    double duration = parts.count >= 3 ? [parts[2] doubleValue] : 0.0;
    uint64_t eventId = TLinkRecordAlert(title, message, duration, @"task12");
    if (eventId == 0) return TLinkError(@"alert_missing_message");
    return TLinkSuccess([NSString stringWithFormat:@"alert_queued;;%llu", eventId]);
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
    return TLinkSuccess([NSString stringWithFormat:@"%@;;dialog_queued;;%llu;;limited_nonblocking_foreground_overlay", sTLinkLastDialogValue ?: @"0", eventId]);
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
    TLinkRecordTouchIndicator(x, y, type, @"native-touch");
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
             "var raw = device.readText('%@') || '';\n"
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

static char sTLinkOCRWorkerOutputPath[PATH_MAX + 1] = {0};
static char sTLinkOCRWorkerPhase[96] = "not_started";

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

    if (subtask != 1) {
        return TLinkError([NSString stringWithFormat:@"unknown_ocr_subtask %d", subtask]);
    }

    if (parts.count < 8) {
        return TLinkError(@"ocr format: 1;;x,,y,,w,,h;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path");
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

    TLinkSetOCRWorkerPhase("vision_request_setup");
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
        unlink(outputTemplate);
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
    NSDictionary *capabilities = @{
        @"touch": @(YES),
        @"touchAck": @(YES),
        @"nativeTouch": @(YES),
        @"touchRecording": @(YES),
        @"touchRecordingMode": @"iohid_monitor_raw_js_replay",
        @"tapMacro": @(YES),
        @"tapMacroMode": @"bounded_async_native_tap",
        @"capture": @(YES),
        @"captureMode": @"detached_iosurface_bitmap",
        @"h264": @(YES),
        @"image": @(YES),
        @"color": @(YES),
        @"frame": @(YES),
        @"keyboardClipboard": @(YES),
        @"hardwareKey": @(YES),
        @"hardwareKeyMode": @"hid_keyboard_event",
        @"ocr": @(YES),
        @"visionOCR": @(YES),
        @"ocrInputMode": @"png_data",
        @"ocrWorkerIsolation": @(YES),
        @"ocrWorkerBreadcrumbs": @(YES),
        @"tesseractOCR": @(NO),
        @"tesseractOCRCompat": @(YES),
        @"tesseractOCRMode": @"vision_fallback_task91_tiled_png_isolated",
        @"script": @(YES),
        @"scriptMode": @"javascriptcore_mvp",
        @"scriptPlaySettings": @(YES),
        @"scriptHardwareKey": @(YES),
        @"scriptTapMacro": @(YES),
        @"scheduler": @(YES),
        @"schedulerMode": @"streamd_lite",
        @"schedulerAutoLaunch": @(YES),
        @"autoLaunchMode": @"startup_after_streamd",
        @"settingsCache": @(YES),
        @"keepAwake": @(YES),
        @"keepAwakeMode": @"app_foreground_idle_timer",
        @"visualFeedback": @(YES),
        @"toastOverlay": @(YES),
        @"alertOverlay": @(YES),
        @"dialogOverlay": @(YES),
        @"dialogOverlayMode": @"limited_nonblocking_foreground_overlay",
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
        @"vpnMode": @"query_only_interface_probe",
        @"frontmost": @(YES),
        @"clearData": @(NO),
        @"shell": @(sTLinkShellTaskEnabled),
        @"shellMode": sTLinkShellTaskEnabled ? @"local_sh_gated_timeout_base64_json" : @"disabled_by_settings",
        @"hidMonitor": @(YES),
        @"privhelper": @(YES),
        @"privhelperMode": @"open_kill_restart_ensure_streamd",
        @"serviceMode": @"helper_ensure_streamd_best_effort",
    };
    CGSize screen = TLinkScreenPixelSize();
    if (sTLinkLastFrontmostBundleId.length > 0) {
        (void)TLinkResolvePidForBundleId(sTLinkLastFrontmostBundleId);
    }
    uint64_t nowMs = TLinkNowMs();
    uint64_t frontmostAgeMs = (sTLinkLastFrontmostAtMs > 0 && nowMs >= sTLinkLastFrontmostAtMs)
        ? nowMs - sTLinkLastFrontmostAtMs
        : 0;
    NSDictionary *payload = @{
        @"runtime": @"trollstore",
        @"service": @"streamd",
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
    [fm createDirectoryAtPath:@"/var/mobile/Library/TLinkauto" withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:@"/var/mobile/Library/TLinkauto/scripts" withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:kTLinkRecordingScriptsPath withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:@"/var/mobile/Library/TLinkauto/config" withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:@"/var/mobile/Library/TLinkauto/config/tweak" withIntermediateDirectories:YES attributes:nil error:nil];
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

static BOOL TLinkAppendVisionOCRTextForRegion(int x,
                                              int y,
                                              int w,
                                              int h,
                                              NSString *visionLanguages,
                                              int level,
                                              NSMutableArray<NSString *> *texts,
                                              NSString **error)
{
    NSString *visionPayload = [NSString stringWithFormat:@"1;;%d,,%d,,%d,,%d;;;;0;;%d;;%@;;%d;;",
                               x,
                               y,
                               w,
                               h,
                               level,
                               visionLanguages ?: @"",
                               level == 0 ? 1 : 0];
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
        BOOL visionAvailable = NO;
        if (@available(iOS 13.0, *)) {
            visionAvailable = YES;
        }
        if (!visionAvailable) return TLinkError(@"unsupported_on_trollstore task=91 vision_fallback_requires_ios13");
        NSError *visionErr = nil;
        NSArray<NSString *> *languages = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:VNRequestTextRecognitionLevelAccurate
                                                                                                             revision:TLinkVisionOCRRevision()
                                                                                                                error:&visionErr];
        if (!languages) return TLinkError([NSString stringWithFormat:@"vision_fallback_languages_failed %@", visionErr.localizedDescription ?: @"unknown"]);
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
    NSString *lang = parts[5] ?: @"";
    NSString *visionLanguages = TLinkVisionLanguagesFromTesseractLanguage(lang);
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
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    const uint64_t maxCompatOCRPixels = 4000000;
    const int maxTilePixels = 650000;
    int tileH = h;
    uint64_t totalPixels = (uint64_t)w * (uint64_t)h;
    if (totalPixels > maxCompatOCRPixels) {
        return TLinkError([NSString stringWithFormat:@"tesseract_vision_fallback_region_too_large max_pixels=%llu requested_pixels=%llu use_smaller_region",
                           (unsigned long long)maxCompatOCRPixels,
                           (unsigned long long)totalPixels]);
    }
    // Fast recognition is substantially more stable in a headless TrollStore
    // process on older devices. Task 27 still exposes the requested Vision
    // level; task 91 is explicitly a compatibility fallback.
    int level = 1;
    if (totalPixels > (uint64_t)maxTilePixels) {
        tileH = MAX(120, maxTilePixels / MAX(w, 1));
    }

    NSString *captureError = nil;
    TLinkSetOCRWorkerPhase("tesseract_compat_capture");
    UIImage *workerScreen = TLinkCaptureScreenImage(&captureError);
    if (!workerScreen || !workerScreen.CGImage) {
        return TLinkError([NSString stringWithFormat:@"tesseract_vision_fallback_capture_failed %@",
                           captureError ?: @"unknown"]);
    }
    sTLinkKeptScreenImage = workerScreen;

    int tileCount = 0;
    NSString *ocrError = nil;
    for (int tileY = y; tileY < y + h; tileY += tileH) {
        @autoreleasepool {
            TLinkSetOCRWorkerPhase("tesseract_compat_tile");
            int currentH = MIN(tileH, y + h - tileY);
            if (currentH <= 0) break;
            tileCount++;
            if (tileCount > 16) {
                ocrError = @"tesseract_vision_fallback_region_too_large max_tiles=16";
                break;
            }
            if (!TLinkAppendVisionOCRTextForRegion(x, tileY, w, currentH, visionLanguages, level, texts, &ocrError)) {
                break;
            }
        }
    }
    sTLinkKeptScreenImage = nil;
    double totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0;
    if (ocrError.length > 0) {
        return TLinkError(ocrError);
    }

    NSString *text = [texts componentsJoinedByString:@"\n"];
    TLinkSetOCRWorkerPhase("tesseract_compat_success");
    return TLinkSuccess([NSString stringWithFormat:@"%@;;-1.00;;0;;%.3f;;0.000;;%.3f",
                         TLinkBase64String(text),
                         totalMs,
                         totalMs]);
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
    uint64_t eventId = TLinkRecordToast([NSString stringWithFormat:@"Keep Awake %@", enabled ? @"On" : @"Off"],
                                        1.5,
                                        0,
                                        2,
                                        14,
                                        @"task40");
    return TLinkSuccess([NSString stringWithFormat:@"keep_awake_%@;;mode=app_foreground_idle_timer;;event=%llu",
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
    int action = 0;
    int requestedValue = 0;
    NSString *parseError = nil;
    if (!TLinkParseConnectivityAction(body, &action, &requestedValue, &parseError)) {
        return TLinkError(parseError ?: @"connectivity_bad_payload");
    }
    if (action == 0) {
        return TLinkSuccess(TLinkVPNInterfaceActive() ? @"1" : @"0");
    }
    return TLinkUnsupported(taskType, @"vpn_control_requires_profile_or_private_entitlement query_only_supported");
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

static NSData *TLinkHandleKnownUnsupportedTask(int taskType)
{
    if (taskType == 59) {
        return TLinkUnsupported(taskType, @"vpn_control_requires_profile_or_private_entitlement");
    }
    return TLinkUnsupported(taskType, nil);
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

    if (taskType == 90) {
        return TLinkHandleUpdateCache(body);
    }

    if (taskType == 91) {
        return TLinkHandleTesseractOCRCompat(body);
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
        NSString *cap = @"runtime=trollstore phase=image-color-frame-ocr-app-script-lite ports=6000,7001,7002,7003,7004,7005,7006 tasks=10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,90,91,96,97,98,99 capabilities=touch,touchRecording,tapMacro,capture,captureDetached,h264,hidMonitor,paths,color,image,frame,ocr,visionOCR,ocrPNGInput,ocrWorkerIsolation,ocrWorkerBreadcrumbs,tesseractOCRCompat,scriptJS,scriptStorage,scriptTaskBridge,scriptPlaySettings,scriptHardwareKey,scriptTapMacro,scheduler,schedulerAutoLaunch,settingsCache,keepAwake,visualFeedback,toastOverlay,alertOverlay,dialogOverlay,touchIndicator,appInfo,appLaunchPrivhelper,appKillPrivhelper,openURLPrivhelper,listBundles,keyboardClipboard,hardwareKey,connectivity,wifi,bluetooth,airplane,cellularData,vpnQuery,shellTaskGated,gracefulShutdown,privhelperRestart,privhelperEnsureStreamd unsupported=trueTesseractOCR,clearData,keychain,vpnControl unsupportedTasks=none keyboard=limited_on_trollstore hardwareKey=hid_keyboard_event touchRecording=iohid_monitor_raw_js_replay tapMacro=bounded_async_native_tap scheduler=streamd_lite autolaunch=startup_after_streamd keepAwake=app_foreground_idle_timer dialog=limited_nonblocking_foreground_overlay connectivity=best_effort_private_framework vpn=query_only_interface_probe shell=local_sh_or_mini_shell_gated_disabled_by_default tesseractOCR=vision_fallback_task91_tiled_png_isolated serviceMode=helper_ensure_streamd_best_effort imageMatch=naive_rgba appMgmt=limited_process_info_helper_launch_kill script=javascriptcore_mvp";
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
    TLinkEnsureRuntimeDirectories();
    TLinkLoadSettingsConfig();
    POCStartSocketServer();
    TLinkScheduleAutoLaunchStartup();
}
