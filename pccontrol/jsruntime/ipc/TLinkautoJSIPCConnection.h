#ifndef TLINKAUTO_JS_IPC_CONNECTION_H
#define TLINKAUTO_JS_IPC_CONNECTION_H

#import <Foundation/Foundation.h>
#include "TLinkautoJSIPCProtocol.h"

@protocol TLinkautoJSIPCConnectionDelegate <NSObject>
- (void)connectionDidReceiveMessage:(TLinkautoJSIPCHeader)header payload:(NSDictionary *)payload;
- (void)connectionDidDisconnect;
@end

@interface TLinkautoJSIPCConnection : NSObject

@property (nonatomic, weak) id<TLinkautoJSIPCConnectionDelegate> delegate;

- (instancetype)initWithSocketFile:(NSString *)socketPath isServer:(BOOL)isServer;
- (void)start;
- (void)stop;

- (BOOL)sendMessageWithType:(uint16_t)type
                 requestId:(uint64_t)requestId
                     runId:(uint64_t)runId
                generation:(uint64_t)generation
                   timeout:(uint32_t)timeoutMs
                   payload:(NSDictionary *)payload;

@end

#endif /* TLINKAUTO_JS_IPC_CONNECTION_H */
