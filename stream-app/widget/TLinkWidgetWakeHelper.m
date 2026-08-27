#import "TLinkWidgetWakeHelper.h"

#import <arpa/inet.h>
#import <dlfcn.h>
#import <netinet/in.h>
#import <stdint.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <unistd.h>

static NSString *const kTLinkHostBundleIdentifier = @"com.tlinkauto.streamcontrol";
static NSString *const kTLinkBootEnabledMarkerPath = @"/var/mobile/Library/TLinkauto/runtime/widget_boot_enabled";
static NSString *const kTLinkWidgetWakeDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/widget_boot_wake.plist";
static const NSTimeInterval kTLinkWidgetWakeRetryInterval = 30.0;

typedef int (*TLinkSBSLaunchApplicationFn)(NSString *, NSURL *, NSDictionary *, NSDictionary *, BOOL);

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

+ (void)wakeHostApplicationIfNecessary
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:kTLinkBootEnabledMarkerPath]) return;
    if ([self isTaskServiceListening]) {
        [self writeDiagnosticsWithResult:@"service_already_running" returnCode:0];
        return;
    }

    NSDictionary *lastDiagnostics = [self lastDiagnostics];
    NSTimeInterval lastAttempt = [lastDiagnostics[@"last_attempt_at"] doubleValue];
    uint64_t lastBootTime = [lastDiagnostics[@"boot_time"] unsignedLongLongValue];
    uint64_t currentBootTime = [self bootTimeSeconds];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (lastBootTime == currentBootTime && lastAttempt > 0 && now >= lastAttempt &&
        now - lastAttempt < kTLinkWidgetWakeRetryInterval) return;

    void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                          RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        [self writeDiagnosticsWithResult:@"springboard_services_unavailable" returnCode:-1];
        return;
    }

    TLinkSBSLaunchApplicationFn launch = (TLinkSBSLaunchApplicationFn)dlsym(
        handle, "SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions");
    if (!launch) {
        [self writeDiagnosticsWithResult:@"launch_symbol_unavailable" returnCode:-2];
        dlclose(handle);
        return;
    }

    NSString *unlockKey = @"unlockDevice";
    NSString *const *unlockKeyAddress = (NSString *const *)dlsym(handle, "SBSApplicationLaunchOptionUnlockDeviceKey");
    if (unlockKeyAddress && *unlockKeyAddress) unlockKey = *unlockKeyAddress;
    NSDictionary *launchOptions = @{unlockKey: @YES};
    int returnCode = launch(kTLinkHostBundleIdentifier, nil, nil, launchOptions, NO);
    [self writeDiagnosticsWithResult:returnCode == 0 ? @"launch_requested" : @"launch_returned_error"
                           returnCode:returnCode];
    dlclose(handle);
}

@end
