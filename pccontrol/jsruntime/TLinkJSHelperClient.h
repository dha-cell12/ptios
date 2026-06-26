#import <Foundation/Foundation.h>

@interface TLinkJSHelperClient : NSObject
- (NSDictionary *)handshakeWithTimeoutMs:(int)timeoutMs;
- (NSDictionary *)statusWithTimeoutMs:(int)timeoutMs;
@end
