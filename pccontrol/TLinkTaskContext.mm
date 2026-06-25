#import "TLinkTaskContext.h"

// --- Cancellation Token ---
@implementation TLinkCancellationToken {
    std::atomic_bool _cancelled;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cancelled.store(false, std::memory_order_relaxed);
    }
    return self;
}

- (void)cancel {
    _cancelled.store(true, std::memory_order_release);
}

- (BOOL)isCancelled {
    return _cancelled.load(std::memory_order_acquire) ? YES : NO;
}

@end

// --- Task Execution Context ---
@implementation TLinkTaskExecutionContext
@end

// --- Script Session ---
@implementation TLinkScriptSession
@end