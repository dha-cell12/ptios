#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Starts the localhost-only Vision OCR RPC endpoint used by streamd. The
// service deliberately owns no UIWindow/scene; UIKit is bootstrapped by the
// surrounding TLinkUIService before this entry point is called.
FOUNDATION_EXPORT void TLinkStartVisionOCRService(void);
FOUNDATION_EXPORT NSString *TLinkVisionOCRServiceProbeSummary(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *TLinkVisionOCRServiceDiagnostics(void);

NS_ASSUME_NONNULL_END
