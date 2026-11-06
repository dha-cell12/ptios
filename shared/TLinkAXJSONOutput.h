#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Synchronous JSON writer with a bounded accepted-byte buffer. A rejected
// partial prefix is never returned; serializer exceptions continue to propagate.
FOUNDATION_EXPORT NSData * _Nullable TLinkAXBoundedJSONData(id object, BOOL * _Nullable tooLarge);
// Captures the calling native budget. OutputLimit maps to tooLarge; cancellation
// or deadline maps to stopped. No rejected/late JSON result is returned.
FOUNDATION_EXPORT NSData * _Nullable TLinkAXBoundedJSONDataWithStop(id object, BOOL * _Nullable tooLarge, BOOL * _Nullable stopped);
NS_ASSUME_NONNULL_END
