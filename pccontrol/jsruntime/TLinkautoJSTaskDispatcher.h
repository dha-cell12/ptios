#ifndef TLINKAUTO_JS_TASK_DISPATCHER_H
#define TLINKAUTO_JS_TASK_DISPATCHER_H

#import <Foundation/Foundation.h>

@protocol TLinkautoJSTaskDispatcher <NSObject>

- (NSDictionary *)dispatchTask:(NSString *)taskName payload:(NSDictionary *)payload;

@end

#endif /* TLINKAUTO_JS_TASK_DISPATCHER_H */
