#import "TLinkautoJSDirectTaskDispatcher.h"

@implementation TLinkautoJSDirectTaskDispatcher {
    TLinkautoJSLegacyTaskAdapter *_adapter;
}

- (instancetype)initWithAdapter:(TLinkautoJSLegacyTaskAdapter *)adapter {
    self = [super init];
    if (self) {
        _adapter = adapter;
    }
    return self;
}

- (NSDictionary *)dispatchTask:(NSString *)taskName payload:(NSDictionary *)payload {
    return [_adapter dispatchLegacyTask:taskName payload:payload];
}

@end
