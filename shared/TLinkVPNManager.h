#import <Foundation/Foundation.h>

typedef void (^TLinkVPNResultCompletion)(NSDictionary *result);

FOUNDATION_EXPORT NSString *TLinkVPNOwnedDescription(void);
FOUNDATION_EXPORT void TLinkVPNConfigureIKEv2(
    NSString *serverAddress,
    NSString *remoteIdentifier,
    NSString *username,
    NSString *password,
    TLinkVPNResultCompletion completion);
FOUNDATION_EXPORT void TLinkVPNConfigureLegacyPrivate(
    NSString *protocolType,
    NSString *serverAddress,
    NSString *username,
    NSString *password,
    NSString *sharedSecret,
    NSString *groupName,
    TLinkVPNResultCompletion completion);
// Narrow synchronous entry point used only by the embedded TSRootBinary.
// The foreground app must use TLinkVPNConfigureLegacyPrivate so credentials
// are transported through the protected one-shot request file.
FOUNDATION_EXPORT NSDictionary *TLinkVPNConfigureLegacyPrivateSynchronouslyForHelper(
    NSString *protocolType,
    NSString *serverAddress,
    NSString *username,
    NSString *password,
    NSString *sharedSecret,
    NSString *groupName,
    NSString *displayName,
    NSInteger encryptionLevel,
    BOOL sendAllTraffic);
// Synchronous root-helper adapter for the asynchronous NEVPNManager path.
// The helper pumps its main run loop until the save/reload sequence completes.
FOUNDATION_EXPORT NSDictionary *TLinkVPNConfigureIKEv2SynchronouslyForHelper(
    NSString *serverAddress,
    NSString *remoteIdentifier,
    NSString *username,
    NSString *password);
FOUNDATION_EXPORT void TLinkVPNReadManagerStatus(
    TLinkVPNResultCompletion completion);
FOUNDATION_EXPORT void TLinkVPNSetOnDemandEnabled(
    BOOL enabled,
    TLinkVPNResultCompletion completion);
FOUNDATION_EXPORT void TLinkVPNSetConnected(
    BOOL connected,
    NSTimeInterval timeout,
    TLinkVPNResultCompletion completion);
