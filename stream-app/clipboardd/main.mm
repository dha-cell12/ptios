#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import "../../shared/TLinkLicenseVerifier.h"
#import "../streamd/headers/IOHIDEventSystemClient.h"

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
typedef SInt32 (*TLinkCFUserNotificationDisplayNoticeFn)(CFTimeInterval,
                                                          CFOptionFlags,
                                                          CFURLRef,
                                                          CFURLRef,
                                                          CFURLRef,
                                                          CFStringRef,
                                                          CFStringRef,
                                                          CFStringRef);
typedef SInt32 (*TLinkCFUserNotificationDisplayAlertFn)(CFTimeInterval,
                                                         CFOptionFlags,
                                                         CFURLRef,
                                                         CFURLRef,
                                                         CFURLRef,
                                                         CFStringRef,
                                                         CFStringRef,
                                                         CFStringRef,
                                                         CFStringRef,
                                                         CFStringRef,
                                                         CFOptionFlags *);

@interface TLinkClipboardApplication : UIApplication
- (UIApplicationState)tlinkSystemApplicationState;
@end

@implementation TLinkClipboardApplication
- (UIApplicationState)applicationState { return UIApplicationStateActive; }
- (UIApplicationState)tlinkSystemApplicationState { return [super applicationState]; }
- (BOOL)_isBackground { return NO; }
- (BOOL)_isApplicationBackgrounded { return NO; }
- (BOOL)_isSuspended { return NO; }
@end

@interface TLinkClipboardApplicationDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation TLinkClipboardApplicationDelegate
@end

@interface TLinkVolumeWindow : UIWindow
@end

@implementation TLinkVolumeWindow
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
@end

@interface UNUserNotificationCenter (TLinkPrivateBundleCenter)
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier queue:(dispatch_queue_t)queue;
@end

static BOOL sTLinkClipboardWriteVerified = NO;
static BOOL sTLinkKeepAwakeRequested = NO;
static NSInteger sTLinkNotificationAuthorizationStatus = -1;
static NSString *sTLinkLastBackgroundVisualResult = @"none";
static NSString *sTLinkNotificationCenterMode = @"uninitialized";
static NSInteger sTLinkToastLastPosition = -1;
static void TLinkClipboardLog(NSString *message);
static NSString *const kTLinkAppNotificationAuthorizationPath = @"/var/mobile/Library/TLinkauto/runtime/app_notification_authorization";
static NSString *const kTLinkStreamControlBundleIdentifier = @"com.tlinkauto.streamcontrol";
static NSString *const kTLinkSettingsConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/config.plist";
static NSString *const kTLinkScriptsRootPath = @"/var/mobile/Library/TLinkauto/scripts";
static NSString *const kTLinkVolumeDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/volume_trigger.plist";
static IOHIDEventSystemClientRef sTLinkVolumeHIDClient = NULL;
static TLinkVolumeWindow *sTLinkVolumeWindow = nil;
static UIViewController *sTLinkVolumeRootController = nil;
static BOOL sTLinkVolumeMenuVisible = NO;
static BOOL sTLinkVolumeUpIsDown = NO;
static NSTimeInterval sTLinkVolumeUpDownUptime = 0.0;
static NSTimeInterval sTLinkVolumeFirstClickUptime = 0.0;
static NSUInteger sTLinkVolumeClickGeneration = 0;
static NSUInteger sTLinkVolumeUpEventCount = 0;
static NSUInteger sTLinkVolumeDoubleClickCount = 0;
static NSString *sTLinkVolumeListenerState = @"not_started";
static NSString *sTLinkVolumeLastAction = @"none";

static BOOL TLinkVolumePopupEnabled(void)
{
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:kTLinkSettingsConfigPath];
    NSNumber *value = [config[@"double_click_volume_show_popup"] isKindOfClass:[NSNumber class]]
        ? config[@"double_click_volume_show_popup"]
        : nil;
    return value ? value.boolValue : YES;
}

static void TLinkWriteVolumeDiagnostics(void)
{
    NSString *directory = [kTLinkVolumeDiagnosticsPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSDictionary *diagnostics = @{
        @"version": @1,
        @"listener": sTLinkVolumeListenerState ?: @"unknown",
        @"enabled": @(TLinkVolumePopupEnabled()),
        @"hid_client": @(sTLinkVolumeHIDClient != NULL),
        @"volume_up_events": @(sTLinkVolumeUpEventCount),
        @"double_clicks": @(sTLinkVolumeDoubleClickCount),
        @"menu_visible": @(sTLinkVolumeMenuVisible),
        @"last_action": sTLinkVolumeLastAction ?: @"none",
        @"updated_at": @([[NSDate date] timeIntervalSince1970]),
    };
    [diagnostics writeToFile:kTLinkVolumeDiagnosticsPath atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey: NSFileProtectionNone}
                                     ofItemAtPath:kTLinkVolumeDiagnosticsPath
                                            error:nil];
}

static NSString *TLinkSendStreamdLine(NSString *line)
{
    int client = socket(AF_INET, SOCK_STREAM, 0);
    if (client < 0) return [NSString stringWithFormat:@"socket_failed errno=%d", errno];
    struct timeval timeout = {4, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (connect(client, (struct sockaddr *)&address, sizeof(address)) != 0) {
        NSString *error = [NSString stringWithFormat:@"connect_streamd_failed errno=%d", errno];
        close(client);
        return error;
    }

    NSString *payload = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    NSData *request = [payload dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)request.bytes;
    NSUInteger remaining = request.length;
    while (remaining > 0) {
        ssize_t written = write(client, bytes, remaining);
        if (written <= 0) break;
        bytes += written;
        remaining -= (NSUInteger)written;
    }

    NSMutableData *responseData = [NSMutableData data];
    char buffer[2048];
    while (responseData.length < 65536) {
        ssize_t count = read(client, buffer, sizeof(buffer));
        if (count <= 0) break;
        [responseData appendBytes:buffer length:(NSUInteger)count];
        if (memchr(buffer, '\n', (size_t)count)) break;
    }
    close(client);
    if (responseData.length == 0) return @"streamd_no_response";
    NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    return [response stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"streamd_non_utf8_response";
}

static BOOL TLinkIsScriptBundleAtPath(NSString *path)
{
    NSString *extension = path.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"tl"] || [extension isEqualToString:@"xxt"]) return YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:[path stringByAppendingPathComponent:@"manifest.json"]] ||
           [fileManager fileExistsAtPath:[path stringByAppendingPathComponent:@"info.plist"]];
}

static NSArray<NSString *> *TLinkVolumeScriptPaths(void)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *rootURL = [NSURL fileURLWithPath:kTLinkScriptsRootPath isDirectory:YES];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:rootURL
                                                   includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey]
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:^BOOL(__unused NSURL *url, __unused NSError *error) {
        return YES;
    }];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        NSNumber *isDirectory = nil;
        NSNumber *isRegularFile = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        [url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        NSString *path = url.path ?: @"";
        if (isDirectory.boolValue && TLinkIsScriptBundleAtPath(path)) {
            [paths addObject:path];
            [enumerator skipDescendants];
        } else if (isRegularFile.boolValue && [path.pathExtension.lowercaseString isEqualToString:@"js"]) {
            [paths addObject:path];
        }
    }
    return [paths sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        return [left.lastPathComponent localizedCaseInsensitiveCompare:right.lastPathComponent];
    }];
}

static void TLinkDismissVolumeWindow(void)
{
    [sTLinkVolumeRootController dismissViewControllerAnimated:NO completion:nil];
    sTLinkVolumeWindow.hidden = YES;
    sTLinkVolumeWindow.rootViewController = nil;
    sTLinkVolumeRootController = nil;
    sTLinkVolumeWindow = nil;
    sTLinkVolumeMenuVisible = NO;
    TLinkWriteVolumeDiagnostics();
}

static void TLinkPrepareSecureVolumeWindow(void)
{
    if (sTLinkVolumeWindow) return;
    CGRect bounds = [UIScreen mainScreen].bounds;
    sTLinkVolumeWindow = [[TLinkVolumeWindow alloc] initWithFrame:bounds];
    sTLinkVolumeWindow.windowLevel = (UIWindowLevel)20000099.9;
    sTLinkVolumeWindow.backgroundColor = [UIColor clearColor];
    sTLinkVolumeWindow.opaque = NO;
    sTLinkVolumeRootController = [[UIViewController alloc] init];
    sTLinkVolumeRootController.view.backgroundColor = [UIColor clearColor];
    sTLinkVolumeWindow.rootViewController = sTLinkVolumeRootController;
    for (id target in @[sTLinkVolumeWindow, sTLinkVolumeRootController.view]) {
        for (NSString *selectorName in @[@"_setSecure:", @"setSecure:"]) {
            SEL secureSelector = NSSelectorFromString(selectorName);
            if ([target respondsToSelector:secureSelector]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(target, secureSelector, YES);
                break;
            }
        }
    }
    [sTLinkVolumeWindow makeKeyAndVisible];
}

static void TLinkPresentVolumeController(UIAlertController *controller)
{
    TLinkPrepareSecureVolumeWindow();
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    if (popover) {
        popover.sourceView = sTLinkVolumeRootController.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(sTLinkVolumeRootController.view.bounds),
                                        CGRectGetMidY(sTLinkVolumeRootController.view.bounds), 1.0, 1.0);
        popover.permittedArrowDirections = 0;
    }
    [sTLinkVolumeRootController presentViewController:controller animated:YES completion:nil];
}

static void TLinkShowVolumeResult(NSString *title, NSString *message)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"TLinkauto"
                                                                       message:message ?: @""
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            TLinkDismissVolumeWindow();
        }]];
        TLinkPresentVolumeController(alert);
    });
}

static void TLinkRunVolumeScript(NSString *path)
{
    sTLinkVolumeLastAction = [NSString stringWithFormat:@"launch_requested:%@", path.lastPathComponent ?: @""];
    TLinkWriteVolumeDiagnostics();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *response = TLinkSendStreamdLine([NSString stringWithFormat:@"19%@", path ?: @""]);
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL succeeded = [response isEqualToString:@"0"] || [response hasPrefix:@"0;;"];
            sTLinkVolumeLastAction = succeeded ? @"launch_succeeded" : @"launch_failed";
            TLinkClipboardLog([NSString stringWithFormat:@"volume trigger: launch path=%@ response=%@", path ?: @"", response ?: @""]);
            TLinkWriteVolumeDiagnostics();
            TLinkShowVolumeResult(@"Launch", response);
        });
    });
}

static void TLinkShowVolumeScriptPicker(void)
{
    NSArray<NSString *> *paths = TLinkVolumeScriptPaths();
    if (paths.count == 0) {
        TLinkShowVolumeResult(@"Launch", @"No .tl, .xxt, or .js script was found in the scripts folder.");
        return;
    }
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Choose Script"
                                                                     message:kTLinkScriptsRootPath
                                                              preferredStyle:UIAlertControllerStyleAlert];
    NSString *prefix = [kTLinkScriptsRootPath stringByAppendingString:@"/"];
    for (NSString *path in paths) {
        NSString *display = [path hasPrefix:prefix] ? [path substringFromIndex:prefix.length] : path.lastPathComponent;
        [picker addAction:[UIAlertAction actionWithTitle:display
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            TLinkRunVolumeScript(path);
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"Back" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        TLinkDismissVolumeWindow();
    }]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TLinkPresentVolumeController(picker);
    });
}

static void TLinkToggleVolumeRecording(void)
{
    sTLinkVolumeLastAction = @"record_requested";
    TLinkWriteVolumeDiagnostics();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *response = TLinkSendStreamdLine(@"14");
        if ([response containsString:@"recording_already_started"]) {
            response = TLinkSendStreamdLine(@"15");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL succeeded = [response isEqualToString:@"0"] || [response hasPrefix:@"0;;"];
            sTLinkVolumeLastAction = succeeded ? @"record_succeeded" : @"record_failed";
            TLinkClipboardLog([NSString stringWithFormat:@"volume trigger: record response=%@", response ?: @""]);
            TLinkWriteVolumeDiagnostics();
            TLinkShowVolumeResult(@"Record", response);
        });
    });
}

static void TLinkShowVolumeActionMenu(void)
{
    NSCAssert([NSThread isMainThread], @"Volume UI must be presented on main thread");
    if (sTLinkVolumeMenuVisible) return;
    if (!TLinkVolumePopupEnabled()) {
        sTLinkVolumeLastAction = @"double_click_ignored_disabled";
        TLinkWriteVolumeDiagnostics();
        return;
    }
    sTLinkVolumeMenuVisible = YES;
    sTLinkVolumeLastAction = @"menu_presented";
    TLinkWriteVolumeDiagnostics();

    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"TLinkauto"
                                                                   message:@"Volume Up was pressed twice."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:@"Launch" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        TLinkShowVolumeScriptPicker();
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Record" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        TLinkToggleVolumeRecording();
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        sTLinkVolumeLastAction = @"cancelled";
        TLinkDismissVolumeWindow();
    }]];
    TLinkPresentVolumeController(menu);
}

static void TLinkHandleVolumeUpTransition(BOOL down, BOOL repeat)
{
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    sTLinkVolumeUpEventCount += 1;
    if (down) {
        if (repeat || sTLinkVolumeUpIsDown) return;
        sTLinkVolumeUpIsDown = YES;
        sTLinkVolumeUpDownUptime = now;
        return;
    }
    if (!sTLinkVolumeUpIsDown) return;
    sTLinkVolumeUpIsDown = NO;
    NSTimeInterval heldFor = now - sTLinkVolumeUpDownUptime;
    if (heldFor < 0.0 || heldFor >= 0.4) {
        sTLinkVolumeFirstClickUptime = 0.0;
        sTLinkVolumeClickGeneration += 1;
        sTLinkVolumeLastAction = @"volume_up_hold_ignored";
        TLinkWriteVolumeDiagnostics();
        return;
    }

    if (sTLinkVolumeFirstClickUptime > 0.0 && now - sTLinkVolumeFirstClickUptime <= 0.5) {
        sTLinkVolumeFirstClickUptime = 0.0;
        sTLinkVolumeClickGeneration += 1;
        sTLinkVolumeDoubleClickCount += 1;
        TLinkShowVolumeActionMenu();
        return;
    }

    sTLinkVolumeFirstClickUptime = now;
    NSUInteger generation = ++sTLinkVolumeClickGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == sTLinkVolumeClickGeneration) sTLinkVolumeFirstClickUptime = 0.0;
    });
}

static void TLinkVolumeHIDCallback(__unused void *target,
                                   __unused void *refcon,
                                   __unused IOHIDEventQueueRef queue,
                                   IOHIDEventRef event)
{
    if (!event || IOHIDEventGetType(event) != kIOHIDEventTypeKeyboard) return;
    int usagePage = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldKeyboardUsagePage);
    int usage = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldKeyboardUsage);
    if (usagePage != 12 || usage != 233) return;
    BOOL down = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldKeyboardDown) != 0;
    BOOL repeat = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldKeyboardRepeat) != 0;
    if ([NSThread isMainThread]) TLinkHandleVolumeUpTransition(down, repeat);
    else dispatch_async(dispatch_get_main_queue(), ^{ TLinkHandleVolumeUpTransition(down, repeat); });
}

static void TLinkStartVolumeHIDListener(void)
{
    if (sTLinkVolumeHIDClient) return;
    sTLinkVolumeHIDClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!sTLinkVolumeHIDClient) {
        sTLinkVolumeListenerState = @"iohid_client_create_failed";
        TLinkClipboardLog(@"volume trigger: IOHIDEventSystemClientCreate returned NULL");
        TLinkWriteVolumeDiagnostics();
        return;
    }
    IOHIDEventSystemClientScheduleWithRunLoop(sTLinkVolumeHIDClient,
                                               CFRunLoopGetMain(),
                                               kCFRunLoopDefaultMode);
    IOHIDEventSystemClientRegisterEventCallback(sTLinkVolumeHIDClient,
                                                 TLinkVolumeHIDCallback,
                                                 NULL,
                                                 NULL);
    sTLinkVolumeListenerState = @"registered_keyboard_page_12_usage_233";
    TLinkClipboardLog(@"volume trigger: IOHID listener registered page=12 usage=233 double_click_ms=500 hold_ms=400");
    TLinkWriteVolumeDiagnostics();
}

static BOOL TLinkAdoptMobileIdentity(void)
{
    if (geteuid() != 0) return geteuid() == 501 && getegid() == 501;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *writablePaths = @[
        @"/var/mobile/Library/TLinkauto",
        @"/var/mobile/Library/TLinkauto/runtime",
    ];
    for (NSString *path in writablePaths) {
        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        chown([path fileSystemRepresentation], 501, 501);
    }
    chown([@"/var/mobile/Library/TLinkauto/clipboardd.log" fileSystemRepresentation], 501, 501);
    if (setgid(501) != 0) {
        TLinkClipboardLog([NSString stringWithFormat:@"mobile identity: setgid(501) failed errno=%d", errno]);
        return NO;
    }
    if (setuid(501) != 0) {
        TLinkClipboardLog([NSString stringWithFormat:@"mobile identity: setuid(501) failed errno=%d", errno]);
        return NO;
    }
    return geteuid() == 501 && getegid() == 501;
}

static void TLinkClipboardLog(NSString *message)
{
    NSString *directory = @"/var/mobile/Library/TLinkauto";
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [directory stringByAppendingPathComponent:@"clipboardd.log"];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [data writeToFile:path atomically:YES];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

static NSString *TLinkClipboardImageType(NSData *data)
{
    if (data.length < 4) return nil;
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    if (data.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47 &&
        bytes[4] == 0x0d && bytes[5] == 0x0a && bytes[6] == 0x1a && bytes[7] == 0x0a) {
        return @"public.png";
    }
    if (bytes[0] == 0xff && bytes[1] == 0xd8) return @"public.jpeg";
    if (data.length >= 6 && bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == '8') {
        return @"com.compuserve.gif";
    }
    if (data.length >= 12 &&
        bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
        bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P') {
        return @"org.webmproject.webp";
    }
    return nil;
}

static UNUserNotificationCenter *TLinkNotificationCenter(void)
{
    static UNUserNotificationCenter *center = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @try {
            id candidate = [UNUserNotificationCenter alloc];
            if ([candidate respondsToSelector:@selector(initWithBundleIdentifier:)]) {
                center = [candidate initWithBundleIdentifier:kTLinkStreamControlBundleIdentifier];
                sTLinkNotificationCenterMode = @"explicit_bundle_identifier";
            } else {
                candidate = [UNUserNotificationCenter alloc];
                if ([candidate respondsToSelector:@selector(initWithBundleIdentifier:queue:)]) {
                    center = [candidate initWithBundleIdentifier:kTLinkStreamControlBundleIdentifier
                                                           queue:dispatch_get_main_queue()];
                    sTLinkNotificationCenterMode = @"explicit_bundle_identifier_queue";
                }
            }
        } @catch (NSException *exception) {
            TLinkClipboardLog([NSString stringWithFormat:@"notification center private init exception=%@",
                               exception.reason ?: exception.name]);
            center = nil;
        }
        if (!center) {
            center = [UNUserNotificationCenter currentNotificationCenter];
            sTLinkNotificationCenterMode = @"current_process_fallback";
        }
        TLinkClipboardLog([NSString stringWithFormat:@"notification center mode=%@ main_bundle=%@ target_bundle=%@",
                           sTLinkNotificationCenterMode,
                           NSBundle.mainBundle.bundleIdentifier ?: @"<nil>",
                           kTLinkStreamControlBundleIdentifier]);
    });
    return center;
}

static void TLinkRefreshNotificationAuthorizationStatus(void)
{
    [TLinkNotificationCenter()
        getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
            sTLinkNotificationAuthorizationStatus = settings.authorizationStatus;
        }];
}

static NSInteger TLinkAppNotificationAuthorizationStatus(void)
{
    NSString *value = [NSString stringWithContentsOfFile:kTLinkAppNotificationAuthorizationPath
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    return value.length > 0 ? [value integerValue] : -1;
}

static dispatch_queue_t TLinkBackgroundVisualQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tlinkauto.clipboardd.background-visual", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void TLinkScheduleCFUserNotification(NSDictionary *payload, NSString *reason)
{
    NSDictionary *event = [payload copy] ?: @{};
    sTLinkLastBackgroundVisualResult = @"cfusernotification_pending";
    dispatch_async(TLinkBackgroundVisualQueue(), ^{
        NSString *kind = [event[@"kind"] isKindOfClass:[NSString class]] ? event[@"kind"] : @"toast";
        NSString *title = [event[@"title"] isKindOfClass:[NSString class]] ? event[@"title"] : @"TLinkauto";
        NSString *message = [event[@"message"] isKindOfClass:[NSString class]] ? event[@"message"] : @"";
        NSString *okTitle = [event[@"ok"] isKindOfClass:[NSString class]] ? event[@"ok"] : @"OK";
        NSString *cancelTitle = [event[@"cancel"] isKindOfClass:[NSString class]] ? event[@"cancel"] : @"Cancel";
        double duration = [event[@"duration"] doubleValue];
        if (duration <= 0.0) duration = [kind isEqualToString:@"toast"] ? 3.0 : 30.0;
        if (duration > 30.0) duration = 30.0;

        SInt32 result = -1;
        TLinkCFUserNotificationDisplayAlertFn displayAlert =
            (TLinkCFUserNotificationDisplayAlertFn)dlsym(RTLD_DEFAULT, "CFUserNotificationDisplayAlert");
        if (displayAlert) {
            BOOL toastMode = [kind isEqualToString:@"toast"];
            CFOptionFlags responseFlags = 0;
            CFOptionFlags flags = toastMode ? kCFUserNotificationNoDefaultButtonFlag : 0;
            result = displayAlert(duration,
                                  flags,
                                  NULL,
                                  NULL,
                                  NULL,
                                  (__bridge CFStringRef)(title.length > 0 ? title : @"TLinkauto"),
                                  (__bridge CFStringRef)message,
                                  toastMode ? NULL : (__bridge CFStringRef)okTitle,
                                  [kind isEqualToString:@"dialog"] ? (__bridge CFStringRef)cancelTitle : NULL,
                                  NULL,
                                  &responseFlags);
            TLinkClipboardLog([NSString stringWithFormat:@"CFUserNotification alert kind=%@ no_button=%d result=%d response=%lu reason=%@",
                               kind, toastMode ? 1 : 0, (int)result, (unsigned long)responseFlags, reason ?: @"direct"]);
        } else if ([kind isEqualToString:@"toast"]) {
            TLinkCFUserNotificationDisplayNoticeFn displayNotice =
                (TLinkCFUserNotificationDisplayNoticeFn)dlsym(RTLD_DEFAULT, "CFUserNotificationDisplayNotice");
            if (displayNotice) {
                result = displayNotice(duration,
                                       0,
                                       NULL,
                                       NULL,
                                       NULL,
                                       (__bridge CFStringRef)(title.length > 0 ? title : @"TLinkauto"),
                                       (__bridge CFStringRef)message,
                                       (__bridge CFStringRef)@"OK");
                TLinkClipboardLog([NSString stringWithFormat:@"CFUserNotification notice result=%d reason=%@",
                                   (int)result, reason ?: @"direct"]);
            } else {
                sTLinkLastBackgroundVisualResult = @"cfusernotification_notice_symbol_unavailable";
                TLinkClipboardLog(@"CFUserNotificationDisplayNotice unavailable");
                return;
            }
        } else {
            sTLinkLastBackgroundVisualResult = @"cfusernotification_alert_symbol_unavailable";
            TLinkClipboardLog(@"CFUserNotificationDisplayAlert unavailable");
            return;
        }
        sTLinkLastBackgroundVisualResult = [NSString stringWithFormat:@"cfusernotification_%@_result_%d", kind, (int)result];
    });
}

static NSString *TLinkHandleBackgroundUIBridge(NSArray<NSString *> *parts)
{
    if (parts.count < 2) return @"-1;;background_ui_missing_payload\r\n";
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:parts[1] options:0];
    NSDictionary *payload = jsonData
        ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil]
        : nil;
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return @"-1;;background_ui_bad_payload\r\n";
    }

    NSString *action = [payload[@"action"] isKindOfClass:[NSString class]] ? payload[@"action"] : @"";
    if ([action isEqualToString:@"keep_awake"]) {
        BOOL enabled = [payload[@"enabled"] boolValue];
        [UIApplication sharedApplication].idleTimerDisabled = enabled;
        sTLinkKeepAwakeRequested = enabled;
        return [NSString stringWithFormat:@"0;;background_keep_awake_%@;;idle_timer_disabled=%d;;best_effort=1\r\n",
                enabled ? @"enabled" : @"disabled",
                [UIApplication sharedApplication].idleTimerDisabled ? 1 : 0];
    }

    if (![action isEqualToString:@"visual"]) {
        return @"-1;;background_ui_unsupported_action\r\n";
    }

    NSString *kind = [payload[@"kind"] isKindOfClass:[NSString class]] ? payload[@"kind"] : @"toast";
    NSString *message = [payload[@"message"] isKindOfClass:[NSString class]] ? payload[@"message"] : @"";
    if (message.length == 0) return @"-1;;background_visual_missing_message\r\n";
    if ([kind isEqualToString:@"toast"]) {
        NSInteger requestedPosition = [payload[@"position"] integerValue];
        if (requestedPosition < 0 || requestedPosition > 2) requestedPosition = 2;
        sTLinkToastLastPosition = requestedPosition;
        TLinkScheduleCFUserNotification(payload, @"uidaemon_window_not_compositor_hosted");
        return [NSString stringWithFormat:@"0;;background_visual_cfusernotification_queued;;toast;;requested_position=%ld;;effective_position=center;;limited_on_trollstore\r\n",
                (long)requestedPosition];
    }
    TLinkScheduleCFUserNotification(payload, @"v13_background_visual");
    return [NSString stringWithFormat:@"0;;background_visual_cfusernotification_queued;;%@\r\n", kind];
}

static NSString *TLinkClipboardHandleBodyForCurrentEUID(NSString *body)
{
    NSArray<NSString *> *parts = [body ?: @"" componentsSeparatedByString:@";;"];
    if (parts.count < 1) return @"-1;;clipboardd_missing_subtask\r\n";
    int subtask = [parts[0] intValue];
    @try {
        if (subtask == 90) {
            return TLinkHandleBackgroundUIBridge(parts);
        }
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];

    if (subtask == 6) {
        return [NSString stringWithFormat:@"0;;%@\r\n", pasteboard.string ?: @""];
    }
    if (subtask == 7) {
        if (parts.count < 2) return @"-1;;clipboardd_save_text_missing_content\r\n";
        NSString *text = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@";;"];
        pasteboard.string = text ?: @"";
        NSString *saved = pasteboard.string ?: @"";
        if (![saved isEqualToString:text ?: @""]) {
            pasteboard.items = @[@{@"public.utf8-plain-text": text ?: @""}];
            saved = pasteboard.string ?: @"";
        }
        if (![saved isEqualToString:text ?: @""]) {
            return [NSString stringWithFormat:@"-1;;clipboardd_text_verify_failed expected=%lu actual=%lu\r\n",
                    (unsigned long)(text ?: @"").length, (unsigned long)saved.length];
        }
        sTLinkClipboardWriteVerified = YES;
        return @"0\r\n";
    }
    if (subtask == 8) {
        if (parts.count < 3 || ![parts[1] isEqualToString:@"file"]) {
            return @"-1;;clipboardd_image_requires_file_path\r\n";
        }
        NSString *path = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@";;"];
        NSData *imageData = [NSData dataWithContentsOfFile:path];
        if (imageData.length == 0) {
            return [NSString stringWithFormat:@"-1;;clipboardd_image_read_failed path=%@\r\n", path ?: @""];
        }
        NSString *type = TLinkClipboardImageType(imageData);
        if (!type.length) return @"-1;;clipboardd_image_unsupported_format\r\n";
        pasteboard.items = @[@{type: imageData}];
        if (pasteboard.items.count == 0) return @"-1;;clipboardd_image_verify_failed\r\n";
        sTLinkClipboardWriteVerified = YES;
        return [NSString stringWithFormat:@"0;;clipboard_image_data;;%@;;%lu\r\n",
                type, (unsigned long)imageData.length];
    }
    if (subtask == 9) {
        UIApplication *application = [UIApplication sharedApplication];
        UIApplicationState state = application.applicationState;
        UIApplicationState systemState = [application isKindOfClass:[TLinkClipboardApplication class]]
            ? [(TLinkClipboardApplication *)application tlinkSystemApplicationState]
            : state;
        return [NSString stringWithFormat:@"0;;clipboardd_ready;;version=13;;pid=%d;;uid=%d;;euid=%d;;gid=%d;;egid=%d;;mobile_identity=%d;;state=%ld;;system_state=%ld;;write_verified=%d;;background_entitlement=1;;background_ui_bridge=1;;license_gate=1;;volume_hid_listener=%d;;volume_listener_state=%@;;volume_popup_enabled=%d;;volume_up_events=%lu;;volume_double_clicks=%lu;;volume_menu_visible=%d;;volume_last_action=%@;;background_visual_mode=cfusernotification_toast_alert_fixed_center;;toast_overlay_visible=0;;toast_requested_position=%ld;;toast_effective_position=center;;notification_center=%@;;main_bundle=%@;;notification_auth=%ld;;app_notification_auth=%ld;;background_visual_last=%@;;keep_awake_requested=%d;;idle_timer_disabled=%d\r\n",
                getpid(), getuid(), geteuid(), getgid(), getegid(),
                (geteuid() == 501 && getegid() == 501) ? 1 : 0,
                (long)state, (long)systemState,
                sTLinkClipboardWriteVerified ? 1 : 0,
                sTLinkVolumeHIDClient ? 1 : 0,
                sTLinkVolumeListenerState ?: @"unknown",
                TLinkVolumePopupEnabled() ? 1 : 0,
                (unsigned long)sTLinkVolumeUpEventCount,
                (unsigned long)sTLinkVolumeDoubleClickCount,
                sTLinkVolumeMenuVisible ? 1 : 0,
                sTLinkVolumeLastAction ?: @"none",
                (long)sTLinkToastLastPosition,
                sTLinkNotificationCenterMode ?: @"unknown",
                NSBundle.mainBundle.bundleIdentifier ?: @"<nil>",
                (long)sTLinkNotificationAuthorizationStatus,
                (long)TLinkAppNotificationAuthorizationStatus(),
                sTLinkLastBackgroundVisualResult ?: @"none",
                sTLinkKeepAwakeRequested ? 1 : 0,
                application.idleTimerDisabled ? 1 : 0];
    }
        return @"-1;;clipboardd_unsupported_subtask\r\n";
    } @catch (NSException *exception) {
        TLinkClipboardLog([NSString stringWithFormat:@"pasteboard exception=%@", exception.reason ?: exception.name]);
        return [NSString stringWithFormat:@"-1;;clipboardd_exception %@\r\n", exception.reason ?: exception.name ?: @"unknown"];
    }
}

static NSString *TLinkClipboardHandleBody(NSString *body)
{
    uid_t originalEUID = geteuid();
    BOOL switchedToMobile = originalEUID == 0 && seteuid(501) == 0;
    if (originalEUID == 0 && !switchedToMobile) {
        int switchError = errno;
        return [NSString stringWithFormat:@"-1;;clipboardd_switch_mobile_euid_failed errno=%d\r\n", switchError];
    }
    NSString *response = TLinkClipboardHandleBodyForCurrentEUID(body);
    int restoreError = 0;
    if (switchedToMobile && seteuid(originalEUID) != 0) restoreError = errno;
    if (restoreError != 0) {
        return [NSString stringWithFormat:@"-1;;clipboardd_restore_root_euid_failed errno=%d\r\n", restoreError];
    }
    return response;
}

static NSString *TLinkClipboardHandleLine(NSString *line)
{
    NSString *trimmed = [line ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@";;"];
    if (parts.count < 2 || ![parts[0] isEqualToString:@"1"]) return @"-1;;clipboardd_bad_request\r\n";
    NSData *data = [[NSData alloc] initWithBase64EncodedString:parts[1] options:0];
    NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (!body) return @"-1;;clipboardd_bad_body_base64\r\n";
    int subtask = [[[body componentsSeparatedByString:@";;"] firstObject] intValue];
    if (subtask != 9) {
        NSString *licenseError = nil;
        if (!TLinkLicenseFeatureAllowed(@"automation", &licenseError)) {
            NSDictionary *status = TLinkLicenseStatusDictionary();
            return [NSString stringWithFormat:@"-1;;license_required component=clipboardd feature=automation state=%@ error=%@\r\n",
                    status[@"state"] ?: @"invalid",
                    licenseError ?: status[@"error"] ?: @"license_required"];
        }
    }

    __block NSString *response = nil;
    void (^work)(void) = ^{
        response = TLinkClipboardHandleBody(body);
    };
    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
    return response ?: @"-1;;clipboardd_empty_response\r\n";
}

static NSString *TLinkReadLine(int client)
{
    struct timeval timeout = {2, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    NSMutableData *data = [NSMutableData data];
    char ch = 0;
    while (data.length < 65536) {
        ssize_t n = read(client, &ch, 1);
        if (n <= 0 || ch == '\n') break;
        [data appendBytes:&ch length:1];
    }
    if (data.length == 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static void TLinkWriteResponse(int client, NSString *response)
{
    NSData *data = [(response ?: @"-1;;clipboardd_empty_response\r\n") dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t n = write(client, bytes, remaining);
        if (n <= 0) break;
        bytes += n;
        remaining -= (NSUInteger)n;
    }
}

static void TLinkRunClipboardServer(void)
{
    @autoreleasepool {
        int server = socket(AF_INET, SOCK_STREAM, 0);
        if (server < 0) {
            TLinkClipboardLog([NSString stringWithFormat:@"socket failed errno=%d", errno]);
            return;
        }
        int yes = 1;
        setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(6012);
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
        if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(server, 8) != 0) {
            TLinkClipboardLog([NSString stringWithFormat:@"bind/listen 6012 failed errno=%d", errno]);
            close(server);
            return;
        }
        TLinkClipboardLog(@"listening 127.0.0.1:6012");

        while (1) {
            int client = accept(server, NULL, NULL);
            if (client < 0) {
                if (errno == EINTR) continue;
                break;
            }
            @autoreleasepool {
                NSString *line = TLinkReadLine(client);
                TLinkWriteResponse(client, line.length ? TLinkClipboardHandleLine(line) : @"-1;;clipboardd_empty_request\r\n");
                close(client);
            }
        }
        close(server);
    }
}

static void TLinkInitializeUIKitPlugin(void)
{
    void *graphics = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
                            RTLD_LAZY | RTLD_GLOBAL);
    void *backboard = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
                             RTLD_LAZY | RTLD_GLOBAL);
    TLinkUIKitBootstrapFn gsInitialize = graphics
        ? (TLinkUIKitBootstrapFn)dlsym(graphics, "GSInitialize")
        : NULL;
    TLinkUIKitBootstrapFn bksDisplayServicesStart = backboard
        ? (TLinkUIKitBootstrapFn)dlsym(backboard, "BKSDisplayServicesStart")
        : NULL;
    TLinkUIApplicationInitializeFn initialize =
        (TLinkUIApplicationInitializeFn)dlsym(RTLD_DEFAULT, "UIApplicationInitialize");
    TLinkUIApplicationInstantiateSingletonFn instantiate =
        (TLinkUIApplicationInstantiateSingletonFn)dlsym(RTLD_DEFAULT, "UIApplicationInstantiateSingleton");

    Class screenClass = NSClassFromString(@"UIScreen");
    SEL initializeSelector = NSSelectorFromString(@"initialize");
    if (screenClass && [screenClass respondsToSelector:initializeSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(screenClass, initializeSelector);
    }
    (void)CFRunLoopGetCurrent();
    if (gsInitialize) gsInitialize();
    if (bksDisplayServicesStart) bksDisplayServicesStart();
    if (initialize) initialize();
    if (instantiate) instantiate([TLinkClipboardApplication class]);
    TLinkClipboardLog([NSString stringWithFormat:@"UIKit bootstrap gs=%d bks=%d initialize=%d instantiate=%d",
                       gsInitialize ? 1 : 0, bksDisplayServicesStart ? 1 : 0,
                       initialize ? 1 : 0, instantiate ? 1 : 0]);

    @try {
        UIApplication *application = [UIApplication sharedApplication];
        static TLinkClipboardApplicationDelegate *delegate = nil;
        if (!delegate) delegate = [[TLinkClipboardApplicationDelegate alloc] init];
        application.delegate = delegate;
        SEL accessibilityInit = NSSelectorFromString(@"_accessibilityInit");
        if ([application respondsToSelector:accessibilityInit]) {
            ((void (*)(id, SEL))objc_msgSend)(application, accessibilityInit);
        }
        SEL complete = NSSelectorFromString(@"__completeAndRunAsPlugin");
        if (application && [application respondsToSelector:complete]) {
            ((void (*)(id, SEL))objc_msgSend)(application, complete);
        }
        UIApplicationState systemState = [application isKindOfClass:[TLinkClipboardApplication class]]
            ? [(TLinkClipboardApplication *)application tlinkSystemApplicationState]
            : application.applicationState;
        TLinkClipboardLog([NSString stringWithFormat:@"UIKit plugin ready app=%d class=%@ state=%ld system_state=%ld",
                           application ? 1 : 0, NSStringFromClass(application.class),
                           (long)application.applicationState, (long)systemState]);
    } @catch (__unused NSException *exception) {
        TLinkClipboardLog([NSString stringWithFormat:@"UIKit plugin exception=%@", exception.reason ?: exception.name]);
    }
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        (void)argc;
        (void)argv;
        signal(SIGPIPE, SIG_IGN);
        TLinkClipboardLog([NSString stringWithFormat:@"starting pid=%d uid=%d euid=%d", getpid(), getuid(), geteuid()]);
        BOOL mobileIdentity = TLinkAdoptMobileIdentity();
        TLinkClipboardLog([NSString stringWithFormat:@"identity mobile=%d uid=%d euid=%d gid=%d egid=%d",
                           mobileIdentity ? 1 : 0, getuid(), geteuid(), getgid(), getegid()]);
        TLinkInitializeUIKitPlugin();
        TLinkStartVolumeHIDListener();
        TLinkRefreshNotificationAuthorizationStatus();
        NSThread *serverThread = [[NSThread alloc] initWithBlock:^{
            TLinkRunClipboardServer();
        }];
        serverThread.name = @"com.tlinkauto.clipboardd.server";
        [serverThread start];
        CFRunLoopRun();
    }
    return 0;
}
