#import "TLinkTaskContext.h"
#import "TLinkautoJSRuntime.h"
#import "TLinkDiagnostic.h"
#import <os/lock.h>

#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <atomic>
#include <dlfcn.h>
#include <math.h>

#include "Screen.h"
#include "RuntimeUtils.h"

#import "jsruntime/TLinkJSRuntimeCore.h"
#import "jsruntime/TLinkInProcessNativeBridge.h"
#import "jsruntime/TLinkautoDeviceBridge.h"
#import "jsruntime/TLinkJSHelperClient.h"

typedef NS_ENUM(int, TLinkJSRuntimeTaskCode) {
    TASK_PERFORM_TOUCH = 10,
    TASK_PROCESS_BRING_FOREGROUND = 11,
    TASK_SHOW_ALERT_BOX = 12,
    TASK_RUN_SHELL = 13,
    TASK_TEMPLATE_MATCH = 21,
    TASK_SHOW_TOAST = 22,
    TASK_COLOR_PICKER = 23,
    TASK_TEXT_INPUT = 24,
    TASK_GET_DEVICE_INFO = 25,
    TASK_TOUCH_INDICATOR = 26,
    TASK_COLOR_SEARCHER = 28,
    TASK_SCREENSHOT = 29,
    TASK_HARDWARE_KEY = 30,
    TASK_APP_KILL = 31,
    TASK_APP_STATE = 32,
    TASK_APP_INFO = 33,
    TASK_FRONTMOST_APP_ID = 34,
    TASK_FRONTMOST_APP_ORIENTATION = 35,
    TASK_SET_AUTO_LAUNCH = 36,
    TASK_LIST_AUTO_LAUNCH = 37,
    TASK_SET_TIMER = 38,
    TASK_REMOVE_TIMER = 39,
    TASK_KEEP_AWAKE = 40,
    TASK_DIALOG = 42,
    TASK_CLEAR_DIALOG = 43,
    TASK_ROOT_DIR = 44,
    TASK_CURRENT_DIR = 45,
    TASK_BOT_PATH = 46,
    TASK_IMAGE_OBJECT = 48,
    TASK_FIND_IMAGE = 49,
    TASK_APP_PID = 50,
    TASK_FRONTMOST_PID = 51,
    TASK_APP_PATHS = 52,
    TASK_LIST_BUNDLES = 53,
    TASK_OPEN_URL = 54,
    TASK_WIFI = 55,
    TASK_BLUETOOTH = 56,
    TASK_AIRPLANE = 57,
    TASK_CELLULAR_DATA = 58,
    TASK_NATIVE_TAP = 62,
    TASK_NATIVE_SWIPE = 63,
    TASK_NATIVE_GESTURE = 64,
    TASK_NATIVE_BATCH = 65,
    TASK_FRAME_CAPTURE = 66,
    TASK_FRAME_RELEASE = 67,
    TASK_FIND_IMAGE_IN_FRAME = 68,
    TASK_COLOR_IN_FRAME = 69,
    TASK_FRAME_BATCH = 70,
    TASK_RUN_SHELL_V2 = 71,
    TASK_OCR_TESSERACT_REGION = 91,
};

typedef bool (*TLinkautoJSShouldTerminateCallback)(JSContextRef ctx, void *opaque);
typedef void (*TLinkautoJSSetExecutionTimeLimitFn)(JSContextGroupRef group, double limit, TLinkautoJSShouldTerminateCallback callback, void *opaque);
typedef void (*TLinkautoJSClearExecutionTimeLimitFn)(JSContextGroupRef group);

static const double kTLinkautoJSWatchdogInterval = 0.1;
static const NSUInteger kTLinkautoJSMaxResponseBytes = 1024 * 1024;
static const unsigned long long kTLinkautoJSMaxBundleFileBytes = 512 * 1024;
static const unsigned long long kTLinkautoJSMaxStorageFileBytes = 512 * 1024;
static const unsigned long long kTLinkautoJSMaxConsoleLogBytes = 512 * 1024;
static NSString * const kTLinkautoJSHelperExecutionGatePath = @"/var/mobile/Library/TLinkauto/enable_js_helper_execution";

@class TLinkautoJSRuntime;

struct TLinkautoJSCancelState {
    std::atomic<bool> aborted;
};

struct TLinkautoJSWatchdogProbeState {
    std::atomic<int> callbacks;
};

@interface TLinkautoJSRuntime () {
    TLinkautoJSCancelState *_cancelState;
    NSCondition *_sleepCondition;
    NSMutableSet<NSNumber *> *_ownedFrameIds;
    NSMutableSet<NSNumber *> *_ownedImageIds;

    TLinkautoJSSetExecutionTimeLimitFn _setExecutionTimeLimit;
    TLinkautoJSClearExecutionTimeLimitFn _clearExecutionTimeLimit;
    BOOL _watchdogAvailable;

    dispatch_queue_t _logQueue;
    os_unfair_lock _logStateLock;
    BOOL _acceptingLogs;

    os_unfair_lock _handlesLock;
    BOOL _acceptingHandles;

    BOOL _running;
    NSString *_runId;
    NSString *_bundlePath;
    NSDictionary *_manifest;
    NSString *_consoleLogPath;
    NSString *_consoleLatestLogPath;
    JSContext *_context;

    TLinkJSRuntimeCore *_core;
    TLinkInProcessNativeBridge *_bridge;
    TLinkTaskExecutionContext *_taskContext;
    BOOL _helperRunning;
    NSString *_helperSessionId;
    NSString *_helperRunId;
    NSString *_helperConsoleLogPath;
    NSString *_helperConsoleLatestLogPath;
}

- (void)beginOwnedHandleTracking;
- (void)releaseOwnedHandles;
- (void)recordLastScriptError:(NSString *)message;
- (void)showDebugToast:(NSString *)message type:(int)type;
- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message;
- (NSDictionary *)bundleTextForRelativePath:(NSString *)relativePath;
- (BOOL)runScriptInHelperAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest error:(NSError **)error;
- (void)trackFrameId:(int)frameId;
- (void)untrackFrameId:(int)frameId;
- (void)untrackAllFrameIds;
- (void)trackImageId:(int)imageId;
- (void)untrackImageId:(int)imageId;
@end

static bool TLinkautoJSShouldTerminate(JSContextRef ctx, void *opaque)
{
    (void)ctx;
    TLinkautoJSCancelState *state = (TLinkautoJSCancelState *)opaque;
    return state && state->aborted.load(std::memory_order_acquire);
}

static bool TLinkautoJSWatchdogProbeCallback(JSContextRef ctx, void *opaque)
{
    (void)ctx;
    TLinkautoJSWatchdogProbeState *state = (TLinkautoJSWatchdogProbeState *)opaque;
    if (state) {
        state->callbacks.fetch_add(1, std::memory_order_relaxed);
    }
    return false;
}

static BOOL TLinkautoJSRunWatchdogSelfTest(TLinkautoJSSetExecutionTimeLimitFn setLimit, TLinkautoJSClearExecutionTimeLimitFn clearLimit)
{
    if (!setLimit || !clearLimit) return NO;

    TLinkautoJSWatchdogProbeState state;
    state.callbacks.store(0, std::memory_order_relaxed);

    JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);
    if (!ctx) return NO;

    JSContextGroupRef group = JSContextGetGroup(ctx);
    setLimit(group, 0.001, TLinkautoJSWatchdogProbeCallback, &state);

    JSStringRef script = JSStringCreateWithUTF8CString("var end = Date.now() + 20; var x = 0; while (Date.now() < end) { x++; } x;");
    JSValueRef exception = NULL;
    JSEvaluateScript(ctx, script, NULL, NULL, 1, &exception);
    JSStringRelease(script);
    clearLimit(group);
    JSGlobalContextRelease(ctx);

    return exception == NULL && state.callbacks.load(std::memory_order_relaxed) > 0;
}

static BOOL TLinkautoJSWatchdogCapability(TLinkautoJSSetExecutionTimeLimitFn setLimit, TLinkautoJSClearExecutionTimeLimitFn clearLimit)
{
    static dispatch_once_t onceToken;
    static BOOL capable = NO;
    dispatch_once(&onceToken, ^{
        capable = TLinkautoJSRunWatchdogSelfTest(setLimit, clearLimit);
    });
    return capable;
}

static BOOL TLinkautoJSIsFiniteNumber(double value)
{
    return isfinite(value);
}

static NSString *TLinkautoJSSanitizePayload(NSString *payload)
{
    if (!payload) return @"";
    if ([payload length] > 8192) {
        return [payload substringToIndex:8192];
    }
    return payload;
}

static NSString *TLinkautoJSSanitizeProtocolText(NSString *text, NSUInteger maxLength)
{
    NSString *safe = [text isKindOfClass:[NSString class]] ? text : [text description];
    safe = safe ?: @"";
    safe = [safe stringByReplacingOccurrencesOfString:@";;" withString:@"; "];
    safe = [safe stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    safe = [safe stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if ([safe length] > maxLength) {
        safe = [safe substringToIndex:maxLength];
    }
    return safe;
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

static id TLinkautoJSJSONFromBase64(NSString *text)
{
    NSString *json = TLinkautoJSBase64Decode(text);
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSString *TLinkautoJSSafeStringPart(NSArray *parts, NSUInteger index)
{
    if (index >= [parts count]) return @"";
    id value = parts[index];
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : [value description];
}

static NSDictionary *TLinkautoJSResultByAdding(NSDictionary *result, NSDictionary *extra)
{
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:result ?: @{}];
    [out addEntriesFromDictionary:extra ?: @{}];
    return out;
}

static NSString *TLinkautoJSSanitizeFileComponent(NSString *value)
{
    if (!value || [value length] == 0) return @"script";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"].invertedSet;
    NSArray *parts = [value componentsSeparatedByCharactersInSet:allowed];
    NSString *joined = [parts componentsJoinedByString:@"_"];
    return [joined length] > 0 ? joined : @"script";
}

static BOOL TLinkautoJSStringContainsAny(NSString *value, NSArray<NSString *> *needles)
{
    if (![value isKindOfClass:[NSString class]]) return YES;
    for (NSString *needle in needles) {
        if ([value rangeOfString:needle].location != NSNotFound) return YES;
    }
    return NO;
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
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? (NSString *)value : defaultValue;
}

static BOOL TLinkautoJSValidToken(NSString *value)
{
    return [value isKindOfClass:[NSString class]] && !TLinkautoJSStringContainsAny(value, @[@";;", @"||", @"@@", @",", @"\r", @"\n"]);
}

static BOOL TLinkautoJSValidProtocolString(NSString *value)
{
    return [value isKindOfClass:[NSString class]] && [value length] > 0 && !TLinkautoJSStringContainsAny(value, @[@";;", @"\r", @"\n"]);
}

static NSDictionary *TLinkautoJSStateResult(NSDictionary *result, NSString *key)
{
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    BOOL enabled = [TLinkautoJSSafeStringPart(parts, 1) intValue] != 0;
    return TLinkautoJSResultByAdding(result, @{ (key ?: @"enabled"): @(enabled), @"value": @(enabled) });
}

static int TLinkautoJSHardwareKeyType(NSString *key)
{
    NSString *k = [[key ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([k isEqualToString:@"home"]) return 1;
    if ([k isEqualToString:@"volume-up"] || [k isEqualToString:@"vol-up"]) return 2;
    if ([k isEqualToString:@"volume-down"] || [k isEqualToString:@"vol-down"]) return 3;
    if ([k isEqualToString:@"lock"] || [k isEqualToString:@"power"]) return 4;
    return 0;
}

static int TLinkautoJSHardwareKeyAction(NSString *action)
{
    NSString *a = [[action ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([a isEqualToString:@"down"]) return 1;
    if ([a isEqualToString:@"up"]) return 0;
    return -1;
}

static int TLinkautoJSTouchIndicatorAction(NSString *action)
{
    NSString *a = [[action ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([a isEqualToString:@"hide"] || [a isEqualToString:@"off"]) return 0;
    if ([a isEqualToString:@"show"] || [a isEqualToString:@"on"]) return 1;
    if ([a isEqualToString:@"reload"]) return 2;
    return -1;
}

static BOOL TLinkautoJSEncodePoint(id point, double *outX, double *outY)
{
    if ([point isKindOfClass:[NSArray class]] && [point count] >= 2) {
        NSArray *arrayPoint = (NSArray *)point;
        double x = [arrayPoint[0] doubleValue];
        double y = [arrayPoint[1] doubleValue];
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) return NO;
        if (outX) *outX = x;
        if (outY) *outY = y;
        return YES;
    }
    if ([point isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictPoint = (NSDictionary *)point;
        double x = [dictPoint[@"x"] doubleValue];
        double y = [dictPoint[@"y"] doubleValue];
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) return NO;
        if (outX) *outX = x;
        if (outY) *outY = y;
        return YES;
    }
    return NO;
}

static NSString *TLinkautoJSEncodeGesturePoints(NSArray *points)
{
    if (![points isKindOfClass:[NSArray class]] || [points count] < 2 || [points count] > 512) return nil;
    NSMutableArray<NSString *> *encoded = [NSMutableArray arrayWithCapacity:[points count]];
    for (id point in points) {
        double x = 0;
        double y = 0;
        if (!TLinkautoJSEncodePoint(point, &x, &y)) return nil;
        [encoded addObject:[NSString stringWithFormat:@"%.2f,%.2f", x, y]];
    }
    return [encoded componentsJoinedByString:@"|"];
}

static BOOL TLinkautoJSEncodePointColor(id point, int *outX, int *outY, int *outR, int *outG, int *outB)
{
    int x = 0, y = 0, r = 0, g = 0, b = 0;
    if ([point isKindOfClass:[NSArray class]] && [point count] >= 5) {
        NSArray *arrayPoint = (NSArray *)point;
        x = [arrayPoint[0] intValue];
        y = [arrayPoint[1] intValue];
        r = [arrayPoint[2] intValue];
        g = [arrayPoint[3] intValue];
        b = [arrayPoint[4] intValue];
    } else if ([point isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictPoint = (NSDictionary *)point;
        x = [dictPoint[@"x"] intValue];
        y = [dictPoint[@"y"] intValue];
        r = dictPoint[@"red"] ? [dictPoint[@"red"] intValue] : [dictPoint[@"r"] intValue];
        g = dictPoint[@"green"] ? [dictPoint[@"green"] intValue] : [dictPoint[@"g"] intValue];
        b = dictPoint[@"blue"] ? [dictPoint[@"blue"] intValue] : [dictPoint[@"b"] intValue];
    } else {
        return NO;
    }
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) return NO;
    if (outX) *outX = x;
    if (outY) *outY = y;
    if (outR) *outR = r;
    if (outG) *outG = g;
    if (outB) *outB = b;
    return YES;
}

static NSString *TLinkautoJSEncodePointColorTable(NSArray *points)
{
    if (![points isKindOfClass:[NSArray class]] || [points count] == 0 || [points count] > 512) return nil;
    NSMutableArray<NSString *> *encoded = [NSMutableArray arrayWithCapacity:[points count]];
    for (id point in points) {
        int x = 0, y = 0, r = 0, g = 0, b = 0;
        if (!TLinkautoJSEncodePointColor(point, &x, &y, &r, &g, &b)) return nil;
        [encoded addObject:[NSString stringWithFormat:@"%d,,%d,,%d,,%d,,%d", x, y, r, g, b]];
    }
    return [encoded componentsJoinedByString:@"|"];
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

@implementation TLinkautoJSRuntime

- (instancetype)init
{
    self = [super init];
    if (self) {
        _cancelState = new TLinkautoJSCancelState();
        _cancelState->aborted.store(false, std::memory_order_release);
        _sleepCondition = [[NSCondition alloc] init];
        _ownedFrameIds = [NSMutableSet set];
        _ownedImageIds = [NSMutableSet set];
        _setExecutionTimeLimit = (TLinkautoJSSetExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
        _clearExecutionTimeLimit = (TLinkautoJSClearExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
        _watchdogAvailable = TLinkautoJSWatchdogCapability(_setExecutionTimeLimit, _clearExecutionTimeLimit);
        
        _logQueue = dispatch_queue_create("com.tlinkauto.js.log", DISPATCH_QUEUE_SERIAL);
        _logStateLock = OS_UNFAIR_LOCK_INIT;
        _acceptingLogs = NO;

        _handlesLock = OS_UNFAIR_LOCK_INIT;
        _acceptingHandles = NO;

        _core = [[TLinkJSRuntimeCore alloc] init];
        _bridge = [[TLinkInProcessNativeBridge alloc] init];
        _bridge.host = self;
        _core.nativeBridge = _bridge;
    }
    return self;
}

- (void)dealloc
{
    delete _cancelState;
}

- (BOOL)running
{
    return _core.running || _helperRunning;
}

- (NSString *)runId
{
    return _helperRunning ? (_helperRunId ?: @"") : (_core.runId ?: @"");
}

- (BOOL)watchdogAvailable
{
    return _core.watchdogAvailable;
}

- (NSString *)currentBundlePath
{
    return _core.currentBundlePath ?: @"";
}

- (NSString *)currentConsoleLogPath
{
    return _helperRunning ? (_helperConsoleLogPath ?: @"") : (_core.currentConsoleLogPath ?: @"");
}

- (NSString *)currentConsoleLatestLogPath
{
    return _helperRunning ? (_helperConsoleLatestLogPath ?: @"") : (_core.currentConsoleLatestLogPath ?: @"");
}

- (NSDictionary *)currentManifest
{
    return _core.currentManifest ?: @{};
}

- (void)prepareConsoleLogFiles
{
    if (![_bundlePath isKindOfClass:[NSString class]] || [_bundlePath length] == 0 || ![_runId isKindOfClass:[NSString class]]) return;
    NSString *dir = [_bundlePath stringByAppendingPathComponent:@"_logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    _consoleLogPath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.log", TLinkautoJSSanitizeFileComponent(_runId)]];
    _consoleLatestLogPath = [dir stringByAppendingPathComponent:@"latest.log"];
    NSString *header = [NSString stringWithFormat:@"[%@] run %@ started\n", [[NSDate date] description], _runId ?: @""];
    [header writeToFile:_consoleLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [header writeToFile:_consoleLatestLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)appendLine:(NSString *)line toConsolePath:(NSString *)path
{
    if (![path isKindOfClass:[NSString class]] || [path length] == 0) return;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkautoJSMaxConsoleLogBytes) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message
{
    os_unfair_lock_lock(&_logStateLock);
    if (!_acceptingLogs) {
        os_unfair_lock_unlock(&_logStateLock);
        return;
    }
    os_unfair_lock_unlock(&_logStateLock);

    NSString *safeLevel = TLinkautoJSSanitizeFileComponent(level ?: @"log");
    NSString *safeMessage = [message isKindOfClass:[NSString class]] ? message : [message description];
    safeMessage = safeMessage ?: @"";
    safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\n", [[NSDate date] description], _runId ?: @"", safeLevel, safeMessage];
    
    NSString *path1 = _consoleLogPath;
    NSString *path2 = _consoleLatestLogPath;
    
    dispatch_async(_logQueue, ^{
        [self appendLine:line toConsolePath:path1];
        [self appendLine:line toConsolePath:path2];
    });
}

- (void)beginOwnedHandleTracking
{
    os_unfair_lock_lock(&_handlesLock);
    _acceptingHandles = YES;
    [_ownedFrameIds removeAllObjects];
    [_ownedImageIds removeAllObjects];
    os_unfair_lock_unlock(&_handlesLock);
}

- (void)trackFrameId:(int)frameId
{
    if (frameId > 0) {
        os_unfair_lock_lock(&_handlesLock);
        if (_acceptingHandles) [_ownedFrameIds addObject:@(frameId)];
        os_unfair_lock_unlock(&_handlesLock);
    }
}

- (void)untrackFrameId:(int)frameId
{
    if (frameId > 0) {
        os_unfair_lock_lock(&_handlesLock);
        [_ownedFrameIds removeObject:@(frameId)];
        os_unfair_lock_unlock(&_handlesLock);
    }
}

- (void)untrackAllFrameIds
{
    os_unfair_lock_lock(&_handlesLock);
    [_ownedFrameIds removeAllObjects];
    os_unfair_lock_unlock(&_handlesLock);
}

- (void)trackImageId:(int)imageId
{
    if (imageId > 0) {
        os_unfair_lock_lock(&_handlesLock);
        if (_acceptingHandles) [_ownedImageIds addObject:@(imageId)];
        os_unfair_lock_unlock(&_handlesLock);
    }
}

- (void)untrackImageId:(int)imageId
{
    if (imageId > 0) {
        os_unfair_lock_lock(&_handlesLock);
        [_ownedImageIds removeObject:@(imageId)];
        os_unfair_lock_unlock(&_handlesLock);
    }
}

- (void)releaseOwnedHandles
{
    os_unfair_lock_lock(&_handlesLock);
    _acceptingHandles = NO;
    NSArray<NSNumber *> *frameIds = [_ownedFrameIds allObjects];
    NSArray<NSNumber *> *imageIds = [_ownedImageIds allObjects];
    [_ownedFrameIds removeAllObjects];
    [_ownedImageIds removeAllObjects];
    os_unfair_lock_unlock(&_handlesLock);

    bool wasAborted = _cancelState->aborted.load(std::memory_order_acquire);
    _cancelState->aborted.store(false, std::memory_order_release);
    for (NSNumber *frameId in frameIds) {
        [self executeNativeRequest:TLinkJSNativeMethodRawTask arguments:@[[NSString stringWithFormat:@"67%d", [frameId intValue]]]];
    }
    for (NSNumber *imageId in imageIds) {
        [self executeNativeRequest:TLinkJSNativeMethodRawTask arguments:@[[NSString stringWithFormat:@"483;;%d", [imageId intValue]]]];
    }
    _cancelState->aborted.store(wasAborted, std::memory_order_release);
}

- (void)requestStop
{
    _cancelState->aborted.store(true, std::memory_order_release);
    [_sleepCondition lock];
    [_sleepCondition broadcast];
    [_sleepCondition unlock];
    [_core requestStop];
    NSString *sessionId = [_helperSessionId copy];
    if (sessionId.length > 0) {
        TLinkJSHelperClient *helper = [[TLinkJSHelperClient alloc] init];
        [helper stopSessionId:sessionId timeoutMs:250];
    }
}

- (BOOL)isAborted
{
    return _cancelState->aborted.load(std::memory_order_acquire) || [_core isAborted];
}

- (void)setAbortExceptionIfNeeded
{
    if (![self isAborted] || !_context) return;
    _context.exception = [JSValue valueWithNewErrorFromMessage:@"AbortError: script execution was stopped" inContext:_context];
}

- (BOOL)interruptibleSleepMs:(double)ms
{
    if (!TLinkautoJSIsFiniteNumber(ms) || ms < 0) {
        [self throwError:@"sleep(ms) requires a finite non-negative number"];
        return false;
    }
    if (ms > 24.0 * 60.0 * 60.0 * 1000.0) {
        ms = 24.0 * 60.0 * 60.0 * 1000.0;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(ms / 1000.0)];
    [_sleepCondition lock];
    while (![self isAborted]) {
        if (![_sleepCondition waitUntilDate:deadline]) {
            break;
        }
    }
    [_sleepCondition unlock];
    [self setAbortExceptionIfNeeded];
    return ![self isAborted];
}

- (void)throwError:(NSString *)message
{
    [_core throwError:(message ?: @"JavaScript runtime error")];
}

- (void)recordLastScriptError:(NSString *)message
{
    setLastScriptError(message ?: @"JavaScript exception");
}

- (void)showDebugToast:(NSString *)message type:(int)type
{
    NSString *safeMessage = TLinkautoJSSanitizeProtocolText(message ?: @"JavaScript error", 180);
    NSString *payload = [NSString stringWithFormat:@"22%d;;%@;;3;;0;;14", type, safeMessage];
    [self executeNativeRequest:TLinkJSNativeMethodRawTask arguments:@[payload ?: @""]];
}

- (NSDictionary *)bundleTextForRelativePath:(NSString *)relativePath
{
    NSString *bundlePath = [_bundlePath stringByStandardizingPath];
    if (![bundlePath isKindOfClass:[NSString class]] || [bundlePath length] == 0) {
        return @{ @"ok": @NO, @"error": @"bundle path is unavailable" };
    }
    if (![relativePath isKindOfClass:[NSString class]] || [relativePath length] == 0) {
        return @{ @"ok": @NO, @"error": @"module path is required" };
    }
    if ([relativePath hasPrefix:@"/"] || [relativePath rangeOfString:@"\0"].location != NSNotFound) {
        return @{ @"ok": @NO, @"error": @"module path must be bundle-relative" };
    }

    NSString *candidate = [[bundlePath stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    NSString *prefix = [bundlePath hasSuffix:@"/"] ? bundlePath : [bundlePath stringByAppendingString:@"/"];
    if (![candidate isEqualToString:bundlePath] && ![candidate hasPrefix:prefix]) {
        return @{ @"ok": @NO, @"error": @"module path escapes bundle" };
    }

    NSString *extension = [[candidate pathExtension] lowercaseString];
    if (!([extension isEqualToString:@"js"] || [extension isEqualToString:@"json"])) {
        return @{ @"ok": @NO, @"error": @"module extension must be .js or .json" };
    }

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:candidate error:nil];
    if (!attrs) {
        return @{ @"ok": @NO, @"error": @"module file not found", @"path": candidate };
    }
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkautoJSMaxBundleFileBytes) {
        return @{ @"ok": @NO, @"error": @"module file is too large", @"path": candidate };
    }

    NSError *readError = nil;
    NSString *source = [NSString stringWithContentsOfFile:candidate encoding:NSUTF8StringEncoding error:&readError];
    if (!source) {
        return @{ @"ok": @NO, @"error": readError.localizedDescription ?: @"failed to read module", @"path": candidate };
    }
    NSString *canonical = [candidate substringFromIndex:[prefix length]];
    return @{ @"ok": @YES, @"path": candidate, @"id": canonical ?: relativePath, @"source": source };
}

- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)relativePath createParent:(BOOL)createParent
{
    return [_core bundleStoragePathForRelativePath:relativePath createParent:createParent];
}

- (void)installWatchdogForContext:(JSContext *)context
{
    if (!_watchdogAvailable || !context) return;
    JSContextRef ctx = [context JSGlobalContextRef];
    JSContextGroupRef group = JSContextGetGroup(ctx);
    _setExecutionTimeLimit(group, kTLinkautoJSWatchdogInterval, TLinkautoJSShouldTerminate, _cancelState);
}

- (void)clearWatchdogForContext:(JSContext *)context
{
    if (!_watchdogAvailable || !context) return;
    JSContextRef ctx = [context JSGlobalContextRef];
    JSContextGroupRef group = JSContextGetGroup(ctx);
    _clearExecutionTimeLimit(group);
}

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context error:(NSError **)error
{
    _cancelState->aborted.store(false, std::memory_order_release);
    id helperFlag = manifest[@"helperRuntimeEnabled"] ?: manifest[@"helper_runtime_enabled"];
    NSString *runtimeLocation = [manifest[@"runtimeLocation"] isKindOfClass:[NSString class]] ? [manifest[@"runtimeLocation"] lowercaseString] : @"";
    BOOL requestedHelper = ([helperFlag respondsToSelector:@selector(boolValue)] && [helperFlag boolValue]) || [runtimeLocation isEqualToString:@"helper"];
    BOOL helperExecutionAllowed = [[NSFileManager defaultManager] fileExistsAtPath:kTLinkautoJSHelperExecutionGatePath];
    BOOL useHelper = requestedHelper && helperExecutionAllowed;
    if (useHelper) {
        return [self runScriptInHelperAtPath:scriptPath bundlePath:bundlePath manifest:manifest error:error];
    }
    [self beginOwnedHandleTracking];
    _taskContext = context;
    @try {
        return [_core runScriptAtPath:scriptPath bundlePath:bundlePath manifest:manifest context:context facade:self error:error];
    } @finally {
        _taskContext = nil;
    }
}

- (BOOL)runScriptInHelperAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest error:(NSError **)error
{
    if (_helperRunning) {
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;JavaScript helper runtime is busy.\r\n"}];
        return NO;
    }
    TLinkJSHelperClient *helper = [[TLinkJSHelperClient alloc] init];
    NSDictionary *start = [helper startScriptAtPath:scriptPath bundlePath:bundlePath manifest:manifest ?: @{} timeoutMs:1000];
    if (![start[@"ok"] boolValue]) {
        NSString *message = [start[@"error"] isKindOfClass:[NSDictionary class]] ? start[@"error"][@"message"] : [start[@"error"] description];
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;JavaScript helper start failed: %@\r\n", message ?: @"unknown"]}];
        return NO;
    }
    NSDictionary *response = start[@"response"];
    NSDictionary *payload = [response[@"payload"] isKindOfClass:[NSDictionary class]] ? response[@"payload"] : @{};
    _helperRunning = YES;
    _helperSessionId = [response[@"sessionId"] copy];
    _helperRunId = [payload[@"runId"] copy];
    _helperConsoleLogPath = [payload[@"consoleLogPath"] copy];
    _helperConsoleLatestLogPath = [payload[@"consoleLatestLogPath"] copy];
    id timeoutValue = manifest[@"helperTimeoutMs"] ?: manifest[@"helper_timeout_ms"];
    double timeoutMs = [timeoutValue respondsToSelector:@selector(doubleValue)] ? [timeoutValue doubleValue] : 10000.0;
    if (!TLinkautoJSIsFiniteNumber(timeoutMs) || timeoutMs <= 0) timeoutMs = 10000.0;
    if (timeoutMs > 5.0 * 60.0 * 1000.0) timeoutMs = 5.0 * 60.0 * 1000.0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(timeoutMs / 1000.0)];
    BOOL ok = NO;
    NSString *failure = nil;
    @try {
        while (!_cancelState->aborted.load(std::memory_order_acquire)) {
            if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
                [helper stopSessionId:_helperSessionId timeoutMs:250];
                failure = [NSString stringWithFormat:@"JavaScript helper timed out after %.0f ms", timeoutMs];
                break;
            }
            NSDictionary *status = [helper statusForSessionId:_helperSessionId timeoutMs:500];
            if (![status[@"ok"] boolValue]) {
                failure = [status[@"error"] description] ?: @"status_failed";
                break;
            }
            NSDictionary *statusResponse = status[@"response"];
            NSDictionary *statusPayload = [statusResponse[@"payload"] isKindOfClass:[NSDictionary class]] ? statusResponse[@"payload"] : @{};
            NSString *state = [statusPayload[@"state"] isKindOfClass:[NSString class]] ? statusPayload[@"state"] : @"unknown";
            NSDictionary *nativeRPC = [statusPayload[@"nativeRPCRequest"] isKindOfClass:[NSDictionary class]] ? statusPayload[@"nativeRPCRequest"] : nil;
            if (nativeRPC) {
                NSString *nativeRequestId = [nativeRPC[@"requestId"] isKindOfClass:[NSString class]] ? nativeRPC[@"requestId"] : @"";
                NSString *method = [nativeRPC[@"method"] isKindOfClass:[NSString class]] ? nativeRPC[@"method"] : @"";
                NSArray *arguments = [nativeRPC[@"arguments"] isKindOfClass:[NSArray class]] ? nativeRPC[@"arguments"] : @[];
                NSDictionary *result = [self executeNativeRequest:method arguments:arguments];
                [helper sendNativeRPCResponse:result requestId:nativeRequestId sessionId:_helperSessionId timeoutMs:500];
            }
            id activeSession = statusPayload[@"activeSessionId"];
            if ([state isEqualToString:@"idle"] || (activeSession && activeSession != [NSNull null] && ![activeSession isEqual:_helperSessionId])) {
                failure = @"JavaScript helper session disappeared";
                break;
            }
            if ([statusPayload[@"runId"] isKindOfClass:[NSString class]]) _helperRunId = [statusPayload[@"runId"] copy];
            if ([statusPayload[@"consoleLogPath"] isKindOfClass:[NSString class]]) _helperConsoleLogPath = [statusPayload[@"consoleLogPath"] copy];
            if ([statusPayload[@"consoleLatestLogPath"] isKindOfClass:[NSString class]]) _helperConsoleLatestLogPath = [statusPayload[@"consoleLatestLogPath"] copy];
            if ([state isEqualToString:@"completed"]) {
                ok = YES;
                break;
            }
            if ([state isEqualToString:@"failed"] || [state isEqualToString:@"cancelled"] || [state isEqualToString:@"crashed"]) {
                failure = [statusPayload[@"lastError"] isKindOfClass:[NSString class]] && [statusPayload[@"lastError"] length] ? statusPayload[@"lastError"] : state;
                [helper stopSessionId:_helperSessionId timeoutMs:250];
                break;
            }
            [NSThread sleepForTimeInterval:0.2];
        }
        if (_cancelState->aborted.load(std::memory_order_acquire)) {
            [helper stopSessionId:_helperSessionId timeoutMs:250];
            failure = @"JavaScript helper execution was stopped";
        }
    } @finally {
        _helperRunning = NO;
        _helperSessionId = nil;
    }
    if (!ok && error) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n", failure ?: @"JavaScript helper execution failed"]}];
    }
    return ok;
}

- (NSDictionary *)executeNativeRequest:(NSString *)method arguments:(NSArray *)arguments {
    TLinkJSNativeRequest *request = [[TLinkJSNativeRequest alloc] initWithMethod:method arguments:arguments];
    TLinkTaskExecutionContext *ctx = _taskContext ?: [[TLinkTaskExecutionContext alloc] init];
    TLinkJSNativeResponse *response = [_bridge executeRequest:request context:ctx error:nil];
    if (response.ok) {
        return response.value ?: @{@"ok": @YES};
    } else {
        [self throwError:response.errorMessage ?: @"Native request failed"];
        return @{@"ok": @NO, @"error": response.errorMessage ?: @"Unknown error"};
    }
}

@end

@implementation TLinkautoDeviceBridge

- (NSDictionary *)runTask:(int)task payload:(NSString *)payload
{
    if (!self.runtime) return @{ @"ok": @NO, @"raw": @"1;;runtime_missing\r\n", @"parts": @[@"1", @"runtime_missing"] };
    if (task < 0 || task > 99) {
        [self.runtime throwError:@"runTask task code out of range"];
        return @{ @"ok": @NO, @"raw": @"1;;task_out_of_range\r\n", @"parts": @[@"1", @"task_out_of_range"] };
    }
    NSString *wire = [NSString stringWithFormat:@"%02d%@", task, TLinkautoJSSanitizePayload(payload)];
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodRawTask arguments:@[wire ?: @""]];
}

- (NSDictionary *)toast:(NSString *)message options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodToast arguments:@[message ?: @"", options ?: @{}]];
}

- (NSDictionary *)tap:(double)x y:(double)y
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodTap arguments:@[@(x), @(y)]];
}

- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodSwipe arguments:@[@(x1), @(y1), @(x2), @(y2), @(duration)]];
}

- (NSDictionary *)longPress:(double)x y:(double)y duration:(double)duration
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodLongPress arguments:@[@(x), @(y), @(duration)]];
}

- (NSDictionary *)gesture:(NSArray *)points options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodGesture arguments:@[points ?: @[], options ?: @{}]];
}

- (NSDictionary *)pickColor:(double)x y:(double)y
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodPickColor arguments:@[@(x), @(y)]];
}

- (NSString *)defaultScreenshotPath
{
    NSString *dir = [self.runtime currentBundlePath];
    if (!dir || [dir length] == 0) {
        dir = @"/tmp";
    }
    NSString *name = [NSString stringWithFormat:@"screenshot_%@.png", TLinkautoJSSanitizeFileComponent([self.runtime runId])];
    return [dir stringByAppendingPathComponent:name];
}

- (NSDictionary *)screenshot
{
    return [self screenshotTo:[self defaultScreenshotPath]];
}

- (NSDictionary *)screenshotTo:(NSString *)path
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodScreenshotTo arguments:@[path ?: @""]];
}

- (NSDictionary *)screenshotRegion:(NSString *)path options:(NSDictionary *)options
{
    NSString *targetPath = ([path isKindOfClass:[NSString class]] && [path length] > 0) ? path : [self defaultScreenshotPath];
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodScreenshotRegion arguments:@[targetPath ?: @"", options ?: @{}]];
}

- (NSDictionary *)frontMostAppId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFrontMostAppId arguments:@[]];
}

- (NSDictionary *)orientation
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodOrientation arguments:@[]];
}

- (NSDictionary *)batch:(NSArray *)commands
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodBatch arguments:@[commands ?: @[]]];
}

- (NSDictionary *)captureFrame:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodCaptureFrame arguments:@[options ?: @{}]];
}

- (NSDictionary *)releaseFrame:(int)frameId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodReleaseFrame arguments:@[@(frameId)]];
}

- (NSDictionary *)releaseAllFrames
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodReleaseAllFrames arguments:@[]];
}

- (NSDictionary *)openImage:(NSString *)path
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodOpenImage arguments:@[path ?: @""]];
}

- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodCaptureImage arguments:@[@(x), @(y), @(width), @(height)]];
}

- (NSDictionary *)releaseImage:(int)imageId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodReleaseImage arguments:@[@(imageId)]];
}

- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFramePickColor arguments:@[@(frameId), @(x), @(y), options ?: @{}]];
}

- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFramePickColors arguments:@[@(frameId), points ?: @[], options ?: @{}]];
}

- (NSDictionary *)frameFindColor:(int)frameId options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFrameFindColor arguments:@[@(frameId), options ?: @{}]];
}

- (NSDictionary *)frameIsColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFrameIsColors arguments:@[@(frameId), points ?: @[], options ?: @{}]];
}

- (NSDictionary *)frameFindMultiColor:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFrameFindMultiColor arguments:@[@(frameId), points ?: @[], options ?: @{}]];
}

- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFindImageInFrame arguments:@[@(frameId), @(imageId), options ?: @{}]];
}

- (NSDictionary *)ocrLanguages
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodOcrLanguages arguments:@[]];
}

- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodOcrFrame arguments:@[@(frameId), options ?: @{}]];
}

- (NSDictionary *)ocr:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodOcr arguments:@[options ?: @{}]];
}

- (NSDictionary *)openApp:(NSString *)bundleId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodOpenApp arguments:@[bundleId ?: @""]];
}

- (NSDictionary *)killApp:(NSString *)bundleId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodKillApp arguments:@[bundleId ?: @""]];
}

- (NSDictionary *)appState:(NSString *)bundleId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodAppState arguments:@[bundleId ?: @""]];
}

- (NSDictionary *)appInfo:(NSString *)bundleId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodAppInfo arguments:@[bundleId ?: @""]];
}

- (NSDictionary *)appPid:(NSString *)bundleId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodAppPid arguments:@[bundleId ?: @""]];
}

- (NSDictionary *)frontMostPid
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFrontMostPid arguments:@[]];
}

- (NSDictionary *)appPaths:(NSString *)bundleId
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodAppPaths arguments:@[bundleId ?: @""]];
}

- (NSDictionary *)listBundles:(BOOL)withInfo
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodListBundles arguments:@[@(withInfo)]];
}

- (NSDictionary *)openUrl:(NSString *)url
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodOpenUrl arguments:@[url ?: @""]];
}

- (NSDictionary *)connectivityTask:(int)task enabledKey:(NSString *)enabledKey value:(NSNumber *)value
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodConnectivity arguments:@[@(task), enabledKey ?: @"enabled", value ?: [NSNull null]]];
}

- (NSDictionary *)wifi
{
    return [self connectivityTask:TASK_WIFI enabledKey:@"enabled" value:nil];
}

- (NSDictionary *)setWifi:(BOOL)enabled
{
    return [self connectivityTask:TASK_WIFI enabledKey:@"enabled" value:@(enabled)];
}

- (NSDictionary *)bluetooth
{
    return [self connectivityTask:TASK_BLUETOOTH enabledKey:@"enabled" value:nil];
}

- (NSDictionary *)setBluetooth:(BOOL)enabled
{
    return [self connectivityTask:TASK_BLUETOOTH enabledKey:@"enabled" value:@(enabled)];
}

- (NSDictionary *)airplaneMode
{
    return [self connectivityTask:TASK_AIRPLANE enabledKey:@"enabled" value:nil];
}

- (NSDictionary *)setAirplaneMode:(BOOL)enabled
{
    return [self connectivityTask:TASK_AIRPLANE enabledKey:@"enabled" value:@(enabled)];
}

- (NSDictionary *)cellularData
{
    return [self connectivityTask:TASK_CELLULAR_DATA enabledKey:@"enabled" value:nil];
}

- (NSDictionary *)setCellularData:(BOOL)enabled
{
    return [self connectivityTask:TASK_CELLULAR_DATA enabledKey:@"enabled" value:@(enabled)];
}

- (NSDictionary *)alert:(NSString *)title message:(NSString *)message duration:(int)duration
{
    NSString *safeTitle = TLinkautoJSSanitizeProtocolText(title ?: @"TLinkauto", 80);
    NSString *safeMessage = TLinkautoJSSanitizeProtocolText(message ?: @"", 300);
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodAlert arguments:@[safeTitle ?: @"TLinkauto", safeMessage ?: @"", @(duration)]];
}

- (NSDictionary *)dialog:(NSDictionary *)options
{
    NSString *title = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"title", @"TLinkauto"), 80);
    NSString *message = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"message", @""), 300);
    NSString *ok = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"ok", @"OK"), 40);
    NSString *cancel = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"cancel", @"Cancel"), 40);
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodDialog arguments:@[title ?: @"TLinkauto", message ?: @"", ok ?: @"OK", cancel ?: @"Cancel"]];
}

- (NSDictionary *)clearDialogValues
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodClearDialogValues arguments:@[]];
}

- (NSDictionary *)keyboardTask:(int)kind content:(NSString *)content
{
    NSString *safeContent = content ? TLinkautoJSSanitizeProtocolText(content, 2048) : nil;
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodKeyboard arguments:@[@(kind), safeContent ?: [NSNull null]]];
}

- (NSDictionary *)showKeyboard
{
    return [self keyboardTask:2 content:@"2"];
}

- (NSDictionary *)hideKeyboard
{
    return [self keyboardTask:2 content:@"1"];
}

- (NSDictionary *)pasteFromClipboard
{
    return [self keyboardTask:5 content:nil];
}

- (NSDictionary *)getClipboardText
{
    NSDictionary *result = [self keyboardTask:6 content:nil];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"text": TLinkautoJSSafeStringPart(parts, 1) });
}

- (NSDictionary *)setClipboardText:(NSString *)text
{
    return [self keyboardTask:7 content:(text ?: @"")];
}

- (NSDictionary *)insertText:(NSString *)text
{
    return [self keyboardTask:1 content:(text ?: @"")];
}

- (NSDictionary *)deleteCharacters:(int)count
{
    if (count <= 0) count = 1;
    if (count > 1024) count = 1024;
    return [self keyboardTask:4 content:[NSString stringWithFormat:@"%d", count]];
}

- (NSDictionary *)moveCursor:(int)offset
{
    if (offset > 1024) offset = 1024;
    if (offset < -1024) offset = -1024;
    return [self keyboardTask:3 content:[NSString stringWithFormat:@"%d", offset]];
}

- (NSDictionary *)hardwareKey:(NSString *)key action:(NSString *)action
{
    int keyType = TLinkautoJSHardwareKeyType(key);
    int keyAction = TLinkautoJSHardwareKeyAction(action);
    if (keyType <= 0 || keyAction < 0) {
        [self.runtime throwError:@"hardwareKey(key, action) supports key home/volume-up/volume-down/lock and action down/up"];
        return @{ @"ok": @NO };
    }
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodHardwareKey arguments:@[@(keyAction), @(keyType)]];
}

- (NSDictionary *)pressHardwareKey:(NSString *)key
{
    int keyType = TLinkautoJSHardwareKeyType(key);
    if (keyType <= 0) {
        [self.runtime throwError:@"pressHardwareKey(key) supports key home/volume-up/volume-down/lock"];
        return @{ @"ok": @NO };
    }
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodPressHardwareKey arguments:@[@(keyType)]];
}

- (NSDictionary *)keepAwake:(BOOL)enabled
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodKeepAwake arguments:@[@(enabled)]];
}

- (NSDictionary *)touchIndicator:(NSString *)action
{
    int value = TLinkautoJSTouchIndicatorAction(action);
    if (value < 0) {
        [self.runtime throwError:@"touchIndicator(action) supports show/hide/reload"];
        return @{ @"ok": @NO };
    }
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodTouchIndicator arguments:@[@(value)]];
}

- (NSDictionary *)pathTask:(int)task key:(NSString *)key
{
    if (task == TASK_ROOT_DIR) return [self.runtime executeNativeRequest:TLinkJSNativeMethodRootDir arguments:@[]];
    if (task == TASK_CURRENT_DIR) return [self.runtime executeNativeRequest:TLinkJSNativeMethodCurrentDir arguments:@[]];
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodBotPath arguments:@[]];
}

- (NSDictionary *)rootDir
{
    return [self pathTask:TASK_ROOT_DIR key:@"rootDir"];
}

- (NSDictionary *)currentDir
{
    return [self pathTask:TASK_CURRENT_DIR key:@"currentDir"];
}

- (NSDictionary *)botPath
{
    return [self pathTask:TASK_BOT_PATH key:@"botPath"];
}

- (NSDictionary *)runShell:(NSString *)command timeoutSeconds:(double)timeoutSeconds
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodRunShell arguments:@[command ?: @"", @(timeoutSeconds)]];
}

- (NSDictionary *)info
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodInfo arguments:@[]];
}

- (NSDictionary *)batteryInfo
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodBatteryInfo arguments:@[]];
}

- (NSDictionary *)saveScreenshotToAlbum:(NSString *)path
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodSaveScreenshotToAlbum arguments:@[path ?: @""]];
}

- (NSDictionary *)clearScreenshotAlbum
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodClearScreenshotAlbum arguments:@[]];
}

- (NSDictionary *)matchTemplate:(NSString *)path options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodMatchTemplate arguments:@[path ?: @"", options ?: @{}]];
}

- (NSDictionary *)findColor:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFindColor arguments:@[options ?: @{}]];
}

- (NSDictionary *)isColors:(NSArray *)points options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodIsColors arguments:@[points ?: @[], options ?: @{}]];
}

- (NSDictionary *)findMultiColor:(NSArray *)points options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFindMultiColor arguments:@[points ?: @[], options ?: @{}]];
}

- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodSetAutoLaunch arguments:@[name ?: @"", script ?: @"", @(enabled)]];
}

- (NSDictionary *)listAutoLaunch
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodListAutoLaunch arguments:@[]];
}

- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodSetTimer arguments:@[name ?: @"", @(interval), @(repeat), script ?: @""]];
}

- (NSDictionary *)removeTimer:(NSString *)name
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodRemoveTimer arguments:@[name ?: @""]];
}

- (NSDictionary *)readText:(NSString *)path
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodReadText arguments:@[path ?: @""]];
}

- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodWriteText arguments:@[path ?: @"", text ?: @""]];
}

- (NSDictionary *)readJSON:(NSString *)path
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodReadJSON arguments:@[path ?: @""]];
}

- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value
{
    id object = [value isKindOfClass:[JSValue class]] ? [value toObject] : value;
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodWriteJSON arguments:@[path ?: @"", object ?: [NSNull null]]];
}

- (NSDictionary *)fileExists:(NSString *)path
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodFileExists arguments:@[path ?: @""]];
}

- (NSDictionary *)deleteFile:(NSString *)path
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodDeleteFile arguments:@[path ?: @""]];
}

- (NSDictionary *)getScreenSize
{
    return [self.runtime executeNativeRequest:TLinkJSNativeMethodGetScreenSize arguments:@[]];
}

- (NSDictionary *)runtimeInfo
{
    BOOL watchdog = [self.runtime watchdogAvailable];
    NSDictionary *manifest = [self.runtime currentManifest];
    NSMutableDictionary *info = [@{
        @"engine": @"JavaScriptCore",
        @"apiVersion": @1,
        @"manifestApiVersion": [manifest[@"apiVersion"] respondsToSelector:@selector(intValue)] ? manifest[@"apiVersion"] : @1,
        @"manifestRuntime": [manifest[@"runtime"] isKindOfClass:[NSString class]] ? manifest[@"runtime"] : @"javascriptcore",
        @"manifestEntry": [manifest[@"entry"] isKindOfClass:[NSString class]] ? manifest[@"entry"] : @"",
        @"manifestCoordinateSpace": [manifest[@"coordinateSpace"] isKindOfClass:[NSString class]] ? manifest[@"coordinateSpace"] : @"native-pixels",
        @"jit": @"unknown",
        @"watchdog": watchdog ? @"private-api" : @"unavailable",
        @"watchdogIntervalMs": @(watchdog ? (int)(kTLinkautoJSWatchdogInterval * 1000.0) : 0),
        @"hardJsCancellation": @(watchdog),
        @"cooperativeCancellation": @YES,
        @"autoReleaseHandles": @YES,
        @"runtimeLocation": @"in-process-prototype",
        @"runId": [self.runtime runId] ?: @"",
        @"consoleLogPath": [self.runtime currentConsoleLogPath] ?: @"",
        @"consoleLatestLogPath": [self.runtime currentConsoleLatestLogPath] ?: @"",
    } mutableCopy];

    TLinkJSHelperClient *helper = [[TLinkJSHelperClient alloc] init];
    NSDictionary *handshake = [helper handshakeWithTimeoutMs:250];
    BOOL helperReachable = [handshake[@"ok"] boolValue];
    info[@"helperReachable"] = @(helperReachable);
    if (helperReachable) {
        NSDictionary *response = handshake[@"response"];
        NSDictionary *payload = [response[@"payload"] isKindOfClass:[NSDictionary class]] ? response[@"payload"] : @{};
        info[@"helperProtocolVersion"] = response[@"protocolVersion"] ?: @"";
        info[@"helperInstanceId"] = response[@"helperInstanceId"] ?: @"";
        info[@"helperVersion"] = payload[@"helperVersion"] ?: @"";
        info[@"helperPid"] = payload[@"pid"] ?: @0;
        info[@"helperState"] = payload[@"state"] ?: @"unknown";
        info[@"helperCapabilities"] = [payload[@"capabilities"] isKindOfClass:[NSDictionary class]] ? payload[@"capabilities"] : @{};
    } else {
        info[@"helperError"] = handshake[@"error"] ?: @"unreachable";
    }
    return info;
}

@end
