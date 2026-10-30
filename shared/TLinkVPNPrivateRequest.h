#import <Foundation/Foundation.h>

// Sends VPN credentials to the embedded TSRootBinary through a randomly named,
// mode-0600, one-shot plist. The returned dictionary never contains secrets.
FOUNDATION_EXPORT NSDictionary *TLinkVPNRunPrivateConfigurationHelper(
    NSString *helperPath,
    NSDictionary *configuration);

// The optional callback is synchronous and is not retained by deferred reaping.
typedef BOOL (^TLinkVPNPrivateRequestShouldStop)(void);
FOUNDATION_EXPORT NSDictionary *TLinkVPNRunPrivateConfigurationHelperWithStop(
    NSString *helperPath,
    NSDictionary *configuration,
    TLinkVPNPrivateRequestShouldStop shouldStop);
