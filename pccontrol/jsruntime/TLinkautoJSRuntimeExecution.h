#ifndef TLINKAUTO_JS_RUNTIME_EXECUTION_H
#define TLINKAUTO_JS_RUNTIME_EXECUTION_H

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "TLinkautoJSRuntimeTypes.h"
#import "TLinkautoJSCancellationToken.h"
#import "TLinkautoJSCWatchdog.h"
#import "TLinkautoJSLogSink.h"
#import "TLinkautoJSHandleRegistry.h"
#import "TLinkautoJSTaskDispatcher.h"

@interface TLinkautoJSRuntimeExecution : NSObject

@property (nonatomic, readonly) NSString *runId;
@property (nonatomic, readonly) uint64_t generation;
@property (nonatomic, readonly) NSCondition *sleepCondition;
@property (nonatomic, readonly) id<TLinkautoJSLogSink> logSink;
@property (nonatomic, readonly) TLinkautoJSHandleRegistry *handleRegistry;
@property (nonatomic, readonly) id<TLinkautoJSTaskDispatcher> taskDispatcher;
@property (nonatomic, readonly) JSContext *jsContext;

- (instancetype)initWithRunId:(NSString *)runId
                   generation:(uint64_t)generation
                   bundlePath:(NSString *)bundlePath
                     manifest:(NSDictionary *)manifest
               taskDispatcher:(id<TLinkautoJSTaskDispatcher>)taskDispatcher;

- (BOOL)isAborted;
- (void)requestStop;
- (void)evaluateScriptAtPath:(NSString *)scriptPath error:(NSError **)error;

@end

#endif /* TLINKAUTO_JS_RUNTIME_EXECUTION_H */
