#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#import <objc/message.h>

typedef void (*TLinkUIApplicationInitializeFn)(void);
typedef void (*TLinkUIApplicationInstantiateSingletonFn)(Class);
typedef void (*TLinkUIKitBootstrapFn)(void);

static NSString *const kTLinkUIServiceDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/uiservice_toast.plist";
static NSString *sTLinkLastResult = @"starting";
static NSUInteger sTLinkToastCount = 0;
static BOOL sTLinkWindowReady = NO;
static BOOL sTLinkToastSecure = YES;
static NSInteger sTLinkLastPosition = 2;
static NSUInteger sTLinkRequestCount = 0;
static NSUInteger sTLinkInvalidRequestCount = 0;
static BOOL sTLinkServerStarted = NO;
static UIView *sTLinkToastBubble = nil;
static NSUInteger sTLinkToastGeneration = 0;
static BOOL sTLinkGSInitializeAvailable = NO;
static BOOL sTLinkGSEventInitializeAvailable = NO;
static BOOL sTLinkBKSDisplayServicesStartAvailable = NO;
static BOOL sTLinkUIApplicationInitializeAvailable = NO;
static BOOL sTLinkUIApplicationInstantiateAvailable = NO;
static BOOL sTLinkPluginCompletionAvailable = NO;
static id sTLinkForegroundAssertion = nil;
static BOOL sTLinkForegroundAssertionCreated = NO;
static BOOL sTLinkForegroundAssertionAcquired = NO;

@interface TLinkUIServiceApplication : UIApplication
- (UIApplicationState)tlinkSystemApplicationState;
@end

@implementation TLinkUIServiceApplication
- (UIApplicationState)applicationState { return UIApplicationStateActive; }
- (UIApplicationState)tlinkSystemApplicationState { return [super applicationState]; }
@end

@interface TLinkUIServiceDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@interface TLinkPassthroughToastWindow : UIWindow
@end

@implementation TLinkPassthroughToastWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    (void)point;
    (void)event;
    return nil;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    (void)point;
    (void)event;
    return NO;
}
- (BOOL)_isSecure { return YES; }
- (BOOL)_isSystemWindow { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
- (BOOL)canBecomeKeyWindow { return NO; }
@end

static TLinkPassthroughToastWindow *sTLinkToastWindow = nil;
static UIViewController *sTLinkRootController = nil;

static void TLinkPrepareToastWindow(void);
static void TLinkStartServerIfNecessary(void);
static void TLinkRefreshHostedWindow(void);

static BOOL TLinkForegroundAssertionIsValid(void)
{
    SEL valid = NSSelectorFromString(@"valid");
    return sTLinkForegroundAssertion && [sTLinkForegroundAssertion respondsToSelector:valid]
        ? ((BOOL (*)(id, SEL))objc_msgSend)(sTLinkForegroundAssertion, valid)
        : NO;
}

static UIApplicationState TLinkSystemApplicationState(void)
{
    UIApplication *application = UIApplication.sharedApplication;
    return [application isKindOfClass:TLinkUIServiceApplication.class]
        ? [(TLinkUIServiceApplication *)application tlinkSystemApplicationState]
        : (application ? application.applicationState : (UIApplicationState)-1);
}

static uint32_t TLinkToastWindowContextID(void)
{
    for (NSString *name in @[@"_contextId", @"contextId"]) {
        SEL selector = NSSelectorFromString(name);
        if ([sTLinkToastWindow respondsToSelector:selector]) {
            return ((uint32_t (*)(id, SEL))objc_msgSend)(sTLinkToastWindow, selector);
        }
    }
    return 0;
}

static void TLinkUIServiceLog(NSString *message)
{
    NSString *directory = @"/var/mobile/Library/TLinkauto";
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [directory stringByAppendingPathComponent:@"uiservice.log"];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", NSDate.date, message ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [data writeToFile:path atomically:YES];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

static void TLinkWriteUIServiceDiagnostics(void)
{
    NSString *directory = [kTLinkUIServiceDiagnosticsPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *status = @{
        @"version": @8,
        @"pid": @(getpid()),
        @"uid": @(getuid()),
        @"euid": @(geteuid()),
        @"gid": @(getgid()),
        @"egid": @(getegid()),
        @"mobile_identity": @(geteuid() == 501 && getegid() == 501),
        @"window_ready": @(sTLinkWindowReady),
        @"launch_mode": @"UIKitPluginHosted",
        @"bootstrap_gs_initialize": @(sTLinkGSInitializeAvailable),
        @"bootstrap_gs_event_initialize": @(sTLinkGSEventInitializeAvailable),
        @"bootstrap_bks_display_services": @(sTLinkBKSDisplayServicesStartAvailable),
        @"bootstrap_uiapplication_initialize": @(sTLinkUIApplicationInitializeAvailable),
        @"bootstrap_uiapplication_instantiate": @(sTLinkUIApplicationInstantiateAvailable),
        @"bootstrap_complete_as_plugin": @(sTLinkPluginCompletionAvailable),
        @"foreground_assertion_created": @(sTLinkForegroundAssertionCreated),
        @"foreground_assertion_acquired": @(sTLinkForegroundAssertionAcquired),
        @"foreground_assertion_valid": @(TLinkForegroundAssertionIsValid()),
        @"window_level": @(sTLinkToastWindow.windowLevel),
        @"requested_window_level": @20000099.9,
        @"window_context_id": @(TLinkToastWindowContextID()),
        @"window_hidden": @(sTLinkToastWindow.hidden),
        @"window_key": @(sTLinkToastWindow.isKeyWindow),
        @"window_width": @(CGRectGetWidth(sTLinkToastWindow.bounds)),
        @"window_height": @(CGRectGetHeight(sTLinkToastWindow.bounds)),
        @"application_state": @(UIApplication.sharedApplication ? UIApplication.sharedApplication.applicationState : -1),
        @"system_application_state": @(TLinkSystemApplicationState()),
        @"secure": @(sTLinkToastSecure),
        @"last_position": @(sTLinkLastPosition),
        @"toast_count": @(sTLinkToastCount),
        @"request_count": @(sTLinkRequestCount),
        @"invalid_request_count": @(sTLinkInvalidRequestCount),
        @"last_result": sTLinkLastResult ?: @"unknown",
        @"updated_at": @([NSDate.date timeIntervalSince1970]),
    };
    [status writeToFile:kTLinkUIServiceDiagnosticsPath atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey: NSFileProtectionNone}
                                     ofItemAtPath:kTLinkUIServiceDiagnosticsPath error:nil];
}

static void TLinkSetSecureForToast(BOOL secure)
{
    sTLinkToastSecure = secure;
    for (id target in @[sTLinkToastWindow, sTLinkRootController.view]) {
        for (NSString *name in @[@"_setSecure:", @"setSecure:"]) {
            SEL selector = NSSelectorFromString(name);
            if ([target respondsToSelector:selector]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(target, selector, secure);
                break;
            }
        }
    }
}

static void TLinkPrepareToastWindow(void)
{
    if (sTLinkToastWindow) return;
    sTLinkToastWindow = [[TLinkPassthroughToastWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    sTLinkToastWindow.windowLevel = (UIWindowLevel)20000099.9;
    sTLinkToastWindow.backgroundColor = UIColor.clearColor;
    sTLinkToastWindow.opaque = NO;
    sTLinkToastWindow.userInteractionEnabled = NO;
    sTLinkRootController = [[UIViewController alloc] init];
    sTLinkRootController.view.backgroundColor = UIColor.clearColor;
    sTLinkRootController.view.userInteractionEnabled = NO;
    sTLinkToastWindow.rootViewController = sTLinkRootController;
    TLinkSetSecureForToast(YES);
    sTLinkToastWindow.hidden = NO;
    sTLinkWindowReady = YES;
    sTLinkLastResult = @"window_ready_passthrough";
    TLinkWriteUIServiceDiagnostics();
}

static void TLinkRefreshHostedWindow(void)
{
    if (!sTLinkToastWindow) return;
    sTLinkToastWindow.hidden = YES;
    sTLinkToastWindow.hidden = NO;
    [sTLinkToastWindow setNeedsLayout];
    [sTLinkRootController.view setNeedsLayout];
    [sTLinkRootController.view setNeedsDisplay];
    [CATransaction flush];
}

static void TLinkShowToast(NSDictionary *payload)
{
    TLinkPrepareToastWindow();
    NSString *message = [payload[@"message"] isKindOfClass:NSString.class] ? payload[@"message"] : @"";
    if (message.length == 0) return;
    NSTimeInterval duration = [payload[@"duration"] doubleValue];
    if (duration <= 0.0) duration = 2.0;
    if (duration > 30.0) duration = 30.0;
    NSInteger position = [payload[@"position"] integerValue];
    if (position < 0 || position > 2) position = 2;
    NSNumber *fontSizeValue = [payload[@"font_size"] isKindOfClass:NSNumber.class]
        ? payload[@"font_size"]
        : payload[@"fontSize"];
    CGFloat fontSize = fontSizeValue.doubleValue;
    if (fontSize <= 0.0) fontSize = 15.0;
    if (fontSize > 50.0) fontSize = 50.0;
    BOOL allowScreenshot = [payload[@"allow_screenshot"] boolValue];
    TLinkSetSecureForToast(!allowScreenshot);
    sTLinkLastPosition = position;

    [sTLinkToastBubble.layer removeAllAnimations];
    [sTLinkToastBubble removeFromSuperview];
    sTLinkToastBubble = nil;
    NSUInteger generation = ++sTLinkToastGeneration;

    CGRect bounds = sTLinkToastWindow.bounds;
    CGFloat maxWidth = MAX(120.0, CGRectGetWidth(bounds) - 48.0);
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = message;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.userInteractionEnabled = NO;
    CGSize labelSize = [label sizeThatFits:CGSizeMake(maxWidth - 32.0, CGFLOAT_MAX)];
    CGFloat width = MIN(maxWidth, ceil(labelSize.width + 32.0));
    CGFloat height = ceil(labelSize.height + 20.0);
    UIEdgeInsets safe = sTLinkToastWindow.safeAreaInsets;
    CGFloat y = position == 0
        ? safe.top + 24.0
        : (position == 1
            ? (CGRectGetHeight(bounds) - height) * 0.5
            : CGRectGetHeight(bounds) - safe.bottom - height - 82.0);
    CGFloat x = (CGRectGetWidth(bounds) - width) * 0.5;

    UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    bubble.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.86];
    bubble.layer.cornerRadius = 10.0;
    bubble.layer.shadowColor = UIColor.blackColor.CGColor;
    bubble.layer.shadowOpacity = 0.22;
    bubble.layer.shadowRadius = 10.0;
    bubble.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    bubble.userInteractionEnabled = NO;
    bubble.alpha = 0.0;
    bubble.transform = CGAffineTransformMakeTranslation(0.0, 8.0);
    label.frame = CGRectInset(bubble.bounds, 16.0, 10.0);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [bubble addSubview:label];
    [sTLinkRootController.view addSubview:bubble];
    sTLinkToastBubble = bubble;
    sTLinkToastCount += 1;
    sTLinkLastResult = [NSString stringWithFormat:@"toast_visible_position_%ld", (long)position];
    TLinkUIServiceLog([NSString stringWithFormat:@"toast visible count=%lu position=%ld duration=%.2f secure=%d app_state=%ld system_state=%ld assertion_valid=%d context_id=%u hidden=%d key=%d",
        (unsigned long)sTLinkToastCount, (long)position, duration, sTLinkToastSecure ? 1 : 0,
        (long)UIApplication.sharedApplication.applicationState,
        (long)TLinkSystemApplicationState(), TLinkForegroundAssertionIsValid() ? 1 : 0,
        TLinkToastWindowContextID(), sTLinkToastWindow.hidden ? 1 : 0,
        sTLinkToastWindow.isKeyWindow ? 1 : 0]);
    TLinkWriteUIServiceDiagnostics();
    TLinkRefreshHostedWindow();
    [UIView animateWithDuration:0.18 animations:^{
        bubble.alpha = 1.0;
        bubble.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.2 delay:duration options:UIViewAnimationOptionCurveEaseIn animations:^{
            bubble.alpha = 0.0;
            bubble.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
        } completion:^(__unused BOOL done) {
            if (generation != sTLinkToastGeneration) return;
            [bubble removeFromSuperview];
            sTLinkToastBubble = nil;
            sTLinkLastResult = @"toast_hidden";
            TLinkWriteUIServiceDiagnostics();
        }];
    }];
}

static NSString *TLinkReadLine(int client)
{
    struct timeval timeout = {2, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    NSMutableData *data = [NSMutableData data];
    char byte = 0;
    while (data.length < 65536) {
        ssize_t count = read(client, &byte, 1);
        if (count <= 0 || byte == '\n') break;
        [data appendBytes:&byte length:1];
    }
    return data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static NSString *TLinkHandleLine(NSString *line)
{
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed isEqualToString:@"ping"]) {
        return [NSString stringWithFormat:@"0;;uiservice_ready;;version=8;;pid=%d;;uid=%d;;euid=%d;;gid=%d;;egid=%d;;mobile_identity=%d;;launch_mode=UIKitPluginHostedNoIdleForeground;;application_state=%ld;;system_application_state=%ld;;window_ready=%d;;window_context_id=%u;;window_level=%.1f;;requested_window_level=20000099.9;;window_hidden=%d;;window_key=%d;;system_window=1;;passthrough=1;;secure=%d;;plugin_complete=%d;;foreground_assertion_created=%d;;foreground_assertion_acquired=%d;;foreground_assertion_valid=%d;;request_count=%lu;;invalid_request_count=%lu;;toast_count=%lu;;last_position=%ld;;last_result=%@\r\n",
                getpid(), getuid(), geteuid(), getgid(), getegid(),
                (geteuid() == 501 && getegid() == 501) ? 1 : 0,
                (long)UIApplication.sharedApplication.applicationState,
                (long)TLinkSystemApplicationState(),
                sTLinkWindowReady ? 1 : 0, TLinkToastWindowContextID(), sTLinkToastWindow.windowLevel,
                sTLinkToastWindow.hidden ? 1 : 0, sTLinkToastWindow.isKeyWindow ? 1 : 0,
                sTLinkToastSecure ? 1 : 0, sTLinkPluginCompletionAvailable ? 1 : 0,
                sTLinkForegroundAssertionCreated ? 1 : 0,
                sTLinkForegroundAssertionAcquired ? 1 : 0,
                TLinkForegroundAssertionIsValid() ? 1 : 0,
                (unsigned long)sTLinkRequestCount,
                (unsigned long)sTLinkInvalidRequestCount, (unsigned long)sTLinkToastCount,
                (long)sTLinkLastPosition, sTLinkLastResult ?: @"unknown"];
    }
    sTLinkRequestCount += 1;
    if (![trimmed hasPrefix:@"1;;"]) {
        sTLinkInvalidRequestCount += 1;
        sTLinkLastResult = @"bad_request";
        TLinkWriteUIServiceDiagnostics();
        return @"-1;;bad_request\r\n";
    }
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:[trimmed substringFromIndex:3] options:0];
    NSDictionary *payload = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
    if (![payload isKindOfClass:NSDictionary.class] || ![payload[@"action"] isEqualToString:@"toast"]) {
        sTLinkInvalidRequestCount += 1;
        sTLinkLastResult = @"bad_toast_payload";
        TLinkWriteUIServiceDiagnostics();
        return @"-1;;bad_toast_payload\r\n";
    }
    __block BOOL queued = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        TLinkShowToast(payload);
        queued = YES;
    });
    return queued ? @"0;;toast_queued;;backend=uiservice_window;;passthrough=1\r\n" : @"-1;;toast_queue_failed\r\n";
}

static void TLinkRunServer(void)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) return;
    int yes = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6017);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(server, 8) != 0) {
        TLinkUIServiceLog([NSString stringWithFormat:@"bind/listen 6017 failed errno=%d", errno]);
        close(server);
        return;
    }
    TLinkUIServiceLog(@"listening 127.0.0.1:6017");
    while (1) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
        @autoreleasepool {
            NSString *request = TLinkReadLine(client);
            NSString *response = request.length > 0 ? TLinkHandleLine(request) : @"-1;;empty_request\r\n";
            NSData *data = [response dataUsingEncoding:NSUTF8StringEncoding];
            write(client, data.bytes, data.length);
            close(client);
        }
    }
    close(server);
}

static void TLinkStartServerIfNecessary(void)
{
    if (sTLinkServerStarted) return;
    sTLinkServerStarted = YES;
    NSThread *serverThread = [[NSThread alloc] initWithBlock:^{ TLinkRunServer(); }];
    serverThread.name = @"com.tlinkauto.uiservice.server";
    [serverThread start];
}

@implementation TLinkUIServiceDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)launchOptions;
    TLinkPrepareToastWindow();
    self.window = sTLinkToastWindow;
    TLinkStartServerIfNecessary();
    sTLinkLastResult = @"plugin_delegate_did_finish_launching";
    TLinkUIServiceLog([NSString stringWithFormat:@"plugin delegate ready bundle=%@ class=%@ state=%ld context_id=%u hidden=%d key=%d",
        NSBundle.mainBundle.bundleIdentifier, NSStringFromClass(application.class),
        (long)application.applicationState, TLinkToastWindowContextID(),
        self.window.hidden ? 1 : 0, self.window.isKeyWindow ? 1 : 0]);
    TLinkWriteUIServiceDiagnostics();
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    TLinkUIServiceLog([NSString stringWithFormat:@"applicationDidBecomeActive state=%ld context_id=%u",
        (long)application.applicationState, TLinkToastWindowContextID()]);
    TLinkWriteUIServiceDiagnostics();
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    TLinkUIServiceLog([NSString stringWithFormat:@"applicationDidEnterBackground state=%ld context_id=%u",
        (long)application.applicationState, TLinkToastWindowContextID()]);
    TLinkWriteUIServiceDiagnostics();
}

@end

static void TLinkAcquireForegroundAssertion(void)
{
    if (sTLinkForegroundAssertion) return;
    dlopen("/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices",
           RTLD_LAZY | RTLD_GLOBAL);
    Class assertionClass = NSClassFromString(@"BKSProcessAssertion");
    SEL initializer = NSSelectorFromString(@"initWithPID:flags:reason:name:withHandler:");
    if (!assertionClass || ![assertionClass instancesRespondToSelector:initializer]) {
        TLinkUIServiceLog([NSString stringWithFormat:
            @"foreground assertion unavailable class=%d selector=%d",
            assertionClass ? 1 : 0,
            assertionClass && [assertionClass instancesRespondToSelector:initializer] ? 1 : 0]);
        return;
    }

    // AssertionServices SPI values used by hosted system UI services:
    // PreventTaskSuspend | PreventTaskThrottleDown | AllowIdleSleep |
    // WantsForegroundResourcePriority, with BackgroundUI reason.
    const uint32_t flags = (1u << 0) | (1u << 1) | (1u << 2) | (1u << 3);
    const uint32_t reason = 7;
    id allocation = ((id (*)(id, SEL))objc_msgSend)(assertionClass, @selector(alloc));
    id handler = [^(BOOL acquired) {
        sTLinkForegroundAssertionAcquired = acquired;
        TLinkUIServiceLog([NSString stringWithFormat:
            @"foreground assertion acquisition acquired=%d valid=%d system_state=%ld",
            acquired ? 1 : 0, TLinkForegroundAssertionIsValid() ? 1 : 0,
            (long)TLinkSystemApplicationState()]);
        TLinkWriteUIServiceDiagnostics();
        if (acquired) {
            dispatch_async(dispatch_get_main_queue(), ^{ TLinkRefreshHostedWindow(); });
        }
    } copy];
    sTLinkForegroundAssertion =
        ((id (*)(id, SEL, pid_t, uint32_t, uint32_t, id, id))objc_msgSend)(
            allocation, initializer, getpid(), flags, reason,
            @"TLinkUIService no_idle_foreground", handler);
    sTLinkForegroundAssertionCreated = sTLinkForegroundAssertion != nil;
    TLinkUIServiceLog([NSString stringWithFormat:
        @"foreground assertion requested created=%d valid=%d flags=0x%x reason=%u",
        sTLinkForegroundAssertionCreated ? 1 : 0,
        TLinkForegroundAssertionIsValid() ? 1 : 0, flags, reason]);
}

static BOOL TLinkInitializeUIKitPlugin(void)
{
    void *graphics = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
                            RTLD_LAZY | RTLD_GLOBAL);
    void *backboard = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
                             RTLD_LAZY | RTLD_GLOBAL);
    TLinkUIKitBootstrapFn gsInitialize = graphics
        ? (TLinkUIKitBootstrapFn)dlsym(graphics, "GSInitialize")
        : NULL;
    TLinkUIKitBootstrapFn gsEventInitialize = graphics
        ? (TLinkUIKitBootstrapFn)dlsym(graphics, "GSEventInitialize")
        : NULL;
    TLinkUIKitBootstrapFn bksDisplayServicesStart = backboard
        ? (TLinkUIKitBootstrapFn)dlsym(backboard, "BKSDisplayServicesStart")
        : NULL;
    TLinkUIApplicationInitializeFn initialize =
        (TLinkUIApplicationInitializeFn)dlsym(RTLD_DEFAULT, "UIApplicationInitialize");
    TLinkUIApplicationInstantiateSingletonFn instantiate =
        (TLinkUIApplicationInstantiateSingletonFn)dlsym(RTLD_DEFAULT, "UIApplicationInstantiateSingleton");

    sTLinkGSInitializeAvailable = gsInitialize != NULL;
    sTLinkGSEventInitializeAvailable = gsEventInitialize != NULL;
    sTLinkBKSDisplayServicesStartAvailable = bksDisplayServicesStart != NULL;
    sTLinkUIApplicationInitializeAvailable = initialize != NULL;
    sTLinkUIApplicationInstantiateAvailable = instantiate != NULL;

    Class screenClass = NSClassFromString(@"UIScreen");
    SEL initializeSelector = NSSelectorFromString(@"initialize");
    if (screenClass && [screenClass respondsToSelector:initializeSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(screenClass, initializeSelector);
    }
    (void)CFRunLoopGetCurrent();
    if (gsInitialize) gsInitialize();
    else if (gsEventInitialize) gsEventInitialize();
    if (bksDisplayServicesStart) bksDisplayServicesStart();
    if (initialize) initialize();
    if (instantiate) instantiate([TLinkUIServiceApplication class]);

    UIApplication *application = UIApplication.sharedApplication;
    if (!application || ![application isKindOfClass:TLinkUIServiceApplication.class]) {
        sTLinkLastResult = @"plugin_application_singleton_failed";
        TLinkUIServiceLog([NSString stringWithFormat:
            @"plugin bootstrap failed app=%d class=%@ gs=%d gsevent=%d bks=%d initialize=%d instantiate=%d",
            application ? 1 : 0, application ? NSStringFromClass(application.class) : @"<nil>",
            sTLinkGSInitializeAvailable ? 1 : 0, sTLinkGSEventInitializeAvailable ? 1 : 0,
            sTLinkBKSDisplayServicesStartAvailable ? 1 : 0,
            sTLinkUIApplicationInitializeAvailable ? 1 : 0,
            sTLinkUIApplicationInstantiateAvailable ? 1 : 0]);
        TLinkWriteUIServiceDiagnostics();
        return NO;
    }

    static TLinkUIServiceDelegate *delegate = nil;
    if (!delegate) delegate = [[TLinkUIServiceDelegate alloc] init];
    application.delegate = delegate;
    application.idleTimerDisabled = YES;
    TLinkAcquireForegroundAssertion();
    SEL accessibilityInit = NSSelectorFromString(@"_accessibilityInit");
    if ([application respondsToSelector:accessibilityInit]) {
        ((void (*)(id, SEL))objc_msgSend)(application, accessibilityInit);
    }
    SEL complete = NSSelectorFromString(@"__completeAndRunAsPlugin");
    sTLinkPluginCompletionAvailable = [application respondsToSelector:complete];
    if (!sTLinkPluginCompletionAvailable) {
        sTLinkLastResult = @"plugin_completion_unavailable";
        TLinkUIServiceLog(@"plugin bootstrap failed: __completeAndRunAsPlugin unavailable");
        TLinkWriteUIServiceDiagnostics();
        return NO;
    }

    @try {
        ((void (*)(id, SEL))objc_msgSend)(application, complete);
    } @catch (NSException *exception) {
        sTLinkLastResult = @"plugin_completion_exception";
        TLinkUIServiceLog([NSString stringWithFormat:@"plugin completion exception=%@",
            exception.reason ?: exception.name]);
        TLinkWriteUIServiceDiagnostics();
        return NO;
    }

    TLinkPrepareToastWindow();
    delegate.window = sTLinkToastWindow;
    TLinkStartServerIfNecessary();
    sTLinkLastResult = @"plugin_hosted_ready";
    TLinkUIServiceLog([NSString stringWithFormat:
        @"plugin hosted ready bundle=%@ class=%@ state=%ld system_state=%ld gs=%d gsevent=%d bks=%d initialize=%d instantiate=%d complete=1 assertion_created=%d assertion_acquired=%d assertion_valid=%d context_id=%u hidden=%d key=%d",
        NSBundle.mainBundle.bundleIdentifier, NSStringFromClass(application.class),
        (long)application.applicationState, (long)TLinkSystemApplicationState(),
        sTLinkGSInitializeAvailable ? 1 : 0, sTLinkGSEventInitializeAvailable ? 1 : 0,
        sTLinkBKSDisplayServicesStartAvailable ? 1 : 0,
        sTLinkUIApplicationInitializeAvailable ? 1 : 0,
        sTLinkUIApplicationInstantiateAvailable ? 1 : 0,
        sTLinkForegroundAssertionCreated ? 1 : 0,
        sTLinkForegroundAssertionAcquired ? 1 : 0,
        TLinkForegroundAssertionIsValid() ? 1 : 0,
        TLinkToastWindowContextID(), sTLinkToastWindow.hidden ? 1 : 0,
        sTLinkToastWindow.isKeyWindow ? 1 : 0]);
    TLinkWriteUIServiceDiagnostics();
    return YES;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        (void)argc;
        (void)argv;
        signal(SIGPIPE, SIG_IGN);
        if (geteuid() == 0) {
            NSFileManager *files = NSFileManager.defaultManager;
            NSString *root = @"/var/mobile/Library/TLinkauto";
            NSString *runtime = [root stringByAppendingPathComponent:@"runtime"];
            [files createDirectoryAtPath:runtime withIntermediateDirectories:YES attributes:nil error:nil];
            chown([root fileSystemRepresentation], 501, 501);
            chown([runtime fileSystemRepresentation], 501, 501);
            if (setgid(501) != 0 || setuid(501) != 0) return 74;
        }
        TLinkUIServiceLog([NSString stringWithFormat:@"starting launch_mode=UIKitPluginHostedNoIdleForeground uid=%d euid=%d gid=%d egid=%d",
            getuid(), geteuid(), getgid(), getegid()]);
        if (!TLinkInitializeUIKitPlugin()) return 75;
        CFRunLoopRun();
    }
    return 0;
}
