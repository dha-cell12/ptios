#import "TLinkVPNForegroundBroker.h"

#import <UIKit/UIKit.h>

#import "../../shared/TLinkLicenseVerifier.h"
#import "../../shared/TLinkVPNDiagnostics.h"
#import "../../shared/TLinkVPNManager.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static const uint16_t kTLinkVPNForegroundBrokerPort = 6015;
static const NSUInteger kTLinkVPNForegroundBrokerMaxRequest = 1024;

static BOOL TLinkVPNForegroundAppActive(void)
{
    __block BOOL active = false;
    void (^readState)(void) = ^{
        active = [UIApplication sharedApplication].applicationState ==
            UIApplicationStateActive;
    };
    if ([NSThread isMainThread]) {
        readState();
    } else {
        dispatch_sync(dispatch_get_main_queue(), readState);
    }
    return active;
}

static NSDictionary *TLinkVPNForegroundBrokerWait(
    void (^operation)(TLinkVPNResultCompletion),
    NSTimeInterval timeout)
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSDictionary *result = nil;
    operation(^(NSDictionary *value) {
        result = value;
        dispatch_semaphore_signal(semaphore);
    });
    long waitResult = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(timeout * NSEC_PER_SEC)));
    if (waitResult != 0 || !result) {
        return @{ @"ok": @0, @"code": @"vpn_broker_operation_timeout" };
    }
    return result;
}

static NSDictionary *TLinkVPNForegroundPreflight(void)
{
    return TLinkVPNDiagnosticsSnapshot(
        @"trollstore",
        @"foreground_candidate",
        @"app_broker_6015_with_interface_fallback",
        @"app_broker_6015_foreground_only",
        @"nevpnmanager_ikev2_candidate",
        @"StreamControl_app_6015",
        nil);
}

static BOOL TLinkVPNForegroundEntitlementReady(NSDictionary *snapshot)
{
    return [snapshot[@"entitlements"][@"allow_vpn"] boolValue] &&
           [snapshot[@"network_extension"][@"manager_class_available"] boolValue];
}

static NSString *TLinkVPNForegroundDiagnosticsResponse(void)
{
    NSMutableDictionary *diagnostics = [TLinkVPNForegroundPreflight() mutableCopy];
    BOOL active = TLinkVPNForegroundAppActive();
    BOOL entitlementReady = TLinkVPNForegroundEntitlementReady(diagnostics);
    NSDictionary *status = TLinkVPNForegroundBrokerWait(
        ^(TLinkVPNResultCompletion completion) {
            TLinkVPNReadManagerStatus(completion);
        },
        8.0);
    BOOL managerAvailable = [status[@"ok"] boolValue];

    diagnostics[@"phase"] = @3;
    diagnostics[@"broker_ready"] = @(active && entitlementReady && managerAvailable);
    diagnostics[@"broker_target"] = @"StreamControl_foreground_app";
    diagnostics[@"entitlement_probe_scope"] = @"foreground_app_process";
    diagnostics[@"profile_state"] = [status[@"configured"] boolValue]
        ? @"configured"
        : @"not_configured";
    diagnostics[@"control_preflight"] = !active
        ? @"blocked_app_not_foreground"
        : (!entitlementReady
            ? @"blocked_missing_entitlement_or_framework"
            : (managerAvailable
                ? @"foreground_manager_ready"
                : @"manager_api_failed"));
    diagnostics[@"app_active"] = @(active);
    diagnostics[@"manager_status"] = @{
        @"available": @(managerAvailable),
        @"configured": @([status[@"configured"] boolValue]),
        @"enabled": @([status[@"enabled"] boolValue]),
        @"connection_status":
            [status[@"connection_status"] isKindOfClass:[NSString class]]
                ? status[@"connection_status"]
                : @"unknown",
        @"last_error": managerAvailable
            ? @""
            : (status[@"code"] ?: @"vpn_status_failed"),
    };
    NSMutableDictionary *networkExtension =
        [diagnostics[@"network_extension"] mutableCopy];
    networkExtension[@"api_exercised"] = @1;
    diagnostics[@"network_extension"] = networkExtension;

    NSError *jsonError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:diagnostics
                                                   options:0
                                                     error:&jsonError];
    if (!json || jsonError) return @"-1;;vpn_diagnostics_encode_failed\r\n";
    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @"";
    return [NSString stringWithFormat:@"0;;%@\r\n", base64];
}

static NSString *TLinkVPNForegroundBrokerResponse(NSString *command)
{
    NSString *clean = [command
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([clean isEqualToString:@"diagnostics"]) {
        return TLinkVPNForegroundDiagnosticsResponse();
    }
    if (!TLinkVPNForegroundAppActive()) {
        return @"-1;;vpn_foreground_app_required\r\n";
    }

    NSString *licenseError = nil;
    if (!TLinkLicenseFeatureAllowed(@"automation", &licenseError)) {
        return [NSString stringWithFormat:@"-1;;vpn_license_denied %@\r\n",
            licenseError ?: @"automation_not_allowed"];
    }
    NSDictionary *preflight = TLinkVPNForegroundPreflight();
    if (!TLinkVPNForegroundEntitlementReady(preflight)) {
        return @"-1;;vpn_trollstore_entitlement_unavailable\r\n";
    }

    if ([clean isEqualToString:@"query"]) {
        NSDictionary *status = TLinkVPNForegroundBrokerWait(
            ^(TLinkVPNResultCompletion completion) {
                TLinkVPNReadManagerStatus(completion);
            },
            8.0);
        if (![status[@"ok"] boolValue]) {
            return [NSString stringWithFormat:@"-1;;%@\r\n",
                status[@"code"] ?: @"vpn_query_failed"];
        }
        return [NSString stringWithFormat:@"0;;%@\r\n",
            [status[@"connected"] boolValue] ? @"1" : @"0"];
    }

    if ([clean isEqualToString:@"connect"] ||
        [clean isEqualToString:@"disconnect"]) {
        BOOL requestedConnected = [clean isEqualToString:@"connect"];
        NSDictionary *result = TLinkVPNForegroundBrokerWait(
            ^(TLinkVPNResultCompletion completion) {
                TLinkVPNSetConnected(requestedConnected, 20.0, completion);
            },
            24.0);
        if (![result[@"ok"] boolValue]) {
            return [NSString stringWithFormat:@"-1;;%@\r\n",
                result[@"code"] ?: @"vpn_transition_failed"];
        }
        return [NSString stringWithFormat:@"0;;%@\r\n",
            requestedConnected ? @"1" : @"0"];
    }
    return @"-1;;vpn_broker_unknown_command\r\n";
}

static void TLinkVPNForegroundHandleClient(int client)
{
    struct timeval timeout = {30, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif

    NSMutableData *requestData = [NSMutableData data];
    uint8_t buffer[256];
    while (requestData.length < kTLinkVPNForegroundBrokerMaxRequest) {
        NSUInteger capacity = MIN(
            sizeof(buffer),
            kTLinkVPNForegroundBrokerMaxRequest - requestData.length);
        ssize_t received = recv(client, buffer, capacity, 0);
        if (received <= 0) break;
        [requestData appendBytes:buffer length:(NSUInteger)received];
        if (memchr(buffer, '\n', (size_t)received)) break;
    }
    NSString *request = requestData.length > 0
        ? [[NSString alloc] initWithData:requestData
                                encoding:NSUTF8StringEncoding]
        : @"";
    NSString *response = request.length > 0
        ? TLinkVPNForegroundBrokerResponse(request)
        : @"-1;;vpn_broker_empty_request\r\n";
    NSData *responseData =
        [response dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const uint8_t *cursor = responseData.bytes;
    NSUInteger remaining = responseData.length;
    while (remaining > 0) {
        ssize_t sent = send(client, cursor, remaining, 0);
        if (sent <= 0) break;
        cursor += sent;
        remaining -= (NSUInteger)sent;
    }
    close(client);
}

static void TLinkVPNForegroundRunServer(void)
{
    @autoreleasepool {
        int server = socket(AF_INET, SOCK_STREAM, 0);
        if (server < 0) {
            NSLog(@"[StreamControl][VPN] socket failed errno=%d", errno);
            return;
        }
        int yes = 1;
        setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        struct sockaddr_in address;
        memset(&address, 0, sizeof(address));
        address.sin_family = AF_INET;
        address.sin_port = htons(kTLinkVPNForegroundBrokerPort);
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
        if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0) {
            NSLog(@"[StreamControl][VPN] bind 127.0.0.1:6015 failed errno=%d",
                  errno);
            close(server);
            return;
        }
        if (listen(server, 4) != 0) {
            NSLog(@"[StreamControl][VPN] listen failed errno=%d", errno);
            close(server);
            return;
        }
        NSLog(@"[StreamControl][VPN] foreground broker listening on 127.0.0.1:6015");
        while (1) {
            int client = accept(server, NULL, NULL);
            if (client < 0) {
                if (errno == EINTR) continue;
                break;
            }
            TLinkVPNForegroundHandleClient(client);
        }
        close(server);
    }
}

void TLinkVPNStartForegroundBroker(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_async(
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                TLinkVPNForegroundRunServer();
            });
    });
}
