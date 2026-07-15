#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

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

static BOOL sTLinkClipboardWriteVerified = NO;
static BOOL sTLinkKeepAwakeRequested = NO;
static NSInteger sTLinkNotificationAuthorizationStatus = -1;

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

static void TLinkRefreshNotificationAuthorizationStatus(void)
{
    [[UNUserNotificationCenter currentNotificationCenter]
        getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
            sTLinkNotificationAuthorizationStatus = settings.authorizationStatus;
        }];
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
    NSString *title = [payload[@"title"] isKindOfClass:[NSString class]] ? payload[@"title"] : @"TLinkauto";
    NSString *message = [payload[@"message"] isKindOfClass:[NSString class]] ? payload[@"message"] : @"";
    if (message.length == 0) return @"-1;;background_visual_missing_message\r\n";
    if (sTLinkNotificationAuthorizationStatus == UNAuthorizationStatusDenied) {
        return @"-1;;background_visual_notification_permission_denied open_StreamControl_Settings_notifications\r\n";
    }
    if (sTLinkNotificationAuthorizationStatus == UNAuthorizationStatusNotDetermined) {
        return @"-1;;background_visual_notification_permission_not_determined open_StreamControl_once\r\n";
    }

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title.length > 0 ? title : @"TLinkauto";
    content.body = message;
    content.userInfo = @{
        @"tlink_kind": kind ?: @"toast",
        @"tlink_event_id": payload[@"event_id"] ?: @0,
    };
    NSString *identifier = [NSString stringWithFormat:@"tlinkauto.%@.%@",
                            kind.length > 0 ? kind : @"visual",
                            payload[@"event_id"] ?: @((long long)(NSDate.date.timeIntervalSince1970 * 1000.0))];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter]
        addNotificationRequest:request
         withCompletionHandler:^(NSError *error) {
            if (error) {
                TLinkClipboardLog([NSString stringWithFormat:@"background visual failed kind=%@ error=%@",
                                   kind, error.localizedDescription ?: @"unknown"]);
            } else {
                TLinkClipboardLog([NSString stringWithFormat:@"background visual queued kind=%@ id=%@",
                                   kind, payload[@"event_id"] ?: @0]);
            }
        }];
    TLinkRefreshNotificationAuthorizationStatus();
    return [NSString stringWithFormat:@"0;;background_visual_notification_queued;;%@;;authorization=%ld\r\n",
            kind, (long)sTLinkNotificationAuthorizationStatus];
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
        return [NSString stringWithFormat:@"0;;clipboardd_ready;;version=5;;pid=%d;;uid=%d;;euid=%d;;state=%ld;;system_state=%ld;;write_verified=%d;;background_entitlement=1;;background_ui_bridge=1;;notification_auth=%ld;;keep_awake_requested=%d;;idle_timer_disabled=%d\r\n",
                getpid(), getuid(), geteuid(), (long)state, (long)systemState,
                sTLinkClipboardWriteVerified ? 1 : 0,
                (long)sTLinkNotificationAuthorizationStatus,
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
        TLinkInitializeUIKitPlugin();
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
