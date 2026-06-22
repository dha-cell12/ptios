#import "TLinkautoJSRuntime.h"

#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <atomic>
#include <dlfcn.h>
#include <math.h>

#include "Task.h"
#include "Screen.h"
#include "RuntimeUtils.h"

typedef bool (*TLinkautoJSShouldTerminateCallback)(JSContextRef ctx, void *opaque);
typedef void (*TLinkautoJSSetExecutionTimeLimitFn)(JSContextGroupRef group, double limit, TLinkautoJSShouldTerminateCallback callback, void *opaque);
typedef void (*TLinkautoJSClearExecutionTimeLimitFn)(JSContextGroupRef group);

static const double kTLinkautoJSWatchdogInterval = 0.1;
static const NSUInteger kTLinkautoJSMaxResponseBytes = 1024 * 1024;

@class TLinkautoJSRuntime;

@protocol TLinkautoDeviceJSExport <JSExport>

JSExportAs(tap,
- (NSDictionary *)tap:(double)x y:(double)y);
JSExportAs(swipe,
- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration);
JSExportAs(runTask,
- (NSDictionary *)runTask:(int)task payload:(NSString *)payload);
JSExportAs(pickColor,
- (NSDictionary *)pickColor:(double)x y:(double)y);
JSExportAs(screenshotTo,
- (NSDictionary *)screenshotTo:(NSString *)path);
JSExportAs(batch,
- (NSDictionary *)batch:(NSArray *)commands);
- (NSDictionary *)getScreenSize;
- (NSDictionary *)screenshot;
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
    TLinkautoJSCancelState *_cancelState;
    NSCondition *_sleepCondition;
    BOOL _running;
    NSString *_runId;
    NSString *_bundlePath;
    JSContext *_context;
    TLinkautoJSSetExecutionTimeLimitFn _setExecutionTimeLimit;
    TLinkautoJSClearExecutionTimeLimitFn _clearExecutionTimeLimit;
    BOOL _watchdogAvailable;
}
- (BOOL)watchdogAvailable;
- (NSString *)currentBundlePath;
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

@implementation TLinkautoJSRuntime

- (instancetype)init
{
    self = [super init];
    if (self) {
        _cancelState = new TLinkautoJSCancelState();
        _cancelState->aborted.store(false, std::memory_order_release);
        _sleepCondition = [[NSCondition alloc] init];
        _setExecutionTimeLimit = (TLinkautoJSSetExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
        _clearExecutionTimeLimit = (TLinkautoJSClearExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
        _watchdogAvailable = TLinkautoJSWatchdogCapability(_setExecutionTimeLimit, _clearExecutionTimeLimit);
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

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath error:(NSError **)error
{
    if (_running) {
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;JavaScript runtime is busy.\r\n"}];
        return NO;
    }

    NSString *script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:error];
    if (!script) {
        return NO;
    }

    _running = YES;
    _runId = [[NSUUID UUID] UUIDString];
    _bundlePath = [bundlePath copy];
    _cancelState->aborted.store(false, std::memory_order_release);

    JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
    JSContext *context = [[JSContext alloc] initWithVirtualMachine:vm];
    _context = context;

    __weak TLinkautoJSRuntime *weakSelf = self;
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        NSLog(@"com.tlinkauto.jsruntime: exception: %@", exception);
        ctx.exception = exception;
        TLinkautoJSRuntime *strongSelf = weakSelf;
        if (strongSelf) {
            setLastScriptError([exception toString] ?: @"JavaScript exception");
        }
    };

    TLinkautoDeviceBridge *bridge = [[TLinkautoDeviceBridge alloc] init];
    bridge.runtime = self;
    context[@"device"] = bridge;

    context[@"sleep"] = ^(double ms) {
        TLinkautoJSRuntime *strongSelf = weakSelf;
        if (strongSelf) [strongSelf interruptibleSleepMs:ms];
    };

    void (^logBlock)(NSString *, NSString *) = ^(NSString *level, NSString *message) {
        NSLog(@"com.tlinkauto.jsruntime[%@][%@]: %@", weakSelf.runId ?: @"", level ?: @"log", message ?: @"");
    };
    context[@"_tlinkautoLog"] = ^(NSString *level, NSString *message) {
        logBlock(level, message);
    };
    NSString *consolePrelude =
        @"(function(){\n"
         "  function fmt(args){ return Array.prototype.map.call(args, function(v){\n"
         "    try { if (typeof v === 'string') return v; return JSON.stringify(v); }\n"
         "    catch(e) { return String(v); }\n"
         "  }).join(' '); }\n"
         "  this.console = {\n"
         "    log: function(){ _tlinkautoLog('log', fmt(arguments)); },\n"
         "    info: function(){ _tlinkautoLog('info', fmt(arguments)); },\n"
         "    warn: function(){ _tlinkautoLog('warn', fmt(arguments)); },\n"
         "    error: function(){ _tlinkautoLog('error', fmt(arguments)); }\n"
         "  };\n"
         "})();";

    [self installWatchdogForContext:context];
    [context evaluateScript:consolePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://console-prelude.js"]];
    NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath ?: @"script.js"];
    [context evaluateScript:script withSourceURL:sourceURL];
    [self clearWatchdogForContext:context];

    BOOL success = !context.exception && ![self isAborted];
    if (!success && error) {
        NSString *message = context.exception ? [context.exception toString] : @"JavaScript execution was stopped";
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n", message ?: @"JavaScript error"]}];
    }

    _context = nil;
    _bundlePath = nil;
    _running = NO;
    return success;
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

- (NSDictionary *)tap:(double)x y:(double)y
{
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
        [self.runtime throwError:@"tap(x, y) requires finite numbers"];
        return @{ @"ok": @NO };
    }
    NSString *payload = [NSString stringWithFormat:@"%.2f;;%.2f", x, y];
    return [self runTask:TASK_NATIVE_TAP payload:payload];
}

- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration
{
    if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) ||
        !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) ||
        !TLinkautoJSIsFiniteNumber(duration)) {
        [self.runtime throwError:@"swipe(...) requires finite numbers"];
        return @{ @"ok": @NO };
    }
    if (duration < 0) duration = 0;
    if (duration > 60000) duration = 60000;
    NSString *payload = [NSString stringWithFormat:@"%.2f;;%.2f;;%.2f;;%.2f;;%.0f", x1, y1, x2, y2, duration];
    return [self runTask:TASK_NATIVE_SWIPE payload:payload];
}

- (NSDictionary *)pickColor:(double)x y:(double)y
{
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
        } else {
            [self.runtime throwError:[NSString stringWithFormat:@"unsupported batch command type: %@", type ?: @""]];
            return @{ @"ok": @NO };
        }
    }

    NSString *payload = [wireCommands componentsJoinedByString:@"||"];
    return [self runTask:TASK_NATIVE_BATCH payload:payload];
}

- (NSDictionary *)getScreenSize
{
    CGFloat width = [Screen getScreenWidth];
    CGFloat height = [Screen getScreenHeight];
    CGFloat scale = [UIScreen mainScreen].scale;
    int orientation = [Screen getScreenOrientation];
    return @{
        @"width": @((int)width),
        @"height": @((int)height),
        @"scale": @(scale),
        @"orientation": @(orientation),
        @"coordinateSpace": @"native-pixels",
        @"revision": @0,
    };
}

- (NSDictionary *)runtimeInfo
{
    BOOL watchdog = [self.runtime watchdogAvailable];
    return @{
        @"engine": @"JavaScriptCore",
        @"apiVersion": @1,
        @"jit": @"unknown",
        @"watchdog": watchdog ? @"private-api" : @"unavailable",
        @"watchdogIntervalMs": @(watchdog ? (int)(kTLinkautoJSWatchdogInterval * 1000.0) : 0),
        @"hardJsCancellation": @(watchdog),
        @"cooperativeCancellation": @YES,
        @"runtimeLocation": @"in-process-prototype",
        @"runId": self.runtime.runId ?: @"",
    };
}

@end
