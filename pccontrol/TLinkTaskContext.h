#ifndef TLINK_TASK_CONTEXT_H
#define TLINK_TASK_CONTEXT_H

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
#include <atomic>
#endif

// --- Cancellation Token ---
@interface TLinkCancellationToken : NSObject
- (void)cancel;
- (BOOL)isCancelled;
@end

// --- Task Execution Context ---
@interface TLinkTaskExecutionContext : NSObject
@property (nonatomic, strong) TLinkCancellationToken *cancellationToken;
@property (nonatomic, assign) NSTimeInterval defaultTimeoutSeconds;
@property (nonatomic, assign) NSUInteger defaultMaxOutputBytes;
@property (nonatomic, copy) NSString *ownerSessionId;
@property (nonatomic, copy) NSString *ownerRunId;
@property (nonatomic, copy) NSString *ownerRuntime;
// Synchronous observer of successful injections; RAW session cleanup uses it on its worker.
@property (nonatomic, copy) void (^didInjectTouchPayload)(const uint8_t *bytes, size_t length);
@end

// --- Script Session ---
@interface TLinkScriptSession : NSObject
@property (nonatomic, assign) uint64_t generation;
@property (nonatomic, strong) TLinkCancellationToken *cancellationToken;
@property (nonatomic, strong) TLinkTaskExecutionContext *taskContext;
@end

#endif /* TLINK_TASK_CONTEXT_H */
