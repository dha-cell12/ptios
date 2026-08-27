#import "TLinkWidgetWakeHelper.h"

#import <arpa/inet.h>
#import <dlfcn.h>
#import <netinet/in.h>
#import <objc/message.h>
#import <stdint.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <unistd.h>

static NSString *const kTLinkHostBundleIdentifier = @"com.tlinkauto.streamcontrol";
static NSString *const kTLinkWidgetWakeDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/widget_boot_wake.plist";
static const NSTimeInterval kTLinkWidgetWakeRetryInterval = 30.0;

typedef int (*TLinkSBSLaunchApplicationFn)(NSString *, NSURL *, NSDictionary *, NSDictionary *, BOOL);
typedef int (*TLinkSBSSimpleLaunchApplicationFn)(CFStringRef, Boolean);

@implementation TLinkWidgetWakeHelper

+ (uint64_t)bootTimeSeconds
{
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    struct timeval bootTime;
    memset(&bootTime, 0, sizeof(bootTime));
    size_t size = sizeof(bootTime);
    if (sysctl(mib, 2, &bootTime, &size, NULL, 0) != 0) return 0;
    return bootTime.tv_sec > 0 ? (uint64_t)bootTime.tv_sec : 0;
}

+ (BOOL)isTaskServiceListening
{
    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor < 0) return NO;

    struct timeval timeout = { .tv_sec = 0, .tv_usec = 250000 };
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    BOOL listening = connect(descriptor, (struct sockaddr *)&address, sizeof(address)) == 0;
    close(descriptor);
    return listening;
}

+ (NSDictionary *)lastDiagnostics
{
    NSDictionary *diagnostics = [NSDictionary dictionaryWithContentsOfFile:kTLinkWidgetWakeDiagnosticsPath];
    return [diagnostics isKindOfClass:[NSDictionary class]] ? diagnostics : @{};
}

+ (void)writeDiagnosticsWithResult:(NSString *)result returnCode:(NSInteger)returnCode
{
    NSString *directory = [kTLinkWidgetWakeDiagnosticsPath stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *diagnostics = @{
        @"last_attempt_at": @([[NSDate date] timeIntervalSince1970]),
        @"boot_time": @([self bootTimeSeconds]),
        @"result": result ?: @"unknown",
        @"return_code": @(returnCode),
        @"host_bundle_id": kTLinkHostBundleIdentifier,
    };
    if ([diagnostics writeToFile:kTLinkWidgetWakeDiagnosticsPath atomically:YES]) {
        [fileManager setAttributes:@{NSFileProtectionKey: NSFileProtectionNone}
                     ofItemAtPath:kTLinkWidgetWakeDiagnosticsPath
                            error:nil];
    }
}

+ (BOOL)launchWithApplicationWorkspace
{
    dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/LaunchServices.framework/LaunchServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY | RTLD_GLOBAL);
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultSelector]) return NO;

    id workspace = nil;
    @try {
        workspace = ((id (*)(Class, SEL))objc_msgSend)(workspaceClass, defaultSelector);
    } @catch (__unused NSException *exception) {
        workspace = nil;
    }
    if (!workspace) return NO;

    for (NSString *selectorName in @[@"openApplicationWithBundleID:", @"openApplicationWithBundleIdentifier:"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![workspace respondsToSelector:selector]) continue;
        @try {
            if (((BOOL (*)(id, SEL, NSString *))objc_msgSend)(workspace, selector, kTLinkHostBundleIdentifier)) return YES;
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

+ (NSString *)wakeHostApplicationIfNecessary
{
    if ([self isTaskServiceListening]) {
        [self writeDiagnosticsWithResult:@"service_already_running" returnCode:0];
        return @"service_already_running";
    }

    NSDictionary *lastDiagnostics = [self lastDiagnostics];
    NSTimeInterval lastAttempt = [lastDiagnostics[@"last_attempt_at"] doubleValue];
    uint64_t lastBootTime = [lastDiagnostics[@"boot_time"] unsignedLongLongValue];
    uint64_t currentBootTime = [self bootTimeSeconds];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (lastBootTime == currentBootTime && lastAttempt > 0 && now >= lastAttempt &&
        now - lastAttempt < kTLinkWidgetWakeRetryInterval) return @"retry_throttled";

    [self writeDiagnosticsWithResult:@"launch_attempt_started" returnCode:0];

    void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                          RTLD_LAZY | RTLD_GLOBAL);
    if (!handle) {
        if ([self launchWithApplicationWorkspace]) {
            [self writeDiagnosticsWithResult:@"launch_requested_workspace" returnCode:0];
            return @"launch_requested_workspace";
        }
        [self writeDiagnosticsWithResult:@"springboard_services_unavailable" returnCode:-1];
        return @"springboard_services_unavailable";
    }

    TLinkSBSLaunchApplicationFn launch = (TLinkSBSLaunchApplicationFn)dlsym(
        handle, "SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions");
    NSString *unlockKey = @"unlockDevice";
    NSString *const *unlockKeyAddress = (NSString *const *)dlsym(handle, "SBSApplicationLaunchOptionUnlockDeviceKey");
    if (unlockKeyAddress && *unlockKeyAddress) unlockKey = *unlockKeyAddress;
    NSDictionary *launchOptions = @{unlockKey: @YES};

    int returnCode = -2;
    if (launch) {
        // Different iOS builds have consumed this option from either options
        // dictionary. Supplying it to both matches the working XXTouch path.
        returnCode = launch(kTLinkHostBundleIdentifier, nil, launchOptions, launchOptions, NO);
        if (returnCode == 0) {
            [self writeDiagnosticsWithResult:@"launch_requested_full_sbs" returnCode:0];
            dlclose(handle);
            return @"launch_requested_full_sbs";
        }
    }

    TLinkSBSSimpleLaunchApplicationFn simpleLaunch = (TLinkSBSSimpleLaunchApplicationFn)dlsym(
        handle, "SBSLaunchApplicationWithIdentifier");
    if (simpleLaunch) {
        int simpleReturnCode = simpleLaunch((__bridge CFStringRef)kTLinkHostBundleIdentifier, false);
        if (simpleReturnCode == 0) {
            [self writeDiagnosticsWithResult:@"launch_requested_simple_sbs" returnCode:0];
            dlclose(handle);
            return @"launch_requested_simple_sbs";
        }
        returnCode = simpleReturnCode;
    }
    dlclose(handle);

    if ([self launchWithApplicationWorkspace]) {
        [self writeDiagnosticsWithResult:@"launch_requested_workspace" returnCode:0];
        return @"launch_requested_workspace";
    }

    [self writeDiagnosticsWithResult:@"launch_failed" returnCode:returnCode];
    return [NSString stringWithFormat:@"launch_failed_%d", returnCode];
}

@end
