#import <Foundation/Foundation.h>

#define TLINK_LICENSE_AUTHORITY_CONTRACT_VERSION 1
#define TLINK_LICENSE_AUTHORITY_SOCKET_PATH \
    "/var/mobile/Library/TLinkauto/run/license-authority.sock"

FOUNDATION_EXPORT NSDictionary *TLinkLicenseAuthorityStatus(
    NSString **error);
