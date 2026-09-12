#import <Foundation/Foundation.h>

// Sends VPN credentials to the embedded TSRootBinary through a randomly named,
// mode-0600, one-shot plist. The returned dictionary never contains secrets.
FOUNDATION_EXPORT NSDictionary *TLinkVPNRunPrivateConfigurationHelper(
    NSString *helperPath,
    NSDictionary *configuration);
