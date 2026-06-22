#ifndef TLINKAUTO_JS_RUNTIME_H
#define TLINKAUTO_JS_RUNTIME_H

#import <Foundation/Foundation.h>
#import "TLinkautoJSTaskDispatcher.h"

@interface TLinkautoJSRuntime : NSObject

@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) NSString *runId;

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest taskDispatcher:(id<TLinkautoJSTaskDispatcher>)taskDispatcher error:(NSError **)error;
- (void)requestStop;

@end

#endif
