#import <Foundation/Foundation.h>

typedef void (^TLinkVPNResultCompletion)(NSDictionary *result);

FOUNDATION_EXPORT NSString *TLinkVPNOwnedDescription(void);
FOUNDATION_EXPORT void TLinkVPNConfigureIKEv2(
    NSString *serverAddress,
    NSString *remoteIdentifier,
    NSString *username,
    NSString *password,
    TLinkVPNResultCompletion completion);
FOUNDATION_EXPORT void TLinkVPNReadManagerStatus(
    TLinkVPNResultCompletion completion);
FOUNDATION_EXPORT void TLinkVPNSetConnected(
    BOOL connected,
    NSTimeInterval timeout,
    TLinkVPNResultCompletion completion);
