#import <Foundation/Foundation.h>
#import "TLinkJSHelperServer.h"
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <errno.h>

static NSString * const kTLinkJSHelperSocketPath = @"/var/mobile/Library/TLinkauto/run/js-helper.sock";

static NSDictionary *TLinkJSDClientRequest(NSString *command, NSDictionary *payload, NSString *sessionId)
{
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) return @{ @"ok": @NO, @"error": @"socket_failed" };

    struct timeval tv;
    tv.tv_sec = 2;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [kTLinkJSHelperSocketPath fileSystemRepresentation], sizeof(addr.sun_path) - 1);
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        int e = errno;
        close(sock);
        return @{ @"ok": @NO, @"error": @"connect_failed", @"errno": @(e) };
    }

    NSDictionary *env = [TLinkJSHelperProtocol envelopeWithCommand:command helperInstanceId:nil sessionId:sessionId requestId:[[NSUUID UUID] UUIDString] payload:payload ?: @{}];
    NSMutableData *data = [[TLinkJSHelperProtocol serializeEnvelope:env error:nil] mutableCopy];
    if (!data) {
        close(sock);
        return @{ @"ok": @NO, @"error": @"serialize_failed" };
    }
    const uint8_t newline = '\n';
    [data appendBytes:&newline length:1];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(sock, bytes, remaining);
        if (written <= 0) {
            int e = errno;
            close(sock);
            return @{ @"ok": @NO, @"error": @"write_failed", @"errno": @(e) };
        }
        bytes += written;
        remaining -= (NSUInteger)written;
    }

    NSMutableData *responseData = [NSMutableData data];
    uint8_t buffer[4096];
    while (true) {
        ssize_t n = read(sock, buffer, sizeof(buffer));
        if (n > 0) {
            [responseData appendBytes:buffer length:(NSUInteger)n];
            if (memchr(responseData.bytes, '\n', responseData.length)) break;
            if (responseData.length > 1024 * 1024) break;
            continue;
        }
        break;
    }
    close(sock);
    NSError *err = nil;
    NSDictionary *response = [TLinkJSHelperProtocol deserializeEnvelope:responseData error:&err];
    if (!response) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"invalid_response" };
    if (response[kTLinkJSHelperKeyError]) return @{ @"ok": @NO, @"response": response, @"error": response[kTLinkJSHelperKeyError] };
    return @{ @"ok": @YES, @"response": response };
}

static void TLinkJSDPrintJSON(NSDictionary *obj)
{
    NSData *json = [NSJSONSerialization dataWithJSONObject:obj ?: @{} options:0 error:nil];
    if (json) {
        fwrite(json.bytes, 1, json.length, stdout);
        fwrite("\n", 1, 1, stdout);
    }
}

int main(int argc, char *argv[], char *envp[]) {
    @autoreleasepool {
        TLinkJSHelperServer *server = [[TLinkJSHelperServer alloc] init];
        if (argc >= 4 && strcmp(argv[1], "--run-script") == 0) {
            NSString *scriptPath = [NSString stringWithUTF8String:argv[2]];
            NSString *bundlePath = [NSString stringWithUTF8String:argv[3]];
            NSDictionary *manifest = @{};
            if (argc >= 5) {
                NSString *manifestPath = [NSString stringWithUTF8String:argv[4]];
                NSData *data = [NSData dataWithContentsOfFile:manifestPath];
                if (data) {
                    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([obj isKindOfClass:[NSDictionary class]]) manifest = obj;
                }
            }
            NSDictionary *status = [server runScriptDirectAtPath:scriptPath bundlePath:bundlePath manifest:manifest];
            TLinkJSDPrintJSON(status);
            NSString *state = [status[@"state"] isKindOfClass:[NSString class]] ? status[@"state"] : @"";
            return [state isEqualToString:@"completed"] ? 0 : 2;
        }
        if (argc >= 4 && strcmp(argv[1], "--client-run") == 0) {
            NSString *scriptPath = [NSString stringWithUTF8String:argv[2]];
            NSString *bundlePath = [NSString stringWithUTF8String:argv[3]];
            NSDictionary *manifest = @{};
            if (argc >= 5) {
                NSString *manifestPath = [NSString stringWithUTF8String:argv[4]];
                NSData *data = [NSData dataWithContentsOfFile:manifestPath];
                if (data) {
                    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([obj isKindOfClass:[NSDictionary class]]) manifest = obj;
                }
            }
            NSDictionary *start = TLinkJSDClientRequest(kTLinkJSHelperCmdStart, @{ @"scriptPath": scriptPath ?: @"", @"bundlePath": bundlePath ?: @"", @"manifest": manifest ?: @{} }, nil);
            if (![start[@"ok"] boolValue]) {
                TLinkJSDPrintJSON(start);
                return 2;
            }
            NSDictionary *response = start[@"response"];
            NSString *sessionId = [response[kTLinkJSHelperKeySessionId] isKindOfClass:[NSString class]] ? response[kTLinkJSHelperKeySessionId] : nil;
            NSDictionary *lastPayload = [response[kTLinkJSHelperKeyPayload] isKindOfClass:[NSDictionary class]] ? response[kTLinkJSHelperKeyPayload] : @{};
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
            while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
                NSString *state = [lastPayload[@"state"] isKindOfClass:[NSString class]] ? lastPayload[@"state"] : @"";
                if ([state isEqualToString:kTLinkJSHelperStateCompleted] || [state isEqualToString:kTLinkJSHelperStateFailed] || [state isEqualToString:kTLinkJSHelperStateCancelled] || [state isEqualToString:kTLinkJSHelperStateCrashed]) {
                    TLinkJSDPrintJSON(lastPayload);
                    return [state isEqualToString:kTLinkJSHelperStateCompleted] ? 0 : 2;
                }
                [NSThread sleepForTimeInterval:0.2];
                NSDictionary *status = TLinkJSDClientRequest(kTLinkJSHelperCmdStatus, @{}, sessionId);
                if (![status[@"ok"] boolValue]) {
                    TLinkJSDPrintJSON(status);
                    return 2;
                }
                NSDictionary *statusResponse = status[@"response"];
                lastPayload = [statusResponse[kTLinkJSHelperKeyPayload] isKindOfClass:[NSDictionary class]] ? statusResponse[kTLinkJSHelperKeyPayload] : @{};
            }
            TLinkJSDPrintJSON(@{ @"state": @"timeout", @"sessionId": sessionId ?: @"" });
            return 2;
        }
        if (argc >= 2 && strcmp(argv[1], "--client-handshake") == 0) {
            NSDictionary *result = TLinkJSDClientRequest(kTLinkJSHelperCmdHandshake, @{}, nil);
            TLinkJSDPrintJSON(result);
            return [result[@"ok"] boolValue] ? 0 : 2;
        }
        if (argc >= 2 && strcmp(argv[1], "--client-status") == 0) {
            NSDictionary *result = TLinkJSDClientRequest(kTLinkJSHelperCmdStatus, @{}, nil);
            TLinkJSDPrintJSON(result);
            return [result[@"ok"] boolValue] ? 0 : 2;
        }
        if (argc >= 3 && strcmp(argv[1], "--client-stop") == 0) {
            NSString *sessionId = [NSString stringWithUTF8String:argv[2]];
            NSDictionary *result = TLinkJSDClientRequest(kTLinkJSHelperCmdStop, @{}, sessionId);
            TLinkJSDPrintJSON(result);
            return [result[@"ok"] boolValue] ? 0 : 2;
        }
        [server run];
    }
    return 0;
}
