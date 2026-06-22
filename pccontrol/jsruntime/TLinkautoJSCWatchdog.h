#ifndef TLINKAUTO_JS_CWATCHDOG_H
#define TLINKAUTO_JS_CWATCHDOG_H

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "TLinkautoJSCancellationToken.h"

@interface TLinkautoJSCWatchdog : NSObject

@property (nonatomic, readonly) BOOL isAvailable;

- (instancetype)initWithToken:(TLinkautoJSCancellationToken *)token;
- (void)installForContext:(JSContext *)context;
- (void)clearForContext:(JSContext *)context;

@end

#endif /* TLINKAUTO_JS_CWATCHDOG_H */
