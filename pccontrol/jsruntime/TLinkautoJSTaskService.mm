#import "TLinkautoJSTaskService.h"
#import "ipc/TLinkautoJSIPCConnection.h"
#import "TLinkautoJSLegacyTaskAdapter.h"
#import <os/lock.h>

@interface TLinkautoJSTaskService () <TLinkautoJSIPCConnectionDelegate>
@end

@implementation TLinkautoJSTaskService {
    TLinkautoJSIPCConnection *_connection;
    TLinkautoJSLegacyTaskAdapter *_legacyAdapter;
    os_unfair_lock _lock;
    uint64_t _activeRunId;
    uint64_t _activeGeneration;
    BOOL _daemonConnected;
    BOOL _isRunning;
    BOOL _lastRunSuccess;
    NSString *_lastRunError;
    NSCondition *_runCondition;
}

+ (instancetype)sharedService {
    static TLinkautoJSTaskService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[TLinkautoJSTaskService alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _legacyAdapter = [[TLinkautoJSLegacyTaskAdapter alloc] initWithExecution:nil]; // Dummy execution for now
        _connection = [[TLinkautoJSIPCConnection alloc] initWithSocketFile:@"/var/mobile/Library/TLinkauto/run/jsruntime.sock" isServer:NO];
        _connection.delegate = self;
        _runCondition = [[NSCondition alloc] init];
    }
    return self;
}

- (void)startService {
    [_connection start];
}

- (void)stopService {
    [_connection stop];
    os_unfair_lock_lock(&_lock);
    _isRunning = NO;
    [_runCondition broadcast];
    os_unfair_lock_unlock(&_lock);
}

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest error:(NSError **)error {
    os_unfair_lock_lock(&_lock);
    if (!_daemonConnected) {
        os_unfair_lock_unlock(&_lock);
        if (error) *error = [NSError errorWithDomain:@"TLinkautoJSTaskService" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Daemon is not connected"}];
        return NO;
    }
    _activeGeneration++;
    uint64_t gen = _activeGeneration;
    _activeRunId = gen;
    os_unfair_lock_unlock(&_lock);

    NSDictionary *payload = @{
        @"scriptPath": scriptPath ?: @"",
        @"bundlePath": bundlePath ?: @"",
        @"manifest": manifest ?: @{}
    };

    [_connection sendMessageWithType:TLJS_MSG_START_RUN
                           requestId:0
                               runId:gen
                          generation:gen
                             timeout:5000
                             payload:payload];

    os_unfair_lock_lock(&_lock);
    _isRunning = YES;
    while (_isRunning) {
        [_runCondition wait];
    }
    BOOL success = _lastRunSuccess;
    if (!success && error) {
        *error = [NSError errorWithDomain:@"TLinkautoJSTaskService" code:1 userInfo:@{NSLocalizedDescriptionKey: _lastRunError ?: @"Script execution failed"}];
    }
    os_unfair_lock_unlock(&_lock);

    return success;
}

- (void)requestStop {
    os_unfair_lock_lock(&_lock);
    uint64_t run = _activeRunId;
    uint64_t gen = _activeGeneration;
    os_unfair_lock_unlock(&_lock);

    [_connection sendMessageWithType:TLJS_MSG_STOP_RUN
                           requestId:0
                               runId:run
                          generation:gen
                             timeout:5000
                             payload:@{}];
}

- (void)connectionDidReceiveMessage:(TLinkautoJSIPCHeader)header payload:(NSDictionary *)payload {
    if (header.messageType == TLJS_MSG_HELLO) {
        os_unfair_lock_lock(&_lock);
        _daemonConnected = YES;
        os_unfair_lock_unlock(&_lock);
    }
    else if (header.messageType == TLJS_MSG_TASK_REQUEST) {
        [self handleTaskRequest:header payload:payload];
    }
    else if (header.messageType == TLJS_MSG_RUN_FINISHED) {
        os_unfair_lock_lock(&_lock);
        _isRunning = NO;
        _lastRunSuccess = [payload[@"ok"] boolValue];
        _lastRunError = payload[@"error"];
        [_runCondition broadcast];
        os_unfair_lock_unlock(&_lock);
    }
}

- (void)handleTaskRequest:(TLinkautoJSIPCHeader)header payload:(NSDictionary *)payload {
    NSString *taskName = payload[@"taskName"];
    NSDictionary *taskPayload = payload[@"payload"];

    NSDictionary *result = [_legacyAdapter dispatchLegacyTask:taskName payload:taskPayload];

    [_connection sendMessageWithType:TLJS_MSG_TASK_RESPONSE
                           requestId:header.requestId
                               runId:header.runId
                          generation:header.generation
                             timeout:header.timeoutMs
                             payload:result ?: @{}];
}

- (void)connectionDidDisconnect {
    os_unfair_lock_lock(&_lock);
    _daemonConnected = NO;
    _isRunning = NO;
    [_runCondition broadcast];
    os_unfair_lock_unlock(&_lock);
}

@end
