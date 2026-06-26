#import <Foundation/Foundation.h>

@interface TLinkJSHelperClient : NSObject
- (NSDictionary *)handshakeWithTimeoutMs:(int)timeoutMs;
- (NSDictionary *)statusWithTimeoutMs:(int)timeoutMs;
- (NSDictionary *)startScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest timeoutMs:(int)timeoutMs;
- (NSDictionary *)statusForSessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs;
- (NSDictionary *)stopSessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs;
@end
