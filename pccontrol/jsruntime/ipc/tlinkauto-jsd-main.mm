#import <Foundation/Foundation.h>
#import "TLinkautoJSIPCConnection.h"
#import "TLinkautoJSIPCTaskDispatcher.h"
#import "../TLinkautoJSRuntime.h"

@interface DaemonApp : NSObject <TLinkautoJSIPCConnectionDelegate>
@end

@implementation DaemonApp {
    TLinkautoJSIPCConnection *_conn;
    TLinkautoJSRuntime *_runtime;
    TLinkautoJSIPCTaskDispatcher *_dispatcher;
}

- (void)start {
    NSLog(@"tlinkauto-jsd: Starting daemon");
    _runtime = [[TLinkautoJSRuntime alloc] init];
    _conn = [[TLinkautoJSIPCConnection alloc] initWithSocketFile:@"/var/mobile/Library/TLinkauto/run/jsruntime.sock" isServer:YES];
    _conn.delegate = self;
    // ensure dir exists
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/TLinkauto/run" withIntermediateDirectories:YES attributes:nil error:nil];
    [_conn start];
    // Wait briefly, then broadcast HELLO to any connected clients
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [_conn sendMessageWithType:TLJS_MSG_HELLO requestId:0 runId:0 generation:0 timeout:5000 payload:@{}];
    });
    [[NSRunLoop currentRunLoop] run];
}

- (void)connectionDidReceiveMessage:(TLinkautoJSIPCHeader)header payload:(NSDictionary *)payload {
    NSLog(@"tlinkauto-jsd: Received message type %d", header.messageType);

    if (header.messageType == TLJS_MSG_START_RUN) {
        NSString *scriptPath = payload[@"scriptPath"];
        NSString *bundlePath = payload[@"bundlePath"];
        NSDictionary *manifest = payload[@"manifest"];

        _dispatcher = [[TLinkautoJSIPCTaskDispatcher alloc] initWithConnection:_conn runId:header.runId generation:header.generation];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *err = nil;
            BOOL ok = [self->_runtime runScriptAtPath:scriptPath bundlePath:bundlePath manifest:manifest taskDispatcher:self->_dispatcher error:&err];

            NSDictionary *result = ok ? @{@"ok": @YES} : @{@"ok": @NO, @"error": err.localizedDescription ?: @"Unknown error"};
            [self->_conn sendMessageWithType:TLJS_MSG_RUN_FINISHED
                                 requestId:header.requestId
                                     runId:header.runId
                                generation:header.generation
                                   timeout:5000
                                   payload:result];
        });
    } else if (header.messageType == TLJS_MSG_STOP_RUN) {
        [_runtime requestStop];
    } else if (header.messageType == TLJS_MSG_TASK_RESPONSE) {
        [_dispatcher handleResponsePayload:payload forRequestId:header.requestId];
    }
}

- (void)connectionDidDisconnect {
    NSLog(@"tlinkauto-jsd: Client disconnected, stopping current run");
    [_runtime requestStop];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        DaemonApp *app = [[DaemonApp alloc] init];
        [app start];
    }
    return 0;
}
