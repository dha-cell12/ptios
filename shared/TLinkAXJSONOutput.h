#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Synchronous JSON writer with a bounded accepted-byte buffer. A rejected
// partial prefix is never returned; serializer exceptions continue to propagate.
FOUNDATION_EXPORT NSData * _Nullable TLinkAXBoundedJSONData(id object, BOOL * _Nullable tooLarge);
NS_ASSUME_NONNULL_END
