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

typedef int (*TLinkUIServiceSBSLaunchApplicationFn)(CFStringRef identifier, Boolean suspended);
typedef CFStringRef (*TLinkUIServiceSBSCopyFrontmostApplicationFn)(void);

static NSString *const kTLinkUIServiceDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/uiservice_toast.plist";
static NSString *const kTLinkUIServiceRestoreBundlePath = @"/var/mobile/Library/TLinkauto/runtime/uiservice_restore_bundle";
static NSString *sTLinkLastResult = @"starting";
static NSString *sTLinkRestoreBundle = @"";
static NSString *sTLinkRestoreResult = @"pending";
static BOOL sTLinkRestoreStarted = NO;
static NSUInteger sTLinkToastCount = 0;
static BOOL sTLinkWindowReady = NO;
static BOOL sTLinkToastSecure = YES;
static NSInteger sTLinkLastPosition = 2;
static NSUInteger sTLinkRequestCount = 0;
static NSUInteger sTLinkInvalidRequestCount = 0;
static BOOL sTLinkServerStarted = NO;
static UIView *sTLinkToastBubble = nil;
static NSUInteger sTLinkToastGeneration = 0;

@interface TLinkUIServiceApplication : UIApplication
- (UIApplicationState)tlinkSystemApplicationState;
@end

@implementation TLinkUIServiceApplication
- (UIApplicationState)applicationState { return UIApplicationStateActive; }
- (UIApplicationState)tlinkSystemApplicationState { return [super applicationState]; }
- (BOOL)_isBackground { return NO; }
- (BOOL)_isApplicationBackgrounded { return NO; }
- (BOOL)_isSuspended { return NO; }
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
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
- (BOOL)canBecomeKeyWindow { return NO; }
@end

static TLinkPassthroughToastWindow *sTLinkToastWindow = nil;
static UIViewController *sTLinkRootController = nil;

static void TLinkPrepareToastWindow(void);
static void TLinkStartServerIfNecessary(void);
static void TLinkScheduleRestorePreviousApplication(NSTimeInterval delay);

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
        @"version": @6,
        @"pid": @(getpid()),
        @"uid": @(getuid()),
        @"euid": @(geteuid()),
        @"gid": @(getgid()),
        @"egid": @(getegid()),
        @"mobile_identity": @(geteuid() == 501 && getegid() == 501),
        @"window_ready": @(sTLinkWindowReady),
        @"launch_mode": @"UIApplicationMain",
        @"restore_bundle": sTLinkRestoreBundle ?: @"",
        @"restore_result": sTLinkRestoreResult ?: @"unknown",
        @"window_level": @(sTLinkToastWindow.windowLevel),
        @"requested_window_level": @20000099.9,
        @"window_context_id": @(TLinkToastWindowContextID()),
        @"window_hidden": @(sTLinkToastWindow.hidden),
        @"window_key": @(sTLinkToastWindow.isKeyWindow),
        @"application_state": @(UIApplication.sharedApplication.applicationState),
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
    TLinkUIServiceLog([NSString stringWithFormat:@"toast visible count=%lu position=%ld duration=%.2f secure=%d context_id=%u hidden=%d key=%d",
        (unsigned long)sTLinkToastCount, (long)position, duration, sTLinkToastSecure ? 1 : 0,
        TLinkToastWindowContextID(), sTLinkToastWindow.hidden ? 1 : 0,
        sTLinkToastWindow.isKeyWindow ? 1 : 0]);
    TLinkWriteUIServiceDiagnostics();
    // Keep the compositor context in foreground until the first real toast has
    // been attached. The restore timer started at launch is only a fail-safe.
    TLinkScheduleRestorePreviousApplication(0.25);

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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)((duration + 0.8) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != sTLinkToastGeneration) return;
        sTLinkLastResult = @"toast_complete_service_exit";
        TLinkUIServiceLog(@"toast complete; exiting ephemeral foreground service");
        TLinkWriteUIServiceDiagnostics();
        exit(0);
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
        return [NSString stringWithFormat:@"0;;uiservice_ready;;version=6;;pid=%d;;uid=%d;;euid=%d;;gid=%d;;egid=%d;;mobile_identity=%d;;launch_mode=UIApplicationMain_restore_frontmost_ephemeral;;window_ready=%d;;window_context_id=%u;;window_level=%.1f;;requested_window_level=20000099.9;;window_hidden=%d;;window_key=%d;;passthrough=1;;secure=%d;;request_count=%lu;;invalid_request_count=%lu;;toast_count=%lu;;last_position=%ld;;restore_bundle=%@;;restore_result=%@;;last_result=%@\r\n",
                getpid(), getuid(), geteuid(), getgid(), getegid(),
                (geteuid() == 501 && getegid() == 501) ? 1 : 0,
                sTLinkWindowReady ? 1 : 0, TLinkToastWindowContextID(), sTLinkToastWindow.windowLevel,
                sTLinkToastWindow.hidden ? 1 : 0, sTLinkToastWindow.isKeyWindow ? 1 : 0,
                sTLinkToastSecure ? 1 : 0, (unsigned long)sTLinkRequestCount,
                (unsigned long)sTLinkInvalidRequestCount, (unsigned long)sTLinkToastCount,
                (long)sTLinkLastPosition, sTLinkRestoreBundle ?: @"",
                sTLinkRestoreResult ?: @"unknown", sTLinkLastResult ?: @"unknown"];
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

static void *TLinkUIServiceSpringBoardServicesHandle(void)
{
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                        RTLD_LAZY | RTLD_GLOBAL);
    });
    return handle;
}

static NSString *TLinkUIServiceCopyFrontmostBundle(void)
{
    void *handle = TLinkUIServiceSpringBoardServicesHandle();
    if (!handle) return nil;
    const char *symbols[] = {
        "SBSCopyFrontmostApplicationDisplayIdentifier",
        "SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay",
        "SBSGetMostElevatedApplicationBundleIdentifier",
        "SBSGetMostElevatedApplicationDisplayIdentifier",
    };
    for (NSUInteger index = 0; index < sizeof(symbols) / sizeof(symbols[0]); index++) {
        TLinkUIServiceSBSCopyFrontmostApplicationFn copyFrontmost =
            (TLinkUIServiceSBSCopyFrontmostApplicationFn)dlsym(handle, symbols[index]);
        if (!copyFrontmost) continue;
        CFStringRef value = copyFrontmost();
        NSString *bundle = value ? [(__bridge NSString *)value copy] : nil;
        if (value && strncmp(symbols[index], "SBSCopy", 7) == 0) CFRelease(value);
        if (bundle.length > 0) return bundle;
    }
    return nil;
}

static void TLinkRestorePreviousApplication(void)
{
    if (sTLinkRestoreStarted) return;
    sTLinkRestoreStarted = YES;
    NSString *raw = [NSString stringWithContentsOfFile:kTLinkUIServiceRestoreBundlePath
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:kTLinkUIServiceRestoreBundlePath error:nil];
    sTLinkRestoreBundle = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *serviceBundle = NSBundle.mainBundle.bundleIdentifier ?: @"com.tlinkauto.streamcontrol.uiservice";
    if (sTLinkRestoreBundle.length == 0) {
        sTLinkRestoreResult = @"marker_missing";
        TLinkUIServiceLog(@"restore_frontmost skipped marker_missing");
        TLinkWriteUIServiceDiagnostics();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(800 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if ([TLinkUIServiceCopyFrontmostBundle() isEqualToString:serviceBundle]) {
                TLinkUIServiceLog(@"restore_frontmost marker missing and service is frontmost; exiting");
                exit(0);
            }
        });
        return;
    }
    if ([sTLinkRestoreBundle isEqualToString:serviceBundle]) {
        sTLinkRestoreResult = @"marker_is_uiservice";
        TLinkUIServiceLog(@"restore_frontmost skipped marker_is_uiservice");
        TLinkWriteUIServiceDiagnostics();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(800 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{ exit(0); });
        return;
    }

    void *handle = TLinkUIServiceSpringBoardServicesHandle();
    TLinkUIServiceSBSLaunchApplicationFn launch = handle
        ? (TLinkUIServiceSBSLaunchApplicationFn)dlsym(handle, "SBSLaunchApplicationWithIdentifier")
        : NULL;
    int rc = launch ? launch((__bridge CFStringRef)sTLinkRestoreBundle, false) : -1;
    sTLinkRestoreResult = rc == 0 ? @"launch_requested" : [NSString stringWithFormat:@"launch_failed_%d", rc];
    TLinkUIServiceLog([NSString stringWithFormat:@"restore_frontmost bundle=%@ rc=%d context_id=%u",
        sTLinkRestoreBundle, rc, TLinkToastWindowContextID()]);
    TLinkWriteUIServiceDiagnostics();

    if (rc != 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(350 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            TLinkUIServiceLog(@"restore_frontmost failed; exiting transparent foreground service");
            exit(0);
        });
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(800 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        NSString *frontmost = TLinkUIServiceCopyFrontmostBundle();
        if ([frontmost isEqualToString:serviceBundle]) {
            sTLinkRestoreResult = @"verify_still_frontmost_exit";
            TLinkUIServiceLog(@"restore_frontmost verification failed; exiting transparent foreground service");
            TLinkWriteUIServiceDiagnostics();
            exit(0);
        }
        sTLinkRestoreResult = frontmost.length > 0
            ? [NSString stringWithFormat:@"verified_%@", frontmost]
            : @"requested_frontmost_unavailable";
        TLinkUIServiceLog([NSString stringWithFormat:@"restore_frontmost verified frontmost=%@",
            frontmost ?: @"<unavailable>"]);
        TLinkWriteUIServiceDiagnostics();
    });
}

static void TLinkScheduleRestorePreviousApplication(NSTimeInterval delay)
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0.0, delay) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        TLinkRestorePreviousApplication();
    });
}

@implementation TLinkUIServiceDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)launchOptions;
    TLinkPrepareToastWindow();
    self.window = sTLinkToastWindow;
    [self.window makeKeyAndVisible];
    [self.window resignKeyWindow];
    TLinkStartServerIfNecessary();
    sTLinkLastResult = @"UIApplicationMain_did_finish_launching";
    TLinkUIServiceLog([NSString stringWithFormat:@"UIApplicationMain ready bundle=%@ class=%@ state=%ld context_id=%u hidden=%d key=%d",
        NSBundle.mainBundle.bundleIdentifier, NSStringFromClass(application.class),
        (long)application.applicationState, TLinkToastWindowContextID(),
        self.window.hidden ? 1 : 0, self.window.isKeyWindow ? 1 : 0]);
    TLinkWriteUIServiceDiagnostics();
    // Allow clipboardd enough time to connect and submit the first toast. If
    // no toast arrives, this timer still releases invisible foreground safely.
    TLinkScheduleRestorePreviousApplication(2.5);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (sTLinkToastCount > 0) return;
        sTLinkLastResult = @"no_toast_service_exit";
        TLinkUIServiceLog(@"no toast received; exiting invisible foreground service");
        TLinkWriteUIServiceDiagnostics();
        exit(0);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3500 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        TLinkUIServiceLog([NSString stringWithFormat:@"UIApplicationMain settled state=%ld context_id=%u hidden=%d key=%d",
            (long)application.applicationState, TLinkToastWindowContextID(),
            self.window.hidden ? 1 : 0, self.window.isKeyWindow ? 1 : 0]);
        TLinkWriteUIServiceDiagnostics();
    });
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

int main(int argc, char *argv[])
{
    @autoreleasepool {
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
        TLinkUIServiceLog([NSString stringWithFormat:@"starting launch_mode=UIApplicationMain_restore_frontmost uid=%d euid=%d gid=%d egid=%d",
            getuid(), geteuid(), getgid(), getegid()]);
        return UIApplicationMain(argc, argv,
                                 NSStringFromClass(TLinkUIServiceApplication.class),
                                 NSStringFromClass(TLinkUIServiceDelegate.class));
    }
    return 0;
}
