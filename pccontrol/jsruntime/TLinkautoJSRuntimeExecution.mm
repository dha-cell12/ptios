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

@end
