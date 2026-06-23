#import "TLinkautoJSRuntimeExecution.h"
#import "TLinkautoJSBridge.h"
#import "../Task.h"
#import "../RuntimeUtils.h"

@implementation TLinkautoJSRuntimeExecution {
    TLinkautoJSCancellationToken *_cancellationToken;
    TLinkautoJSCWatchdog *_watchdog;
    JSVirtualMachine *_jsVirtualMachine;
    TLinkautoJSBridge *_bridge;
    NSString *_bundlePath;
    NSDictionary *_manifest;
}

- (instancetype)initWithRunId:(NSString *)runId
                   generation:(uint64_t)generation
                   bundlePath:(NSString *)bundlePath
                     manifest:(NSDictionary *)manifest
               taskDispatcher:(id<TLinkautoJSTaskDispatcher>)taskDispatcher {
    self = [super init];
    if (self) {
        _runId = [runId copy];
        _generation = generation;
        _bundlePath = [bundlePath copy];
        _manifest = [manifest copy];
        _taskDispatcher = taskDispatcher;

        _sleepCondition = [[NSCondition alloc] init];
        _cancellationToken = [[TLinkautoJSCancellationToken alloc] init];
        _watchdog = [[TLinkautoJSCWatchdog alloc] initWithToken:_cancellationToken];
        _logSink = [[TLinkautoJSFileLogSink alloc] initWithRunId:_runId bundlePath:_bundlePath];
        _handleRegistry = [[TLinkautoJSHandleRegistry alloc] init];

        _jsVirtualMachine = [[JSVirtualMachine alloc] init];
        _jsContext = [[JSContext alloc] initWithVirtualMachine:_jsVirtualMachine];

        _bridge = [[TLinkautoJSBridge alloc] initWithExecution:self];
        [_bridge injectIntoContext:_jsContext];
        __weak typeof(self) weakSelf = self;
        _jsContext[@"sleep"] = ^(double ms) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf interruptibleSleepMs:ms];
        };
    }
    return self;
}

- (BOOL)isAborted {
    return [_cancellationToken isCancelled];
}

- (void)requestStop {
    [_cancellationToken cancel];
    [_sleepCondition lock];
    [_sleepCondition broadcast];
    [_sleepCondition unlock];
}

- (void)evaluateScriptAtPath:(NSString *)scriptPath error:(NSError **)error {
    // Inject bridge and polyfills
    [_watchdog installForContext:_jsContext];

    // Evaluate script here...
    NSString *script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:error];
    if (script) {
        NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath];
        [_jsContext evaluateScript:script withSourceURL:sourceURL];
    }

    [_watchdog clearForContext:_jsContext];

    // Cleanup handles
    [_handleRegistry releaseAll];
    [_logSink close];
}



- (void)setAbortExceptionIfNeeded {
    if (![self isAborted] || !_jsContext) return;
    _jsContext.exception = [JSValue valueWithNewErrorFromMessage:@"JavaScript execution aborted" inContext:_jsContext];
}

- (BOOL)interruptibleSleepMs:(double)ms {
    if (ms < 0 || !isfinite(ms)) {
        if (_jsContext) _jsContext.exception = [JSValue valueWithNewErrorFromMessage:@"sleep(ms) requires a finite non-negative number" inContext:_jsContext];
        return NO;
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
@end
