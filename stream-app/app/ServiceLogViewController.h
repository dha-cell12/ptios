#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// TLinkServiceLogViewController
//
// Full service log screen backed by TLinkLogStore. Renders the shared ring
// buffer in a single text view (joined once per update notification instead of
// O(n^2) string appends) with auto-scroll and a Clear action.
// ---------------------------------------------------------------------------
@interface TLinkServiceLogViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
