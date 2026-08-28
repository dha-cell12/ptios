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
#import <objc/runtime.h>

typedef void (*TLinkUIApplicationInitializeFn)(void);
typedef void (*TLinkUIApplicationInstantiateSingletonFn)(Class);
typedef void (*TLinkUIKitBootstrapFn)(void);

static NSString *const kTLinkUIServiceDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/uiservice_toast.plist";
static NSString *sTLinkLastResult = @"starting";
static NSUInteger sTLinkToastCount = 0;
static BOOL sTLinkWindowReady = NO;
static BOOL sTLinkToastSecure = YES;
static BOOL sTLinkToastWindowSecureAtCreation = YES;
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
static BOOL sTLinkWindowServerStarted = NO;
static BOOL sTLinkStatusBarServerStarted = NO;
static BOOL sTLinkSystemWindowOverrideInstalled = NO;
static BOOL sTLinkWindowLevelHookInstalled = NO;
static id sTLinkWindowHostingController = nil;
static NSUInteger sTLinkWindowRegistrationAttempts = 0;
static NSUInteger sTLinkWindowRegistrationSuccesses = 0;
static NSUInteger sTLinkWindowRegistrationFailures = 0;
static BOOL sTLinkHostWindowRegistered = NO;
static BOOL sTLinkToastWindowRegistered = NO;
static uint32_t sTLinkLastRegisteredContextID = 0;
static NSString *sTLinkLastHostingError = @"none";
static const BOOL kTLinkWindowSceneAttachmentEnabled = NO;

@interface TLinkUIServiceApplication : UIApplication @end

@implementation TLinkUIServiceApplication @end

@interface TLinkUIServiceDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
- (void)refreshHostedWindowRegistration;
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
- (BOOL)_isSecure { return sTLinkToastSecure; }
- (BOOL)_shouldCreateContextAsSecure { return sTLinkToastSecure; }
- (BOOL)_ignoresHitTest { return YES; }
@end

@interface TLinkPassthroughHostWindow : UIWindow
@end

@implementation TLinkPassthroughHostWindow
// Match XXTDaemonAppMainWindow: its only window override is
// _ignoresHitTest. Secure behavior comes from the bundle flags.
- (BOOL)_ignoresHitTest { return YES; }
@end

static TLinkPassthroughHostWindow *sTLinkHostWindow = nil;
static UIViewController *sTLinkHostController = nil;
static TLinkPassthroughToastWindow *sTLinkToastWindow = nil;
static UIViewController *sTLinkRootController = nil;

static void TLinkPrepareHostWindow(void);
static void TLinkPrepareToastWindow(void);
static void TLinkStartServerIfNecessary(void);
static void TLinkRefreshHostedWindow(void);
static void TLinkPresentLocalHostWindow(void);
static void TLinkHidePresentationWindowsIfIdle(NSUInteger generation);
static void TLinkUIServiceLog(NSString *message);

static uint32_t TLinkWindowContextID(UIWindow *window)
{
    for (NSString *name in @[@"_contextId", @"contextId"]) {
        SEL selector = NSSelectorFromString(name);
        if ([window respondsToSelector:selector]) {
            return ((uint32_t (*)(id, SEL))objc_msgSend)(window, selector);
        }
    }
    return 0;
}

typedef void (*TLinkSetWindowLevelIMP)(id, SEL, UIWindowLevel);
static TLinkSetWindowLevelIMP sTLinkOriginalSetWindowLevel = NULL;

static BOOL TLinkAlwaysSystemWindow(id self, SEL selector)
{
    (void)self;
    (void)selector;
    return YES;
}

static BOOL TLinkNeverWindowServerHostingManaged(id self, SEL selector)
{
    (void)self;
    (void)selector;
    return NO;
}

static BOOL TLinkInstallSystemWindowOverrides(void)
{
    Class windowClass = UIWindow.class;
    Class metaClass = object_getClass(windowClass);
    SEL systemWindowSelector = NSSelectorFromString(@"_isSystemWindow");
    SEL hostingManagedSelector = NSSelectorFromString(@"_isWindowServerHostingManaged");
    const char *boolTypes = "B@:";

    BOOL classOverride = class_addMethod(metaClass, systemWindowSelector,
                                         (IMP)TLinkAlwaysSystemWindow, boolTypes);
    if (!classOverride) {
        Method method = class_getClassMethod(windowClass, systemWindowSelector);
        classOverride = method && method_setImplementation(method, (IMP)TLinkAlwaysSystemWindow);
    }
    BOOL instanceOverride = class_addMethod(windowClass, hostingManagedSelector,
                                            (IMP)TLinkNeverWindowServerHostingManaged, boolTypes);
    if (!instanceOverride) {
        Method method = class_getInstanceMethod(windowClass, hostingManagedSelector);
        instanceOverride = method && method_setImplementation(method, (IMP)TLinkNeverWindowServerHostingManaged);
    }
    sTLinkSystemWindowOverrideInstalled = classOverride && instanceOverride;
    return sTLinkSystemWindowOverrideInstalled;
}

static BOOL TLinkSetupAccessibilityWindowHosting(void)
{
    if (sTLinkWindowHostingController) return YES;
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
           RTLD_LAZY | RTLD_GLOBAL);
    Class controllerClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");
    if (!controllerClass) {
        sTLinkLastHostingError = @"hosting_controller_class_missing";
        return NO;
    }
    @try {
        sTLinkWindowHostingController = [[controllerClass alloc] init];
    } @catch (NSException *exception) {
        sTLinkLastHostingError = [NSString stringWithFormat:@"hosting_controller_exception_%@",
                                  exception.name ?: @"unknown"];
        return NO;
    }
    if (!sTLinkWindowHostingController) {
        sTLinkLastHostingError = @"hosting_controller_init_failed";
        return NO;
    }
    sTLinkLastHostingError = @"none";
    return YES;
}

static void TLinkUnregisterWindowContext(UIWindow *window)
{
    if (!window || !sTLinkWindowHostingController) return;
    uint32_t contextID = TLinkWindowContextID(window);
    SEL selector = NSSelectorFromString(@"unregisterWindowWithContextID:");
    if (contextID == 0 || ![sTLinkWindowHostingController respondsToSelector:selector]) return;
    @try {
        ((void (*)(id, SEL, uint32_t))objc_msgSend)(sTLinkWindowHostingController,
                                                    selector, contextID);
    } @catch (__unused NSException *exception) {}
    if (window == sTLinkHostWindow) sTLinkHostWindowRegistered = NO;
    if (window == sTLinkToastWindow) sTLinkToastWindowRegistered = NO;
}

static BOOL TLinkRegisterWindowContext(UIWindow *window, UIWindowLevel level)
{
    sTLinkWindowRegistrationAttempts += 1;
    if (!window || !TLinkSetupAccessibilityWindowHosting()) {
        sTLinkWindowRegistrationFailures += 1;
        return NO;
    }
    uint32_t contextID = TLinkWindowContextID(window);
    if (contextID == 0) {
        sTLinkWindowRegistrationFailures += 1;
        sTLinkLastHostingError = @"window_context_id_zero";
        return NO;
    }
    SEL unregisterSelector = NSSelectorFromString(@"unregisterWindowWithContextID:");
    SEL registerSelector = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    if (![sTLinkWindowHostingController respondsToSelector:unregisterSelector] ||
        ![sTLinkWindowHostingController respondsToSelector:registerSelector]) {
        sTLinkWindowRegistrationFailures += 1;
        sTLinkLastHostingError = @"hosting_controller_selector_missing";
        return NO;
    }
    @try {
        ((void (*)(id, SEL, uint32_t))objc_msgSend)(sTLinkWindowHostingController,
                                                    unregisterSelector, contextID);
        ((void (*)(id, SEL, uint32_t, double))objc_msgSend)(sTLinkWindowHostingController,
                                                            registerSelector, contextID,
                                                            (double)level);
    } @catch (NSException *exception) {
        sTLinkWindowRegistrationFailures += 1;
        sTLinkLastHostingError = [NSString stringWithFormat:@"window_registration_exception_%@",
                                  exception.name ?: @"unknown"];
        return NO;
    }
    sTLinkWindowRegistrationSuccesses += 1;
    sTLinkLastRegisteredContextID = contextID;
    sTLinkLastHostingError = @"none";
    if (window == sTLinkHostWindow) sTLinkHostWindowRegistered = YES;
    if (window == sTLinkToastWindow) sTLinkToastWindowRegistered = YES;
    return YES;
}

static void TLinkHostedSetWindowLevel(id object, SEL selector, UIWindowLevel level)
{
    UIWindow *window = [object isKindOfClass:UIWindow.class] ? (UIWindow *)object : nil;
    BOOL registered = TLinkRegisterWindowContext(window, level);
    if (sTLinkOriginalSetWindowLevel) {
        sTLinkOriginalSetWindowLevel(object, selector, level);
    }
    if (!registered && window && TLinkWindowContextID(window) != 0) {
        TLinkRegisterWindowContext(window, level);
    }
}

static BOOL TLinkInstallWindowLevelHostingHook(void)
{
    Method method = class_getInstanceMethod(UIWindow.class, @selector(setWindowLevel:));
    if (!method) {
        sTLinkLastHostingError = @"set_window_level_method_missing";
        return NO;
    }
    IMP current = method_getImplementation(method);
    if (current == (IMP)TLinkHostedSetWindowLevel) {
        sTLinkWindowLevelHookInstalled = YES;
        return YES;
    }
    sTLinkOriginalSetWindowLevel =
        (TLinkSetWindowLevelIMP)method_setImplementation(method, (IMP)TLinkHostedSetWindowLevel);
    sTLinkWindowLevelHookInstalled = sTLinkOriginalSetWindowLevel != NULL;
    if (!sTLinkWindowLevelHookInstalled) sTLinkLastHostingError = @"set_window_level_hook_failed";
    return sTLinkWindowLevelHookInstalled;
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

static UIWindow *TLinkCurrentApplicationKeyWindow(void)
{
    UIApplication *application = UIApplication.sharedApplication;
    for (NSString *name in @[@"keyWindow", @"_keyWindow"]) {
        SEL selector = NSSelectorFromString(name);
        if ([application respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(application, selector);
            if ([value isKindOfClass:UIWindow.class]) return (UIWindow *)value;
        }
    }
    return nil;
}

static void TLinkPresentLocalHostWindow(void)
{
    if (!sTLinkHostWindow) return;
    sTLinkHostWindow.hidden = NO;
    [sTLinkHostWindow makeKeyAndVisible];
}

static void TLinkHidePresentationWindowsIfIdle(NSUInteger generation)
{
    if (generation != sTLinkToastGeneration) return;
    if (sTLinkToastBubble) return;
    sTLinkToastWindow.hidden = YES;
    sTLinkHostWindow.hidden = YES;
}

static void TLinkWriteUIServiceDiagnostics(void)
{
    NSString *directory = [kTLinkUIServiceDiagnosticsPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *status = @{
        @"version": @22,
        @"pid": @(getpid()),
        @"uid": @(getuid()),
        @"euid": @(geteuid()),
        @"gid": @(getgid()),
        @"egid": @(getegid()),
        @"mobile_identity": @(geteuid() == 501 && getegid() == 501),
        @"window_ready": @(sTLinkWindowReady),
        @"launch_mode": @"UIKitPluginSBSAccessibilityContextHosting",
        @"bootstrap_gs_initialize": @(sTLinkGSInitializeAvailable),
        @"bootstrap_gs_event_initialize": @(sTLinkGSEventInitializeAvailable),
        @"bootstrap_bks_display_services": @(sTLinkBKSDisplayServicesStartAvailable),
        @"bootstrap_uiapplication_initialize": @(sTLinkUIApplicationInitializeAvailable),
        @"bootstrap_uiapplication_instantiate": @(sTLinkUIApplicationInstantiateAvailable),
        @"bootstrap_complete_as_plugin": @(sTLinkPluginCompletionAvailable),
        @"bootstrap_window_server": @(sTLinkWindowServerStarted),
        @"bootstrap_status_bar_server": @(sTLinkStatusBarServerStarted),
        @"system_window_override_installed": @(sTLinkSystemWindowOverrideInstalled),
        @"window_level_hook_installed": @(sTLinkWindowLevelHookInstalled),
        @"accessibility_hosting_controller_available": @(sTLinkWindowHostingController != nil),
        @"window_registration_attempts": @(sTLinkWindowRegistrationAttempts),
        @"window_registration_successes": @(sTLinkWindowRegistrationSuccesses),
        @"window_registration_failures": @(sTLinkWindowRegistrationFailures),
        @"last_registered_context_id": @(sTLinkLastRegisteredContextID),
        @"last_hosting_error": sTLinkLastHostingError ?: @"unknown",
        @"host_window_registered": @(sTLinkHostWindowRegistered),
        @"toast_window_registered": @(sTLinkToastWindowRegistered),
        @"foreground_scene_created": @NO,
        @"presentation_binder_created": @NO,
        @"window_scene_attachment_enabled": @(kTLinkWindowSceneAttachmentEnabled),
        @"host_window_context_zero": @(TLinkWindowContextID(sTLinkHostWindow) == 0),
        @"toast_window_context_zero": @(TLinkWindowContextID(sTLinkToastWindow) == 0),
        @"application_key_window_matches_host": @(TLinkCurrentApplicationKeyWindow() == sTLinkHostWindow),
        @"display_entitlement_contract_declared": @YES,
        @"passthrough_transparency_enforced": @YES,
        @"connected_scene_count": @(UIApplication.sharedApplication.connectedScenes.count),
        @"application_window_count": @(UIApplication.sharedApplication.windows.count),
        @"window_level": @(sTLinkToastWindow.windowLevel),
        @"requested_window_level": @20000099.9,
        @"requested_host_window_level": @10000010.0,
        @"window_context_id": @(TLinkWindowContextID(sTLinkToastWindow)),
        @"window_scene_attached": @NO,
        @"window_scene_activation_state": @(-1),
        @"window_hidden": @(sTLinkToastWindow.hidden),
        @"window_key": @(sTLinkToastWindow.isKeyWindow),
        @"window_width": @(CGRectGetWidth(sTLinkToastWindow.bounds)),
        @"window_height": @(CGRectGetHeight(sTLinkToastWindow.bounds)),
        @"host_window_ready": @(sTLinkHostWindow != nil),
        @"host_window_level": @(sTLinkHostWindow.windowLevel),
        @"host_window_context_id": @(TLinkWindowContextID(sTLinkHostWindow)),
        @"host_window_scene_attached": @NO,
        @"host_window_scene_activation_state": @(-1),
        @"host_window_hidden": @(sTLinkHostWindow.hidden),
        @"host_window_key": @(sTLinkHostWindow.isKeyWindow),
        @"application_state": @(UIApplication.sharedApplication ? UIApplication.sharedApplication.applicationState : -1),
        @"secure": @(sTLinkToastSecure),
        @"window_secure_at_creation": @(sTLinkToastWindowSecureAtCreation),
        @"render_mode": @"xxtouch_sbs_accessibility_context_registration",
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

static void TLinkPrepareHostWindow(void)
{
    if (sTLinkHostWindow) return;
    sTLinkHostWindow = [[TLinkPassthroughHostWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    sTLinkHostWindow.backgroundColor = UIColor.clearColor;
    sTLinkHostWindow.opaque = NO;
    sTLinkHostWindow.layer.opaque = NO;
    sTLinkHostController = [[UIViewController alloc] init];
    sTLinkHostController.view.backgroundColor = UIColor.clearColor;
    sTLinkHostController.view.opaque = NO;
    sTLinkHostController.view.layer.opaque = NO;
    sTLinkHostWindow.rootViewController = sTLinkHostController;
    sTLinkHostWindow.windowLevel = (UIWindowLevel)10000010.0;
    sTLinkHostWindow.hidden = YES;
    TLinkRegisterWindowContext(sTLinkHostWindow, sTLinkHostWindow.windowLevel);
}

static void TLinkPrepareToastWindow(void)
{
    if (sTLinkToastWindow) return;
    sTLinkToastWindow = [[TLinkPassthroughToastWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    sTLinkToastWindowSecureAtCreation = sTLinkToastSecure;
    sTLinkToastWindow.backgroundColor = UIColor.clearColor;
    sTLinkToastWindow.opaque = NO;
    sTLinkToastWindow.layer.opaque = NO;
    sTLinkToastWindow.userInteractionEnabled = NO;
    sTLinkRootController = [[UIViewController alloc] init];
    sTLinkRootController.view.backgroundColor = UIColor.clearColor;
    sTLinkRootController.view.opaque = NO;
    sTLinkRootController.view.layer.opaque = NO;
    sTLinkRootController.view.userInteractionEnabled = NO;
    sTLinkToastWindow.rootViewController = sTLinkRootController;
    TLinkSetSecureForToast(sTLinkToastSecure);
    sTLinkToastWindow.windowLevel = (UIWindowLevel)20000099.9;
    sTLinkToastWindow.hidden = YES;
    sTLinkToastWindowRegistered = TLinkRegisterWindowContext(
        sTLinkToastWindow, sTLinkToastWindow.windowLevel);
    sTLinkWindowReady = sTLinkToastWindowRegistered;
    sTLinkLastResult = sTLinkWindowReady
        ? @"window_ready_accessibility_hosted"
        : @"window_not_compositor_hosted";
    TLinkWriteUIServiceDiagnostics();
}

static void TLinkRefreshHostedWindow(void)
{
    [sTLinkHostWindow setNeedsLayout];
    [sTLinkHostController.view setNeedsLayout];
    [sTLinkToastWindow setNeedsLayout];
    [sTLinkRootController.view setNeedsLayout];
    [sTLinkRootController.view setNeedsDisplay];
    [CATransaction flush];
}

static void TLinkShowToast(NSDictionary *payload)
{
    BOOL allowScreenshot = [payload[@"allow_screenshot"] boolValue];
    // Select the CA context security before the lazy window is created.
    // Changing it after init is too late for the initial compositor context.
    sTLinkToastSecure = !allowScreenshot;
    if (sTLinkToastWindow && sTLinkToastWindowSecureAtCreation != sTLinkToastSecure) {
        [sTLinkToastBubble removeFromSuperview];
        sTLinkToastBubble = nil;
        TLinkUnregisterWindowContext(sTLinkToastWindow);
        sTLinkToastWindow.hidden = YES;
        sTLinkToastWindow.rootViewController = nil;
        sTLinkToastWindow = nil;
        sTLinkRootController = nil;
        sTLinkWindowReady = NO;
    }
    TLinkPrepareToastWindow();
    NSString *message = [payload[@"message"] isKindOfClass:NSString.class] ? payload[@"message"] : @"";
    if (message.length == 0) {
        TLinkHidePresentationWindowsIfIdle(sTLinkToastGeneration);
        return;
    }
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
    TLinkSetSecureForToast(!allowScreenshot);
    sTLinkLastPosition = position;

    [sTLinkToastBubble.layer removeAllAnimations];
    [sTLinkToastBubble removeFromSuperview];
    sTLinkToastBubble = nil;
    NSUInteger generation = ++sTLinkToastGeneration;

    CGRect bounds = UIScreen.mainScreen.bounds;
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
    UIEdgeInsets safe = sTLinkHostWindow.safeAreaInsets;
    CGFloat y = position == 0
        ? safe.top + 24.0
        : (position == 1
            ? (CGRectGetHeight(bounds) - height) * 0.5
            : CGRectGetHeight(bounds) - safe.bottom - height - 82.0);
    CGFloat x = (CGRectGetWidth(bounds) - width) * 0.5;

    CGRect presentationFrame = CGRectMake(x, y, width, height);
    sTLinkHostWindow.frame = bounds;
    sTLinkToastWindow.frame = bounds;
    sTLinkHostController.view.frame = sTLinkHostWindow.bounds;
    sTLinkRootController.view.frame = sTLinkToastWindow.bounds;

    UIView *bubble = [[UIView alloc] initWithFrame:presentationFrame];
    bubble.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.86];
    bubble.layer.cornerRadius = 10.0;
    bubble.layer.shadowColor = UIColor.blackColor.CGColor;
    bubble.layer.shadowOpacity = 0.22;
    bubble.layer.shadowRadius = 10.0;
    bubble.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    bubble.userInteractionEnabled = NO;
    // The hosted plugin normally reports UIApplicationStateBackground. Commit
    // visible model-layer state directly because the context is hosted by SBS.
    bubble.alpha = 1.0;
    bubble.transform = CGAffineTransformIdentity;
    label.frame = CGRectInset(bubble.bounds, 16.0, 10.0);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [bubble addSubview:label];
    [sTLinkRootController.view addSubview:bubble];
    [sTLinkRootController.view bringSubviewToFront:bubble];
    BOOL hostRegistered = TLinkRegisterWindowContext(sTLinkHostWindow,
                                                     sTLinkHostWindow.windowLevel);
    BOOL toastRegistered = TLinkRegisterWindowContext(sTLinkToastWindow,
                                                      sTLinkToastWindow.windowLevel);
    if (!hostRegistered || !toastRegistered) {
        [bubble removeFromSuperview];
        sTLinkToastBubble = nil;
        sTLinkHostWindow.hidden = YES;
        sTLinkToastWindow.hidden = YES;
        sTLinkLastResult = @"toast_rejected_no_compositor_hosting";
        TLinkUIServiceLog([NSString stringWithFormat:
            @"toast rejected host_registered=%d toast_registered=%d host_context_id=%u toast_context_id=%u error=%@",
            hostRegistered ? 1 : 0, toastRegistered ? 1 : 0,
            TLinkWindowContextID(sTLinkHostWindow), TLinkWindowContextID(sTLinkToastWindow),
            sTLinkLastHostingError ?: @"unknown"]);
        TLinkWriteUIServiceDiagnostics();
        return;
    }
    sTLinkWindowReady = YES;
    TLinkPresentLocalHostWindow();
    sTLinkToastWindow.hidden = NO;
    sTLinkToastBubble = bubble;
    sTLinkToastCount += 1;
    sTLinkLastResult = [NSString stringWithFormat:@"toast_visible_position_%ld", (long)position];
    TLinkUIServiceLog([NSString stringWithFormat:@"toast visible count=%lu position=%ld duration=%.2f secure=%d app_state=%ld hosting_controller=%d host_registered=%d toast_registered=%d host_context_id=%u host_hidden=%d host_key=%d app_key_matches=%d toast_context_id=%u",
        (unsigned long)sTLinkToastCount, (long)position, duration, sTLinkToastSecure ? 1 : 0,
        (long)UIApplication.sharedApplication.applicationState,
        sTLinkWindowHostingController ? 1 : 0,
        sTLinkHostWindowRegistered ? 1 : 0, sTLinkToastWindowRegistered ? 1 : 0,
        TLinkWindowContextID(sTLinkHostWindow),
        sTLinkHostWindow.hidden ? 1 : 0, sTLinkHostWindow.isKeyWindow ? 1 : 0,
        TLinkCurrentApplicationKeyWindow() == sTLinkHostWindow ? 1 : 0,
        TLinkWindowContextID(sTLinkToastWindow)]);
    TLinkWriteUIServiceDiagnostics();
    TLinkRefreshHostedWindow();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != sTLinkToastGeneration) return;
        [bubble removeFromSuperview];
        sTLinkToastBubble = nil;
        TLinkHidePresentationWindowsIfIdle(generation);
        sTLinkLastResult = @"toast_hidden";
        TLinkWriteUIServiceDiagnostics();
        TLinkRefreshHostedWindow();
    });
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
        return [NSString stringWithFormat:@"0;;uiservice_ready;;version=22;;pid=%d;;uid=%d;;euid=%d;;gid=%d;;egid=%d;;mobile_identity=%d;;launch_mode=UIKitPluginSBSAccessibilityContextHosting;;application_state=%ld;;window_ready=%d;;window_context_id=%u;;window_scene_attached=0;;window_scene_activation_state=-1;;window_level=%.1f;;requested_window_level=20000099.9;;window_hidden=%d;;window_key=%d;;host_window_ready=%d;;host_window_context_id=%u;;host_window_scene_attached=0;;host_window_scene_activation_state=-1;;host_window_level=%.1f;;requested_host_window_level=10000010.0;;host_window_hidden=%d;;host_window_key=%d;;ignores_hit_test=1;;passthrough=1;;secure=%d;;render_mode=xxtouch_sbs_accessibility_context_registration;;plugin_complete=%d;;window_server_started=%d;;status_bar_server_started=%d;;system_window_override_installed=%d;;window_level_hook_installed=%d;;accessibility_hosting_controller_available=%d;;window_scene_attachment_enabled=0;;host_window_registered=%d;;toast_window_registered=%d;;window_registration_attempts=%lu;;window_registration_successes=%lu;;window_registration_failures=%lu;;last_registered_context_id=%u;;last_hosting_error=%@;;request_count=%lu;;invalid_request_count=%lu;;toast_count=%lu;;last_position=%ld;;last_result=%@\r\n",
                getpid(), getuid(), geteuid(), getgid(), getegid(),
                (geteuid() == 501 && getegid() == 501) ? 1 : 0,
                (long)UIApplication.sharedApplication.applicationState,
                sTLinkWindowReady ? 1 : 0, TLinkWindowContextID(sTLinkToastWindow),
                sTLinkToastWindow.windowLevel,
                sTLinkToastWindow.hidden ? 1 : 0, sTLinkToastWindow.isKeyWindow ? 1 : 0,
                sTLinkHostWindow ? 1 : 0, TLinkWindowContextID(sTLinkHostWindow),
                sTLinkHostWindow.windowLevel, sTLinkHostWindow.hidden ? 1 : 0,
                sTLinkHostWindow.isKeyWindow ? 1 : 0,
                sTLinkToastSecure ? 1 : 0, sTLinkPluginCompletionAvailable ? 1 : 0,
                sTLinkWindowServerStarted ? 1 : 0,
                sTLinkStatusBarServerStarted ? 1 : 0,
                sTLinkSystemWindowOverrideInstalled ? 1 : 0,
                sTLinkWindowLevelHookInstalled ? 1 : 0,
                sTLinkWindowHostingController ? 1 : 0,
                sTLinkHostWindowRegistered ? 1 : 0,
                sTLinkToastWindowRegistered ? 1 : 0,
                (unsigned long)sTLinkWindowRegistrationAttempts,
                (unsigned long)sTLinkWindowRegistrationSuccesses,
                (unsigned long)sTLinkWindowRegistrationFailures,
                sTLinkLastRegisteredContextID,
                sTLinkLastHostingError ?: @"unknown",
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
    TLinkPrepareHostWindow();
    self.window = sTLinkHostWindow;
    self.window.hidden = YES;
    TLinkRefreshHostedWindow();
    TLinkStartServerIfNecessary();
    sTLinkLastResult = @"plugin_delegate_did_finish_launching";
    TLinkUIServiceLog([NSString stringWithFormat:@"plugin delegate ready bundle=%@ class=%@ state=%ld hosting_controller=%d host_registered=%d host_context_id=%u host_hidden=%d host_key=%d toast_context_id=%u toast_hidden=%d toast_key=%d",
        NSBundle.mainBundle.bundleIdentifier, NSStringFromClass(application.class),
        (long)application.applicationState, sTLinkWindowHostingController ? 1 : 0,
        sTLinkHostWindowRegistered ? 1 : 0, TLinkWindowContextID(sTLinkHostWindow),
        sTLinkHostWindow.hidden ? 1 : 0, sTLinkHostWindow.isKeyWindow ? 1 : 0,
        TLinkWindowContextID(sTLinkToastWindow), sTLinkToastWindow.hidden ? 1 : 0,
        sTLinkToastWindow.isKeyWindow ? 1 : 0]);
    TLinkWriteUIServiceDiagnostics();
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    TLinkUIServiceLog([NSString stringWithFormat:@"applicationDidBecomeActive state=%ld context_id=%u",
        (long)application.applicationState, TLinkWindowContextID(sTLinkHostWindow)]);
    TLinkWriteUIServiceDiagnostics();
}

- (void)refreshHostedWindowRegistration
{
    if (sTLinkToastBubble) {
        TLinkRegisterWindowContext(sTLinkHostWindow, sTLinkHostWindow.windowLevel);
        TLinkRegisterWindowContext(sTLinkToastWindow, sTLinkToastWindow.windowLevel);
        TLinkPresentLocalHostWindow();
        TLinkRefreshHostedWindow();
    }
}

@end

#if 0
// Retained temporarily as deactivated migration reference. Rendering must never
// attach a UIWindow to a synthetic FrontBoard scene; SBS hosts CA contexts.
static id TLinkSendObject(id target, NSString *selectorName)
{
    SEL selector = NSSelectorFromString(selectorName);
    return target && [target respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(target, selector)
        : nil;
}

static UIWindowScene *TLinkWindowSceneFromObjectGraph(id value,
                                                       NSInteger depth,
                                                       NSMutableSet<NSValue *> *visited)
{
    if (!value || depth < 0 || visited.count >= 256) return nil;
    if ([value isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)value;
    if ([value isKindOfClass:UIWindow.class]) return ((UIWindow *)value).windowScene;

    NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)value];
    if ([visited containsObject:identity]) return nil;
    [visited addObject:identity];

    if ([value isKindOfClass:NSDictionary.class]) {
        for (id child in [(NSDictionary *)value allValues]) {
            UIWindowScene *scene = TLinkWindowSceneFromObjectGraph(child, depth - 1, visited);
            if (scene) return scene;
        }
        return nil;
    }
    if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSSet.class] ||
        [value isKindOfClass:NSOrderedSet.class]) {
        for (id child in value) {
            UIWindowScene *scene = TLinkWindowSceneFromObjectGraph(child, depth - 1, visited);
            if (scene) return scene;
        }
        return nil;
    }
    if (depth == 0) return nil;

    NSString *className = NSStringFromClass([value class]);
    BOOL mayOwnScene = [className containsString:@"Binder"] ||
                       [className containsString:@"Presentation"] ||
                       [className containsString:@"StateMachine"] ||
                       [className containsString:@"Scene"] ||
                       [className containsString:@"RootWindow"] ||
                       [className hasPrefix:@"FB"] || [className hasPrefix:@"_UI"];
    if (!mayOwnScene) return nil;

    for (Class current = object_getClass(value); current; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(current, &count);
        for (unsigned int index = 0; index < count; index++) {
            const char *type = ivar_getTypeEncoding(ivars[index]);
            if (!type || type[0] != '@') continue;
            id child = object_getIvar(value, ivars[index]);
            UIWindowScene *scene = TLinkWindowSceneFromObjectGraph(child, depth - 1, visited);
            if (scene) {
                free(ivars);
                return scene;
            }
        }
        free(ivars);
    }
    return nil;
}

static UIWindowScene *TLinkDiscoverHostedWindowScene(void)
{
    if (@available(iOS 13.0, *)) {
        if (sTLinkDiscoveredWindowScene) return sTLinkDiscoveredWindowScene;
        UIApplication *application = UIApplication.sharedApplication;
        for (UIScene *scene in application.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                sTLinkDiscoveredWindowScene = (UIWindowScene *)scene;
                sTLinkSceneDiscoverySource = @"UIApplication.connectedScenes";
                return sTLinkDiscoveredWindowScene;
            }
        }
        for (UIWindow *window in application.windows) {
            if (window.windowScene) {
                sTLinkDiscoveredWindowScene = window.windowScene;
                sTLinkSceneDiscoverySource = @"UIApplication.windows";
                return sTLinkDiscoveredWindowScene;
            }
        }

        NSArray<NSString *> *applicationSelectors = @[
            @"_findUISceneForLegacyInterfaceOrientation", @"_allScenes",
            @"_connectedScenes", @"windowScenes", @"_windowScenes"
        ];
        for (NSString *selectorName in applicationSelectors) {
            id candidate = TLinkSendObject(application, selectorName);
            UIWindowScene *scene = TLinkWindowSceneFromObjectGraph(
                candidate, 3, [NSMutableSet set]);
            if (scene) {
                sTLinkDiscoveredWindowScene = scene;
                sTLinkSceneDiscoverySource = [@"UIApplication." stringByAppendingString:selectorName];
                return scene;
            }
        }

        NSArray *roots = @[
            sTLinkPresentationBinder ?: NSNull.null,
            sTLinkForegroundScene ?: NSNull.null,
        ];
        NSArray<NSString *> *keys = @[
            @"windowScene", @"_windowScene", @"hostingWindow", @"_hostingWindow",
            @"rootWindow", @"_rootWindow", @"window", @"_window",
            @"stateMachine", @"_stateMachine", @"presentationWindow", @"_presentationWindow"
        ];
        for (id root in roots) {
            if (root == NSNull.null) continue;
            for (NSString *key in keys) {
                @try {
                    id candidate = [root valueForKey:key];
                    UIWindowScene *scene = TLinkWindowSceneFromObjectGraph(
                        candidate, 4, [NSMutableSet set]);
                    if (scene) {
                        sTLinkDiscoveredWindowScene = scene;
                        sTLinkSceneDiscoverySource = [NSString stringWithFormat:@"%@.%@",
                            NSStringFromClass([root class]), key];
                        return scene;
                    }
                } @catch (__unused NSException *exception) {}
            }
            UIWindowScene *scene = TLinkWindowSceneFromObjectGraph(
                root, 6, [NSMutableSet set]);
            if (scene) {
                sTLinkDiscoveredWindowScene = scene;
                sTLinkSceneDiscoverySource = [NSString stringWithFormat:@"%@.object_graph",
                    NSStringFromClass([root class])];
                return scene;
            }
        }
    }
    return nil;
}

static BOOL TLinkSetupCompactPresentationScene(CGRect presentationFrame)
{
    if (!kTLinkCompactPresentationSceneEnabled || CGRectIsEmpty(presentationFrame)) return NO;
    if (sTLinkForegroundSceneSetupAttempted) {
        if (sTLinkForegroundSceneSetupSucceeded) {
            TLinkSetCompactScenePresentation(presentationFrame, YES);
        }
        return sTLinkForegroundSceneSetupSucceeded;
    }
    sTLinkForegroundSceneSetupAttempted = YES;
    dlopen("/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard",
           RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",
           RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore",
           RTLD_LAZY | RTLD_GLOBAL);

    Class definitionClass = NSClassFromString(@"FBSMutableSceneDefinition");
    Class identityClass = NSClassFromString(@"FBSSceneIdentity");
    Class clientIdentityClass = NSClassFromString(@"FBSSceneClientIdentity");
    Class specificationClass = NSClassFromString(@"UIApplicationSceneSpecification");
    Class parametersClass = NSClassFromString(@"FBSMutableSceneParameters");
    Class settingsClass = NSClassFromString(@"UIMutableApplicationSceneSettings");
    Class clientSettingsClass = NSClassFromString(@"UIMutableApplicationSceneClientSettings");
    Class sceneManagerClass = NSClassFromString(@"FBSceneManager");
    Class binderClass = NSClassFromString(@"UIRootWindowScenePresentationBinder");
    NSArray *requiredClasses = @[
        definitionClass ?: NSNull.null, identityClass ?: NSNull.null,
        clientIdentityClass ?: NSNull.null, specificationClass ?: NSNull.null,
        parametersClass ?: NSNull.null, settingsClass ?: NSNull.null,
        clientSettingsClass ?: NSNull.null, sceneManagerClass ?: NSNull.null,
        binderClass ?: NSNull.null,
    ];
    if ([requiredClasses containsObject:NSNull.null]) {
        sTLinkLastResult = @"frontboard_scene_class_missing";
        TLinkUIServiceLog([NSString stringWithFormat:@"foreground scene class missing availability=%@",
            [requiredClasses valueForKey:@"description"]]);
        TLinkWriteUIServiceDiagnostics();
        return NO;
    }

    @try {
        UIScreen *screen = UIScreen.mainScreen;
        id displayConfiguration = TLinkSendObject(screen, @"displayConfiguration");
        id definition = TLinkSendObject(definitionClass, @"definition");
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"com.tlinkauto.streamcontrol.uiservice";
        NSString *sceneIdentifier = [bundleIdentifier stringByAppendingString:@".compact-toast"];
        id identity = ((id (*)(id, SEL, id))objc_msgSend)(
            identityClass, NSSelectorFromString(@"identityForIdentifier:"), sceneIdentifier);
        id clientIdentity = TLinkSendObject(clientIdentityClass, @"localIdentity");
        id specification = TLinkSendObject(specificationClass, @"specification");
        ((void (*)(id, SEL, id))objc_msgSend)(definition, NSSelectorFromString(@"setIdentity:"), identity);
        ((void (*)(id, SEL, id))objc_msgSend)(definition, NSSelectorFromString(@"setClientIdentity:"), clientIdentity);
        ((void (*)(id, SEL, id))objc_msgSend)(definition, NSSelectorFromString(@"setSpecification:"), specification);

        id definitionSpecification = TLinkSendObject(definition, @"specification");
        id parameters = ((id (*)(id, SEL, id))objc_msgSend)(
            parametersClass, NSSelectorFromString(@"parametersForSpecification:"), definitionSpecification);
        id settings = TLinkSendObject(settingsClass, @"new");
        ((void (*)(id, SEL, id))objc_msgSend)(settings, NSSelectorFromString(@"setDisplayConfiguration:"), displayConfiguration);
        ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, NSSelectorFromString(@"setFrame:"), presentationFrame);
        ((void (*)(id, SEL, double))objc_msgSend)(settings, NSSelectorFromString(@"setLevel:"), 1.0);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(settings, NSSelectorFromString(@"setForeground:"), YES);
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, NSSelectorFromString(@"setInterfaceOrientation:"), 1);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(settings, NSSelectorFromString(@"setDeviceOrientationEventsEnabled:"), NO);
        SEL peripherySelector = NSSelectorFromString(@"_displayPeripheryInsets");
        if ([screen respondsToSelector:peripherySelector] &&
            [settings respondsToSelector:NSSelectorFromString(@"setSafeAreaInsetsPortrait:")]) {
            UIEdgeInsets insets = ((UIEdgeInsets (*)(id, SEL))objc_msgSend)(screen, peripherySelector);
            ((void (*)(id, SEL, UIEdgeInsets))objc_msgSend)(
                settings, NSSelectorFromString(@"setSafeAreaInsetsPortrait:"), insets);
        }
        id ignoreReasons = TLinkSendObject(settings, @"ignoreOcclusionReasons");
        if ([ignoreReasons respondsToSelector:@selector(addObject:)]) {
            [ignoreReasons addObject:@"SystemApp"];
        }
        ((void (*)(id, SEL, id))objc_msgSend)(parameters, NSSelectorFromString(@"setSettings:"), settings);

        id clientSettings = TLinkSendObject(clientSettingsClass, @"new");
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(clientSettings, NSSelectorFromString(@"setInterfaceOrientation:"), 1);
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(clientSettings, NSSelectorFromString(@"setStatusBarStyle:"), 0);
        ((void (*)(id, SEL, id))objc_msgSend)(parameters, NSSelectorFromString(@"setClientSettings:"), clientSettings);

        id sceneManager = TLinkSendObject(sceneManagerClass, @"sharedInstance");
        id scene = ((id (*)(id, SEL, id, id))objc_msgSend)(
            sceneManager, NSSelectorFromString(@"createSceneWithDefinition:initialParameters:"),
            definition, parameters);
        id binderAllocation = ((id (*)(id, SEL))objc_msgSend)(binderClass, @selector(alloc));
        id binder = ((id (*)(id, SEL, NSInteger, id))objc_msgSend)(
            binderAllocation, NSSelectorFromString(@"initWithPriority:displayConfiguration:"),
            0, displayConfiguration);
        if (binder && scene) {
            ((void (*)(id, SEL, id))objc_msgSend)(binder, NSSelectorFromString(@"addScene:"), scene);
        }
        sTLinkForegroundSceneSettings = settings;
        sTLinkForegroundScene = scene;
        sTLinkPresentationBinder = binder;
        sTLinkForegroundSceneSetupSucceeded = scene && binder && TLinkForegroundSceneIsForeground();
        sTLinkLastResult = sTLinkForegroundSceneSetupSucceeded
            ? @"frontboard_scene_ready"
            : @"frontboard_scene_incomplete";
        TLinkUIServiceLog([NSString stringWithFormat:
            @"foreground scene setup success=%d scene=%d binder=%d foreground=%d identifier=%@ frame=%.1fx%.1f",
            sTLinkForegroundSceneSetupSucceeded ? 1 : 0, scene ? 1 : 0, binder ? 1 : 0,
            TLinkForegroundSceneIsForeground() ? 1 : 0, sceneIdentifier,
            CGRectGetWidth(presentationFrame), CGRectGetHeight(presentationFrame)]);
    } @catch (NSException *exception) {
        sTLinkForegroundSceneSetupSucceeded = NO;
        sTLinkLastResult = @"frontboard_scene_exception";
        TLinkUIServiceLog([NSString stringWithFormat:@"foreground scene exception=%@",
            exception.reason ?: exception.name]);
    }
    TLinkWriteUIServiceDiagnostics();
    return sTLinkForegroundSceneSetupSucceeded;
}

static void TLinkSetCompactScenePresentation(CGRect presentationFrame, BOOL foreground)
{
    if (!sTLinkForegroundScene || !sTLinkForegroundSceneSettings) return;
    @try {
        ((void (*)(id, SEL, CGRect))objc_msgSend)(
            sTLinkForegroundSceneSettings, NSSelectorFromString(@"setFrame:"), presentationFrame);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            sTLinkForegroundSceneSettings, NSSelectorFromString(@"setForeground:"), foreground);
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(
            sTLinkForegroundScene,
            NSSelectorFromString(@"updateSettings:withTransitionContext:completion:"),
            sTLinkForegroundSceneSettings, nil, nil);
        if (foreground) TLinkRefreshHostedWindow();
    } @catch (NSException *exception) {
        sTLinkLastResult = @"frontboard_scene_update_exception";
        TLinkUIServiceLog([NSString stringWithFormat:@"foreground scene update exception=%@",
            exception.reason ?: exception.name]);
        TLinkWriteUIServiceDiagnostics();
    }
}
#endif

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

    BOOL systemWindowReady = TLinkInstallSystemWindowOverrides();
    BOOL windowLevelHookReady = TLinkInstallWindowLevelHostingHook();
    TLinkSetupAccessibilityWindowHosting();
    if (!systemWindowReady || !windowLevelHookReady) {
        sTLinkLastResult = @"window_hosting_bootstrap_failed";
        TLinkUIServiceLog([NSString stringWithFormat:
            @"window hosting bootstrap failed system_override=%d level_hook=%d controller=%d error=%@",
            systemWindowReady ? 1 : 0, windowLevelHookReady ? 1 : 0,
            sTLinkWindowHostingController ? 1 : 0, sTLinkLastHostingError ?: @"unknown"]);
        TLinkWriteUIServiceDiagnostics();
        return NO;
    }

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
    Class applicationClass = TLinkUIServiceApplication.class;
    SEL startWindowServer = NSSelectorFromString(@"_startWindowServerIfNecessary");
    if ([applicationClass respondsToSelector:startWindowServer]) {
        ((void (*)(id, SEL))objc_msgSend)(applicationClass, startWindowServer);
        sTLinkWindowServerStarted = YES;
    }
    SEL startStatusBarServer = NSSelectorFromString(@"_startStatusBarServerIfNecessary");
    if ([applicationClass respondsToSelector:startStatusBarServer]) {
        ((void (*)(id, SEL))objc_msgSend)(applicationClass, startStatusBarServer);
        sTLinkStatusBarServerStarted = YES;
    }
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

    TLinkPrepareHostWindow();
    delegate.window = sTLinkHostWindow;
    sTLinkHostWindow.hidden = YES;
    sTLinkHostWindowRegistered = TLinkRegisterWindowContext(
        sTLinkHostWindow, sTLinkHostWindow.windowLevel);
    TLinkRefreshHostedWindow();
    TLinkStartServerIfNecessary();
    sTLinkLastResult = @"plugin_hosted_ready";
    TLinkUIServiceLog([NSString stringWithFormat:
        @"plugin hosted ready bundle=%@ class=%@ state=%ld gs=%d gsevent=%d bks=%d initialize=%d instantiate=%d complete=1 window_server=%d status_bar_server=%d system_override=%d level_hook=%d hosting_controller=%d host_registered=%d host_context_id=%u host_hidden=%d host_key=%d toast_context_id=%u toast_hidden=%d toast_key=%d",
        NSBundle.mainBundle.bundleIdentifier, NSStringFromClass(application.class),
        (long)application.applicationState,
        sTLinkGSInitializeAvailable ? 1 : 0, sTLinkGSEventInitializeAvailable ? 1 : 0,
        sTLinkBKSDisplayServicesStartAvailable ? 1 : 0,
        sTLinkUIApplicationInitializeAvailable ? 1 : 0,
        sTLinkUIApplicationInstantiateAvailable ? 1 : 0,
        sTLinkWindowServerStarted ? 1 : 0,
        sTLinkStatusBarServerStarted ? 1 : 0,
        sTLinkSystemWindowOverrideInstalled ? 1 : 0,
        sTLinkWindowLevelHookInstalled ? 1 : 0,
        sTLinkWindowHostingController ? 1 : 0,
        sTLinkHostWindowRegistered ? 1 : 0,
        TLinkWindowContextID(sTLinkHostWindow), sTLinkHostWindow.hidden ? 1 : 0,
        sTLinkHostWindow.isKeyWindow ? 1 : 0, TLinkWindowContextID(sTLinkToastWindow),
        sTLinkToastWindow.hidden ? 1 : 0, sTLinkToastWindow.isKeyWindow ? 1 : 0]);
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
        TLinkUIServiceLog([NSString stringWithFormat:@"starting launch_mode=UIKitPluginSBSAccessibilityContextHosting uid=%d euid=%d gid=%d egid=%d",
            getuid(), geteuid(), getgid(), getegid()]);
        if (!TLinkInitializeUIKitPlugin()) return 75;
        CFRunLoopRun();
    }
    return 0;
}
