#ifndef TLINK_TASK_CONTEXT_H
#define TLINK_TASK_CONTEXT_H

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
#include "../shared/TLinkNativeBudget.h"
#endif

// --- Cancellation Token ---
@interface TLinkCancellationToken : NSObject
- (void)cancel;
- (BOOL)isCancelled;
#ifdef __cplusplus
- (std::shared_ptr<TLinkNativeCancellation>)nativeCancellation;
#endif
@end

// --- Task Execution Context ---
@interface TLinkTaskExecutionContext : NSObject
#ifdef __cplusplus
- (TLinkNativeBudgetPtr)nativeBudget;
- (void)setNativeBudget:(TLinkNativeBudgetPtr)budget;
#endif
@property (nonatomic, strong) TLinkCancellationToken *cancellationToken;
@property (nonatomic, assign) NSTimeInterval defaultTimeoutSeconds;
@property (nonatomic, assign) NSUInteger defaultMaxOutputBytes;
@property (nonatomic, copy) NSString *ownerSessionId;
@property (nonatomic, copy) NSString *ownerRunId;
@property (nonatomic, copy) NSString *ownerRuntime;
// Synchronous observer of successful injections; RAW session cleanup uses it on its worker.
@property (nonatomic, copy) void (^didInjectTouchPayload)(const uint8_t *bytes, size_t length);
@end

#ifdef __cplusplus
TLinkNativeBudgetPtr TLinkTaskBudget(TLinkTaskExecutionContext *context);
TLinkTaskExecutionContext *TLinkNativeCallContext(TLinkTaskExecutionContext *parent, BOOL cleanup, BOOL capture, double operationTimeout = 0);
#endif

// --- Script Session ---
@interface TLinkScriptSession : NSObject
@property (nonatomic, assign) uint64_t generation;
@property (nonatomic, strong) TLinkCancellationToken *cancellationToken;
@property (nonatomic, strong) TLinkTaskExecutionContext *taskContext;
@end

#endif /* TLINK_TASK_CONTEXT_H */
