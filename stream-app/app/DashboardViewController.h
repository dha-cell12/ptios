#import <UIKit/UIKit.h>

@class SCStreamSupervisor;

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// TLinkDashboardViewController
//
// "Dashboard" tab: service status card (running state, pid, ports), quick
// actions (ensure/stop/restart, self-test tap, capture probe) and a recent
// log preview. Replaces the orphaned SCViewController debug screen with a
// card-based layout wired into the tab bar.
// ---------------------------------------------------------------------------
@interface TLinkDashboardViewController : UIViewController

- (instancetype)initWithSupervisor:(SCStreamSupervisor *)supervisor NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
