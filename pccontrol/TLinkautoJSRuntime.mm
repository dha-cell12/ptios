#import "TLinkTaskContext.h"
#import "TLinkautoJSRuntime.h"
#import "TLinkDiagnostic.h"
#import <os/lock.h>

#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <atomic>
#include <dlfcn.h>
#include <math.h>

#include "Task.h"
#include "Screen.h"
#include "RuntimeUtils.h"

#import "jsruntime/TLinkJSRuntimeCore.h"
#import "jsruntime/TLinkInProcessNativeBridge.h"

typedef bool (*TLinkautoJSShouldTerminateCallback)(JSContextRef ctx, void *opaque);
typedef void (*TLinkautoJSSetExecutionTimeLimitFn)(JSContextGroupRef group, double limit, TLinkautoJSShouldTerminateCallback callback, void *opaque);
typedef void (*TLinkautoJSClearExecutionTimeLimitFn)(JSContextGroupRef group);

static const double kTLinkautoJSWatchdogInterval = 0.1;
static const NSUInteger kTLinkautoJSMaxResponseBytes = 1024 * 1024;
static const unsigned long long kTLinkautoJSMaxBundleFileBytes = 512 * 1024;
static const unsigned long long kTLinkautoJSMaxStorageFileBytes = 512 * 1024;
static const unsigned long long kTLinkautoJSMaxConsoleLogBytes = 512 * 1024;

@class TLinkautoJSRuntime;

@protocol TLinkautoDeviceJSExport <JSExport>

JSExportAs(tap,
- (NSDictionary *)tap:(double)x y:(double)y);
JSExportAs(swipe,
- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration);
JSExportAs(longPress,
- (NSDictionary *)longPress:(double)x y:(double)y duration:(double)duration);
JSExportAs(gesture,
- (NSDictionary *)gesture:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(runTask,
- (NSDictionary *)runTask:(int)task payload:(NSString *)payload);
JSExportAs(toast,
- (NSDictionary *)toast:(NSString *)message options:(NSDictionary *)options);
JSExportAs(pickColor,
- (NSDictionary *)pickColor:(double)x y:(double)y);
JSExportAs(screenshotTo,
- (NSDictionary *)screenshotTo:(NSString *)path);
JSExportAs(screenshotRegion,
- (NSDictionary *)screenshotRegion:(NSString *)path options:(NSDictionary *)options);
JSExportAs(batch,
- (NSDictionary *)batch:(NSArray *)commands);
JSExportAs(captureFrame,
- (NSDictionary *)captureFrame:(NSDictionary *)options);
JSExportAs(releaseFrame,
- (NSDictionary *)releaseFrame:(int)frameId);
JSExportAs(openImage,
- (NSDictionary *)openImage:(NSString *)path);
JSExportAs(captureImage,
- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height);
JSExportAs(releaseImage,
- (NSDictionary *)releaseImage:(int)imageId);
JSExportAs(framePickColor,
- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options);
JSExportAs(framePickColors,
- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(frameFindColor,
- (NSDictionary *)frameFindColor:(int)frameId options:(NSDictionary *)options);
JSExportAs(frameIsColors,
- (NSDictionary *)frameIsColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(frameFindMultiColor,
- (NSDictionary *)frameFindMultiColor:(int)frameId points:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(findImageInFrame,
- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options);
JSExportAs(ocrFrame,
- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options);
JSExportAs(ocr,
- (NSDictionary *)ocr:(NSDictionary *)options);
JSExportAs(openApp,
- (NSDictionary *)openApp:(NSString *)bundleId);
JSExportAs(killApp,
- (NSDictionary *)killApp:(NSString *)bundleId);
JSExportAs(appState,
- (NSDictionary *)appState:(NSString *)bundleId);
JSExportAs(appInfo,
- (NSDictionary *)appInfo:(NSString *)bundleId);
JSExportAs(appPid,
- (NSDictionary *)appPid:(NSString *)bundleId);
JSExportAs(appPaths,
- (NSDictionary *)appPaths:(NSString *)bundleId);
JSExportAs(listBundles,
- (NSDictionary *)listBundles:(BOOL)withInfo);
JSExportAs(openUrl,
- (NSDictionary *)openUrl:(NSString *)url);
JSExportAs(setWifi,
- (NSDictionary *)setWifi:(BOOL)enabled);
JSExportAs(setBluetooth,
- (NSDictionary *)setBluetooth:(BOOL)enabled);
JSExportAs(setAirplaneMode,
- (NSDictionary *)setAirplaneMode:(BOOL)enabled);
JSExportAs(setCellularData,
- (NSDictionary *)setCellularData:(BOOL)enabled);
JSExportAs(alert,
- (NSDictionary *)alert:(NSString *)title message:(NSString *)message duration:(int)duration);
JSExportAs(dialog,
- (NSDictionary *)dialog:(NSDictionary *)options);
JSExportAs(setClipboardText,
- (NSDictionary *)setClipboardText:(NSString *)text);
JSExportAs(insertText,
- (NSDictionary *)insertText:(NSString *)text);
JSExportAs(deleteCharacters,
- (NSDictionary *)deleteCharacters:(int)count);
JSExportAs(moveCursor,
- (NSDictionary *)moveCursor:(int)offset);
JSExportAs(hardwareKey,
- (NSDictionary *)hardwareKey:(NSString *)key action:(NSString *)action);
JSExportAs(pressHardwareKey,
- (NSDictionary *)pressHardwareKey:(NSString *)key);
JSExportAs(keepAwake,
- (NSDictionary *)keepAwake:(BOOL)enabled);
JSExportAs(touchIndicator,
- (NSDictionary *)touchIndicator:(NSString *)action);
JSExportAs(runShell,
- (NSDictionary *)runShell:(NSString *)command timeoutSeconds:(double)timeoutSeconds);
JSExportAs(saveScreenshotToAlbum,
- (NSDictionary *)saveScreenshotToAlbum:(NSString *)path);
JSExportAs(matchTemplate,
- (NSDictionary *)matchTemplate:(NSString *)path options:(NSDictionary *)options);
JSExportAs(findColor,
- (NSDictionary *)findColor:(NSDictionary *)options);
JSExportAs(isColors,
- (NSDictionary *)isColors:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(findMultiColor,
- (NSDictionary *)findMultiColor:(NSArray *)points options:(NSDictionary *)options);
JSExportAs(setAutoLaunch,
- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled);
JSExportAs(setTimer,
- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script);
JSExportAs(removeTimer,
- (NSDictionary *)removeTimer:(NSString *)name);
JSExportAs(readText,
- (NSDictionary *)readText:(NSString *)path);
JSExportAs(writeText,
- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text);
JSExportAs(readJSON,
- (NSDictionary *)readJSON:(NSString *)path);
JSExportAs(writeJSON,
- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value);
JSExportAs(fileExists,
- (NSDictionary *)fileExists:(NSString *)path);
JSExportAs(deleteFile,
- (NSDictionary *)deleteFile:(NSString *)path);
- (NSDictionary *)getScreenSize;
- (NSDictionary *)screenshot;
- (NSDictionary *)releaseAllFrames;
- (NSDictionary *)info;
- (NSDictionary *)batteryInfo;
- (NSDictionary *)clearScreenshotAlbum;
- (NSDictionary *)listAutoLaunch;
- (NSDictionary *)ocrLanguages;
- (NSDictionary *)clearDialogValues;
- (NSDictionary *)getClipboardText;
- (NSDictionary *)pasteFromClipboard;
- (NSDictionary *)showKeyboard;
- (NSDictionary *)hideKeyboard;
- (NSDictionary *)rootDir;
- (NSDictionary *)currentDir;
- (NSDictionary *)botPath;
- (NSDictionary *)frontMostPid;
- (NSDictionary *)wifi;
- (NSDictionary *)bluetooth;
- (NSDictionary *)airplaneMode;
- (NSDictionary *)cellularData;
- (NSDictionary *)frontMostAppId;
- (NSDictionary *)orientation;
- (NSDictionary *)runtimeInfo;

@end

@interface TLinkautoDeviceBridge : NSObject <TLinkautoDeviceJSExport>
@property(nonatomic, weak) TLinkautoJSRuntime *runtime;
@end

struct TLinkautoJSCancelState {
    std::atomic<bool> aborted;
};

struct TLinkautoJSWatchdogProbeState {
    std::atomic<int> callbacks;
};

@interface TLinkautoJSRuntime ()
{
    NSMutableSet<NSNumber *> *_ownedFrameIds;
    NSMutableSet<NSNumber *> *_ownedImageIds;
    
    os_unfair_lock _handlesLock;
    BOOL _acceptingHandles;
}
@property (nonatomic, strong) TLinkJSRuntimeCore *core;
@property (nonatomic, strong) TLinkInProcessNativeBridge *bridge;
- (BOOL)watchdogAvailable;
- (NSString *)currentBundlePath;
- (void)throwError:(NSString *)message;
- (NSDictionary *)taskResultForPayload:(NSString *)payload;
- (void)showDebugToast:(NSString *)message type:(int)type;
- (NSDictionary *)bundleTextForRelativePath:(NSString *)relativePath;
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)relativePath createParent:(BOOL)createParent;
- (NSString *)currentConsoleLogPath;
- (NSString *)currentConsoleLatestLogPath;
- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message;
- (NSDictionary *)currentManifest;
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
        _acceptingLogs = NO;
        
        _acceptingHandles = NO;
    }
    return self;
}

- (void)dealloc
{
    delete _cancelState;
}

- (BOOL)running
{
    return _running;
}

- (NSString *)runId
{
    return _runId ?: @"";
}

- (BOOL)watchdogAvailable
{
    return _watchdogAvailable;
}

- (NSString *)currentBundlePath
{
    return _bundlePath ?: @"";
}

- (NSString *)currentConsoleLogPath
{
    return _consoleLogPath ?: @"";
}

- (NSString *)currentConsoleLatestLogPath
{
    return _consoleLatestLogPath ?: @"";
}

- (NSDictionary *)currentManifest
{
    return _manifest ?: @{};
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
        [self taskResultForPayload:[NSString stringWithFormat:@"67%d", [frameId intValue]]];
    }
    for (NSNumber *imageId in imageIds) {
        [self taskResultForPayload:[NSString stringWithFormat:@"483;;%d", [imageId intValue]]];
    }
    _cancelState->aborted.store(wasAborted, std::memory_order_release);
}

- (void)requestStop
{
    _cancelState->aborted.store(true, std::memory_order_release);
    [_sleepCondition lock];
    [_sleepCondition broadcast];
    [_sleepCondition unlock];
}

- (BOOL)isAborted
{
    return _cancelState->aborted.load(std::memory_order_acquire);
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
    if (_context) {
        _context.exception = [JSValue valueWithNewErrorFromMessage:(message ?: @"JavaScript runtime error") inContext:_context];
    }
}

- (void)showDebugToast:(NSString *)message type:(int)type
{
    NSString *safeMessage = TLinkautoJSSanitizeProtocolText(message ?: @"JavaScript error", 180);
    NSString *payload = [NSString stringWithFormat:@"22%d;;%@;;3;;0;;14", type, safeMessage];
    [self taskResultForPayload:payload];
}

- (NSDictionary *)taskResultForPayload:(NSString *)payload
{
    if ([self isAborted]) {
        [self setAbortExceptionIfNeeded];
        return @{ @"ok": @NO, @"raw": @"1;;AbortError\r\n", @"parts": @[@"1", @"AbortError"] };
    }

    NSString *safePayload = TLinkautoJSSanitizePayload(payload);
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
    BOOL ok = [status hasPrefix:@"0"];
    return @{ @"ok": @(ok), @"raw": raw, @"parts": parts ?: @[] };
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
    NSString *bundlePath = [_bundlePath stringByStandardizingPath];
    if (![bundlePath isKindOfClass:[NSString class]] || [bundlePath length] == 0) {
        return @{ @"ok": @NO, @"error": @"bundle path is unavailable" };
    }
    if (![relativePath isKindOfClass:[NSString class]] || [relativePath length] == 0) {
        return @{ @"ok": @NO, @"error": @"path is required" };
    }
    if ([relativePath hasPrefix:@"/"] || [relativePath rangeOfString:@"\0"].location != NSNotFound) {
        return @{ @"ok": @NO, @"error": @"path must be bundle-relative" };
    }

    NSString *candidate = [[bundlePath stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    NSString *prefix = [bundlePath hasSuffix:@"/"] ? bundlePath : [bundlePath stringByAppendingString:@"/"];
    if (![candidate hasPrefix:prefix]) {
        return @{ @"ok": @NO, @"error": @"path escapes bundle" };
    }

    NSString *name = [candidate lastPathComponent];
    if ([name isEqualToString:@"manifest.json"] || [name isEqualToString:@"info.plist"]) {
        return @{ @"ok": @NO, @"error": @"refusing to modify bundle metadata" };
    }
    if ([[[candidate pathExtension] lowercaseString] isEqualToString:@"js"]) {
        return @{ @"ok": @NO, @"error": @"refusing to modify JavaScript source files" };
    }

    if (createParent) {
        NSString *dir = [candidate stringByDeletingLastPathComponent];
        NSError *mkdirError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
            return @{ @"ok": @NO, @"error": mkdirError.localizedDescription ?: @"failed to create parent directory", @"path": candidate };
        }
    }
    return @{ @"ok": @YES, @"path": candidate };
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
    return [_core runScriptAtPath:scriptPath bundlePath:bundlePath manifest:manifest context:context facade:self error:error];
}

- (NSDictionary *)executeNativeRequest:(NSString *)method arguments:(NSArray *)arguments {
    TLinkJSNativeRequest *request = [[TLinkJSNativeRequest alloc] initWithMethod:method arguments:arguments];
    TLinkTaskExecutionContext *ctx = [[TLinkTaskExecutionContext alloc] init];
    ctx.runtime = self;
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
    return [self.runtime taskResultForPayload:wire];
}

- (NSDictionary *)toast:(NSString *)message options:(NSDictionary *)options
{
    return [self.runtime executeNativeRequest:@"toast" arguments:@[message ?: @"", options ?: @{}]];
}

- (NSDictionary *)tap:(double)x y:(double)y
{
    return [self.runtime executeNativeRequest:@"tap" arguments:@[@(x), @(y)]];
}

- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration
{
    return [self.runtime executeNativeRequest:@"swipe" arguments:@[@(x1), @(y1), @(x2), @(y2), @(duration)]];
}

- (NSDictionary *)longPress:(double)x y:(double)y duration:(double)duration
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) {
        [self.runtime throwError:@"longPress(x, y, duration) requires finite numbers"];
        return @{ @"ok": @NO };
    }
    if (duration < 0) duration = 0;
    if (duration > 60000) duration = 60000;
    NSString *payload = [NSString stringWithFormat:@"%.2f;;%.2f;;%.0f", x, y, duration];
    return [self runTask:TASK_NATIVE_TAP payload:payload];
}

- (NSDictionary *)gesture:(NSArray *)points options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *encoded = TLinkautoJSEncodeGesturePoints(points);
    if (!encoded) {
        [self.runtime throwError:@"gesture(points, options) requires 2-512 points as [x,y] arrays or {x,y} objects"];
        return @{ @"ok": @NO };
    }
    int finger = TLinkautoJSIntOption(options, @"finger", 0);
    int duration = TLinkautoJSIntOption(options, @"duration", TLinkautoJSIntOption(options, @"durationMs", 300));
    if (duration < 0) duration = 0;
    if (duration > 60000) duration = 60000;
    NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%@", finger, duration, encoded];
    return [self runTask:TASK_NATIVE_GESTURE payload:payload];
}

- (NSDictionary *)pickColor:(double)x y:(double)y
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
        [self.runtime throwError:@"pickColor(x, y) requires finite numbers"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_COLOR_PICKER payload:[NSString stringWithFormat:@"%.0f;;%.0f", x, y]];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 4) {
        return result;
    }
    return TLinkautoJSResultByAdding(result, @{
        @"red": @([TLinkautoJSSafeStringPart(parts, 1) intValue]),
        @"green": @([TLinkautoJSSafeStringPart(parts, 2) intValue]),
        @"blue": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
    });
}

- (NSString *)defaultScreenshotPath
{
    NSString *dir = [self.runtime currentBundlePath];
    if (!dir || [dir length] == 0) {
        dir = @"/tmp";
    }
    NSString *name = [NSString stringWithFormat:@"screenshot_%@.png", TLinkautoJSSanitizeFileComponent(self.runtime.runId)];
    return [dir stringByAppendingPathComponent:name];
}

- (NSDictionary *)screenshot
{
    return [self screenshotTo:[self defaultScreenshotPath]];
}

- (NSDictionary *)screenshotTo:(NSString *)path
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *targetPath = ([path isKindOfClass:[NSString class]] && [path length] > 0) ? path : [self defaultScreenshotPath];
    if (TLinkautoJSStringContainsAny(targetPath, @[@";;", @"\r", @"\n"])) {
        [self.runtime throwError:@"screenshot path contains unsupported protocol delimiter"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_SCREENSHOT payload:[NSString stringWithFormat:@"1;;%@", targetPath]];
    NSArray *parts = result[@"parts"];
    NSString *resultPath = [parts count] >= 2 ? TLinkautoJSSafeStringPart(parts, 1) : targetPath;
    return TLinkautoJSResultByAdding(result, @{ @"path": resultPath ?: @"" });
}

- (NSDictionary *)screenshotRegion:(NSString *)path options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *targetPath = ([path isKindOfClass:[NSString class]] && [path length] > 0) ? path : [self defaultScreenshotPath];
    if (TLinkautoJSStringContainsAny(targetPath, @[@";;", @"\r", @"\n"])) {
        [self.runtime throwError:@"screenshot path contains unsupported protocol delimiter"];
        return @{ @"ok": @NO };
    }

    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) ||
        !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height) || width <= 0 || height <= 0) {
        [self.runtime throwError:@"screenshotRegion(path, options) requires finite positive width/height"];
        return @{ @"ok": @NO };
    }

    NSDictionary *result = [self runTask:TASK_SCREENSHOT payload:[NSString stringWithFormat:@"1;;%@;;%.0f;;%.0f;;%.0f;;%.0f", targetPath, x, y, width, height]];
    NSArray *parts = result[@"parts"];
    NSString *resultPath = [parts count] >= 2 ? TLinkautoJSSafeStringPart(parts, 1) : targetPath;
    return TLinkautoJSResultByAdding(result, @{
        @"path": resultPath ?: @"",
        @"x": @(x),
        @"y": @(y),
        @"width": @(width),
        @"height": @(height),
    });
}

- (NSDictionary *)frontMostAppId
{
    NSDictionary *result = [self runTask:TASK_FRONTMOST_APP_ID payload:@""];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"bundleId": TLinkautoJSSafeStringPart(parts, 1) });
}

- (NSDictionary *)orientation
{
    NSDictionary *result = [self runTask:TASK_FRONTMOST_APP_ORIENTATION payload:@""];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"value": @([TLinkautoJSSafeStringPart(parts, 1) intValue]) });
}

- (NSDictionary *)batch:(NSArray *)commands
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (![commands isKindOfClass:[NSArray class]]) {
        [self.runtime throwError:@"batch(commands) requires an array"];
        return @{ @"ok": @NO };
    }
    if ([commands count] > 256) {
        [self.runtime throwError:@"batch(commands) accepts at most 256 commands"];
        return @{ @"ok": @NO };
    }

    NSMutableArray<NSString *> *wireCommands = [NSMutableArray arrayWithCapacity:[commands count]];
    for (id item in commands) {
        if ([item isKindOfClass:[NSString class]]) {
            NSString *raw = (NSString *)item;
            if (TLinkautoJSStringContainsAny(raw, @[@"||", @"\r", @"\n"])) {
                [self.runtime throwError:@"raw batch command contains unsupported protocol delimiter"];
                return @{ @"ok": @NO };
            }
            if ([raw hasPrefix:@"62"] || [raw hasPrefix:@"63"] || [raw hasPrefix:@"64"]) {
                [wireCommands addObject:raw];
            } else {
                [self.runtime throwError:@"raw batch command must start with allowed native task 62/63/64"];
                return @{ @"ok": @NO };
            }
            continue;
        }
        if (![item isKindOfClass:[NSDictionary class]]) {
            [self.runtime throwError:@"batch command must be an object or raw command string"];
            return @{ @"ok": @NO };
        }
        NSDictionary *cmd = (NSDictionary *)item;
        NSString *type = [[cmd[@"type"] description] lowercaseString];
        if ([type isEqualToString:@"tap"]) {
            double x = [cmd[@"x"] doubleValue];
            double y = [cmd[@"y"] doubleValue];
            double duration = cmd[@"duration"] ? [cmd[@"duration"] doubleValue] : 50.0;
            if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) {
                [self.runtime throwError:@"batch tap requires finite x/y/duration"];
                return @{ @"ok": @NO };
            }
            [wireCommands addObject:[NSString stringWithFormat:@"62%.2f;;%.2f;;%.0f", x, y, duration]];
        } else if ([type isEqualToString:@"swipe"]) {
            double x1 = [cmd[@"x1"] doubleValue];
            double y1 = [cmd[@"y1"] doubleValue];
            double x2 = [cmd[@"x2"] doubleValue];
            double y2 = [cmd[@"y2"] doubleValue];
            double duration = cmd[@"duration"] ? [cmd[@"duration"] doubleValue] : 300.0;
            if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) ||
                !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) || !TLinkautoJSIsFiniteNumber(duration)) {
                [self.runtime throwError:@"batch swipe requires finite coordinates/duration"];
                return @{ @"ok": @NO };
            }
            [wireCommands addObject:[NSString stringWithFormat:@"63%.2f;;%.2f;;%.2f;;%.2f;;%.0f", x1, y1, x2, y2, duration]];
        } else if ([type isEqualToString:@"gesture"]) {
            NSArray *points = [cmd[@"points"] isKindOfClass:[NSArray class]] ? cmd[@"points"] : nil;
            NSString *encoded = TLinkautoJSEncodeGesturePoints(points);
            if (!encoded) {
                [self.runtime throwError:@"batch gesture requires 2-512 valid points"];
                return @{ @"ok": @NO };
            }
            int finger = cmd[@"finger"] ? [cmd[@"finger"] intValue] : 0;
            int duration = cmd[@"duration"] ? [cmd[@"duration"] intValue] : (cmd[@"durationMs"] ? [cmd[@"durationMs"] intValue] : 300);
            if (duration < 0) duration = 0;
            if (duration > 60000) duration = 60000;
            [wireCommands addObject:[NSString stringWithFormat:@"64%d;;%d;;%@", finger, duration, encoded]];
        } else {
            [self.runtime throwError:[NSString stringWithFormat:@"unsupported batch command type: %@", type ?: @""]];
            return @{ @"ok": @NO };
        }
    }

    NSString *payload = [wireCommands componentsJoinedByString:@"||"];
    return [self runTask:TASK_NATIVE_BATCH payload:payload];
}

- (NSDictionary *)captureFrame:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    BOOL needGray = TLinkautoJSIntOption(options, @"gray", 1) != 0;
    BOOL needBGRA = TLinkautoJSIntOption(options, @"bgra", 1) != 0;
    int ttlMs = TLinkautoJSIntOption(options, @"ttlMs", 1000);
    if (!needGray && !needBGRA) {
        needGray = YES;
        needBGRA = YES;
    }
    if (ttlMs <= 0) ttlMs = 1000;
    NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%d", needGray ? 1 : 0, needBGRA ? 1 : 0, ttlMs];
    NSDictionary *result = [self runTask:TASK_FRAME_CAPTURE payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 15) return result;
    int frameId = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    [self.runtime trackFrameId:frameId];
    return TLinkautoJSResultByAdding(result, @{
        @"id": @(frameId),
        @"width": @([TLinkautoJSSafeStringPart(parts, 2) intValue]),
        @"height": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
        @"bytesPerRow": @([TLinkautoJSSafeStringPart(parts, 4) intValue]),
        @"scale": @([TLinkautoJSSafeStringPart(parts, 5) doubleValue]),
        @"coordinateSpace": TLinkautoJSSafeStringPart(parts, 6),
        @"pixelFormat": TLinkautoJSSafeStringPart(parts, 7),
        @"hasBGRA": @([TLinkautoJSSafeStringPart(parts, 8) intValue] != 0),
        @"hasGray": @([TLinkautoJSSafeStringPart(parts, 9) intValue] != 0),
        @"createdAtMs": @([TLinkautoJSSafeStringPart(parts, 10) longLongValue]),
        @"captureMs": @([TLinkautoJSSafeStringPart(parts, 11) doubleValue]),
        @"bgraMs": @([TLinkautoJSSafeStringPart(parts, 12) doubleValue]),
        @"grayMs": @([TLinkautoJSSafeStringPart(parts, 13) doubleValue]),
        @"totalMs": @([TLinkautoJSSafeStringPart(parts, 14) doubleValue]),
    });
}

- (NSDictionary *)releaseFrame:(int)frameId
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (frameId <= 0) {
        [self.runtime throwError:@"releaseFrame(frameId) requires a positive id"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_FRAME_RELEASE payload:[NSString stringWithFormat:@"%d", frameId]];
    if ([result[@"ok"] boolValue]) [self.runtime untrackFrameId:frameId];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"released": @([TLinkautoJSSafeStringPart(parts, 1) intValue]) });
}

- (NSDictionary *)releaseAllFrames
{
    NSDictionary *result = [self runTask:TASK_FRAME_RELEASE payload:@"all"];
    if ([result[@"ok"] boolValue]) [self.runtime untrackAllFrameIds];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"released": @([TLinkautoJSSafeStringPart(parts, 1) intValue]) });
}

- (NSDictionary *)openImage:(NSString *)path
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (![path isKindOfClass:[NSString class]] || [path length] == 0 || TLinkautoJSStringContainsAny(path, @[@";;", @"\r", @"\n"])) {
        [self.runtime throwError:@"openImage(path) requires a valid path"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_IMAGE_OBJECT payload:[NSString stringWithFormat:@"2;;%@", path]];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 4) return result;
    int imageId = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    [self.runtime trackImageId:imageId];
    return TLinkautoJSResultByAdding(result, @{
        @"id": @(imageId),
        @"width": @([TLinkautoJSSafeStringPart(parts, 2) intValue]),
        @"height": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
    });
}

- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) ||
        !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height) || width <= 0 || height <= 0) {
        [self.runtime throwError:@"captureImage(x, y, width, height) requires finite positive dimensions"];
        return @{ @"ok": @NO };
    }
    NSString *payload = [NSString stringWithFormat:@"1;;%.0f;;%.0f;;%.0f;;%.0f", x, y, width, height];
    NSDictionary *result = [self runTask:TASK_IMAGE_OBJECT payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 4) return result;
    int imageId = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    [self.runtime trackImageId:imageId];
    return TLinkautoJSResultByAdding(result, @{
        @"id": @(imageId),
        @"width": @([TLinkautoJSSafeStringPart(parts, 2) intValue]),
        @"height": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
    });
}

- (NSDictionary *)releaseImage:(int)imageId
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (imageId <= 0) {
        [self.runtime throwError:@"releaseImage(imageId) requires a positive id"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_IMAGE_OBJECT payload:[NSString stringWithFormat:@"3;;%d", imageId]];
    if ([result[@"ok"] boolValue]) [self.runtime untrackImageId:imageId];
    return result;
}

- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (frameId <= 0 || !TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
        [self.runtime throwError:@"framePickColor(frameId, x, y) requires a frame id and finite coordinates"];
        return @{ @"ok": @NO };
    }
    NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
    if (!TLinkautoJSValidToken(coord)) {
        [self.runtime throwError:@"coord contains unsupported protocol delimiter"];
        return @{ @"ok": @NO };
    }
    int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
    NSString *payload = [NSString stringWithFormat:@"%d;;pick;;%.0f;;%.0f;;%@;;%d", frameId, x, y, coord, maxAgeMs];
    NSDictionary *result = [self runTask:TASK_COLOR_IN_FRAME payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 7) return result;
    return TLinkautoJSResultByAdding(result, @{
        @"red": @([TLinkautoJSSafeStringPart(parts, 1) intValue]),
        @"green": @([TLinkautoJSSafeStringPart(parts, 2) intValue]),
        @"blue": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
        @"ageMs": @([TLinkautoJSSafeStringPart(parts, 4) longLongValue]),
        @"totalMs": @([TLinkautoJSSafeStringPart(parts, 5) doubleValue]),
    });
}

- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (frameId <= 0 || ![points isKindOfClass:[NSArray class]] || [points count] == 0) {
        [self.runtime throwError:@"framePickColors(frameId, points) requires a frame id and non-empty points array"];
        return @{ @"ok": @NO };
    }
    NSMutableArray<NSString *> *encoded = [NSMutableArray arrayWithCapacity:[points count]];
    for (id point in points) {
        double x = 0;
        double y = 0;
        if ([point isKindOfClass:[NSArray class]] && [point count] >= 2) {
            NSArray *arrayPoint = (NSArray *)point;
            x = [arrayPoint[0] doubleValue];
            y = [arrayPoint[1] doubleValue];
        } else if ([point isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dictPoint = (NSDictionary *)point;
            x = [dictPoint[@"x"] doubleValue];
            y = [dictPoint[@"y"] doubleValue];
        } else {
            [self.runtime throwError:@"framePickColors points must be [x,y] arrays or {x,y} objects"];
            return @{ @"ok": @NO };
        }
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
            [self.runtime throwError:@"framePickColors points require finite coordinates"];
            return @{ @"ok": @NO };
        }
        [encoded addObject:[NSString stringWithFormat:@"%.0f,%.0f", x, y]];
    }
    NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
    if (!TLinkautoJSValidToken(coord)) {
        [self.runtime throwError:@"coord contains unsupported protocol delimiter"];
        return @{ @"ok": @NO };
    }
    int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
    NSString *payload = [NSString stringWithFormat:@"%d;;pick_many;;%@;;%@;;%d", frameId, [encoded componentsJoinedByString:@"|"], coord, maxAgeMs];
    NSDictionary *result = [self runTask:TASK_COLOR_IN_FRAME payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 5) return result;
    NSMutableArray *colors = [NSMutableArray array];
    for (NSString *item in [TLinkautoJSSafeStringPart(parts, 1) componentsSeparatedByString:@"|"]) {
        NSArray *fields = [item componentsSeparatedByString:@","];
        if ([fields count] == 5) {
            [colors addObject:@{
                @"x": @([fields[0] intValue]),
                @"y": @([fields[1] intValue]),
                @"red": @([fields[2] intValue]),
                @"green": @([fields[3] intValue]),
                @"blue": @([fields[4] intValue]),
            }];
        }
    }
    return TLinkautoJSResultByAdding(result, @{
        @"colors": colors,
        @"ageMs": @([TLinkautoJSSafeStringPart(parts, 2) longLongValue]),
        @"totalMs": @([TLinkautoJSSafeStringPart(parts, 3) doubleValue]),
    });
}

- (NSDictionary *)frameFindColor:(int)frameId options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (frameId <= 0) {
        [self.runtime throwError:@"frameFindColor(frameId, options) requires a positive frame id"];
        return @{ @"ok": @NO };
    }
    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);
    int redMin = TLinkautoJSIntOption(options, @"redMin", TLinkautoJSIntOption(options, @"rMin", 0));
    int redMax = TLinkautoJSIntOption(options, @"redMax", TLinkautoJSIntOption(options, @"rMax", 255));
    int greenMin = TLinkautoJSIntOption(options, @"greenMin", TLinkautoJSIntOption(options, @"gMin", 0));
    int greenMax = TLinkautoJSIntOption(options, @"greenMax", TLinkautoJSIntOption(options, @"gMax", 255));
    int blueMin = TLinkautoJSIntOption(options, @"blueMin", TLinkautoJSIntOption(options, @"bMin", 0));
    int blueMax = TLinkautoJSIntOption(options, @"blueMax", TLinkautoJSIntOption(options, @"bMax", 255));
    int skip = TLinkautoJSIntOption(options, @"skip", 0);
    NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
    if (!TLinkautoJSValidToken(coord) || !TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
        [self.runtime throwError:@"frameFindColor options require finite x/y/width/height and valid coord"];
        return @{ @"ok": @NO };
    }
    int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
    NSString *payload = [NSString stringWithFormat:@"%d;;search_single;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d;;%@;;%d",
                         frameId, x, y, width, height, redMin, redMax, greenMin, greenMax, blueMin, blueMax, skip, coord, maxAgeMs];
    NSDictionary *result = [self runTask:TASK_COLOR_IN_FRAME payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 9) return result;
    int foundX = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    int foundY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
    return TLinkautoJSResultByAdding(result, @{
        @"matched": @(foundX >= 0 && foundY >= 0),
        @"x": @(foundX),
        @"y": @(foundY),
        @"red": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
        @"green": @([TLinkautoJSSafeStringPart(parts, 4) intValue]),
        @"blue": @([TLinkautoJSSafeStringPart(parts, 5) intValue]),
        @"ageMs": @([TLinkautoJSSafeStringPart(parts, 6) longLongValue]),
        @"totalMs": @([TLinkautoJSSafeStringPart(parts, 7) doubleValue]),
    });
}

- (NSDictionary *)frameIsColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *table = TLinkautoJSEncodePointColorTable(points);
    if (frameId <= 0 || !table) {
        [self.runtime throwError:@"frameIsColors(frameId, points, options) requires a frame id and point colors"];
        return @{ @"ok": @NO };
    }
    int mode = TLinkautoJSIntOption(options, @"mode", 1);
    double value = TLinkautoJSDoubleOption(options, @"value", TLinkautoJSDoubleOption(options, @"tolerance", 0));
    NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
    if (!TLinkautoJSValidToken(coord)) {
        [self.runtime throwError:@"coord contains unsupported protocol delimiter"];
        return @{ @"ok": @NO };
    }
    int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
    NSDictionary *result = [self runTask:TASK_COLOR_IN_FRAME payload:[NSString stringWithFormat:@"%d;;is_colors;;%@;;%d;;%.4f;;%@;;%d", frameId, table, mode, value, coord, maxAgeMs]];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 5) return result;
    BOOL matched = [TLinkautoJSSafeStringPart(parts, 1) intValue] != 0;
    return TLinkautoJSResultByAdding(result, @{
        @"matched": @(matched),
        @"value": @(matched),
        @"ageMs": @([TLinkautoJSSafeStringPart(parts, 2) longLongValue]),
        @"totalMs": @([TLinkautoJSSafeStringPart(parts, 3) doubleValue]),
    });
}

- (NSDictionary *)frameFindMultiColor:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *table = TLinkautoJSEncodePointColorTable(points);
    if (frameId <= 0 || !table) {
        [self.runtime throwError:@"frameFindMultiColor(frameId, points, options) requires a frame id and relative point colors"];
        return @{ @"ok": @NO };
    }
    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);
    int mode = TLinkautoJSIntOption(options, @"mode", 1);
    double value = TLinkautoJSDoubleOption(options, @"value", TLinkautoJSDoubleOption(options, @"tolerance", 0));
    int skip = TLinkautoJSIntOption(options, @"skip", 0);
    NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
    if (!TLinkautoJSValidToken(coord) || !TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
        [self.runtime throwError:@"frameFindMultiColor options require finite x/y/width/height and valid coord"];
        return @{ @"ok": @NO };
    }
    int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
    NSString *payload = [NSString stringWithFormat:@"%d;;find_multi_point;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%.4f;;%d;;%@;;%d", frameId, x, y, width, height, table, mode, value, skip, coord, maxAgeMs];
    NSDictionary *result = [self runTask:TASK_COLOR_IN_FRAME payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 6) return result;
    int foundX = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    int foundY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
    return TLinkautoJSResultByAdding(result, @{
        @"matched": @(foundX >= 0 && foundY >= 0),
        @"x": @(foundX),
        @"y": @(foundY),
        @"ageMs": @([TLinkautoJSSafeStringPart(parts, 3) longLongValue]),
        @"totalMs": @([TLinkautoJSSafeStringPart(parts, 4) doubleValue]),
    });
}

- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (frameId <= 0 || imageId <= 0) {
        [self.runtime throwError:@"findImageInFrame(frameId, imageId, options) requires positive ids"];
        return @{ @"ok": @NO };
    }
    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);
    double acceptable = TLinkautoJSDoubleOption(options, @"acceptable", 0.95);
    double scaleMin = TLinkautoJSDoubleOption(options, @"scaleMin", 1.0);
    double scaleMax = TLinkautoJSDoubleOption(options, @"scaleMax", 1.0);
    double scaleStep = TLinkautoJSDoubleOption(options, @"scaleStep", 1.0);
    int pixelSkip = TLinkautoJSIntOption(options, @"pixelSkip", 0);
    NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
    if (!TLinkautoJSValidToken(coord)) {
        [self.runtime throwError:@"coord contains unsupported protocol delimiter"];
        return @{ @"ok": @NO };
    }
    int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
    NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%.0f;;%.0f;;%.0f;;%.0f;;%.4f;;%.4f;;%.4f;;%.4f;;%d;;%@;;%d",
                         frameId, imageId, x, y, width, height, acceptable, scaleMin, scaleMax, scaleStep, pixelSkip, coord, maxAgeMs];
    NSDictionary *result = [self runTask:TASK_FIND_IMAGE_IN_FRAME payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 11) return result;
    int matchX = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    int matchY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
    return TLinkautoJSResultByAdding(result, @{
        @"matched": @(matchX >= 0 && matchY >= 0),
        @"x": @(matchX),
        @"y": @(matchY),
        @"width": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
        @"height": @([TLinkautoJSSafeStringPart(parts, 4) intValue]),
        @"centerX": @([TLinkautoJSSafeStringPart(parts, 5) doubleValue]),
        @"centerY": @([TLinkautoJSSafeStringPart(parts, 6) doubleValue]),
        @"score": @([TLinkautoJSSafeStringPart(parts, 7) doubleValue]),
        @"ageMs": @([TLinkautoJSSafeStringPart(parts, 8) longLongValue]),
        @"totalMs": @([TLinkautoJSSafeStringPart(parts, 9) doubleValue]),
    });
}

- (NSDictionary *)ocrLanguages
{
    NSDictionary *result = [self runTask:TASK_OCR_TESSERACT_REGION payload:@"check_langs"];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 3) return TLinkautoJSOCRResultByAddingDecodedError(result);
    NSString *langsText = TLinkautoJSBase64Decode(TLinkautoJSSafeStringPart(parts, 2));
    NSArray *langs = [langsText length] > 0 ? [langsText componentsSeparatedByString:@","] : @[];
    return TLinkautoJSResultByAdding(result, @{
        @"languages": langs,
        @"value": langsText ?: @"",
    });
}

- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if ([self.runtime isAborted]) {
        [self.runtime throwError:@"JavaScript execution was aborted"];
        return @{ @"ok": @NO };
    }
    if (frameId <= 0) {
        [self.runtime throwError:@"ocrFrame(frameId, options) requires a positive frame id"];
        return @{ @"ok": @NO };
    }

    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) ||
        !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
        [self.runtime throwError:@"ocrFrame options require finite x/y/width/height"];
        return @{ @"ok": @NO };
    }

    NSString *lang = TLinkautoJSStringOption(options, @"lang", @"vie");
    NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
    if (!TLinkautoJSValidToken(lang) || !TLinkautoJSValidToken(coord)) {
        [self.runtime throwError:@"ocrFrame lang/coord contains unsupported protocol delimiter"];
        return @{ @"ok": @NO };
    }

    int oem = TLinkautoJSIntOption(options, @"oem", 1);
    int psm = TLinkautoJSIntOption(options, @"psm", 7);
    int scaleUp = TLinkautoJSIntOption(options, @"scaleUp", 2);
    int thresholdMode = TLinkautoJSIntOption(options, @"thresholdMode", 0);
    int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
    NSString *whitelist = TLinkautoJSStringOption(options, @"whitelist", @"");

    NSString *payload = [NSString stringWithFormat:@"%d;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%d;;%@;;%d;;%d;;%@;;%d",
                         frameId, x, y, width, height, lang, oem, psm,
                         TLinkautoJSBase64Encode(whitelist), scaleUp, thresholdMode, coord, maxAgeMs];
    NSDictionary *result = [self runTask:TASK_OCR_TESSERACT_REGION payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue]) return TLinkautoJSOCRResultByAddingDecodedError(result);
    if ([parts count] < 7) return result;

    return TLinkautoJSResultByAdding(result, @{
        @"text": TLinkautoJSBase64Decode(TLinkautoJSSafeStringPart(parts, 1)),
        @"confidence": @([TLinkautoJSSafeStringPart(parts, 2) doubleValue]),
        @"ageMs": @([TLinkautoJSSafeStringPart(parts, 3) longLongValue]),
        @"ocrMs": @([TLinkautoJSSafeStringPart(parts, 4) doubleValue]),
        @"preprocessMs": @([TLinkautoJSSafeStringPart(parts, 5) doubleValue]),
        @"totalMs": @([TLinkautoJSSafeStringPart(parts, 6) doubleValue]),
    });
}

- (NSDictionary *)ocr:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *frame = [self captureFrame:@{
        @"gray": @1,
        @"bgra": @0,
        @"ttlMs": @(TLinkautoJSIntOption(options, @"ttlMs", 1000)),
    }];
    if (![frame[@"ok"] boolValue]) return frame;

    int frameId = [frame[@"id"] intValue];
    NSMutableDictionary *ocrOptions = [NSMutableDictionary dictionaryWithDictionary:[options isKindOfClass:[NSDictionary class]] ? options : @{}];
    if (!ocrOptions[@"width"]) ocrOptions[@"width"] = frame[@"width"] ?: @0;
    if (!ocrOptions[@"height"]) ocrOptions[@"height"] = frame[@"height"] ?: @0;

    NSDictionary *ocrResult = [self ocrFrame:frameId options:ocrOptions];
    [self releaseFrame:frameId];
    return ocrResult;
}

- (NSDictionary *)openApp:(NSString *)bundleId
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(bundleId)) {
        [self.runtime throwError:@"openApp(bundleId) requires a valid bundle id"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_PROCESS_BRING_FOREGROUND payload:bundleId];
}

- (NSDictionary *)killApp:(NSString *)bundleId
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(bundleId)) {
        [self.runtime throwError:@"killApp(bundleId) requires a valid bundle id"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_APP_KILL payload:bundleId];
}

- (NSDictionary *)appState:(NSString *)bundleId
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(bundleId)) {
        [self.runtime throwError:@"appState(bundleId) requires a valid bundle id"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_APP_STATE payload:bundleId];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    int state = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    return TLinkautoJSResultByAdding(result, @{
        @"state": @(state),
        @"running": @(state > 0),
    });
}

- (NSDictionary *)appInfo:(NSString *)bundleId
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(bundleId)) {
        [self.runtime throwError:@"appInfo(bundleId) requires a valid bundle id"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_APP_INFO payload:bundleId];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 6) return result;
    return TLinkautoJSResultByAdding(result, @{
        @"bundleId": TLinkautoJSSafeStringPart(parts, 1),
        @"name": TLinkautoJSSafeStringPart(parts, 2),
        @"shortVersion": TLinkautoJSSafeStringPart(parts, 3),
        @"bundleVersion": TLinkautoJSSafeStringPart(parts, 4),
        @"state": @([TLinkautoJSSafeStringPart(parts, 5) intValue]),
    });
}

- (NSDictionary *)appPid:(NSString *)bundleId
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(bundleId)) {
        [self.runtime throwError:@"appPid(bundleId) requires a valid bundle id"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_APP_PID payload:bundleId];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"pid": @([TLinkautoJSSafeStringPart(parts, 1) intValue]) });
}

- (NSDictionary *)frontMostPid
{
    NSDictionary *result = [self runTask:TASK_FRONTMOST_PID payload:@""];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"pid": @([TLinkautoJSSafeStringPart(parts, 1) intValue]) });
}

- (NSDictionary *)appPaths:(NSString *)bundleId
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(bundleId)) {
        [self.runtime throwError:@"appPaths(bundleId) requires a valid bundle id"];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [self runTask:TASK_APP_PATHS payload:bundleId];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue]) return result;
    return TLinkautoJSResultByAdding(result, @{
        @"bundlePath": [parts count] > 1 ? TLinkautoJSSafeStringPart(parts, 1) : @"",
        @"dataPath": [parts count] > 2 ? TLinkautoJSSafeStringPart(parts, 2) : @"",
    });
}

- (NSDictionary *)listBundles:(BOOL)withInfo
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *result = [self runTask:TASK_LIST_BUNDLES payload:(withInfo ? @"1" : @"0")];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    if (withInfo) {
        id obj = TLinkautoJSJSONFromBase64(TLinkautoJSSafeStringPart(parts, 1));
        NSArray *items = [obj isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)obj)[@"items"] : @[];
        return TLinkautoJSResultByAdding(result, @{ @"items": [items isKindOfClass:[NSArray class]] ? items : @[] });
    }
    NSString *raw = TLinkautoJSSafeStringPart(parts, 1);
    NSArray *bundleIds = [raw length] > 0 ? [raw componentsSeparatedByString:@",,"] : @[];
    return TLinkautoJSResultByAdding(result, @{ @"bundleIds": bundleIds });
}

- (NSDictionary *)openUrl:(NSString *)url
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(url)) {
        [self.runtime throwError:@"openUrl(url) requires a valid URL string"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_OPEN_URL payload:url];
}

- (NSDictionary *)connectivityTask:(int)task enabledKey:(NSString *)enabledKey value:(NSNumber *)value
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *payload = value ? [NSString stringWithFormat:@"1;;%d", [value boolValue] ? 1 : 0] : @"0";
    return TLinkautoJSStateResult([self runTask:task payload:payload], enabledKey ?: @"enabled");
}

- (NSDictionary *)wifi
{
    return [self connectivityTask:TASK_WIFI enabledKey:@"enabled" value:nil];
}

- (NSDictionary *)setWifi:(BOOL)enabled
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    return [self connectivityTask:TASK_WIFI enabledKey:@"enabled" value:@(enabled)];
}

- (NSDictionary *)bluetooth
{
    return [self connectivityTask:TASK_BLUETOOTH enabledKey:@"enabled" value:nil];
}

- (NSDictionary *)setBluetooth:(BOOL)enabled
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    return [self connectivityTask:TASK_BLUETOOTH enabledKey:@"enabled" value:@(enabled)];
}

- (NSDictionary *)airplaneMode
{
    return [self connectivityTask:TASK_AIRPLANE enabledKey:@"enabled" value:nil];
}

- (NSDictionary *)setAirplaneMode:(BOOL)enabled
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    return [self connectivityTask:TASK_AIRPLANE enabledKey:@"enabled" value:@(enabled)];
}

- (NSDictionary *)cellularData
{
    return [self connectivityTask:TASK_CELLULAR_DATA enabledKey:@"enabled" value:nil];
}

- (NSDictionary *)setCellularData:(BOOL)enabled
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    return [self connectivityTask:TASK_CELLULAR_DATA enabledKey:@"enabled" value:@(enabled)];
}

- (NSDictionary *)alert:(NSString *)title message:(NSString *)message duration:(int)duration
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *safeTitle = TLinkautoJSSanitizeProtocolText(title ?: @"TLinkauto", 80);
    NSString *safeMessage = TLinkautoJSSanitizeProtocolText(message ?: @"", 300);
    if (duration <= 0) duration = 3;
    return [self runTask:TASK_SHOW_ALERT_BOX payload:[NSString stringWithFormat:@"%@;;%@;;%d", safeTitle, safeMessage, duration]];
}

- (NSDictionary *)dialog:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *title = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"title", @"TLinkauto"), 80);
    NSString *message = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"message", @""), 300);
    NSString *ok = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"ok", @"OK"), 40);
    NSString *cancel = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"cancel", @"Cancel"), 40);
    NSDictionary *result = [self runTask:TASK_DIALOG payload:[NSString stringWithFormat:@"%@;;%@;;%@;;%@", title, message, ok, cancel]];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"response": @([TLinkautoJSSafeStringPart(parts, 1) intValue]) });
}

- (NSDictionary *)clearDialogValues
{
    return [self runTask:TASK_CLEAR_DIALOG payload:@""];
}

- (NSDictionary *)keyboardTask:(int)kind content:(NSString *)content
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *payload = content ? [NSString stringWithFormat:@"%d;;%@", kind, TLinkautoJSSanitizeProtocolText(content, 2048)] : [NSString stringWithFormat:@"%d", kind];
    return [self runTask:TASK_TEXT_INPUT payload:payload];
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
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    return [self keyboardTask:7 content:(text ?: @"")];
}

- (NSDictionary *)insertText:(NSString *)text
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    return [self keyboardTask:1 content:(text ?: @"")];
}

- (NSDictionary *)deleteCharacters:(int)count
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (count <= 0) count = 1;
    if (count > 1024) count = 1024;
    return [self keyboardTask:4 content:[NSString stringWithFormat:@"%d", count]];
}

- (NSDictionary *)moveCursor:(int)offset
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (offset > 1024) offset = 1024;
    if (offset < -1024) offset = -1024;
    return [self keyboardTask:3 content:[NSString stringWithFormat:@"%d", offset]];
}

- (NSDictionary *)hardwareKey:(NSString *)key action:(NSString *)action
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    int keyType = TLinkautoJSHardwareKeyType(key);
    int keyAction = TLinkautoJSHardwareKeyAction(action);
    if (keyType <= 0 || keyAction < 0) {
        [self.runtime throwError:@"hardwareKey(key, action) supports key home/volume-up/volume-down/lock and action down/up"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_HARDWARE_KEY payload:[NSString stringWithFormat:@"%d;;%d", keyAction, keyType]];
}

- (NSDictionary *)pressHardwareKey:(NSString *)key
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *down = [self hardwareKey:key action:@"down"];
    if (![down[@"ok"] boolValue]) return down;
    [NSThread sleepForTimeInterval:0.05];
    NSDictionary *up = [self hardwareKey:key action:@"up"];
    return TLinkautoJSResultByAdding(up, @{ @"down": down });
}

- (NSDictionary *)keepAwake:(BOOL)enabled
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    return [self runTask:TASK_KEEP_AWAKE payload:(enabled ? @"1" : @"0")];
}

- (NSDictionary *)touchIndicator:(NSString *)action
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    int value = TLinkautoJSTouchIndicatorAction(action);
    if (value < 0) {
        [self.runtime throwError:@"touchIndicator(action) supports show/hide/reload"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_TOUCH_INDICATOR payload:[NSString stringWithFormat:@"%d", value]];
}

- (NSDictionary *)pathTask:(int)task key:(NSString *)key
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *result = [self runTask:task payload:@""];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    NSString *path = TLinkautoJSSafeStringPart(parts, 1);
    NSMutableDictionary *extra = [NSMutableDictionary dictionaryWithObject:path forKey:@"path"];
    extra[key ?: @"path"] = path;
    return TLinkautoJSResultByAdding(result, extra);
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
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(command)) {
        [self.runtime throwError:@"runShell(command) requires a non-empty single-line command"];
        return @{ @"ok": @NO };
    }
    // Optional timeout: prepend "timeout;;" only when a finite positive value is given.
    // The command itself can never contain ";;" (rejected above), so the first ";;"
    // is unambiguously the separator parsed by the Task.xm handler.
    NSString *payload = command;
    if (TLinkautoJSIsFiniteNumber(timeoutSeconds) && timeoutSeconds > 0) {
        payload = [NSString stringWithFormat:@"%.3f;;%@", timeoutSeconds, command];
    }
    NSDictionary *result = [self runTask:TASK_RUN_SHELL payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    NSArray *outputParts = [parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)];
    NSString *output = [[outputParts componentsJoinedByString:@";;"] stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
    output = [output stringByReplacingOccurrencesOfString:@"\\r" withString:@"\r"];
    return TLinkautoJSResultByAdding(result, @{ @"output": output ?: @"" });
}

- (NSDictionary *)info
{
    NSDictionary *result = [self runTask:TASK_GET_DEVICE_INFO payload:@"30"];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 6) return result;
    return TLinkautoJSResultByAdding(result, @{
        @"name": TLinkautoJSSafeStringPart(parts, 1),
        @"systemName": TLinkautoJSSafeStringPart(parts, 2),
        @"systemVersion": TLinkautoJSSafeStringPart(parts, 3),
        @"model": TLinkautoJSSafeStringPart(parts, 4),
        @"identifierForVendor": TLinkautoJSSafeStringPart(parts, 5),
    });
}

- (NSDictionary *)batteryInfo
{
    NSDictionary *result = [self runTask:TASK_GET_DEVICE_INFO payload:@"31"];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 3) return result;
    return TLinkautoJSResultByAdding(result, @{
        @"state": @([TLinkautoJSSafeStringPart(parts, 1) intValue]),
        @"level": @([TLinkautoJSSafeStringPart(parts, 2) doubleValue]),
    });
}

- (NSDictionary *)saveScreenshotToAlbum:(NSString *)path
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(path)) {
        [self.runtime throwError:@"saveScreenshotToAlbum(path) requires a valid path"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_SCREENSHOT payload:[NSString stringWithFormat:@"2;;%@", path]];
}

- (NSDictionary *)clearScreenshotAlbum
{
    return [self runTask:TASK_SCREENSHOT payload:@"3"];
}

- (NSDictionary *)matchTemplate:(NSString *)path options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(path)) {
        [self.runtime throwError:@"matchTemplate(path, options) requires a valid template path"];
        return @{ @"ok": @NO };
    }
    int maxTryTimes = TLinkautoJSIntOption(options, @"maxTryTimes", 2);
    double acceptable = TLinkautoJSDoubleOption(options, @"acceptable", 0.8);
    double scaleRatio = TLinkautoJSDoubleOption(options, @"scaleRatio", 0.8);
    NSString *payload = [NSString stringWithFormat:@"%@;;%d;;%.4f;;%.4f", path, maxTryTimes, acceptable, scaleRatio];
    NSDictionary *result = [self runTask:TASK_TEMPLATE_MATCH payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 5) return result;
    double x = [TLinkautoJSSafeStringPart(parts, 1) doubleValue];
    double y = [TLinkautoJSSafeStringPart(parts, 2) doubleValue];
    double width = [TLinkautoJSSafeStringPart(parts, 3) doubleValue];
    double height = [TLinkautoJSSafeStringPart(parts, 4) doubleValue];
    return TLinkautoJSResultByAdding(result, @{
        @"matched": @(width > 0 && height > 0),
        @"x": @(x),
        @"y": @(y),
        @"width": @(width),
        @"height": @(height),
        @"centerX": @(x + width / 2.0),
        @"centerY": @(y + height / 2.0),
    });
}

- (NSDictionary *)findColor:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);
    int redMin = TLinkautoJSIntOption(options, @"redMin", TLinkautoJSIntOption(options, @"rMin", 0));
    int redMax = TLinkautoJSIntOption(options, @"redMax", TLinkautoJSIntOption(options, @"rMax", 255));
    int greenMin = TLinkautoJSIntOption(options, @"greenMin", TLinkautoJSIntOption(options, @"gMin", 0));
    int greenMax = TLinkautoJSIntOption(options, @"greenMax", TLinkautoJSIntOption(options, @"gMax", 255));
    int blueMin = TLinkautoJSIntOption(options, @"blueMin", TLinkautoJSIntOption(options, @"bMin", 0));
    int blueMax = TLinkautoJSIntOption(options, @"blueMax", TLinkautoJSIntOption(options, @"bMax", 255));
    int skip = TLinkautoJSIntOption(options, @"skip", 0);
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
        [self.runtime throwError:@"findColor(options) requires finite x/y/width/height"];
        return @{ @"ok": @NO };
    }
    NSString *payload = [NSString stringWithFormat:@"1;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d",
                         x, y, width, height, redMin, redMax, greenMin, greenMax, blueMin, blueMax, skip];
    NSDictionary *result = [self runTask:TASK_COLOR_SEARCHER payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 6) return result;
    int foundX = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    int foundY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
    return TLinkautoJSResultByAdding(result, @{
        @"matched": @(foundX >= 0 && foundY >= 0),
        @"x": @(foundX),
        @"y": @(foundY),
        @"red": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
        @"green": @([TLinkautoJSSafeStringPart(parts, 4) intValue]),
        @"blue": @([TLinkautoJSSafeStringPart(parts, 5) intValue]),
    });
}

- (NSDictionary *)isColors:(NSArray *)points options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *table = TLinkautoJSEncodePointColorTable(points);
    if (!table) {
        [self.runtime throwError:@"isColors(points, options) requires 1-512 point colors"];
        return @{ @"ok": @NO };
    }
    int mode = TLinkautoJSIntOption(options, @"mode", 1);
    double value = TLinkautoJSDoubleOption(options, @"value", TLinkautoJSDoubleOption(options, @"tolerance", 0));
    NSDictionary *result = [self runTask:TASK_COLOR_SEARCHER payload:[NSString stringWithFormat:@"2;;%@;;%d;;%.4f", table, mode, value]];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    BOOL matched = [TLinkautoJSSafeStringPart(parts, 1) intValue] != 0;
    return TLinkautoJSResultByAdding(result, @{ @"matched": @(matched), @"value": @(matched) });
}

- (NSDictionary *)findMultiColor:(NSArray *)points options:(NSDictionary *)options
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSString *table = TLinkautoJSEncodePointColorTable(points);
    if (!table) {
        [self.runtime throwError:@"findMultiColor(points, options) requires 1-512 relative point colors"];
        return @{ @"ok": @NO };
    }
    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);
    int mode = TLinkautoJSIntOption(options, @"mode", 1);
    double value = TLinkautoJSDoubleOption(options, @"value", TLinkautoJSDoubleOption(options, @"tolerance", 0));
    int skip = TLinkautoJSIntOption(options, @"skip", 0);
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
        [self.runtime throwError:@"findMultiColor(points, options) requires finite x/y/width/height"];
        return @{ @"ok": @NO };
    }
    NSString *payload = [NSString stringWithFormat:@"3;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%.4f;;%d", x, y, width, height, table, mode, value, skip];
    NSDictionary *result = [self runTask:TASK_COLOR_SEARCHER payload:payload];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 3) return result;
    int foundX = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    int foundY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
    return TLinkautoJSResultByAdding(result, @{
        @"matched": @(foundX >= 0 && foundY >= 0),
        @"x": @(foundX),
        @"y": @(foundY),
    });
}

- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(name) || !TLinkautoJSValidProtocolString(script)) {
        [self.runtime throwError:@"setAutoLaunch(name, script, enabled) requires valid name and script path"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_SET_AUTO_LAUNCH payload:[NSString stringWithFormat:@"%@;;%@;;%d", name, script, enabled ? 1 : 0]];
}

- (NSDictionary *)listAutoLaunch
{
    NSDictionary *result = [self runTask:TASK_LIST_AUTO_LAUNCH payload:@""];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue]) return result;
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 1; i < [parts count]; i++) {
        NSString *entry = TLinkautoJSSafeStringPart(parts, i);
        if ([entry length] == 0) continue;
        NSArray *fields = [entry componentsSeparatedByString:@",,"];
        if ([fields count] >= 3) {
            [items addObject:@{
                @"name": TLinkautoJSSafeStringPart(fields, 0),
                @"script": TLinkautoJSSafeStringPart(fields, 1),
                @"enabled": @([TLinkautoJSSafeStringPart(fields, 2) intValue] != 0),
            }];
        }
    }
    return TLinkautoJSResultByAdding(result, @{ @"items": items });
}

- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(name) || !TLinkautoJSValidProtocolString(script) || !TLinkautoJSIsFiniteNumber(interval) || interval <= 0) {
        [self.runtime throwError:@"setTimer(name, interval, repeat, script) requires valid values"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_SET_TIMER payload:[NSString stringWithFormat:@"%@;;%.3f;;%d;;%@", name, interval, repeat ? 1 : 0, script]];
}

- (NSDictionary *)removeTimer:(NSString *)name
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    if (!TLinkautoJSValidProtocolString(name)) {
        [self.runtime throwError:@"removeTimer(name) requires a valid timer name"];
        return @{ @"ok": @NO };
    }
    return [self runTask:TASK_REMOVE_TIMER payload:name];
}

- (NSDictionary *)readText:(NSString *)path
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *resolved = [self.runtime bundleStoragePathForRelativePath:path createParent:NO];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *resolvedPath = resolved[@"path"];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:resolvedPath error:nil];
    if (!attrs) return @{ @"ok": @NO, @"error": @"file not found", @"path": resolvedPath ?: @"" };
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkautoJSMaxStorageFileBytes) {
        return @{ @"ok": @NO, @"error": @"file is too large", @"path": resolvedPath ?: @"" };
    }
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:resolvedPath encoding:NSUTF8StringEncoding error:&error];
    if (!text) return @{ @"ok": @NO, @"error": error.localizedDescription ?: @"failed to read file", @"path": resolvedPath ?: @"" };
    return @{ @"ok": @YES, @"path": resolvedPath ?: @"", @"text": text };
}

- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *resolved = [self.runtime bundleStoragePathForRelativePath:path createParent:YES];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *safeText = [text isKindOfClass:[NSString class]] ? text : [text description];
    safeText = safeText ?: @"";
    NSData *data = [safeText dataUsingEncoding:NSUTF8StringEncoding];
    if ([data length] > kTLinkautoJSMaxStorageFileBytes) {
        return @{ @"ok": @NO, @"error": @"text is too large", @"path": resolved[@"path"] ?: @"" };
    }
    NSError *error = nil;
    BOOL ok = [safeText writeToFile:resolved[@"path"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!ok) return @{ @"ok": @NO, @"error": error.localizedDescription ?: @"failed to write file", @"path": resolved[@"path"] ?: @"" };
    return @{ @"ok": @YES, @"path": resolved[@"path"] ?: @"", @"bytes": @([data length]) };
}

- (NSDictionary *)readJSON:(NSString *)path
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *textResult = [self readText:path];
    if (![textResult[@"ok"] boolValue]) return textResult;
    NSData *data = [textResult[@"text"] dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    if (!value) return @{ @"ok": @NO, @"error": error.localizedDescription ?: @"failed to parse JSON", @"path": textResult[@"path"] ?: @"" };
    return @{ @"ok": @YES, @"path": textResult[@"path"] ?: @"", @"value": value };
}

- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    id object = [value isKindOfClass:[JSValue class]] ? [value toObject] : value;
    if (!object || ![NSJSONSerialization isValidJSONObject:object]) {
        [self.runtime throwError:@"writeJSON(path, value) requires a JSON-serializable object or array"];
        return @{ @"ok": @NO };
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!data) return @{ @"ok": @NO, @"error": error.localizedDescription ?: @"failed to encode JSON" };
    if ([data length] > kTLinkautoJSMaxStorageFileBytes) return @{ @"ok": @NO, @"error": @"JSON is too large" };
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
    return [self writeText:path text:text];
}

- (NSDictionary *)fileExists:(NSString *)path
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *resolved = [self.runtime bundleStoragePathForRelativePath:path createParent:NO];
    if (![resolved[@"ok"] boolValue]) return resolved;
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:resolved[@"path"] isDirectory:&isDir];
    return @{ @"ok": @YES, @"path": resolved[@"path"] ?: @"", @"exists": @(exists), @"directory": @(exists && isDir) };
}

- (NSDictionary *)deleteFile:(NSString *)path
{
    // PHASE0_BRIDGE_TODO: migrate this typed API to TLinkJSNativeBridge.
    NSDictionary *resolved = [self.runtime bundleStoragePathForRelativePath:path createParent:NO];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *resolvedPath = resolved[@"path"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
        return @{ @"ok": @YES, @"path": resolvedPath ?: @"", @"deleted": @NO };
    }
    NSError *error = nil;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:resolvedPath error:&error];
    if (!ok) return @{ @"ok": @NO, @"error": error.localizedDescription ?: @"failed to delete file", @"path": resolvedPath ?: @"" };
    return @{ @"ok": @YES, @"path": resolvedPath ?: @"", @"deleted": @YES };
}

- (NSDictionary *)getScreenSize
{
    return [self.runtime executeNativeRequest:@"getScreenSize" arguments:@[]];
}

- (NSDictionary *)runtimeInfo
{
    BOOL watchdog = [self.runtime watchdogAvailable];
    NSDictionary *manifest = [self.runtime currentManifest];
    return @{
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
        @"runId": self.runtime.runId ?: @"",
        @"consoleLogPath": [self.runtime currentConsoleLogPath] ?: @"",
        @"consoleLatestLogPath": [self.runtime currentConsoleLatestLogPath] ?: @"",
    };
}

@end
