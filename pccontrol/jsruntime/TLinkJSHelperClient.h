#import <Foundation/Foundation.h>

@interface TLinkJSHelperClient : NSObject
- (NSDictionary *)handshakeWithTimeoutMs:(int)timeoutMs;
- (NSDictionary *)statusWithTimeoutMs:(int)timeoutMs;
- (NSDictionary *)startScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest timeoutMs:(int)timeoutMs;
- (NSDictionary *)statusForSessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs;
// Wake hint only: read a fresh status and validate ownership before native dispatch.
- (NSDictionary *)waitForChangeAfterSequence:(uint64_t)sequence sessionId:(NSString *)sessionId waitMs:(int)waitMs timeoutMs:(int)timeoutMs;
- (NSDictionary *)stopSessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs;
- (NSDictionary *)sendNativeRPCResponse:(NSDictionary *)result requestId:(NSString *)requestId sessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs;
@end
