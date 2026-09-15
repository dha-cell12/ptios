#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const TLinkAXSnapshotSchema;
FOUNDATION_EXPORT NSString *const TLinkAXBackendName;

// Read-only AXRuntime capability and runtime state. This never returns UI text.
FOUNDATION_EXPORT NSDictionary *TLinkAXCapabilitySnapshot(void);

// Best-effort foreground application context: bundle_id, pid and source.
FOUNDATION_EXPORT NSDictionary *TLinkAXCopyFrontmostContext(void);

// Flat foreground accessibility snapshot. The numeric AXRuntime attribute used
// on supported iOS builds does not expose stable parent/child relationships.
FOUNDATION_EXPORT NSDictionary *TLinkAXCopySnapshot(pid_t pid,
                                                    NSString *bundleID,
                                                    NSDictionary * _Nullable options);

FOUNDATION_EXPORT NSDictionary *TLinkAXFindElement(pid_t pid,
                                                   NSString *bundleID,
                                                   NSDictionary *selector);

FOUNDATION_EXPORT NSDictionary *TLinkAXElementAtPoint(pid_t pid,
                                                      NSString *bundleID,
                                                      CGPoint point);

FOUNDATION_EXPORT BOOL TLinkAXResultSucceeded(NSDictionary *result);

NS_ASSUME_NONNULL_END
