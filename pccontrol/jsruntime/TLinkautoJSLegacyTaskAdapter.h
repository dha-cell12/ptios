#ifndef TLINKAUTO_JS_LEGACY_TASK_ADAPTER_H
#define TLINKAUTO_JS_LEGACY_TASK_ADAPTER_H

#import <Foundation/Foundation.h>

@class TLinkautoJSRuntimeExecution;

@interface TLinkautoJSLegacyTaskAdapter : NSObject

- (instancetype)initWithExecution:(TLinkautoJSRuntimeExecution *)execution;
- (void)setExecution:(TLinkautoJSRuntimeExecution *)execution;
- (NSDictionary *)dispatchLegacyTask:(NSString *)taskName payload:(NSDictionary *)payload;

@end

#endif /* TLINKAUTO_JS_LEGACY_TASK_ADAPTER_H */
