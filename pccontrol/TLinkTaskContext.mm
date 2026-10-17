#import "TLinkTaskContext.h"
#include <cmath>

// Cancellation ownership is shared by native-call budgets; cancel also wakes active waits.
@implementation TLinkCancellationToken {
    std::shared_ptr<TLinkNativeCancellation> _nativeCancellation;
}
- (instancetype)init {
    self = [super init];
    if (self) _nativeCancellation = std::make_shared<TLinkNativeCancellation>();
    return self;
}
- (void)cancel { _nativeCancellation->cancel(); }
- (BOOL)isCancelled { return _nativeCancellation->cancelled(); }
- (std::shared_ptr<TLinkNativeCancellation>)nativeCancellation { return _nativeCancellation; }
@end

@implementation TLinkTaskExecutionContext {
    TLinkNativeBudgetPtr _nativeBudget;
}
- (TLinkNativeBudgetPtr)nativeBudget { return _nativeBudget; }
- (void)setNativeBudget:(TLinkNativeBudgetPtr)budget { _nativeBudget = std::move(budget); }
@end

TLinkNativeBudgetPtr TLinkTaskBudget(TLinkTaskExecutionContext *context) {
    if (!context) return TLinkCurrentNativeBudget();
    auto budget = [context nativeBudget];
    if (budget) return budget;
    auto token = context.cancellationToken;
    return std::make_shared<TLinkNativeBudget>(token ? [token nativeCancellation] : std::shared_ptr<TLinkNativeCancellation>{},
        TLinkNativeDeadline(context.defaultTimeoutSeconds), context.defaultMaxOutputBytes);
}
TLinkTaskExecutionContext *TLinkNativeCallContext(TLinkTaskExecutionContext *parent, BOOL cleanup, BOOL capture, double operationTimeout) {
    TLinkTaskExecutionContext *child = [[TLinkTaskExecutionContext alloc] init];
    child.cancellationToken = parent.cancellationToken;
    auto inherited = parent ? [parent nativeBudget] : TLinkNativeBudgetPtr{};
    // A nested wire dispatch inherits the typed operation's selected timeout (e.g. shell 120s).
    double requested = std::isfinite(operationTimeout) && operationTimeout > 0 ? MIN(operationTimeout, 300.0)
        : (inherited && std::isfinite(parent.defaultTimeoutSeconds) && parent.defaultTimeoutSeconds > 0 ? parent.defaultTimeoutSeconds : 30.0);
    child.defaultTimeoutSeconds = parent.defaultTimeoutSeconds > 0 && std::isfinite(parent.defaultTimeoutSeconds)
        ? MIN(parent.defaultTimeoutSeconds, requested) : requested;
    child.defaultMaxOutputBytes = parent.defaultMaxOutputBytes > 0 ? MIN(parent.defaultMaxOutputBytes, (NSUInteger)(1024 * 1024)) : 1024 * 1024;
    child.ownerSessionId = parent.ownerSessionId; child.ownerRunId = parent.ownerRunId; child.ownerRuntime = parent.ownerRuntime;
    child.didInjectTouchPayload = parent.didInjectTouchPayload;
    child.allowsAutomationForOwner = parent.allowsAutomationForOwner;
    uint64_t deadline = TLinkNativeDeadline(child.defaultTimeoutSeconds);
    if (inherited && inherited->deadline()) deadline = std::min(deadline, inherited->deadline());
    auto token = parent.cancellationToken;
    [child setNativeBudget:std::make_shared<TLinkNativeBudget>(token ? [token nativeCancellation] : std::shared_ptr<TLinkNativeCancellation>{},
        deadline, child.defaultMaxOutputBytes, cleanup, capture)];
    return child;
}

// --- Script Session ---
@implementation TLinkScriptSession
@end