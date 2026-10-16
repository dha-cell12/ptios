#ifndef TLINK_NATIVE_DISPATCH_H
#define TLINK_NATIVE_DISPATCH_H
#include "TLinkNativeBudget.h"
#import <dispatch/dispatch.h>
// Queue residence consumes the caller's existing deadline. Expired work is skipped when
// admitted; synchronous callers still wait for any previous non-cooperative owner operation.
static inline void TLinkNativeDispatchSync(dispatch_queue_t queue, dispatch_block_t operation) {
    auto budget = TLinkCurrentNativeBudget();
    dispatch_sync(queue, ^{
        TLinkNativeBudgetScope scope(budget);
        if (!TLinkNativeStopped()) operation();
    });
}
#endif
