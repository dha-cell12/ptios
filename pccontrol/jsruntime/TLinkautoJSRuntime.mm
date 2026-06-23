#import "TLinkautoJSRuntime.h"
#import "TLinkautoJSRuntimeExecution.h"
#import <os/lock.h>

@implementation TLinkautoJSRuntime {
    TLinkautoJSRuntimeExecution *_activeExecution;
    os_unfair_lock _lock;
    uint64_t _generationCounter;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _generationCounter = 0;
    }
    return self;
}

- (BOOL)running {
    os_unfair_lock_lock(&_lock);
    BOOL isRunning = _activeExecution != nil;
    os_unfair_lock_unlock(&_lock);
    return isRunning;
}

- (NSString *)runId {
    os_unfair_lock_lock(&_lock);
    NSString *rid = _activeExecution.runId;
    os_unfair_lock_unlock(&_lock);
    return rid;
}

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest taskDispatcher:(id<TLinkautoJSTaskDispatcher>)taskDispatcher error:(NSError **)error {
    os_unfair_lock_lock(&_lock);
    if (_activeExecution) {
        os_unfair_lock_unlock(&_lock);
        if (error) {
            *error = [NSError errorWithDomain:@"TLinkautoJSRuntime" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Another script is already running"}];
        }
        return NO;
    }

    _generationCounter++;
    NSString *newRunId = [[NSUUID UUID] UUIDString];

    _activeExecution = [[TLinkautoJSRuntimeExecution alloc] initWithRunId:newRunId
                                                               generation:_generationCounter
                                                               bundlePath:bundlePath
                                                                 manifest:manifest
                                                           taskDispatcher:taskDispatcher];

    os_unfair_lock_unlock(&_lock);

    NSError *evalError = nil;
    [_activeExecution evaluateScriptAtPath:scriptPath error:&evalError];

    os_unfair_lock_lock(&_lock);
    _activeExecution = nil;
    os_unfair_lock_unlock(&_lock);

    if (evalError) {
        if (error) {
            *error = evalError;
        }
        return NO;
    }

    return YES;
}

- (void)requestStop {
    os_unfair_lock_lock(&_lock);
    TLinkautoJSRuntimeExecution *exec = _activeExecution;
    os_unfair_lock_unlock(&_lock);

    if (exec) {
        [exec requestStop];
    }
}

@end
