#import <Foundation/Foundation.h>

typedef BOOL (^TLinkJSHelperCancellationCheck)(void);

@interface TLinkJSHelperClient : NSObject
// Used synchronously by the owning run loop; clear before cleanup stop requests.
- (void)setCancellationCheck:(TLinkJSHelperCancellationCheck)check;
// Run-owned, synchronous use only. Disabled by default; disabling closes idle reuse.
- (void)setConnectionReuseEnabled:(BOOL)enabled;
- (NSDictionary *)handshakeWithTimeoutMs:(int)timeoutMs;
- (NSDictionary *)statusWithTimeoutMs:(int)timeoutMs;
- (NSDictionary *)startScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest timeoutMs:(int)timeoutMs;
- (NSDictionary *)statusForSessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs;
// Wake hint only: read a fresh status and validate ownership before native dispatch.
- (NSDictionary *)waitForChangeAfterSequence:(uint64_t)sequence sessionId:(NSString *)sessionId waitMs:(int)waitMs timeoutMs:(int)timeoutMs;
- (NSDictionary *)stopSessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs;
- (NSDictionary *)sendNativeRPCResponse:(NSDictionary *)result requestId:(NSString *)requestId sessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs;
@end
