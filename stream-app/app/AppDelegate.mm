#import "AppDelegate.h"
#import "BackgroundServiceScheduler.h"
#import <QuartzCore/QuartzCore.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#import <UserNotifications/UserNotifications.h>
#include <arpa/inet.h>
#include <errno.h>
#include <math.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#import "ScriptsViewController.h"
#import "SettingsViewController.h"
#import "StreamSupervisor.h"
#import "TLinkSocketClient.h"

// ---------------------------------------------------------------------------
// SCAppDelegate
//
// Stands up the window + navigation controller and forces light mode to match
// the Tlinkauto app's visual style. The supervisor is created/owned by the
// app delegate so the service lifecycle is independent from any visible tab.
// ---------------------------------------------------------------------------

static NSString *const kTLinkAppForegroundHeartbeatPath = @"/var/mobile/Library/TLinkauto/runtime/app_foreground_heartbeat";
static NSString *const kTLinkAppNotificationAuthorizationPath = @"/var/mobile/Library/TLinkauto/runtime/app_notification_authorization";

@interface SCAppDelegate ()
@property(nonatomic, strong) NSTimer *visualFeedbackTimer;
@property(nonatomic, assign) BOOL visualFeedbackPollInFlight;
@property(nonatomic, assign) uint64_t lastVisualEventId;
@property(nonatomic, assign) NSInteger lastVisualFeedbackPid;
@property(nonatomic, assign) NSInteger visualFeedbackBurstPollsRemaining;
@property(nonatomic, strong) SCStreamSupervisor *serviceSupervisor;
@property(nonatomic, strong) SCBackgroundServiceScheduler *backgroundServiceScheduler;
@property(nonatomic, assign) BOOL ocrServerStarted;
@property(nonatomic, assign) BOOL clipboardServerStarted;
@end

@implementation SCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)launchOptions;

    self.serviceSupervisor = [[SCStreamSupervisor alloc] init];
    self.backgroundServiceScheduler = [[SCBackgroundServiceScheduler alloc] initWithSupervisor:self.serviceSupervisor];
    [self.backgroundServiceScheduler registerTasks];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    SCScriptsViewController *scripts = [[SCScriptsViewController alloc] initWithScriptsPath:@"/var/mobile/Library/TLinkauto/scripts"];
    SCSettingsViewController *settings = [[SCSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];

    UINavigationController *scriptsNav = [[UINavigationController alloc] initWithRootViewController:scripts];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];

    scriptsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Scripts"
                                                          image:[UIImage systemImageNamed:@"list.dash"]
                                                            tag:0];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
                                                           image:[UIImage systemImageNamed:@"gearshape"]
                                                             tag:1];

    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = @[scriptsNav, settingsNav];
    tabs.selectedIndex = 0;

    if (@available(iOS 13.0, *)) {
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }

    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(requestVisualFeedbackBurstPoll:)
                                                 name:@"TLinkVisualFeedbackNeedsPoll"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(requestStreamServiceRestart:)
                                                 name:@"TLinkRestartStreamService"
                                               object:nil];
    [self ensureStreamServiceForReason:@"launch" background:NO];
    [self.backgroundServiceScheduler scheduleRecoveryTasksForReason:@"app_launch"];
    [self startAppSideOCRServer];
    [self startAppSideClipboardServer];
    [self startVisualFeedbackMonitor];

    return YES;
}

- (void)requestStreamServiceRestart:(NSNotification *)notification
{
    (void)notification;
    NSLog(@"[StreamControl] restart streamd requested from Settings");
    [self.serviceSupervisor restart];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    (void)application;
    [self ensureStreamServiceForReason:@"active" background:NO];
    [self startAppSideOCRServer];
    [self startAppSideClipboardServer];
    [self startVisualFeedbackMonitor];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    (void)application;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self stopVisualFeedbackMonitor];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    (void)application;
    [self ensureStreamServiceForReason:@"background" background:YES];
    [self.backgroundServiceScheduler scheduleRecoveryTasksForReason:@"app_background"];
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
    [self writeForegroundHeartbeat];
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
    [[NSFileManager defaultManager] removeItemAtPath:kTLinkAppForegroundHeartbeatPath error:nil];
}

- (void)pollVisualFeedback
{
    [self writeForegroundHeartbeat];
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

- (void)writeForegroundHeartbeat
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSString *directory = [kTLinkAppForegroundHeartbeatPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    uint64_t nowMs = (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000.0);
    [[NSString stringWithFormat:@"%llu", nowMs] writeToFile:kTLinkAppForegroundHeartbeatPath
                                                   atomically:NO
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
}

- (void)requestBackgroundVisualNotificationPermission
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        [self persistNotificationAuthorizationStatus:settings.authorizationStatus];
        if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                                  completionHandler:^(BOOL granted, NSError *error) {
                NSLog(@"[StreamControl][Visual] notification permission granted=%d error=%@",
                      granted ? 1 : 0, error.localizedDescription ?: @"none");
                [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *updated) {
                    [self persistNotificationAuthorizationStatus:updated.authorizationStatus];
                }];
            }];
        });
    }];
}

- (void)persistNotificationAuthorizationStatus:(UNAuthorizationStatus)status
{
    NSString *directory = [kTLinkAppNotificationAuthorizationPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSString stringWithFormat:@"%ld", (long)status] writeToFile:kTLinkAppNotificationAuthorizationPath
                                                         atomically:NO
                                                           encoding:NSUTF8StringEncoding
                                                              error:nil];
}

- (void)handleVisualFeedbackStatusResponse:(NSString *)response
{
    if (![response hasPrefix:@"0;;"]) return;
    NSString *payload = [[response substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (jsonData.length == 0) return;
    NSDictionary *status = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if (![status isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *keepAwake = status[@"keep_awake"];
    if ([keepAwake isKindOfClass:[NSDictionary class]]) {
        BOOL enabled = [keepAwake[@"enabled"] boolValue];
        if ([UIApplication sharedApplication].idleTimerDisabled != enabled) {
            [UIApplication sharedApplication].idleTimerDisabled = enabled;
        }
    }

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

- (void)startAppSideOCRServer
{
    if (self.ocrServerStarted) return;
    self.ocrServerStarted = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self runAppSideOCRServer];
    });
}

- (NSString *)protocolSafeOCRText:(NSString *)text
{
    NSMutableString *safe = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "] mutableCopy];
    [safe replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@";;" withString:@"; " options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@",," withString:@", " options:0 range:NSMakeRange(0, safe.length)];
    return safe ?: @"";
}

- (CGImageRef)newRGBImageFromImageData:(NSData *)imageData error:(NSString **)error CF_RETURNS_RETAINED
{
    if (imageData.length == 0) {
        if (error) *error = @"empty_image_data";
        return nil;
    }

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (!source) {
        if (error) *error = @"image_source_create_failed";
        return nil;
    }
    CGImageRef decoded = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!decoded) {
        if (error) *error = @"image_decode_failed";
        return nil;
    }

    size_t width = CGImageGetWidth(decoded);
    size_t height = CGImageGetHeight(decoded);
    if (width == 0 || height == 0 || width > 12000 || height > 12000) {
        CGImageRelease(decoded);
        if (error) *error = @"image_bad_dimensions";
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    size_t bytesPerRow = width * 4;
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 width,
                                                 height,
                                                 8,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        CGImageRelease(decoded);
        if (error) *error = @"rgb_context_create_failed";
        return nil;
    }

    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), decoded);
    CGImageRef rgbImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(decoded);
    if (!rgbImage && error) *error = @"rgb_image_create_failed";
    return rgbImage;
}

- (BOOL)performTextRecognitionWithImage:(CGImageRef)image
                                  level:(VNRequestTextRecognitionLevel)level
                                request:(VNRecognizeTextRequest **)outRequest
                                  error:(NSError **)outError
{
    if (!image) return NO;
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *finishedRequest, NSError *error) {
        (void)finishedRequest;
        (void)error;
    }];
    request.recognitionLevel = level;
    request.usesLanguageCorrection = NO;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image
                                                                        orientation:kCGImagePropertyOrientationUp
                                                                            options:@{}];
    NSError *visionError = nil;
    BOOL ok = [handler performRequests:@[request] error:&visionError];
    if (ok) {
        if (outRequest) *outRequest = request;
        return YES;
    }
    if (outError) *outError = visionError;
    return NO;
}

- (NSString *)performAppSideOCRRequestLine:(NSString *)line
{
    NSArray<NSString *> *parts = [[line ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@";;"];
    if (parts.count < 7 || ![parts[0] isEqualToString:@"1"]) return @"-1;;app_ocr_bad_request\r\n";
    NSString *imagePath = parts[1];
    NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
    if (imageData.length == 0) {
        return [NSString stringWithFormat:@"-1;;app_ocr_png_missing path=%@\r\n", imagePath ?: @""];
    }

    if (@available(iOS 13.0, *)) {
        CGFloat originX = [parts[2] doubleValue];
        CGFloat originY = [parts[3] doubleValue];
        CGFloat regionW = MAX(1.0, [parts[4] doubleValue]);
        CGFloat regionH = MAX(1.0, [parts[5] doubleValue]);
        int levelValue = [parts[6] intValue];

        NSString *decodeError = nil;
        CGImageRef rgbImage = [self newRGBImageFromImageData:imageData error:&decodeError];
        if (!rgbImage) {
            return [NSString stringWithFormat:@"-1;;app_ocr_rgb_decode_failed %@\r\n", decodeError ?: @"unknown"];
        }

        VNRequestTextRecognitionLevel requestedLevel = levelValue == 1 ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
        VNRecognizeTextRequest *request = nil;
        NSError *visionError = nil;
        BOOL ok = [self performTextRecognitionWithImage:rgbImage
                                                  level:requestedLevel
                                                request:&request
                                                  error:&visionError];
        NSString *firstError = visionError.localizedDescription ?: @"unknown";
        if (!ok && requestedLevel == VNRequestTextRecognitionLevelFast) {
            visionError = nil;
            ok = [self performTextRecognitionWithImage:rgbImage
                                                 level:VNRequestTextRecognitionLevelAccurate
                                               request:&request
                                                 error:&visionError];
        }
        CGImageRelease(rgbImage);
        if (!ok) {
            return [NSString stringWithFormat:@"-1;;app_ocr_failed first=%@ retry=%@\r\n",
                    firstError,
                    visionError.localizedDescription ?: @"unknown"];
        }

        NSMutableArray<NSString *> *output = [NSMutableArray array];
        for (VNRecognizedTextObservation *observation in request.results) {
            if (![observation isKindOfClass:[VNRecognizedTextObservation class]]) continue;
            VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
            if (!candidate.string.length) continue;
            CGRect bb = observation.boundingBox;
            int x = (int)llround(originX + bb.origin.x * regionW);
            int y = (int)llround(originY + (1.0 - bb.origin.y - bb.size.height) * regionH);
            int w = (int)llround(bb.size.width * regionW);
            int h = (int)llround(bb.size.height * regionH);
            [output addObject:[NSString stringWithFormat:@"%@,,%d,,%d,,%d,,%d",
                               [self protocolSafeOCRText:candidate.string], x, y, w, h]];
        }
        return [NSString stringWithFormat:@"0;;%@\r\n", [output componentsJoinedByString:@";;"]];
    }

    return @"-1;;app_ocr_requires_ios13\r\n";
}

- (void)startAppSideClipboardServer
{
    if (self.clipboardServerStarted) return;
    self.clipboardServerStarted = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self runAppSideClipboardServer];
    });
}

- (NSString *)pasteboardImageTypeForData:(NSData *)imageData
{
    if (imageData.length < 4) return nil;
    const unsigned char *bytes = (const unsigned char *)imageData.bytes;
    if (imageData.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
        bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
        return @"public.png";
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return @"public.jpeg";
    if (imageData.length >= 6 && bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == '8') {
        return @"com.compuserve.gif";
    }
    if (imageData.length >= 12 &&
        bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
        bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P') {
        return @"org.webmproject.webp";
    }
    return nil;
}

- (NSString *)performClipboardBody:(NSString *)body
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        return @"-1;;app_clipboard_requires_foreground\r\n";
    }
    NSArray<NSString *> *parts = [body ?: @"" componentsSeparatedByString:@";;"];
    if (parts.count < 1) return @"-1;;app_clipboard_missing_subtask\r\n";
    int subtask = [parts[0] intValue];
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];

    if (subtask == 6) {
        return [NSString stringWithFormat:@"0;;%@\r\n", pasteboard.string ?: @""];
    }
    if (subtask == 7) {
        if (parts.count < 2) return @"-1;;app_clipboard_save_text_missing_content\r\n";
        NSString *text = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@";;"];
        pasteboard.string = text ?: @"";
        NSString *stored = pasteboard.string ?: @"";
        if (![stored isEqualToString:text ?: @""]) {
            return [NSString stringWithFormat:@"-1;;app_clipboard_text_verify_failed expected=%lu actual=%lu\r\n",
                    (unsigned long)text.length, (unsigned long)stored.length];
        }
        return @"0\r\n";
    }
    if (subtask == 8) {
        if (parts.count < 3 || ![parts[1] isEqualToString:@"file"]) return @"-1;;app_clipboard_image_requires_file_path\r\n";
        NSString *imagePath = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@";;"];
        NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
        if (imageData.length == 0) return [NSString stringWithFormat:@"-1;;app_clipboard_image_read_failed path=%@\r\n", imagePath ?: @""];
        NSString *type = [self pasteboardImageTypeForData:imageData];
        if (!type.length) return @"-1;;app_clipboard_image_unsupported_format\r\n";
        pasteboard.items = @[@{type: imageData}];
        return [NSString stringWithFormat:@"0;;clipboard_image_data;;%@;;%lu\r\n", type, (unsigned long)imageData.length];
    }
    return @"-1;;app_clipboard_unsupported_subtask\r\n";
}

- (NSString *)performAppSideClipboardRequestLine:(NSString *)line
{
    NSArray<NSString *> *parts = [[line ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@";;"];
    if (parts.count < 2 || ![parts[0] isEqualToString:@"1"]) return @"-1;;app_clipboard_bad_request\r\n";
    NSData *bodyData = [[NSData alloc] initWithBase64EncodedString:parts[1] options:0];
    NSString *body = bodyData ? [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] : nil;
    if (!body) return @"-1;;app_clipboard_bad_body_base64\r\n";

    __block NSString *response = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        response = [self performClipboardBody:body];
    });
    return response ?: @"-1;;app_clipboard_empty_response\r\n";
}

- (void)writeString:(NSString *)string toSocket:(int)client
{
    NSData *data = [(string ?: @"-1;;app_ocr_empty_response\r\n") dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(client, bytes, remaining);
        if (written <= 0) break;
        bytes += written;
        remaining -= (NSUInteger)written;
    }
}

- (NSString *)readLineFromSocket:(int)client
{
    NSMutableData *data = [NSMutableData data];
    char ch = 0;
    while (data.length < 16384) {
        ssize_t n = read(client, &ch, 1);
        if (n <= 0) break;
        if (ch == '\n') break;
        [data appendBytes:&ch length:1];
    }
    if (data.length == 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)handleAppSideOCRClient:(int)client
{
    @autoreleasepool {
        NSString *line = [self readLineFromSocket:client];
        NSString *response = line.length > 0 ? [self performAppSideOCRRequestLine:line] : @"-1;;app_ocr_empty_request\r\n";
        [self writeString:response toSocket:client];
        close(client);
    }
}

- (void)handleAppSideClipboardClient:(int)client
{
    @autoreleasepool {
        NSString *line = [self readLineFromSocket:client];
        NSString *response = line.length > 0 ? [self performAppSideClipboardRequestLine:line] : @"-1;;app_clipboard_empty_request\r\n";
        [self writeString:response toSocket:client];
        close(client);
    }
}

- (void)runAppSideOCRServer
{
    @autoreleasepool {
        int server = socket(AF_INET, SOCK_STREAM, 0);
        if (server < 0) {
            NSLog(@"[StreamControl][OCR] socket failed errno=%d", errno);
            self.ocrServerStarted = NO;
            return;
        }
        int yes = 1;
        setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(6011);
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
        if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
            NSLog(@"[StreamControl][OCR] bind 127.0.0.1:6011 failed errno=%d", errno);
            close(server);
            self.ocrServerStarted = NO;
            return;
        }
        if (listen(server, 4) != 0) {
            NSLog(@"[StreamControl][OCR] listen failed errno=%d", errno);
            close(server);
            self.ocrServerStarted = NO;
            return;
        }
        NSLog(@"[StreamControl][OCR] app-side OCR server listening on 127.0.0.1:6011");

        while (1) {
            int client = accept(server, NULL, NULL);
            if (client < 0) {
                if (errno == EINTR) continue;
                break;
            }
            [self handleAppSideOCRClient:client];
        }
        close(server);
        self.ocrServerStarted = NO;
    }
}

- (void)runAppSideClipboardServer
{
    @autoreleasepool {
        int server = socket(AF_INET, SOCK_STREAM, 0);
        if (server < 0) {
            NSLog(@"[StreamControl][Clipboard] socket failed errno=%d", errno);
            self.clipboardServerStarted = NO;
            return;
        }
        int yes = 1;
        setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(6013);
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
        if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
            NSLog(@"[StreamControl][Clipboard] bind 127.0.0.1:6013 failed errno=%d", errno);
            close(server);
            self.clipboardServerStarted = NO;
            return;
        }
        if (listen(server, 4) != 0) {
            NSLog(@"[StreamControl][Clipboard] listen failed errno=%d", errno);
            close(server);
            self.clipboardServerStarted = NO;
            return;
        }
        NSLog(@"[StreamControl][Clipboard] app-side clipboard server listening on 127.0.0.1:6013");

        while (1) {
            int client = accept(server, NULL, NULL);
            if (client < 0) {
                if (errno == EINTR) continue;
                break;
            }
#ifdef SO_NOSIGPIPE
            int noSigPipe = 1;
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif
            [self handleAppSideClipboardClient:client];
        }
        close(server);
        self.clipboardServerStarted = NO;
    }
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
