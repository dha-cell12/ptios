#ifndef TLINKAUTO_JS_CANCELLATION_TOKEN_H
#define TLINKAUTO_JS_CANCELLATION_TOKEN_H

#import <Foundation/Foundation.h>
#include <atomic>

// From original _cancelState struct
struct TLinkautoJSCancelState {
    std::atomic<bool> aborted;
};

@interface TLinkautoJSCancellationToken : NSObject

@property (nonatomic, readonly) BOOL isCancelled;

- (void)cancel;
- (struct TLinkautoJSCancelState *)cancelState;

@end

#endif
