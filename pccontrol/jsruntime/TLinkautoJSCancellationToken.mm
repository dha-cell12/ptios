#import "TLinkautoJSCancellationToken.h"

@implementation TLinkautoJSCancellationToken {
    struct TLinkautoJSCancelState *_state;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = new TLinkautoJSCancelState();
        _state->aborted.store(false, std::memory_order_release);
    }
    return self;
}

- (void)dealloc {
    if (_state) {
        delete _state;
        _state = nullptr;
    }
}

- (BOOL)isCancelled {
    return _state->aborted.load(std::memory_order_acquire);
}

- (void)cancel {
    _state->aborted.store(true, std::memory_order_release);
}

- (struct TLinkautoJSCancelState *)cancelState {
    return _state;
}

@end
