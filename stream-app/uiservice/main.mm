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
@end
@implementation TLinkUIServiceDelegate
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
        @"version": @1,
        @"pid": @(getpid()),
        @"uid": @(getuid()),
        @"euid": @(geteuid()),
        @"gid": @(getgid()),
        @"egid": @(getegid()),
        @"mobile_identity": @(geteuid() == 501 && getegid() == 501),
        @"window_ready": @(sTLinkWindowReady),
        @"window_level": @(sTLinkToastWindow.windowLevel),
        @"secure": @(sTLinkToastSecure),
        @"last_position": @(sTLinkLastPosition),
        @"toast_count": @(sTLinkToastCount),
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
    TLinkWriteUIServiceDiagnostics();

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
        return [NSString stringWithFormat:@"0;;uiservice_ready;;version=1;;pid=%d;;uid=%d;;euid=%d;;gid=%d;;egid=%d;;mobile_identity=%d;;window_ready=%d;;window_level=%.1f;;passthrough=1;;secure=%d;;toast_count=%lu;;last_position=%ld;;last_result=%@\r\n",
                getpid(), getuid(), geteuid(), getgid(), getegid(),
                (geteuid() == 501 && getegid() == 501) ? 1 : 0,
                sTLinkWindowReady ? 1 : 0, sTLinkToastWindow.windowLevel,
                sTLinkToastSecure ? 1 : 0, (unsigned long)sTLinkToastCount,
                (long)sTLinkLastPosition, sTLinkLastResult ?: @"unknown"];
    }
    if (![trimmed hasPrefix:@"1;;"]) return @"-1;;bad_request\r\n";
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:[trimmed substringFromIndex:3] options:0];
    NSDictionary *payload = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
    if (![payload isKindOfClass:NSDictionary.class] || ![payload[@"action"] isEqualToString:@"toast"]) {
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

static void TLinkInitializeUIKitPlugin(void)
{
    void *graphics = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY | RTLD_GLOBAL);
    void *backboard = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_GLOBAL);
    TLinkUIKitBootstrapFn gsInitialize = graphics ? (TLinkUIKitBootstrapFn)dlsym(graphics, "GSInitialize") : NULL;
    TLinkUIKitBootstrapFn bksStart = backboard ? (TLinkUIKitBootstrapFn)dlsym(backboard, "BKSDisplayServicesStart") : NULL;
    TLinkUIApplicationInitializeFn initialize = (TLinkUIApplicationInitializeFn)dlsym(RTLD_DEFAULT, "UIApplicationInitialize");
    TLinkUIApplicationInstantiateSingletonFn instantiate =
        (TLinkUIApplicationInstantiateSingletonFn)dlsym(RTLD_DEFAULT, "UIApplicationInstantiateSingleton");
    Class screenClass = NSClassFromString(@"UIScreen");
    SEL screenInitialize = NSSelectorFromString(@"initialize");
    if ([screenClass respondsToSelector:screenInitialize]) ((void (*)(id, SEL))objc_msgSend)(screenClass, screenInitialize);
    (void)CFRunLoopGetCurrent();
    if (gsInitialize) gsInitialize();
    if (bksStart) bksStart();
    if (initialize) initialize();
    if (instantiate) instantiate(TLinkUIServiceApplication.class);
    UIApplication *application = UIApplication.sharedApplication;
    static TLinkUIServiceDelegate *delegate = nil;
    delegate = [[TLinkUIServiceDelegate alloc] init];
    application.delegate = delegate;
    SEL complete = NSSelectorFromString(@"__completeAndRunAsPlugin");
    if ([application respondsToSelector:complete]) ((void (*)(id, SEL))objc_msgSend)(application, complete);
    TLinkUIServiceLog([NSString stringWithFormat:@"UIKit ready bundle=%@ class=%@", NSBundle.mainBundle.bundleIdentifier, NSStringFromClass(application.class)]);
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
        TLinkUIServiceLog([NSString stringWithFormat:@"starting uid=%d euid=%d gid=%d egid=%d", getuid(), geteuid(), getgid(), getegid()]);
        TLinkInitializeUIKitPlugin();
        TLinkPrepareToastWindow();
        NSThread *serverThread = [[NSThread alloc] initWithBlock:^{ TLinkRunServer(); }];
        serverThread.name = @"com.tlinkauto.uiservice.server";
        [serverThread start];
        CFRunLoopRun();
    }
    return 0;
}
