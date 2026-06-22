#ifndef TLINKAUTO_JS_DIRECT_TASK_DISPATCHER_H
#define TLINKAUTO_JS_DIRECT_TASK_DISPATCHER_H

#import <Foundation/Foundation.h>
#import "TLinkautoJSTaskDispatcher.h"
#import "TLinkautoJSLegacyTaskAdapter.h"

@interface TLinkautoJSDirectTaskDispatcher : NSObject <TLinkautoJSTaskDispatcher>

- (instancetype)initWithAdapter:(TLinkautoJSLegacyTaskAdapter *)adapter;

@end

#endif /* TLINKAUTO_JS_DIRECT_TASK_DISPATCHER_H */
