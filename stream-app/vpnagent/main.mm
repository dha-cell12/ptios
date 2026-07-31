#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#import "../../shared/TLinkLicenseVerifier.h"
#import "../../shared/TLinkVPNDiagnostics.h"
#import "../../shared/TLinkVPNManager.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <grp.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static const uint16_t kTLinkVPNAgentPort = 6016;
static const NSUInteger kTLinkVPNAgentMaxRequest = 1024;

static void TLinkVPNAgentKeepAliveTimer(
    __unused CFRunLoopTimerRef timer,
    __unused void *info)
{
}

static NSDictionary *TLinkVPNAgentWait(
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
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
    if (waitResult != 0 || !result) {
        return @{ @"ok": @0, @"code": @"vpnagent_operation_timeout" };
    }
    return result;
}

static NSDictionary *TLinkVPNAgentPreflight(void)
{
    return TLinkVPNDiagnosticsSnapshot(
        @"trollstore",
        @"background_agent_candidate",
        @"agent_6016_app_6015_interface_fallback",
        @"agent_6016_with_foreground_fallback",
        @"nevpnmanager_ikev2_background_agent_candidate",
        @"vpnagent_6016_then_StreamControl_6015",
        nil);
}

static BOOL TLinkVPNAgentEntitlementReady(NSDictionary *snapshot)
{
    return [snapshot[@"entitlements"][@"allow_vpn"] boolValue] &&
           [snapshot[@"network_extension"][@"manager_class_available"] boolValue];
}

static NSString *TLinkVPNAgentDiagnosticsResponse(void)
{
    NSMutableDictionary *diagnostics = [TLinkVPNAgentPreflight() mutableCopy];
    BOOL entitlementReady = TLinkVPNAgentEntitlementReady(diagnostics);
    NSDictionary *status = TLinkVPNAgentWait(
        ^(TLinkVPNResultCompletion completion) {
            TLinkVPNReadManagerStatus(completion);
        },
        8.0);
    BOOL managerAvailable = [status[@"ok"] boolValue];

    diagnostics[@"phase"] = @5;
    diagnostics[@"broker_ready"] = @(entitlementReady && managerAvailable);
    diagnostics[@"broker_target"] = @"vpnagent_mobile_process";
    diagnostics[@"entitlement_probe_scope"] = @"vpnagent_process";
    diagnostics[@"profile_state"] = [status[@"configured"] boolValue]
        ? @"configured"
        : @"not_configured";
    diagnostics[@"control_preflight"] = !entitlementReady
        ? @"blocked_missing_entitlement_or_framework"
        : (managerAvailable ? @"background_manager_ready" : @"manager_api_failed");
    diagnostics[@"diagnostics_source"] = @"background_vpnagent";
    diagnostics[@"agent_version"] = @2;
    diagnostics[@"process_uid"] = @((int)getuid());
    diagnostics[@"process_euid"] = @((int)geteuid());
    diagnostics[@"process_gid"] = @((int)getgid());
    diagnostics[@"process_egid"] = @((int)getegid());
    diagnostics[@"on_demand_policy"] =
        @"local_ui_connect_all_networks_explicit_disconnect_disables";
    diagnostics[@"manager_status"] = @{
        @"available": @(managerAvailable),
        @"configured": @([status[@"configured"] boolValue]),
        @"enabled": @([status[@"enabled"] boolValue]),
        @"on_demand_enabled": @([status[@"on_demand_enabled"] boolValue]),
        @"on_demand_rule_count": status[@"on_demand_rule_count"] ?: @0,
        @"on_demand_mode": status[@"on_demand_mode"] ?: @"disabled",
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
    return [NSString stringWithFormat:@"0;;%@\r\n",
        [json base64EncodedStringWithOptions:0] ?: @""];
}

static NSString *TLinkVPNAgentResponse(NSString *command)
{
    NSString *clean = [command stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([clean isEqualToString:@"ping"]) {
        return [NSString stringWithFormat:
            @"0;;vpnagent_ready version=2 phase=5 uid=%d euid=%d gid=%d egid=%d\r\n",
            getuid(), geteuid(), getgid(), getegid()];
    }
    if ([clean isEqualToString:@"diagnostics"]) {
        return TLinkVPNAgentDiagnosticsResponse();
    }

    NSString *licenseError = nil;
    if (!TLinkLicenseFeatureAllowed(@"automation", &licenseError)) {
        return [NSString stringWithFormat:@"-1;;vpn_license_denied %@\r\n",
            licenseError ?: @"automation_not_allowed"];
    }
    if (!TLinkVPNAgentEntitlementReady(TLinkVPNAgentPreflight())) {
        return @"-1;;vpnagent_entitlement_unavailable\r\n";
    }

    if ([clean isEqualToString:@"query"]) {
        NSDictionary *status = TLinkVPNAgentWait(
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
        NSDictionary *result = TLinkVPNAgentWait(
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
    return @"-1;;vpnagent_unknown_command\r\n";
}

static void TLinkVPNAgentHandleClient(int client)
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
    while (requestData.length < kTLinkVPNAgentMaxRequest) {
        NSUInteger capacity = MIN(sizeof(buffer),
            kTLinkVPNAgentMaxRequest - requestData.length);
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
        ? TLinkVPNAgentResponse(request)
        : @"-1;;vpnagent_empty_request\r\n";
    NSData *responseData =
        [response dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const uint8_t *cursor = (const uint8_t *)responseData.bytes;
    NSUInteger remaining = responseData.length;
    while (remaining > 0) {
        ssize_t sent = send(client, cursor, remaining, 0);
        if (sent <= 0) break;
        cursor += sent;
        remaining -= (NSUInteger)sent;
    }
    close(client);
}

static void TLinkVPNAgentRunServer(void)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) return;
    int yes = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(kTLinkVPNAgentPort);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(server);
        return;
    }
    if (listen(server, 4) != 0) {
        close(server);
        return;
    }
    while (1) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
        dispatch_async(
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    TLinkVPNAgentHandleClient(client);
                }
            });
    }
    close(server);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        if (argc > 1 && strcmp(argv[1], "--version") == 0) {
            printf("vpnagent version=2 phase=5 port=6016 persona=mobile\n");
            return 0;
        }
        if (argc <= 1 || strcmp(argv[1], "--daemon") != 0) {
            fprintf(stderr, "usage: vpnagent --daemon|--version\n");
            return 64;
        }

        // TSRootBinaries or an older package can cause the executable to
        // enter as root even when privhelper requested the mobile persona.
        // Drop supplementary groups first and fail closed unless both the
        // real and effective identities are mobile before touching NEVPNManager.
        if (geteuid() == 0) {
            if (setgroups(0, NULL) != 0 ||
                setgid(501) != 0 ||
                setuid(501) != 0) {
                fprintf(stderr,
                    "vpnagent privilege drop failed errno=%d uid=%d euid=%d\n",
                    errno, getuid(), geteuid());
                return 65;
            }
        }
        if (getuid() != 501 || geteuid() != 501 ||
            getgid() != 501 || getegid() != 501) {
            fprintf(stderr,
                "vpnagent refuses non-mobile identity uid=%d euid=%d gid=%d egid=%d\n",
                getuid(), geteuid(), getgid(), getegid());
            return 66;
        }

        dispatch_async(
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool {
                TLinkVPNAgentRunServer();
            }
        });
        CFRunLoopTimerRef keepAlive = CFRunLoopTimerCreate(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 3600.0,
            3600.0,
            0,
            0,
            TLinkVPNAgentKeepAliveTimer,
            NULL);
        if (keepAlive) {
            CFRunLoopAddTimer(
                CFRunLoopGetCurrent(), keepAlive, kCFRunLoopCommonModes);
            CFRelease(keepAlive);
        }
        CFRunLoopRun();
    }
    return 0;
}
