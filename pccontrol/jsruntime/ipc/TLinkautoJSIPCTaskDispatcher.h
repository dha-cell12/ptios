#ifndef TLINKAUTO_JS_IPC_TASK_DISPATCHER_H
#define TLINKAUTO_JS_IPC_TASK_DISPATCHER_H

#import <Foundation/Foundation.h>
#import "../TLinkautoJSTaskDispatcher.h"
#import "TLinkautoJSIPCConnection.h"

@interface TLinkautoJSIPCTaskDispatcher : NSObject <TLinkautoJSTaskDispatcher>

- (instancetype)initWithConnection:(TLinkautoJSIPCConnection *)connection runId:(uint64_t)runId generation:(uint64_t)generation;

// Exposed for the Daemon to route incoming responses back to waiting dispatchers
- (void)handleResponsePayload:(NSDictionary *)payload forRequestId:(uint64_t)requestId;

@end

#endif /* TLINKAUTO_JS_IPC_TASK_DISPATCHER_H */
