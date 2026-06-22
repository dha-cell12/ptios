#import "TLinkautoJSIPCTaskDispatcher.h"
#import <os/lock.h>

@interface TLinkautoJSPendingTask : NSObject
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, strong) NSDictionary *response;
@property (nonatomic, assign) BOOL finished;
@end
@implementation TLinkautoJSPendingTask
@end

@implementation TLinkautoJSIPCTaskDispatcher {
    TLinkautoJSIPCConnection *_connection;
    uint64_t _runId;
    uint64_t _generation;
    uint64_t _nextRequestId;
    NSMutableDictionary<NSNumber *, TLinkautoJSPendingTask *> *_pendingTasks;
    os_unfair_lock _lock;
}

- (instancetype)initWithConnection:(TLinkautoJSIPCConnection *)connection runId:(uint64_t)runId generation:(uint64_t)generation {
    self = [super init];
    if (self) {
        _connection = connection;
        _runId = runId;
        _generation = generation;
        _nextRequestId = 1;
        _pendingTasks = [NSMutableDictionary dictionary];
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (void)handleResponsePayload:(NSDictionary *)payload forRequestId:(uint64_t)requestId {
    os_unfair_lock_lock(&_lock);
    TLinkautoJSPendingTask *task = _pendingTasks[@(requestId)];
    os_unfair_lock_unlock(&_lock);

    if (task) {
        [task.condition lock];
        task.response = payload;
        task.finished = YES;
        [task.condition signal];
        [task.condition unlock];
    }
}

- (NSDictionary *)dispatchTask:(NSString *)taskName payload:(NSDictionary *)payload {
    os_unfair_lock_lock(&_lock);
    uint64_t reqId = _nextRequestId++;
    TLinkautoJSPendingTask *task = [[TLinkautoJSPendingTask alloc] init];
    task.condition = [[NSCondition alloc] init];
    task.finished = NO;
    _pendingTasks[@(reqId)] = task;
    os_unfair_lock_unlock(&_lock);

    BOOL sent = [_connection sendMessageWithType:TLJS_MSG_TASK_REQUEST
                                       requestId:reqId
                                           runId:_runId
                                      generation:_generation
                                         timeout:5000 // 5s timeout default
                                         payload:@{@"taskName": taskName ?: @"", @"payload": payload ?: @{}}];
    if (!sent) {
        os_unfair_lock_lock(&_lock);
        [_pendingTasks removeObjectForKey:@(reqId)];
        os_unfair_lock_unlock(&_lock);
        return @{@"ok": @NO, @"error": @"ipc send failed"};
    }

    [task.condition lock];
    while (!task.finished) {
        // Wait for response from io queue
        [task.condition wait];
    }
    [task.condition unlock];

    os_unfair_lock_lock(&_lock);
    [_pendingTasks removeObjectForKey:@(reqId)];
    os_unfair_lock_unlock(&_lock);

    return task.response ?: @{@"ok": @NO, @"error": @"empty ipc response"};
}

@end
