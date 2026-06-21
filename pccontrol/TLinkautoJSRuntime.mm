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
- (NSDictionary *)getScreenSize;
- (NSDictionary *)runtimeInfo;

@end

@interface TLinkautoDeviceBridge : NSObject <TLinkautoDeviceJSExport>
@property(nonatomic, weak) TLinkautoJSRuntime *runtime;
@end

struct TLinkautoJSCancelState {
    std::atomic<bool> aborted;
};

@interface TLinkautoJSRuntime ()
{
    TLinkautoJSCancelState *_cancelState;
    NSCondition *_sleepCondition;
    BOOL _running;
    NSString *_runId;
    JSContext *_context;
    TLinkautoJSSetExecutionTimeLimitFn _setExecutionTimeLimit;
    TLinkautoJSClearExecutionTimeLimitFn _clearExecutionTimeLimit;
    BOOL _watchdogAvailable;
}
- (BOOL)watchdogAvailable;
@end

static bool TLinkautoJSShouldTerminate(JSContextRef ctx, void *opaque)
{
    (void)ctx;
    TLinkautoJSCancelState *state = (TLinkautoJSCancelState *)opaque;
    return state && state->aborted.load(std::memory_order_acquire);
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
        _watchdogAvailable = _setExecutionTimeLimit && _clearExecutionTimeLimit;
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
    (void)bundlePath;
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

    void (^logBlock)(NSString *) = ^(NSString *message) {
        NSLog(@"com.tlinkauto.jsruntime[%@]: %@", weakSelf.runId ?: @"", message ?: @"");
    };
    context[@"console"] = @{
        @"log": ^(JSValue *value) { logBlock([value toString]); },
        @"info": ^(JSValue *value) { logBlock([value toString]); },
        @"warn": ^(JSValue *value) { logBlock([NSString stringWithFormat:@"WARN: %@", [value toString]]); },
        @"error": ^(JSValue *value) { logBlock([NSString stringWithFormat:@"ERROR: %@", [value toString]]); },
    };

    [self installWatchdogForContext:context];
    NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath ?: @"script.js"];
    [context evaluateScript:script withSourceURL:sourceURL];
    [self clearWatchdogForContext:context];

    BOOL success = !context.exception && ![self isAborted];
    if (!success && error) {
        NSString *message = context.exception ? [context.exception toString] : @"JavaScript execution was stopped";
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n", message ?: @"JavaScript error"]}];
    }

    _context = nil;
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
        @"hardJsCancellation": @(watchdog),
        @"cooperativeCancellation": @YES,
        @"runId": self.runtime.runId ?: @"",
    };
}

@end
