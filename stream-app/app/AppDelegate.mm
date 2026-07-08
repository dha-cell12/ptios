#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "ScriptsViewController.h"
#import "SettingsViewController.h"
#import "StreamSupervisor.h"
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
@property(nonatomic, assign) NSInteger lastVisualFeedbackPid;
@property(nonatomic, assign) NSInteger visualFeedbackBurstPollsRemaining;
@property(nonatomic, strong) SCStreamSupervisor *serviceSupervisor;
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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(requestVisualFeedbackBurstPoll:)
                                                 name:@"TLinkVisualFeedbackNeedsPoll"
                                               object:nil];
    self.serviceSupervisor = [[SCStreamSupervisor alloc] init];
    [self ensureStreamServiceForReason:@"launch" background:NO];
    [self startVisualFeedbackMonitor];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    (void)application;
    [self ensureStreamServiceForReason:@"active" background:NO];
    [self startVisualFeedbackMonitor];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    (void)application;
    [self stopVisualFeedbackMonitor];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    (void)application;
    [self ensureStreamServiceForReason:@"background" background:YES];
}

- (void)ensureStreamServiceForReason:(NSString *)reason background:(BOOL)background
{
    if (!self.serviceSupervisor) self.serviceSupervisor = [[SCStreamSupervisor alloc] init];
    NSLog(@"[StreamControl] ensure streamd service reason=%@", reason ?: @"unknown");

    if (background) {
        __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
        task = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"TLinkEnsureStreamd"
                                                             expirationHandler:^{
            if (task != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:task];
                task = UIBackgroundTaskInvalid;
            }
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (task != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:task];
                task = UIBackgroundTaskInvalid;
            }
        });
    }

    [self.serviceSupervisor ensureService];
}

- (void)startVisualFeedbackMonitor
{
    if (self.visualFeedbackTimer) return;
    self.visualFeedbackTimer = [NSTimer timerWithTimeInterval:0.25
                                                       target:self
                                                     selector:@selector(pollVisualFeedback)
                                                     userInfo:nil
                                                      repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.visualFeedbackTimer forMode:NSRunLoopCommonModes];
    [self pollVisualFeedback];
}

- (void)requestVisualFeedbackBurstPoll:(NSNotification *)notification
{
    (void)notification;
    [self startVisualFeedbackMonitor];
    self.visualFeedbackBurstPollsRemaining = MAX(self.visualFeedbackBurstPollsRemaining, 12);
    [self pollVisualFeedback];
}

- (void)stopVisualFeedbackMonitor
{
    [self.visualFeedbackTimer invalidate];
    self.visualFeedbackTimer = nil;
    self.visualFeedbackPollInFlight = NO;
    self.visualFeedbackBurstPollsRemaining = 0;
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
            if (self.visualFeedbackBurstPollsRemaining > 0) {
                self.visualFeedbackBurstPollsRemaining--;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self pollVisualFeedback];
                });
            }
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

    NSInteger streamdPid = [status[@"pid"] integerValue];
    if (streamdPid > 0) {
        if (self.lastVisualFeedbackPid > 0 && self.lastVisualFeedbackPid != streamdPid) {
            self.lastVisualEventId = 0;
        }
        self.lastVisualFeedbackPid = streamdPid;
    }

    NSDictionary *visualFeedback = status[@"visual_feedback"];
    NSArray *events = [visualFeedback isKindOfClass:[NSDictionary class]] ? visualFeedback[@"events"] : nil;
    if (![events isKindOfClass:[NSArray class]]) return;

    uint64_t serverLastEventId = [visualFeedback[@"last_event_id"] unsignedLongLongValue];
    if (serverLastEventId > 0 && serverLastEventId < self.lastVisualEventId) {
        self.lastVisualEventId = 0;
    }

    uint64_t maxSeen = self.lastVisualEventId;
    uint64_t nowMs = (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000.0);
    for (NSDictionary *event in events) {
        if (![event isKindOfClass:[NSDictionary class]]) continue;
        uint64_t eventId = [event[@"id"] unsignedLongLongValue];
        if (eventId == 0 || eventId <= self.lastVisualEventId) continue;
        if (eventId > maxSeen) maxSeen = eventId;

        id kindObject = event[@"kind"];
        NSString *kind = [kindObject isKindOfClass:[NSString class]] ? kindObject : @"";
        uint64_t tsMs = [event[@"ts_ms"] unsignedLongLongValue];
        if (tsMs > 0 && nowMs > tsMs && nowMs - tsMs > 10000) continue;

        if ([kind isEqualToString:@"toast"]) {
            id messageObject = event[@"message"];
            NSString *message = [messageObject isKindOfClass:[NSString class]] ? messageObject : @"";
            if (message.length == 0) continue;
            NSTimeInterval duration = [event[@"duration"] doubleValue];
            NSInteger position = [event[@"position"] integerValue];
            CGFloat fontSize = (CGFloat)[event[@"fontSize"] doubleValue];
            [self showToastOverlayWithMessage:message duration:duration position:position fontSize:fontSize];
        } else if ([kind isEqualToString:@"alert"]) {
            id titleObject = event[@"title"];
            id messageObject = event[@"message"];
            NSString *title = [titleObject isKindOfClass:[NSString class]] ? titleObject : @"TLinkauto";
            NSString *message = [messageObject isKindOfClass:[NSString class]] ? messageObject : @"";
            if (message.length == 0) continue;
            [self showAlertOverlayWithTitle:title message:message duration:[event[@"duration"] doubleValue]];
        } else if ([kind isEqualToString:@"dialog"]) {
            id titleObject = event[@"title"];
            id messageObject = event[@"message"];
            id okObject = event[@"ok"];
            id cancelObject = event[@"cancel"];
            NSString *title = [titleObject isKindOfClass:[NSString class]] ? titleObject : @"TLinkauto";
            NSString *message = [messageObject isKindOfClass:[NSString class]] ? messageObject : @"";
            NSString *okTitle = [okObject isKindOfClass:[NSString class]] ? okObject : @"OK";
            NSString *cancelTitle = [cancelObject isKindOfClass:[NSString class]] ? cancelObject : @"Cancel";
            [self showDialogOverlayWithTitle:title message:message okTitle:okTitle cancelTitle:cancelTitle];
        } else if ([kind isEqualToString:@"touch"]) {
            [self showTouchIndicatorAtX:[event[@"x"] doubleValue]
                                      y:[event[@"y"] doubleValue]
                            screenWidth:[event[@"screen_width"] doubleValue]
                           screenHeight:[event[@"screen_height"] doubleValue]
                                   type:[event[@"type"] integerValue]];
        }
    }
    self.lastVisualEventId = maxSeen;
}

- (UIViewController *)topViewControllerFromViewController:(UIViewController *)viewController
{
    if (!viewController) return nil;
    UIViewController *presented = viewController.presentedViewController;
    if (presented) return [self topViewControllerFromViewController:presented];
    if ([viewController isKindOfClass:[UINavigationController class]]) {
        return [self topViewControllerFromViewController:[(UINavigationController *)viewController visibleViewController]];
    }
    if ([viewController isKindOfClass:[UITabBarController class]]) {
        return [self topViewControllerFromViewController:[(UITabBarController *)viewController selectedViewController]];
    }
    return viewController;
}

- (void)showAlertOverlayWithTitle:(NSString *)title message:(NSString *)message duration:(NSTimeInterval)duration
{
    if (message.length == 0 || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    UIViewController *presenter = [self topViewControllerFromViewController:self.window.rootViewController];
    if (!presenter || [presenter isKindOfClass:[UIAlertController class]]) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title.length > 0 ? title : @"TLinkauto"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];

    if (duration > 0.0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (alert.presentingViewController) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }
        });
    }
}

- (void)showDialogOverlayWithTitle:(NSString *)title message:(NSString *)message okTitle:(NSString *)okTitle cancelTitle:(NSString *)cancelTitle
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    UIViewController *presenter = [self topViewControllerFromViewController:self.window.rootViewController];
    if (!presenter || [presenter isKindOfClass:[UIAlertController class]]) return;

    UIAlertController *dialog = [UIAlertController alertControllerWithTitle:title.length > 0 ? title : @"TLinkauto"
                                                                    message:message ?: @""
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [dialog addAction:[UIAlertAction actionWithTitle:okTitle.length > 0 ? okTitle : @"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
    if (cancelTitle.length > 0) {
        [dialog addAction:[UIAlertAction actionWithTitle:cancelTitle
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    }
    [presenter presentViewController:dialog animated:YES completion:nil];
}

- (void)showTouchIndicatorAtX:(CGFloat)x y:(CGFloat)y screenWidth:(CGFloat)screenWidth screenHeight:(CGFloat)screenHeight type:(NSInteger)type
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    UIWindow *window = self.window;
    if (!window || screenWidth <= 0.0 || screenHeight <= 0.0) return;

    CGFloat px = x / screenWidth * CGRectGetWidth(window.bounds);
    CGFloat py = y / screenHeight * CGRectGetHeight(window.bounds);
    CGFloat size = type == 2 ? 22.0 : 30.0;
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(px - size / 2.0, py - size / 2.0, size, size)];
    dot.userInteractionEnabled = NO;
    dot.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:type == 2 ? 0.35 : 0.45];
    dot.layer.cornerRadius = size / 2.0;
    dot.layer.borderWidth = 2.0;
    dot.layer.borderColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.85].CGColor;
    dot.transform = CGAffineTransformMakeScale(0.6, 0.6);
    dot.alpha = 0.0;
    [window addSubview:dot];

    [UIView animateWithDuration:0.08 animations:^{
        dot.alpha = 1.0;
        dot.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.28
                              delay:0.08
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            dot.alpha = 0.0;
            dot.transform = CGAffineTransformMakeScale(1.45, 1.45);
        } completion:^(__unused BOOL done) {
            [dot removeFromSuperview];
        }];
    }];
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
