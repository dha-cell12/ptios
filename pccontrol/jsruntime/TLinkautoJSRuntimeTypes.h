#ifndef TLINKAUTO_JS_RUNTIME_TYPES_H
#define TLINKAUTO_JS_RUNTIME_TYPES_H

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TLinkautoJSRuntimeState) {
    TLinkautoJSRuntimeStateIdle = 0,
    TLinkautoJSRuntimeStateStarting,
    TLinkautoJSRuntimeStateRunning,
    TLinkautoJSRuntimeStateStopping
};

typedef NS_ENUM(NSInteger, TLinkautoJSRunOutcome) {
    TLinkautoJSRunOutcomeNone = 0,
    TLinkautoJSRunOutcomeCompleted,
    TLinkautoJSRunOutcomeCancelled,
    TLinkautoJSRunOutcomeTimedOut,
    TLinkautoJSRunOutcomeFailed,
    TLinkautoJSRunOutcomeDaemonCrashed,
    TLinkautoJSRunOutcomeTaskServiceDisconnected
};

@interface TLinkautoJSRunResult : NSObject
@property (nonatomic, copy) NSString *runId;
@property (nonatomic, assign) uint64_t generation;
@property (nonatomic, assign) TLinkautoJSRunOutcome outcome;
@property (nonatomic, assign) NSInteger errorCode;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, assign) uint64_t startedAt;
@property (nonatomic, assign) uint64_t finishedAt;
@end

#endif /* TLINKAUTO_JS_RUNTIME_TYPES_H */
