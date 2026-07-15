#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
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

@interface TLinkToastWindow : UIWindow
@end

@implementation TLinkToastWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    (void)point;
    (void)event;
    return nil;
}
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
static TLinkToastWindow *sTLinkToastWindow = nil;
static UIView *sTLinkToastBubble = nil;
static uint64_t sTLinkToastGeneration = 0;
static NSInteger sTLinkToastLastPosition = -1;
static NSString *const kTLinkAppNotificationAuthorizationPath = @"/var/mobile/Library/TLinkauto/runtime/app_notification_authorization";
static NSString *const kTLinkStreamControlBundleIdentifier = @"com.tlinkauto.streamcontrol";

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

static BOOL TLinkNotificationStatusAllowsDelivery(NSInteger status)
{
    return status == UNAuthorizationStatusAuthorized ||
           status == UNAuthorizationStatusProvisional ||
           status == UNAuthorizationStatusEphemeral;
}

static BOOL TLinkShowGlobalToastOverlay(NSDictionary *payload)
{
    if (![NSThread isMainThread]) return NO;
    NSString *message = [payload[@"message"] isKindOfClass:[NSString class]] ? payload[@"message"] : @"";
    if (message.length == 0) return NO;

    @try {
        UIScreen *screen = [UIScreen mainScreen];
        CGRect bounds = screen.bounds;
        if (CGRectIsEmpty(bounds)) return NO;

        NSInteger position = [payload[@"position"] integerValue];
        if (position < 0 || position > 2) position = 2;
        CGFloat fontSize = [payload[@"fontSize"] doubleValue];
        if (fontSize <= 0.0) fontSize = 15.0;
        if (fontSize > 50.0) fontSize = 50.0;
        NSTimeInterval duration = [payload[@"duration"] doubleValue];
        if (duration <= 0.0) duration = 2.0;
        if (duration > 30.0) duration = 30.0;

        if (!sTLinkToastWindow) {
            sTLinkToastWindow = [[TLinkToastWindow alloc] initWithFrame:bounds];
            UIViewController *root = [[UIViewController alloc] init];
            root.view.backgroundColor = [UIColor clearColor];
            root.view.userInteractionEnabled = NO;
            sTLinkToastWindow.rootViewController = root;
            sTLinkToastWindow.backgroundColor = [UIColor clearColor];
            sTLinkToastWindow.userInteractionEnabled = NO;
            sTLinkToastWindow.windowLevel = UIWindowLevelAlert + 1000.0;
            sTLinkToastWindow.screen = screen;
        }
        sTLinkToastWindow.frame = bounds;
        sTLinkToastWindow.rootViewController.view.frame = bounds;
        [sTLinkToastBubble removeFromSuperview];

        CGFloat maxWidth = MAX(120.0, CGRectGetWidth(bounds) - 48.0);
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = message;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.userInteractionEnabled = NO;

        CGSize labelSize = [label sizeThatFits:CGSizeMake(maxWidth - 32.0, CGFLOAT_MAX)];
        CGFloat bubbleWidth = MIN(maxWidth, ceil(labelSize.width + 32.0));
        CGFloat bubbleHeight = MAX(40.0, ceil(labelSize.height + 20.0));
        CGFloat y = 0.0;
        if (position == 0) {
            y = 54.0;
        } else if (position == 1) {
            y = (CGRectGetHeight(bounds) - bubbleHeight) / 2.0;
        } else {
            y = CGRectGetHeight(bounds) - bubbleHeight - 92.0;
        }
        CGFloat x = (CGRectGetWidth(bounds) - bubbleWidth) / 2.0;

        UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(x, y, bubbleWidth, bubbleHeight)];
        bubble.userInteractionEnabled = NO;
        bubble.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.86];
        bubble.layer.cornerRadius = 10.0;
        bubble.layer.shadowColor = [UIColor blackColor].CGColor;
        bubble.layer.shadowOpacity = 0.22;
        bubble.layer.shadowRadius = 10.0;
        bubble.layer.shadowOffset = CGSizeMake(0.0, 4.0);
        bubble.alpha = 0.0;
        label.frame = CGRectInset(bubble.bounds, 16.0, 10.0);
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [bubble addSubview:label];
        [sTLinkToastWindow.rootViewController.view addSubview:bubble];
        sTLinkToastBubble = bubble;
        sTLinkToastLastPosition = position;
        uint64_t generation = ++sTLinkToastGeneration;
        sTLinkToastWindow.hidden = NO;

        [UIView animateWithDuration:0.15 animations:^{
            bubble.alpha = 1.0;
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != sTLinkToastGeneration) return;
            [UIView animateWithDuration:0.18 animations:^{
                bubble.alpha = 0.0;
            } completion:^(__unused BOOL finished) {
                if (generation != sTLinkToastGeneration) return;
                [bubble removeFromSuperview];
                sTLinkToastBubble = nil;
                sTLinkToastWindow.hidden = YES;
            }];
        });
        sTLinkLastBackgroundVisualResult = [NSString stringWithFormat:@"uidaemon_toast_presented_position_%ld", (long)position];
        TLinkClipboardLog([NSString stringWithFormat:@"UIDaemon toast presented position=%ld frame=%@ duration=%.2f window_level=%.1f",
                           (long)position, NSStringFromCGRect(bubble.frame), duration, sTLinkToastWindow.windowLevel]);
        return YES;
    } @catch (NSException *exception) {
        sTLinkLastBackgroundVisualResult = @"uidaemon_toast_exception";
        TLinkClipboardLog([NSString stringWithFormat:@"UIDaemon toast exception=%@",
                           exception.reason ?: exception.name]);
        return NO;
    }
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
    NSString *title = [payload[@"title"] isKindOfClass:[NSString class]] ? payload[@"title"] : @"TLinkauto";
    NSString *message = [payload[@"message"] isKindOfClass:[NSString class]] ? payload[@"message"] : @"";
    if (message.length == 0) return @"-1;;background_visual_missing_message\r\n";
    NSInteger appAuthorization = TLinkAppNotificationAuthorizationStatus();
    if ([kind isEqualToString:@"toast"]) {
        if (TLinkShowGlobalToastOverlay(payload)) {
            return [NSString stringWithFormat:@"0;;background_visual_uidaemon_toast_presented;;position=%ld\r\n",
                    (long)sTLinkToastLastPosition];
        }
        TLinkScheduleCFUserNotification(payload, @"uidaemon_toast_failed");
        return @"0;;background_visual_uidaemon_toast_failed_cfusernotification_queued\r\n";
    }
    if (!TLinkNotificationStatusAllowsDelivery(sTLinkNotificationAuthorizationStatus)) {
        TLinkScheduleCFUserNotification(payload, @"daemon_notification_center_not_authorized");
        return [NSString stringWithFormat:@"0;;background_visual_cfusernotification_queued;;%@;;daemon_authorization=%ld;;app_authorization=%ld\r\n",
                kind, (long)sTLinkNotificationAuthorizationStatus, (long)appAuthorization];
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
    sTLinkLastBackgroundVisualResult = @"pending";
    [TLinkNotificationCenter()
        addNotificationRequest:request
         withCompletionHandler:^(NSError *error) {
            if (error) {
                sTLinkLastBackgroundVisualResult = [NSString stringWithFormat:@"failed_%@_%ld",
                    error.domain ?: @"unknown", (long)error.code];
                TLinkClipboardLog([NSString stringWithFormat:@"background visual failed kind=%@ error=%@",
                                   kind, error.localizedDescription ?: @"unknown"]);
                TLinkScheduleCFUserNotification(payload, [NSString stringWithFormat:@"usernotifications_%@_%ld",
                    error.domain ?: @"unknown", (long)error.code]);
            } else {
                sTLinkLastBackgroundVisualResult = @"accepted";
                TLinkClipboardLog([NSString stringWithFormat:@"background visual queued kind=%@ id=%@",
                                   kind, payload[@"event_id"] ?: @0]);
            }
        }];
    TLinkRefreshNotificationAuthorizationStatus();
    return [NSString stringWithFormat:@"0;;background_visual_notification_queued;;%@;;daemon_authorization=%ld;;app_authorization=%ld\r\n",
            kind, (long)sTLinkNotificationAuthorizationStatus, (long)appAuthorization];
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
        return [NSString stringWithFormat:@"0;;clipboardd_ready;;version=10;;pid=%d;;uid=%d;;euid=%d;;state=%ld;;system_state=%ld;;write_verified=%d;;background_entitlement=1;;background_ui_bridge=1;;background_visual_mode=uidaemon_positioned_toast_cfusernotification_alert;;toast_overlay_visible=%d;;toast_position=%ld;;notification_center=%@;;main_bundle=%@;;notification_auth=%ld;;app_notification_auth=%ld;;background_visual_last=%@;;keep_awake_requested=%d;;idle_timer_disabled=%d\r\n",
                getpid(), getuid(), geteuid(), (long)state, (long)systemState,
                sTLinkClipboardWriteVerified ? 1 : 0,
                (sTLinkToastWindow && !sTLinkToastWindow.hidden && sTLinkToastBubble) ? 1 : 0,
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
