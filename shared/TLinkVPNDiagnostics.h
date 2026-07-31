#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *TLinkVPNManagedProfileIdentifier(void);

FOUNDATION_EXPORT NSDictionary *TLinkVPNDiagnosticsSnapshot(
    NSString *runtime,
    NSString *state,
    NSString *query,
    NSString *control,
    NSString *backend,
    NSString *broker,
    NSNumber *effectiveConnected);

FOUNDATION_EXPORT NSString *TLinkVPNDiagnosticsBase64(
    NSString *runtime,
    NSString *state,
    NSString *query,
    NSString *control,
    NSString *backend,
    NSString *broker,
    NSNumber *effectiveConnected,
    NSError **error);
