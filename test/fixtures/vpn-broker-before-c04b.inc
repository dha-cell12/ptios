#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#import "../shared/TLinkVPNDiagnostics.h"
#import "../shared/TLinkVPNManager.h"
#import "../shared/TLinkLicenseVerifier.h"
#import "../shared/TLinkRootfullLicenseBuild.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static const uint16_t kTLinkVPNBrokerPort = 6014;
static const NSUInteger kTLinkVPNBrokerMaxRequest = 1024;

static NSDictionary *TLinkVPNBrokerWait(
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
        return @{@"ok": @0, @"code": @"vpn_broker_operation_timeout"};
    }
    return result;
}

static NSString *TLinkVPNBrokerResponse(NSString *command)
{
    NSString *clean = [command
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![clean isEqualToString:@"diagnostics"]) {
        NSString *licenseError = nil;
        if (!TLinkLicenseFeatureAllowed(@"automation", &licenseError)) {
            return [NSString stringWithFormat:@"-1;;vpn_license_denied %@\r\n",
                licenseError ?: @"automation_not_allowed"];
        }
    }
    if ([clean isEqualToString:@"query"]) {
        NSDictionary *status = TLinkVPNBrokerWait(
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
        NSDictionary *result = TLinkVPNBrokerWait(
            ^(TLinkVPNResultCompletion completion) {
                TLinkVPNSetConnected(
                    requestedConnected,
                    20.0,
                    completion);
            },
            24.0);
        if (![result[@"ok"] boolValue]) {
            return [NSString stringWithFormat:@"-1;;%@\r\n",
                result[@"code"] ?: @"vpn_transition_failed"];
        }
        return [NSString stringWithFormat:@"0;;%@\r\n",
            requestedConnected ? @"1" : @"0"];
    }

    if ([clean isEqualToString:@"diagnostics"]) {
        NSDictionary *status = TLinkVPNBrokerWait(
            ^(TLinkVPNResultCompletion completion) {
                TLinkVPNReadManagerStatus(completion);
            },
            8.0);
        NSNumber *effectiveConnected = [status[@"ok"] boolValue]
            ? @([status[@"connected"] boolValue])
            : nil;
        NSMutableDictionary *diagnostics = [
            TLinkVPNDiagnosticsSnapshot(
                @"rootfull",
                @"full_control",
                @"app_broker_6014",
                @"app_broker_6014",
                @"nevpnmanager_ikev2",
                @"tlinkauto_vpnd_6014",
                effectiveConnected)
            mutableCopy];
        diagnostics[@"phase"] = @4;
        diagnostics[@"broker_ready"] = @1;
        diagnostics[@"broker_target"] = @"tlinkauto_vpnd";
        diagnostics[@"diagnostics_source"] = @"rootfull_broker";
        diagnostics[@"entitlement_probe_scope"] = @"broker_process";
        diagnostics[@"on_demand_policy"] =
            @"local_ui_connect_all_networks_explicit_disconnect_disables";
        diagnostics[@"profile_state"] = [status[@"configured"] boolValue]
            ? @"configured"
            : @"not_configured";
        diagnostics[@"manager_status"] = @{
            @"available": @([status[@"ok"] boolValue]),
            @"configured": @([status[@"configured"] boolValue]),
            @"enabled": @([status[@"enabled"] boolValue]),
            @"on_demand_enabled":
                @([status[@"on_demand_enabled"] boolValue]),
            @"on_demand_rule_count":
                status[@"on_demand_rule_count"] ?: @0,
            @"on_demand_mode": status[@"on_demand_mode"] ?: @"disabled",
            @"connection_status":
                [status[@"connection_status"] isKindOfClass:[NSString class]]
                    ? status[@"connection_status"]
                    : @"unknown",
            @"last_error": [status[@"ok"] boolValue]
                ? @""
                : (status[@"code"] ?: @"vpn_status_failed"),
        };
        NSError *jsonError = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:diagnostics
                                                       options:0
                                                         error:&jsonError];
        if (!json || jsonError) {
            return @"-1;;vpn_diagnostics_encode_failed\r\n";
        }
        NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @"";
        return [NSString stringWithFormat:@"0;;%@\r\n", base64];
    }

    return @"-1;;vpn_broker_unknown_command\r\n";
}

static void TLinkVPNBrokerHandleClient(int client)
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
    while (requestData.length < kTLinkVPNBrokerMaxRequest) {
        NSUInteger capacity = MIN(
            sizeof(buffer),
            kTLinkVPNBrokerMaxRequest - requestData.length);
        ssize_t received = recv(client, buffer, capacity, 0);
        if (received <= 0) break;
        [requestData appendBytes:buffer length:(NSUInteger)received];
        if (memchr(buffer, '\n', (size_t)received)) break;
    }
    if (requestData.length == 0) {
        close(client);
        return;
    }
    NSString *command =
        [[NSString alloc] initWithData:requestData
                              encoding:NSUTF8StringEncoding] ?: @"";
    NSString *response = TLinkVPNBrokerResponse(command);
    NSData *responseData =
        [response dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const uint8_t *bytes = (const uint8_t *)responseData.bytes;
    NSUInteger remaining = responseData.length;
    while (remaining > 0) {
        ssize_t sent = send(client, bytes, remaining, 0);
        if (sent <= 0) break;
        bytes += sent;
        remaining -= (NSUInteger)sent;
    }
    close(client);
}

static void TLinkVPNBrokerRunServer(void)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) {
        NSLog(@"[TLinkVPNBroker] socket failed errno=%d", errno);
        return;
    }
    int reuse = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(kTLinkVPNBrokerPort);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        listen(server, 8) != 0) {
        NSLog(@"[TLinkVPNBroker] bind/listen failed errno=%d", errno);
        close(server);
        return;
    }
    NSLog(@"[TLinkVPNBroker] listening on 127.0.0.1:%u",
          (unsigned)kTLinkVPNBrokerPort);

    while (true) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
        dispatch_async(
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    TLinkVPNBrokerHandleClient(client);
                }
            });
    }
    close(server);
}

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        NSLog(@"[TLinkVPNBroker] licenseBuildMode=%s verifierBuildMode=%@",
              TLinkRootfullLicenseBuildMode(),
              TLinkLicenseBuildMode());
        dispatch_async(
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    TLinkVPNBrokerRunServer();
                }
            });
        CFRunLoopRun();
    }
    return 0;
}
