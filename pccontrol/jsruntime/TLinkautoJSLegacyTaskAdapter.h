#ifndef TLINKAUTO_JS_LEGACY_TASK_ADAPTER_H
#define TLINKAUTO_JS_LEGACY_TASK_ADAPTER_H

#import <Foundation/Foundation.h>

@protocol TLinkautoJSTaskContext <NSObject>
@property (nonatomic, readonly) uint64_t runId;
@property (nonatomic, readonly) uint64_t generation;
- (BOOL)isCancelled;
@end

@interface TLinkautoJSLegacyTaskAdapter : NSObject

- (instancetype)initWithTaskContext:(id<TLinkautoJSTaskContext>)context;
- (void)setTaskContext:(id<TLinkautoJSTaskContext>)context;
- (NSDictionary *)dispatchLegacyTask:(NSString *)taskName payload:(NSDictionary *)payload;

@end

#endif /* TLINKAUTO_JS_LEGACY_TASK_ADAPTER_H */
