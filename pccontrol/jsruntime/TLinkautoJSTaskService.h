#ifndef TLINKAUTO_JS_TASK_SERVICE_H
#define TLINKAUTO_JS_TASK_SERVICE_H

#import <Foundation/Foundation.h>

@interface TLinkautoJSTaskService : NSObject

+ (instancetype)sharedService;

- (void)startService;
- (void)stopService;

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest error:(NSError **)error;
- (void)requestStop;

@end

#endif /* TLINKAUTO_JS_TASK_SERVICE_H */
