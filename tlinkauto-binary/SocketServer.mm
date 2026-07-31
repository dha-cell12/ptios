// TODO: multiple client write back support

#include "SocketServer.h"
#include "IPCConstants.h"
#include "../shared/TLinkRootfullLicenseBuild.h"
#include "../shared/TLinkLicenseVerifier.h"
#include "../shared/TLinkRootfullLicensePolicy.h"
#include <string.h>
#include <ctype.h>
#include <stdlib.h>
#include <dispatch/dispatch.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <netinet/tcp.h>
#include <atomic>

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>
#ifdef ZX_DAEMON
#import "../pccontrol/TemplateMatch.h"
// Needed for TextRecognizer subtask constants (e.g. TASK_TEXT_FROM_AREA, TASK_GET_SUPPORTED_LANGUAGE_LIST)
#import "../pccontrol/TextRecognization/TextRecognizer.h"
#import "../pccontrol/TextRecognization/VKOcrManager.h"
#endif

#import "../pccontrol/Common.h"

#ifndef TLINKAUTO_FILE_LOG
#define TLINKAUTO_FILE_LOG 0
#endif

static NSMutableDictionary *socketClients = NULL;

typedef NS_ENUM(uint8_t, ZXWireProtocol) {
    ZXWireProtocolUnknown = 0,
    ZXWireProtocolLegacyV0 = 1,
    ZXWireProtocolJSONV1 = 2,
};

@interface ZXClientContext : NSObject
@property(nonatomic, assign) CFReadStreamRef readStream;
@property(nonatomic, assign) CFWriteStreamRef writeStream;
@property(nonatomic, assign) CFRunLoopRef runLoop;
@property(nonatomic, strong) NSMutableData *buffer;
@property(nonatomic, assign) ZXWireProtocol protocol;
@end

@implementation ZXClientContext
@end

static const UInt8 kZXTPMagic[4] = {'Z', 'X', 'T', 'P'};
static const UInt8 kZXTPVersion = 1;
static const UInt32 kZXTPMaxBodySize = 1024 * 1024;
static const NSUInteger kZXLegacyMaxBufferSize = 64 * 1024;
static const size_t kZXTPHeaderSize = 10;
static std::atomic<uint64_t> sTLinkRootfullLicenseTask10DropCount(0);

static NSData *zx_handleLegacyRequestBytes(const char *buffer);
static void zx_processClientBuffer(ZXClientContext *ctx);
static void zx_writeAll(CFWriteStreamRef stream, NSData *data);
static NSDictionary *zx_jsonResponseFromLegacy(NSData *legacy, NSNumber *reqId);
static NSData *zx_frameJSONResponse(NSDictionary *obj);
static void zx_logf(const char *fmt, ...);
static bool zx_isHotPathPayload(const char *payload);

static dispatch_queue_t socketQueue()
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tlinkauto.tlinkautod.socket", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void zx_cleanupClient(CFReadStreamRef readStream)
{
    if (!readStream || !socketClients) {
        return;
    }

    NSNumber *key = @((long)readStream);
    ZXClientContext *ctx = [socketClients objectForKey:key];
    if (ctx) {
        CFWriteStreamRef writeStream = ctx.writeStream;
        CFRunLoopRef runLoop = ctx.runLoop ? ctx.runLoop : CFRunLoopGetCurrent();
        [socketClients removeObjectForKey:key];

        CFReadStreamSetClient(readStream, 0, NULL, NULL);
        CFReadStreamUnscheduleFromRunLoop(readStream, runLoop, kCFRunLoopCommonModes);
        CFReadStreamClose(readStream);
        CFRelease(readStream);

        if (writeStream) {
            CFWriteStreamClose(writeStream);
            CFRelease(writeStream);
        }
        zx_logf("client closed");
        return;
    }

    // Already cleaned up. Avoid double-closing/releasing the CF stream from queued events.
}

#if TLINKAUTO_FILE_LOG
static NSString *zx_logFilePath(void)
{
    return @"/var/mobile/Library/TLinkauto/tlinkautod.log";
}

static dispatch_queue_t logQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0);
        queue = dispatch_queue_create("com.tlinkauto.tlinkautod.log", attr);
    });
    return queue;
}

static void zx_ensureLogDir(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *dir = @"/var/mobile/Library/TLinkauto";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:true
                                                   attributes:nil
                                                        error:nil];
    });
}

static void zx_ensureLogFile(void)
{
    zx_ensureLogDir();
    NSString *path = zx_logFilePath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSData data] writeToFile:path atomically:true];
    }
}
#endif

static void zx_logf(const char *fmt, ...)
{
    char msg[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(msg, sizeof(msg), fmt, args);
    va_end(args);

    // Always mirror to system log as well.
    NSLog(@"[tlinkautod] %s", msg);

#if TLINKAUTO_FILE_LOG
    // Append to file with timestamp.
    NSDate *now = [NSDate date];
    static NSDateFormatter *df = nil;
    static dispatch_once_t dateFormatterOnce;
    dispatch_once(&dateFormatterOnce, ^{
        df = [[NSDateFormatter alloc] init];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });

    NSString *line = [NSString stringWithFormat:@"%@ %s\n", [df stringFromDate:now], msg];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;

    dispatch_async(logQueue(), ^{
        static NSFileHandle *fh = nil;
        static dispatch_once_t fileHandleOnce;
        dispatch_once(&fileHandleOnce, ^{
            zx_ensureLogFile();
            fh = [NSFileHandle fileHandleForWritingAtPath:zx_logFilePath()];
            @try { [fh seekToEndOfFile]; } @catch (__unused NSException *e) { fh = nil; }
        });
        if (!fh) return;
        @try { [fh writeData:data]; } @catch (__unused NSException *e) {}
    });
#endif
}

static void readStream(CFReadStreamRef readStream, CFStreamEventType eventype, void * clientCallBackInfo);
static void TCPServerAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

// Reference: https://www.jianshu.com/p/9353105a9129

static dispatch_queue_t ipcQueue()
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tlinkauto.tlinkautod.ipc", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static bool zx_isHotPathPayload(const char *payload)
{
    if (!payload) return false;
    const char *task = strstr(payload, kTLinkautoIPCCommandTaskPrefix);
    if (!task) return false;
    task += strlen(kTLinkautoIPCCommandTaskPrefix);
    return strncmp(task, "10", 2) == 0 ||
           strncmp(task, "61", 2) == 0 ||
           strncmp(task, "62", 2) == 0 ||
           strncmp(task, "63", 2) == 0 ||
           strncmp(task, "64", 2) == 0 ||
           strncmp(task, "65", 2) == 0 ||
           strncmp(task, "66", 2) == 0 ||
           strncmp(task, "67", 2) == 0 ||
           strncmp(task, "68", 2) == 0 ||
           strncmp(task, "69", 2) == 0 ||
           strncmp(task, "70", 2) == 0 ||
           strncmp(task, "91", 2) == 0;
}

static int getTaskTypeFromBuffer(const char *buffer)
{
    if (!buffer || !isdigit(buffer[0]) || !isdigit(buffer[1])) {
        return -1;
    }
    return (buffer[0] - '0') * 10 + (buffer[1] - '0');
}

static bool shouldRouteToSpringBoard(int taskType)
{
    switch (taskType) {
        case 10: // TASK_PERFORM_TOUCH
        case 11: // TASK_PROCESS_BRING_FOREGROUND
        case 12: // TASK_SHOW_ALERT_BOX
        case 14: // TASK_TOUCH_RECORDING_START
        case 15: // TASK_TOUCH_RECORDING_STOP
        case 16: // TASK_CRAZY_TAP
        case 17: // TASK_RAPID_FIRE_TAP
        case 19: // TASK_PLAY_SCRIPT
        case 20: // TASK_PLAY_SCRIPT_FORCE_STOP
#ifndef ZX_DAEMON
        case 21: // TASK_TEMPLATE_MATCH
#endif
        case 22: // TASK_SHOW_TOAST
        case 23: // TASK_COLOR_PICKER
        case 24: // TASK_TEXT_INPUT
        case 25: // TASK_GET_DEVICE_INFO
        case 26: // TASK_TOUCH_INDICATOR

        // ✅ FIX: OCR must always route to SpringBoard (Vision stable there)
        case 27: // TASK_TEXT_RECOGNIZER

        case 28: // TASK_COLOR_SEARCHER
        case 29: // TASK_SCREENSHOT
        case 30: // TASK_HARDWARE_KEY
        case 31: // TASK_APP_KILL
        case 32: // TASK_APP_STATE
        case 33: // TASK_APP_INFO
        case 34: // TASK_FRONTMOST_APP_ID
        case 35: // TASK_FRONTMOST_APP_ORIENTATION
        case 36: // TASK_SET_AUTO_LAUNCH
        case 37: // TASK_LIST_AUTO_LAUNCH
        case 38: // TASK_SET_TIMER
        case 39: // TASK_REMOVE_TIMER
        case 40: // TASK_KEEP_AWAKE
        case 41: // TASK_STOP_SCRIPT
        case 42: // TASK_DIALOG
        case 43: // TASK_CLEAR_DIALOG
        case 44: // TASK_ROOT_DIR
        case 45: // TASK_CURRENT_DIR
        case 46: // TASK_BOT_PATH
        case 47: // TASK_SCREEN_KEEP
        case 48: // TASK_IMAGE_OBJECT
        case 49: // TASK_FIND_IMAGE
        case 50: // TASK_APP_PID
        case 51: // TASK_FRONTMOST_PID
        case 52: // TASK_APP_PATHS
        case 53: // TASK_LIST_BUNDLES
        case 54: // TASK_OPEN_URL
        case 55: // TASK_WIFI
        case 56: // TASK_BLUETOOTH
        case 57: // TASK_AIRPLANE
        case 58: // TASK_CELLULAR_DATA
        case 59: // TASK_VPN
        case 60: // TASK_HELLO_STATUS
        case 61: // TASK_PERFORM_TOUCH_ACK
        case 62: // TASK_NATIVE_TAP
        case 63: // TASK_NATIVE_SWIPE
        case 64: // TASK_NATIVE_GESTURE
        case 65: // TASK_NATIVE_BATCH
        case 66: // TASK_FRAME_CAPTURE
        case 67: // TASK_FRAME_RELEASE
        case 68: // TASK_FIND_IMAGE_IN_FRAME
        case 69: // TASK_COLOR_IN_FRAME
        case 70: // TASK_FRAME_BATCH
        case 91: // TASK_OCR_TESSERACT_REGION
        case 90: // TASK_UPDATE_CACHE
            return true;
        default:
            return false;
    }
}

static bool shouldWaitForResponse(int taskType)
{
    switch (taskType) {
        case 10: // TASK_PERFORM_TOUCH
        case 14: // TASK_TOUCH_RECORDING_START
        case 15: // TASK_TOUCH_RECORDING_STOP
        case 16: // TASK_CRAZY_TAP
        case 17: // TASK_RAPID_FIRE_TAP
        case 19: // TASK_PLAY_SCRIPT
        case 20: // TASK_PLAY_SCRIPT_FORCE_STOP
        case 36: // TASK_SET_AUTO_LAUNCH
        case 38: // TASK_SET_TIMER
        case 39: // TASK_REMOVE_TIMER
        case 40: // TASK_KEEP_AWAKE
            return false;
        default:
            return true;
    }
}

static CFDataRef sendIPCMessage(const char *payload, bool waitForResponse)
{
    CFDataRef responseData = NULL;
    if (access(kTLinkautoIPCReadyMarkerPath, F_OK) != 0) {
        NSLog(@"### com.tlinkauto.tlinkautod: IPC ready marker missing.");
        return NULL;
    }
    static CFMessagePortRef remotePort = NULL;
    if (remotePort && !CFMessagePortIsValid(remotePort)) {
        CFRelease(remotePort);
        remotePort = NULL;
    }
    if (!remotePort) {
        remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, kTLinkautoIPCPortName);
    }
    if (!remotePort) {
        NSLog(@"### com.tlinkauto.tlinkautod: unable to find SpringBoard IPC port.");
        return NULL;
    }

    bool pingRequired = waitForResponse && strcmp(payload, kTLinkautoIPCCommandPing) != 0;
    if (pingRequired) {
        static CFAbsoluteTime lastPingSuccess = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastPingSuccess > 1.0) {
            CFDataRef pingData = CFDataCreate(kCFAllocatorDefault,
                                              (const UInt8 *)kTLinkautoIPCCommandPing,
                                              strlen(kTLinkautoIPCCommandPing));
            SInt32 pingResult = CFMessagePortSendRequest(remotePort,
                                                         1,
                                                         pingData,
                                                         2.0,
                                                         2.0,
                                                         kCFRunLoopDefaultMode,
                                                         NULL);
            if (pingData) {
                CFRelease(pingData);
            }
            if (pingResult != kCFMessagePortSuccess) {
                NSLog(@"### com.tlinkauto.tlinkautod: IPC ping failed with code %d", (int)pingResult);
                if (remotePort) {
                    CFRelease(remotePort);
                    remotePort = NULL;
                }
                return NULL;
            } else {
                lastPingSuccess = now;
            }
        }
    }

    CFDataRef messageData = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)payload, strlen(payload));
    bool hotPathPayload = zx_isHotPathPayload(payload);
    if (!hotPathPayload) {
        NSLog(@"### com.tlinkauto.tlinkautod: IPC send payload: %s", payload);
    }
    CFDataRef *responseTarget = waitForResponse ? &responseData : NULL;
    const CFTimeInterval sendTimeout = waitForResponse ? 5.0 : 1.5;
    SInt32 result = CFMessagePortSendRequest(remotePort,
                                             1,
                                             messageData,
                                             sendTimeout,
                                             sendTimeout,
                                             kCFRunLoopDefaultMode,
                                             responseTarget);
    if (result != kCFMessagePortSuccess) {
        NSLog(@"### com.tlinkauto.tlinkautod: IPC send failed with code %d", (int)result);
        if (remotePort) {
            CFRelease(remotePort);
            remotePort = NULL;
        }
    } else if (!hotPathPayload) {
        NSLog(@"### com.tlinkauto.tlinkautod: IPC send success");
    }

    if (messageData) {
        CFRelease(messageData);
    }
    return responseData;
}

// ------------------------------
// Daemon-side handlers for heavy tasks (21)
// Strategy: ask SpringBoard to capture a screenshot via task 29, then process locally.
// NOTE: Return value is a malloc'ed C-string that caller must free().

#ifdef ZX_DAEMON
static char *handleTemplateMatchTaskInDaemon(const char *buffer);
#endif

static char *zx_strdup_nsstring(NSString *s)
{
    if (!s) {
        const char *fallback = "1;;nil_response\r\n";
        return (char *)strdup(fallback);
    }
    const char *utf8 = [s UTF8String];
    if (!utf8) {
        const char *fallback = "1;;utf8_encode_failed\r\n";
        return (char *)strdup(fallback);
    }
    return (char *)strdup(utf8);
}

static NSString *zx_ipcResponseToString(CFDataRef responseData)
{
    if (!responseData) return nil;
    const UInt8 *bytes = CFDataGetBytePtr(responseData);
    CFIndex len = CFDataGetLength(responseData);
    if (!bytes || len <= 0) return nil;
    NSData *d = [NSData dataWithBytes:bytes length:(NSUInteger)len];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

static NSString *zx_ipcCaptureScreenshotToPath(NSString *path, NSString **errString)
{
    if (!path || [path length] == 0) {
        if (errString) *errString = @"-1;;Screenshot path is empty.\r\n";
        return nil;
    }

    NSString *taskPayload = [NSString stringWithFormat:@"%s29%s1;;%@", kTLinkautoIPCCommandTaskPrefix, "", path];
    __block CFDataRef responseData = NULL;
    dispatch_sync(ipcQueue(), ^{
        responseData = sendIPCMessage([taskPayload UTF8String], true);
    });
    NSString *resp = zx_ipcResponseToString(responseData);
    if (responseData) CFRelease(responseData);
    if (!resp) {
        if (errString) *errString = @"1;;ipc_screenshot_no_response\r\n";
        return nil;
    }
    if ([resp hasPrefix:@"0;;"]) {
        NSString *p = [resp substringFromIndex:3];
        p = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([p length] == 0) return path;
        return p;
    }
    if (errString) *errString = resp;
    return nil;
}

static int zx_ipcGetFrontmostOrientation(void)
{
    NSString *taskPayload = [NSString stringWithFormat:@"%s35", kTLinkautoIPCCommandTaskPrefix];
    __block CFDataRef responseData = NULL;
    dispatch_sync(ipcQueue(), ^{
        responseData = sendIPCMessage([taskPayload UTF8String], true);
    });
    NSString *resp = zx_ipcResponseToString(responseData);
    if (responseData) CFRelease(responseData);
    if (!resp || ![resp hasPrefix:@"0;;"]) {
        return 1;
    }
    NSString *val = [[resp substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [val intValue] ?: 1;
}

static NSString *zx_makeTempScreenshotPath(void)
{
    NSString *uuid = [[NSUUID UUID] UUIDString];
    return [NSString stringWithFormat:@"/tmp/tlinkautod_capture_%@.png", uuid];
}

static void zx_safeUnlink(NSString *path)
{
    if (!path) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

#ifdef ZX_DAEMON
static char *handleTemplateMatchTaskInDaemon(const char *buffer)
{
    zx_logf("Task21 enter: raw=%s", buffer ? buffer : "(null)");
    const char *eventC = buffer ? buffer + 2 : NULL;
    if (!eventC) return (char *)strdup("-1;;Empty task payload.\r\n");
    NSString *eventData = [NSString stringWithUTF8String:eventC] ?: @"";
    NSArray *parts = [eventData componentsSeparatedByString:@";;"];
    NSString *templatePath = (parts.count >= 1) ? parts[0] : @"";
    int maxTryTimes = 2;
    float acceptableValue = 0.8f;
    float scaleRation = 0.8f;
    if (parts.count == 4) {
        maxTryTimes = [parts[1] intValue];
        acceptableValue = [parts[2] floatValue];
        scaleRation = [parts[3] floatValue];
    } else if (parts.count != 1) {
        return (char *)strdup("-1;;The data format should be \"template_path[;;max_try_times;;acceptable_value;;scaleRation]\"\r\n");
    }
    if ([templatePath length] == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:templatePath]) {
        NSString *err = [NSString stringWithFormat:@"-1;;Template image not found for image matching. Template path: %@\r\n", templatePath];
        zx_logf("Task21 error: template not found path=%s", [templatePath UTF8String]);
        return zx_strdup_nsstring(err);
    }

    zx_logf("Task21 template=%s maxTry=%d acceptable=%.3f scale=%.3f", [templatePath UTF8String], maxTryTimes, acceptableValue, scaleRation);

    NSString *tmpPath = zx_makeTempScreenshotPath();
    NSString *errString = nil;
    NSString *shotPath = zx_ipcCaptureScreenshotToPath(tmpPath, &errString);
    if (!shotPath) {
        zx_logf("Task21 screenshot capture failed: %s", errString ? [errString UTF8String] : "(no err)");
        zx_safeUnlink(tmpPath);
        return zx_strdup_nsstring(errString ?: @"-1;;Failed to capture screenshot.\r\n");
    }

    for (int i = 0; i < 3; i++) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:shotPath]) break;
        usleep(40000);
    }
    struct stat st;
    long long fsz = (stat([shotPath fileSystemRepresentation], &st) == 0) ? (long long)st.st_size : -1;
    zx_logf("Task21 screenshot path=%s size=%lld", [shotPath UTF8String], fsz);

    NSError *err = nil;
    TemplateMatch *tm = [[TemplateMatch alloc] init];
    [tm setAcceptableValue:acceptableValue];
    [tm setMaxTryTimes:maxTryTimes];
    [tm setScaleRation:scaleRation];

    zx_logf("Task21 start match (opencv) screenshot=%s template=%s", [shotPath UTF8String], [templatePath UTF8String]);
    CGRect r = [tm templateMatchWithPath:shotPath templatePath:templatePath error:&err];
    zx_logf("Task21 end match (opencv)");
    zx_safeUnlink(shotPath);

    if (err) {
        zx_logf("Task21 match error: %s", [[err localizedDescription] UTF8String]);
        return zx_strdup_nsstring([err localizedDescription]);
    }
    zx_logf("Task21 match rect x=%.2f y=%.2f w=%.2f h=%.2f", r.origin.x, r.origin.y, r.size.width, r.size.height);
    NSString *resp = [NSString stringWithFormat:@"0;;%.2f;;%.2f;;%.2f;;%.2f\r\n", r.origin.x, r.origin.y, r.size.width, r.size.height];
    return zx_strdup_nsstring(resp);
}
#endif

static void zx_writeAll(CFWriteStreamRef stream, NSData *data)
{
    if (!stream || !data || data.length == 0) {
        return;
    }
    const UInt8 *bytes = (const UInt8 *)data.bytes;
    CFIndex remaining = (CFIndex)data.length;
    while (remaining > 0) {
        CFIndex wrote = CFWriteStreamWrite(stream, bytes, remaining);
        if (wrote <= 0) {
            break;
        }
        bytes += wrote;
        remaining -= wrote;
    }
}

static NSData *zx_dataFromCString(const char *cstr)
{
    if (!cstr) {
        return nil;
    }
    return [NSData dataWithBytes:cstr length:strlen(cstr)];
}

static NSData *zx_rootfullPhase6DiagnosticResponse(int taskType, const char *buffer)
{
    if (taskType == 75 || taskType == 76) {
        uint64_t generationBefore = TLinkLicenseGeneration();
        NSString *action = @"status";
        if (taskType == 76) {
            NSString *rawBody = buffer && strlen(buffer) > 2
                ? [NSString stringWithUTF8String:buffer + 2]
                : @"";
            NSString *mode = [[rawBody ?: @"" stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
            if ([mode isEqualToString:@"reload"]) {
                TLinkLicenseInvalidateCache();
                action = @"reload";
            } else {
                TLinkLicenseAdvanceGeneration();
                action = @"advance";
            }
        }

        NSMutableDictionary *status = [TLinkLicenseStatusDictionary() mutableCopy];
        status[@"license_contract_version"] = @1;
        status[@"rootfull_license_phase"] = @6;
        status[@"runtime"] = @"rootfull";
        status[@"runtime_gate_active"] = @1;
        status[@"activation_lifecycle_active"] = @1;
        status[@"enforcement_scope"] = @"task_and_long_running_component_gate";
        status[@"task_policy"] = @"rootfull_explicit_v1";
        status[@"h264_gate_active"] = @1;
        status[@"h264_heartbeat_interval_ms"] = @5000;
        status[@"script_heartbeat_active"] = @1;
        status[@"script_heartbeat_interval_ms"] = @1000;
        status[@"scheduler_launch_gate_active"] = @1;
        status[@"helper_runtime_gate_active"] = @1;
        status[@"ui_feature_snapshot_active"] = @1;
        status[@"release_integrity_active"] = @1;
        status[@"anti_rollback_active"] = @1;
        status[@"verifier_performance"] = TLinkLicensePerformanceDictionary();
        status[@"task10_license_drop_count"] =
            @(sTLinkRootfullLicenseTask10DropCount.load(std::memory_order_relaxed));
        status[@"rootfull_build_mode"] =
            [NSString stringWithUTF8String:TLinkRootfullLicenseBuildMode()] ?: @"";
        status[@"verifier_build_mode"] = TLinkLicenseBuildMode() ?: @"";
        status[@"cache_invalidated"] = @(taskType == 76);
        status[@"generation_before"] = @(generationBefore);
        status[@"license_generation"] = @(TLinkLicenseGeneration());
        status[@"generation_action"] = action;
        status[@"source"] = @"tlinkautod_rootfull_phase6_release_hardened";
        NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
        if (json.length == 0) {
            return zx_dataFromCString("-1;;license_status_json_failed\r\n");
        }
        NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @"";
        return zx_dataFromCString([[NSString stringWithFormat:@"0;;%@\r\n", base64] UTF8String]);
    }

    switch (taskType) {
        case 97: {
            NSDictionary *status = TLinkLicenseStatusDictionary();
            return zx_dataFromCString([[NSString stringWithFormat:
                @"0;;runtime=rootfull service=tlinkautod license_contract_version=1 license_phase=6 verifier=shared_signed_lease activationUI=1 lifecycle=foreground_single_flight_backoff runtimeGate=1 gateScope=task_and_long_running_component taskPolicy=rootfull_explicit_v1 h264Gate=1 h264HeartbeatMs=5000 scriptHeartbeat=1 scriptHeartbeatMs=1000 schedulerGate=1 helperGate=1 uiFeatureSnapshot=1 verifierMetrics=1 releaseIntegrity=1 antiRollback=1 task10LicenseDropCount=%llu licenseState=%@ licenseConfigured=%d licenseGeneration=%llu rootfullBuildMode=%s verifierBuildMode=%@ ports=6000,7001,7002,7003,7004,7005,7006 visionOCRState=ready visionOCRProfiles=springboard_default visionOCRRoute=daemon_to_springboard visionOCRFallback=none ocrDefaultEngine=tesseract ocrEngineSelector=none ocrProtocolVersion=legacy_v1 ocrLegacyTasks=27,91 vpnContractVersion=1 vpnLegacyTask=59 vpnProfileScope=tlink_owned_only vpnConfigurationTransport=local_ui_keychain_only vpnCredentialsOverTask59=forbidden vpnState=broker_managed vpnQuery=broker_localhost_6014 vpnControl=broker_localhost_6014 vpnBackend=nevpnmanager_ikev2 vpnBroker=tlinkauto_vpnd_6014 vpnPhase=2 vpnDiagnostics=task59_action2_base64_json_v1 vpnEntitlementProbe=broker_process_via_592 vpnProfileIdentifier=tlinkauto-managed-v1\r\n",
                (unsigned long long)sTLinkRootfullLicenseTask10DropCount.load(std::memory_order_relaxed),
                status[@"state"] ?: @"invalid",
                [status[@"configured"] boolValue] ? 1 : 0,
                (unsigned long long)TLinkLicenseGeneration(),
                TLinkRootfullLicenseBuildMode(),
                TLinkLicenseBuildMode()] UTF8String]);
        }
        case 99:
            return zx_dataFromCString("0;;tlinkauto_alive\r\n");
        default:
            return nil;
    }
}

static NSData *zx_handleLegacyRequestBytes(const char *buffer)
{
    if (!buffer) {
        return nil;
    }
    const int taskType = getTaskTypeFromBuffer(buffer);
    if (taskType != 10 && taskType != 61) {
        zx_logf("received task payload: %s", buffer);
    }

    NSString *licenseDenial = nil;
    BOOL homeCommand = strcmp(buffer, kTLinkautoIPCCommandHome) == 0;
    BOOL licenseAllowed = homeCommand
        ? TLinkRootfullLicenseComponentAllowed(@"automation", @"home_command", &licenseDenial)
        : TLinkRootfullLicenseTaskAllowed(taskType, &licenseDenial);
    if (!licenseAllowed) {
        if (taskType == 10) {
            sTLinkRootfullLicenseTask10DropCount.fetch_add(1, std::memory_order_relaxed);
            zx_logf("task 10 dropped by rootfull license gate");
            return nil;
        }
        zx_logf("task %d denied by rootfull license gate: %s",
                taskType,
                [licenseDenial UTF8String] ?: "license_required");
        return zx_dataFromCString([licenseDenial UTF8String]);
    }

    NSData *phase6Diagnostic = zx_rootfullPhase6DiagnosticResponse(taskType, buffer);
    if (phase6Diagnostic) {
        return phase6Diagnostic;
    }

    if (taskType == 96) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(150 * NSEC_PER_MSEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            exit(0);
        });
        return zx_dataFromCString("0;;tlinkautod_exiting\r\n");
    }

#ifdef ZX_DAEMON
    // daemon only handles task 21; task 27 routes to SpringBoard
    if (taskType == 21) {
        const char *respC = handleTemplateMatchTaskInDaemon(buffer);
        NSData *resp = zx_dataFromCString(respC);
        if (respC) free((void *)respC);
        return resp;
    }
#endif

    bool isSpringBoardTask = taskType >= 0 && shouldRouteToSpringBoard(taskType);

    if (strcmp(buffer, kTLinkautoIPCCommandHome) == 0) {
        isSpringBoardTask = true;
    }

    if (isSpringBoardTask) {
        char ipcPayload[4096];
        if (strcmp(buffer, kTLinkautoIPCCommandHome) == 0) {
            snprintf(ipcPayload, sizeof(ipcPayload), "%s", kTLinkautoIPCCommandHome);
        } else {
            int written = snprintf(ipcPayload, sizeof(ipcPayload), "%s%s", kTLinkautoIPCCommandTaskPrefix, buffer);
            if (written < 0 || (size_t)written >= sizeof(ipcPayload)) {
                zx_logf("IPC payload too large; dropping task");
                return zx_dataFromCString("1;;ipc_payload_too_large\r\n");
            }
        }
        NSString *payloadString = [NSString stringWithUTF8String:ipcPayload];
        if (!payloadString) {
            return zx_dataFromCString("1;;invalid_payload\r\n");
        }
        bool waitForResponse = strcmp(buffer, kTLinkautoIPCCommandHome) == 0
            ? true
            : shouldWaitForResponse(taskType);
        __block CFDataRef responseData = NULL;
        dispatch_sync(ipcQueue(), ^{
            responseData = sendIPCMessage([payloadString UTF8String], waitForResponse);
        });
        if (!waitForResponse && taskType == 10) {
            // No response for touch.
            if (responseData) {
                CFRelease(responseData);
            }
            return nil;
        }
        if (responseData) {
            const UInt8 *responseBytes = CFDataGetBytePtr(responseData);
            CFIndex responseLength = CFDataGetLength(responseData);
            NSData *response = nil;
            if (responseBytes && responseLength > 0) {
                response = [NSData dataWithBytes:responseBytes length:(NSUInteger)responseLength];
                NSString *responseString = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
                if (taskType != 61) {
                    zx_logf("IPC response: %s", responseString ? [responseString UTF8String] : "(null)");
                }
            } else {
                zx_logf("IPC response empty");
                response = zx_dataFromCString("0\r\n");
            }
            CFRelease(responseData);
            return response;
        }

        const char *fallback = waitForResponse ? "1;;ipc_not_ready\r\n" : "0;;queued\r\n";
        return zx_dataFromCString(fallback);
    }

    return zx_dataFromCString("1;;tlinkautod: task handling not implemented\r\n");
}

static NSDictionary *zx_jsonResponseFromLegacy(NSData *legacy, NSNumber *reqId)
{
    NSString *s = legacy ? [[NSString alloc] initWithData:legacy encoding:NSUTF8StringEncoding] : @"";
    if (!s) {
        return @{@"id": reqId ?: @0, @"ok": @false, @"data": [NSNull null], @"error": @"invalid_response"};
    }
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if ([s length] == 0) {
        return @{@"id": reqId ?: @0, @"ok": @true, @"data": [NSNull null], @"error": [NSNull null]};
    }

    NSArray<NSString *> *parts = [s componentsSeparatedByString:@";;"];
    NSString *status = parts.count > 0 ? parts[0] : @"1";
    if (![status hasPrefix:@"0"]) {
        NSString *err = parts.count >= 2 ? parts[1] : @"Unknown error";
        return @{@"id": reqId ?: @0, @"ok": @false, @"data": [NSNull null], @"error": err};
    }

    NSArray *data = parts.count > 1 ? [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] : @[];
    return @{@"id": reqId ?: @0, @"ok": @true, @"data": data, @"error": [NSNull null]};
}

static NSData *zx_frameJSONResponse(NSDictionary *obj)
{
    if (!obj) {
        return nil;
    }
    NSError *err = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&err];
    if (!body || err) {
        return nil;
    }
    if (body.length > kZXTPMaxBodySize) {
        return nil;
    }
    UInt8 header[kZXTPHeaderSize];
    header[0] = kZXTPMagic[0];
    header[1] = kZXTPMagic[1];
    header[2] = kZXTPMagic[2];
    header[3] = kZXTPMagic[3];
    header[4] = kZXTPVersion;
    header[5] = 0;
    UInt32 len = (UInt32)body.length;
    header[6] = (UInt8)((len >> 24) & 0xFF);
    header[7] = (UInt8)((len >> 16) & 0xFF);
    header[8] = (UInt8)((len >> 8) & 0xFF);
    header[9] = (UInt8)(len & 0xFF);

    NSMutableData *framed = [NSMutableData dataWithBytes:header length:sizeof(header)];
    [framed appendData:body];
    return framed;
}

static void zx_processClientBuffer(ZXClientContext *ctx)
{
    if (!ctx || !ctx.buffer) {
        return;
    }

    while (true) {
        const UInt8 *bytes = (const UInt8 *)ctx.buffer.bytes;
        const NSUInteger len = ctx.buffer.length;
        if (len == 0) {
            return;
        }

        if (ctx.protocol == ZXWireProtocolUnknown) {
            if (len >= 4 && memcmp(bytes, kZXTPMagic, 4) == 0) {
                ctx.protocol = ZXWireProtocolJSONV1;
            } else if (len >= 2 && isdigit(bytes[0]) && isdigit(bytes[1])) {
                ctx.protocol = ZXWireProtocolLegacyV0;
            } else if (len >= 4) {
                // Default to legacy if it doesn't look like ZXTP.
                ctx.protocol = ZXWireProtocolLegacyV0;
            } else {
                return;
            }
        }

        if (ctx.protocol == ZXWireProtocolLegacyV0) {
            if (ctx.buffer.length > kZXLegacyMaxBufferSize) {
                zx_logf("legacy buffer too large; clearing client buffer");
                [ctx.buffer setLength:0];
                return;
            }

            // Parse line-delimited requests.
            NSUInteger nl = NSNotFound;
            for (NSUInteger i = 0; i < len; i++) {
                if (bytes[i] == '\n') {
                    nl = i;
                    break;
                }
            }
            if (nl == NSNotFound) {
                // Backward compatibility:
                // TLinkauto app (Play Script) sends task 19 without trailing CRLF.
                // The legacy implementation processed whatever arrived in a single read.
                if (len >= 2 && isdigit(bytes[0]) && isdigit(bytes[1])) {
                    int taskType = getTaskTypeFromBuffer((const char *)bytes);
                    if (taskType == 19 && len > 2) {
                        char *line = (char *)malloc(len + 1);
                        memcpy(line, bytes, len);
                        line[len] = 0;
                        NSData *resp = zx_handleLegacyRequestBytes(line);
                        zx_writeAll(ctx.writeStream, resp);
                        free(line);
                        [ctx.buffer setLength:0];
                    }
                }
                return;
            }

            NSUInteger lineLen = nl;
            if (lineLen > 0 && bytes[lineLen - 1] == '\r') {
                lineLen -= 1;
            }

            if (lineLen > 0) {
                char *line = (char *)malloc(lineLen + 1);
                memcpy(line, bytes, lineLen);
                line[lineLen] = 0;
                NSData *resp = zx_handleLegacyRequestBytes(line);
                zx_writeAll(ctx.writeStream, resp);
                free(line);
            }

            NSUInteger removeLen = nl + 1;
            if (ctx.buffer.length >= removeLen) {
                [ctx.buffer replaceBytesInRange:NSMakeRange(0, removeLen) withBytes:NULL length:0];
            } else {
                zx_logf("legacy buffer changed during parse; clearing client buffer");
                [ctx.buffer setLength:0];
                return;
            }
            continue;
        }

        // ZXTP v1
        if (len < kZXTPHeaderSize) {
            return;
        }
        if (memcmp(bytes, kZXTPMagic, 4) != 0) {
            // Desync: fallback to legacy.
            ctx.protocol = ZXWireProtocolLegacyV0;
            continue;
        }
        if (bytes[4] != kZXTPVersion) {
            // Unsupported version.
            NSDictionary *respObj = @{@"id": @0, @"ok": @false, @"data": [NSNull null], @"error": @"unsupported_version"};
            zx_writeAll(ctx.writeStream, zx_frameJSONResponse(respObj));
            [ctx.buffer setLength:0];
            return;
        }

        UInt32 bodyLen = ((UInt32)bytes[6] << 24) | ((UInt32)bytes[7] << 16) | ((UInt32)bytes[8] << 8) | (UInt32)bytes[9];
        if (bodyLen > kZXTPMaxBodySize) {
            NSDictionary *respObj = @{@"id": @0, @"ok": @false, @"data": [NSNull null], @"error": @"body_too_large"};
            zx_writeAll(ctx.writeStream, zx_frameJSONResponse(respObj));
            [ctx.buffer setLength:0];
            return;
        }
        if (len < kZXTPHeaderSize + (NSUInteger)bodyLen) {
            return;
        }

        NSData *body = [ctx.buffer subdataWithRange:NSMakeRange(kZXTPHeaderSize, (NSUInteger)bodyLen)];
        NSError *jsonErr = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:body options:0 error:&jsonErr];
        NSNumber *reqId = @0;
        if (jsonErr || ![obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *respObj = @{@"id": reqId, @"ok": @false, @"data": [NSNull null], @"error": @"invalid_json"};
            zx_writeAll(ctx.writeStream, zx_frameJSONResponse(respObj));
        } else {
            NSDictionary *dict = (NSDictionary *)obj;
            reqId = [dict objectForKey:@"id"];
            if (![reqId isKindOfClass:[NSNumber class]]) {
                reqId = @0;
            }
            NSNumber *taskNum = [dict objectForKey:@"task"];
            NSArray *args = [dict objectForKey:@"args"];
            if (![taskNum isKindOfClass:[NSNumber class]]) {
                NSDictionary *respObj = @{@"id": reqId, @"ok": @false, @"data": [NSNull null], @"error": @"missing_task"};
                zx_writeAll(ctx.writeStream, zx_frameJSONResponse(respObj));
            } else {
                int task = [taskNum intValue];
                NSMutableString *legacy = [NSMutableString stringWithFormat:@"%02d", task];
                if ([args isKindOfClass:[NSArray class]] && args.count > 0) {
                    id first = args[0];
                    [legacy appendString:[first isKindOfClass:[NSString class]] ? (NSString *)first : [first description]];
                    for (NSUInteger i = 1; i < args.count; i++) {
                        id a = args[i];
                        NSString *part = [a isKindOfClass:[NSString class]] ? (NSString *)a : [a description];
                        [legacy appendFormat:@";;%@", part ?: @""];
                    }
                }

                // Fire-and-forget tasks should not emit a JSON response frame,
                // because many clients don't read responses for these tasks.
                // Emitting a frame would desync subsequent request/response pairs.
                bool fireAndForget = (task == 10 || task == 14 || task == 15 || task == 16 || task == 17 || task == 19 || task == 20 || task == 36 || task == 38 || task == 39 || task == 40);
                NSData *legacyResp = zx_handleLegacyRequestBytes([legacy UTF8String]);
                if (!fireAndForget) {
                    NSDictionary *respObj = zx_jsonResponseFromLegacy(legacyResp, reqId);
                    zx_writeAll(ctx.writeStream, zx_frameJSONResponse(respObj));
                }
            }
        }

        NSUInteger removeLen = kZXTPHeaderSize + (NSUInteger)bodyLen;
        if (ctx.buffer.length >= removeLen) {
            [ctx.buffer replaceBytesInRange:NSMakeRange(0, removeLen) withBytes:NULL length:0];
        } else {
            zx_logf("v1 buffer changed during parse; clearing client buffer");
            [ctx.buffer setLength:0];
            return;
        }
    }
}

static void handleDaemonMessage(UInt8 *buff, CFWriteStreamRef client)
{
    if (!buff) {
        return;
    }
    NSData *resp = zx_handleLegacyRequestBytes((const char *)buff);
    zx_writeAll(client, resp);
}

void socketServer()
{
    @autoreleasepool {
        CFSocketRef _socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, TCPServerAcceptCallBack, NULL);

        if (_socket == NULL) {
            NSLog(@"### com.tlinkauto.tlinkautod: failed to create socket.");
            return;
        }

        UInt32 reused = 1;

        setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, (const void *)&reused, sizeof(reused));

        struct sockaddr_in Socketaddr;
        memset(&Socketaddr, 0, sizeof(Socketaddr));
        Socketaddr.sin_len = sizeof(Socketaddr);
        Socketaddr.sin_family = AF_INET;

        Socketaddr.sin_addr.s_addr = inet_addr(TLinkautoD_ADDR);

        Socketaddr.sin_port = htons(TLinkautoD_PORT);

        CFDataRef address = CFDataCreate(kCFAllocatorDefault,  (UInt8 *)&Socketaddr, sizeof(Socketaddr));

        if (CFSocketSetAddress(_socket, address) != kCFSocketSuccess) {

            if (_socket) {
                CFRelease(_socket);
            }

            _socket = NULL;
        }
        if (address) {
            CFRelease(address);
        }

        if (_socket == NULL) {
            NSLog(@"### com.tlinkauto.tlinkautod: failed to bind socket.");
            return;
        }

        socketClients = [[NSMutableDictionary alloc] init];

        NSLog(@"### com.tlinkauto.tlinkautod: connection waiting on port %d", TLinkautoD_PORT);
        CFRunLoopRef cfrunLoop = CFRunLoopGetCurrent();
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);

        CFRunLoopAddSource(cfrunLoop, source, kCFRunLoopCommonModes);

        CFRelease(source);
        CFRunLoopRun();
    }

}

static void readStream(CFReadStreamRef readStream, CFStreamEventType eventype, void * clientCallBackInfo)
{
    dispatch_async(socketQueue(), ^{
        @autoreleasepool{
            if (eventype == kCFStreamEventEndEncountered || eventype == kCFStreamEventErrorOccurred) {
                zx_cleanupClient(readStream);
                return;
            }
            if (eventype != kCFStreamEventHasBytesAvailable) {
                return;
            }

            UInt8 readDataBuff[2048];

            CFIndex hasRead = CFReadStreamRead(readStream, readDataBuff, sizeof(readDataBuff));

            if (hasRead > 0) {
                ZXClientContext *ctx = [socketClients objectForKey:@((long)readStream)];
                if (!ctx) {
                    zx_logf("read event for unknown client; ignoring");
                    return;
                }
                [ctx.buffer appendBytes:readDataBuff length:(NSUInteger)hasRead];
                zx_processClientBuffer(ctx);
            } else {
                zx_cleanupClient(readStream);
            }
        }
    });

}

static void TCPServerAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    if (kCFSocketAcceptCallBack == type) {

        CFSocketNativeHandle  nativeSocketHandle = *(CFSocketNativeHandle *)data;
        int one = 1;
        setsockopt(nativeSocketHandle, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

        uint8_t name[SOCK_MAXADDRLEN];
        socklen_t namelen = sizeof(name);

        if (getpeername(nativeSocketHandle, (struct sockaddr *)name, &namelen) != 0) {

            NSLog(@"### com.tlinkauto.tlinkautod: ++++++++getpeername+++++++");

            close(nativeSocketHandle);
            return;
        }

        struct sockaddr_in *addr_in = (struct sockaddr_in *)name;
        NSLog(@"### com.tlinkauto.tlinkautod: connection starts from %s:%d", inet_ntoa(addr_in->sin_addr), ntohs(addr_in->sin_port));

        CFReadStreamRef readStreamRef = NULL;
        CFWriteStreamRef writeStreamRef = NULL;

        CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStreamRef, &writeStreamRef);

        if (readStreamRef && writeStreamRef) {
            CFReadStreamSetProperty(readStreamRef, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
            CFWriteStreamSetProperty(writeStreamRef, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);

            CFReadStreamOpen(readStreamRef);
            CFWriteStreamOpen(writeStreamRef);

            CFStreamClientContext context = {0, NULL, NULL, NULL };

            CFOptionFlags events = kCFStreamEventHasBytesAvailable | kCFStreamEventEndEncountered | kCFStreamEventErrorOccurred;
            if (!CFReadStreamSetClient(readStreamRef, events, readStream, &context)) {
                NSLog(@"### com.tlinkauto.tlinkautod: error 1");
                CFReadStreamClose(readStreamRef);
                CFWriteStreamClose(writeStreamRef);
                CFRelease(readStreamRef);
                CFRelease(writeStreamRef);
                return;
            }

            ZXClientContext *ctx = [[ZXClientContext alloc] init];
            ctx.readStream = readStreamRef;
            ctx.writeStream = writeStreamRef;
            ctx.runLoop = CFRunLoopGetCurrent();
            ctx.buffer = [NSMutableData data];
            ctx.protocol = ZXWireProtocolUnknown;
            dispatch_sync(socketQueue(), ^{
                [socketClients setObject:ctx forKey:@((long)readStreamRef)];
            });

            CFReadStreamScheduleWithRunLoop(readStreamRef, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
        }
        else
        {
            if (readStreamRef) {
                CFReadStreamClose(readStreamRef);
                CFRelease(readStreamRef);
            }
            if (writeStreamRef) {
                CFWriteStreamClose(writeStreamRef);
                CFRelease(writeStreamRef);
            }
            close(nativeSocketHandle);
        }

    }

}
