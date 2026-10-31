#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *TLinkVPNManagedProfileIdentifier(void);

// Admission-only view: cached process entitlements and a fresh framework probe.
// Full diagnostic/private compatibility and mutable VPN state are not evaluated.
FOUNDATION_EXPORT NSDictionary *TLinkVPNControlPreflight(void);

// Successful current-process entitlement reads are memoized immutably; read
// errors retry. Connection state and other mutable diagnostics remain fresh.
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
