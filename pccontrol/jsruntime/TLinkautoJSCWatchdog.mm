#import "TLinkautoJSCWatchdog.h"
#include <dlfcn.h>

typedef bool (*TLinkautoJSShouldTerminateCallback)(JSContextRef ctx, void *opaque);
typedef void (*TLinkautoJSSetExecutionTimeLimitFn)(JSContextGroupRef group, double limit, TLinkautoJSShouldTerminateCallback callback, void *opaque);
typedef void (*TLinkautoJSClearExecutionTimeLimitFn)(JSContextGroupRef group);

static const double kTLinkautoJSWatchdogInterval = 0.1;

struct TLinkautoJSWatchdogProbeState {
    std::atomic<int> callbacks;
};

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

static bool TLinkautoJSShouldTerminate(JSContextRef ctx, void *opaque)
{
    (void)ctx;
    TLinkautoJSCancelState *state = (TLinkautoJSCancelState *)opaque;
    return state && state->aborted.load(std::memory_order_acquire);
}

@implementation TLinkautoJSCWatchdog {
    TLinkautoJSCancellationToken *_token;
    TLinkautoJSSetExecutionTimeLimitFn _setLimit;
    TLinkautoJSClearExecutionTimeLimitFn _clearLimit;
    BOOL _available;
}

- (instancetype)initWithToken:(TLinkautoJSCancellationToken *)token {
    self = [super init];
    if (self) {
        _token = token;
        _setLimit = (TLinkautoJSSetExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
        _clearLimit = (TLinkautoJSClearExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
        _available = TLinkautoJSWatchdogCapability(_setLimit, _clearLimit);
    }
    return self;
}

- (BOOL)isAvailable {
    return _available;
}

- (void)installForContext:(JSContext *)context {
    if (!_available || !context) return;
    JSContextRef ctx = [context JSGlobalContextRef];
    JSContextGroupRef group = JSContextGetGroup(ctx);
    _setLimit(group, kTLinkautoJSWatchdogInterval, TLinkautoJSShouldTerminate, [_token cancelState]);
}

- (void)clearForContext:(JSContext *)context {
    if (!_available || !context) return;
    JSContextRef ctx = [context JSGlobalContextRef];
    JSContextGroupRef group = JSContextGetGroup(ctx);
    _clearLimit(group);
}

@end
