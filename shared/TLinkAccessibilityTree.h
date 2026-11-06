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
// Snapshot/find/at share eight process-local running/queued call slots. Overflow
// returns ui_ax_busy with partial/retryable; admitted operations stay serialized.
// Snapshot/find row text is limited to 65536 UTF-8 bytes per field; oversize
// returns ui_response_too_large/partial. This is not a provider allocation bound.
FOUNDATION_EXPORT NSDictionary *TLinkAXCopySnapshot(pid_t pid,
                                                    NSString *bundleID,
                                                    NSDictionary * _Nullable options);

FOUNDATION_EXPORT NSDictionary *TLinkAXFindElement(pid_t pid,
                                                   NSString *bundleID,
                                                   NSDictionary *selector);

// Hit-test text uses the same per-field limit and caller output admission;
// oversize returns ui_response_too_large/partial instead of a successful element.
// Native budget overflow retains the existing caller-stop precedence.
FOUNDATION_EXPORT NSDictionary *TLinkAXElementAtPoint(pid_t pid,
                                                      NSString *bundleID,
                                                      CGPoint point);

FOUNDATION_EXPORT BOOL TLinkAXResultSucceeded(NSDictionary *result);

// Mutation must not rely on a selector result from an incomplete AX snapshot.
// Missing completeness flags also fail closed.
FOUNDATION_EXPORT BOOL TLinkAXResultCompleteForAction(NSDictionary *result);

NS_ASSUME_NONNULL_END
