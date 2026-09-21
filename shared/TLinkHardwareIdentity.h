#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Collects raw evidence only. The license server owns normalization, matching,
// risk scoring, and the final device verdict.
FOUNDATION_EXPORT NSDictionary *TLinkCopyHardwareIdentityEvidence(void);

NS_ASSUME_NONNULL_END
