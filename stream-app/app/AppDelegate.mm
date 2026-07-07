#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "ScriptsViewController.h"
#import "SettingsViewController.h"
#import "TLinkSocketClient.h"
#import "ViewController.h"

// ---------------------------------------------------------------------------
// SCAppDelegate
//
// Stands up the window + navigation controller and forces light mode to match
// the Tlinkauto app's visual style. The supervisor is created/owned by the
// root view controller so its lifecycle is tied to the UI.
// ---------------------------------------------------------------------------

@interface SCAppDelegate ()
@property(nonatomic, strong) NSTimer *visualFeedbackTimer;
@property(nonatomic, assign) BOOL visualFeedbackPollInFlight;
@property(nonatomic, assign) uint64_t lastVisualEventId;
@end

@implementation SCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    SCScriptsViewController *scripts = [[SCScriptsViewController alloc] initWithScriptsPath:@"/var/mobile/Library/TLinkauto/scripts"];
    SCViewController *service = [[SCViewController alloc] init];
    SCSettingsViewController *settings = [[SCSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];

    UINavigationController *scriptsNav = [[UINavigationController alloc] initWithRootViewController:scripts];
    UINavigationController *serviceNav = [[UINavigationController alloc] initWithRootViewController:service];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];

    scriptsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Scripts"
                                                          image:[UIImage systemImageNamed:@"list.dash"]
                                                            tag:0];
    serviceNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Service"
                                                          image:[UIImage systemImageNamed:@"dot.radiowaves.left.and.right"]
                                                            tag:1];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
                                                           image:[UIImage systemImageNamed:@"gearshape"]
                                                             tag:2];

    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = @[scriptsNav, serviceNav, settingsNav];
    tabs.selectedIndex = 1;

    if (@available(iOS 13.0, *)) {
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }

    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    [self startVisualFeedbackMonitor];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    (void)application;
    [self startVisualFeedbackMonitor];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    (void)application;
    [self stopVisualFeedbackMonitor];
}

- (void)startVisualFeedbackMonitor
{
    if (self.visualFeedbackTimer) return;
    self.visualFeedbackTimer = [NSTimer timerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(pollVisualFeedback)
                                                     userInfo:nil
                                                      repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.visualFeedbackTimer forMode:NSRunLoopCommonModes];
    [self pollVisualFeedback];
}

- (void)stopVisualFeedbackMonitor
{
    [self.visualFeedbackTimer invalidate];
    self.visualFeedbackTimer = nil;
    self.visualFeedbackPollInFlight = NO;
}

- (void)pollVisualFeedback
{
    if (self.visualFeedbackPollInFlight) return;
    self.visualFeedbackPollInFlight = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:60 args:@[] timeout:2.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.visualFeedbackPollInFlight = NO;
            [self handleVisualFeedbackStatusResponse:response];
        });
    });
}

- (void)handleVisualFeedbackStatusResponse:(NSString *)response
{
    if (![response hasPrefix:@"0;;"]) return;
    NSString *payload = [[response substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (jsonData.length == 0) return;
    NSDictionary *status = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if (![status isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *visualFeedback = status[@"visual_feedback"];
    NSArray *events = [visualFeedback isKindOfClass:[NSDictionary class]] ? visualFeedback[@"events"] : nil;
    if (![events isKindOfClass:[NSArray class]]) return;

    uint64_t maxSeen = self.lastVisualEventId;
    uint64_t nowMs = (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000.0);
    for (NSDictionary *event in events) {
        if (![event isKindOfClass:[NSDictionary class]]) continue;
        uint64_t eventId = [event[@"id"] unsignedLongLongValue];
        if (eventId == 0 || eventId <= self.lastVisualEventId) continue;
        if (eventId > maxSeen) maxSeen = eventId;

        id kindObject = event[@"kind"];
        NSString *kind = [kindObject isKindOfClass:[NSString class]] ? kindObject : @"";
        if (![kind isEqualToString:@"toast"]) continue;
        uint64_t tsMs = [event[@"ts_ms"] unsignedLongLongValue];
        if (tsMs > 0 && nowMs > tsMs && nowMs - tsMs > 10000) continue;

        id messageObject = event[@"message"];
        NSString *message = [messageObject isKindOfClass:[NSString class]] ? messageObject : @"";
        if (message.length == 0) continue;
        NSTimeInterval duration = [event[@"duration"] doubleValue];
        NSInteger position = [event[@"position"] integerValue];
        CGFloat fontSize = (CGFloat)[event[@"fontSize"] doubleValue];
        [self showToastOverlayWithMessage:message duration:duration position:position fontSize:fontSize];
    }
    self.lastVisualEventId = maxSeen;
}

- (void)showToastOverlayWithMessage:(NSString *)message duration:(NSTimeInterval)duration position:(NSInteger)position fontSize:(CGFloat)fontSize
{
    if (message.length == 0 || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    UIWindow *window = self.window;
    if (!window) return;

    if (duration <= 0.0) duration = 2.0;
    if (duration > 30.0) duration = 30.0;
    if (fontSize <= 0.0) fontSize = 15.0;
    if (fontSize > 50.0) fontSize = 50.0;

    const NSInteger toastTag = 600022;
    [[window viewWithTag:toastTag] removeFromSuperview];

    CGFloat maxWidth = CGRectGetWidth(window.bounds) - 48.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;

    CGSize labelSize = [label sizeThatFits:CGSizeMake(maxWidth - 32.0, CGFLOAT_MAX)];
    CGFloat bubbleWidth = MIN(maxWidth, ceil(labelSize.width + 32.0));
    CGFloat bubbleHeight = ceil(labelSize.height + 20.0);
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat y = 0.0;
    if (position == 0) {
        y = safe.top + 24.0;
    } else if (position == 1) {
        y = (CGRectGetHeight(window.bounds) - bubbleHeight) / 2.0;
    } else {
        y = CGRectGetHeight(window.bounds) - safe.bottom - bubbleHeight - 82.0;
    }
    CGFloat x = (CGRectGetWidth(window.bounds) - bubbleWidth) / 2.0;

    UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(x, y, bubbleWidth, bubbleHeight)];
    bubble.tag = toastTag;
    bubble.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.86];
    bubble.layer.cornerRadius = 10.0;
    bubble.layer.shadowColor = [UIColor blackColor].CGColor;
    bubble.layer.shadowOpacity = 0.22;
    bubble.layer.shadowRadius = 10.0;
    bubble.layer.shadowOffset = CGSizeMake(0, 4);
    bubble.alpha = 0.0;
    bubble.transform = CGAffineTransformMakeTranslation(0, 8.0);

    label.frame = CGRectInset(bubble.bounds, 16.0, 10.0);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [bubble addSubview:label];
    [window addSubview:bubble];

    [UIView animateWithDuration:0.18 animations:^{
        bubble.alpha = 1.0;
        bubble.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.2
                              delay:duration
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            bubble.alpha = 0.0;
            bubble.transform = CGAffineTransformMakeTranslation(0, -8.0);
        } completion:^(__unused BOOL done) {
            [bubble removeFromSuperview];
        }];
    }];
}

@end
