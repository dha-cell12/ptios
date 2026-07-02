#import <Foundation/Foundation.h>
#import "TLinkJSHelperServer.h"
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

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

static NSDictionary *TLinkJSDManifestAtPath(NSString *path)
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @{};
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

static NSDictionary *TLinkJSDClientRunScript(NSString *scriptPath, NSString *bundlePath, NSDictionary *manifest, double timeoutSeconds)
{
    NSDictionary *start = TLinkJSDClientRequest(kTLinkJSHelperCmdStart, @{ @"scriptPath": scriptPath ?: @"", @"bundlePath": bundlePath ?: @"", @"manifest": manifest ?: @{} }, nil);
    if (![start[@"ok"] boolValue]) return start;
    NSDictionary *response = [start[@"response"] isKindOfClass:[NSDictionary class]] ? start[@"response"] : @{};
    NSString *sessionId = [response[kTLinkJSHelperKeySessionId] isKindOfClass:[NSString class]] ? response[kTLinkJSHelperKeySessionId] : nil;
    NSDictionary *lastPayload = [response[kTLinkJSHelperKeyPayload] isKindOfClass:[NSDictionary class]] ? response[kTLinkJSHelperKeyPayload] : @{};
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds > 0 ? timeoutSeconds : 30.0];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        NSString *state = [lastPayload[@"state"] isKindOfClass:[NSString class]] ? lastPayload[@"state"] : @"";
        if ([state isEqualToString:kTLinkJSHelperStateCompleted] || [state isEqualToString:kTLinkJSHelperStateFailed] || [state isEqualToString:kTLinkJSHelperStateCancelled] || [state isEqualToString:kTLinkJSHelperStateCrashed]) {
            return lastPayload;
        }
        [NSThread sleepForTimeInterval:0.2];
        NSDictionary *status = TLinkJSDClientRequest(kTLinkJSHelperCmdStatus, @{}, sessionId);
        if (![status[@"ok"] boolValue]) return status;
        NSDictionary *statusResponse = [status[@"response"] isKindOfClass:[NSDictionary class]] ? status[@"response"] : @{};
        lastPayload = [statusResponse[kTLinkJSHelperKeyPayload] isKindOfClass:[NSDictionary class]] ? statusResponse[kTLinkJSHelperKeyPayload] : @{};
    }
    return @{ @"state": @"timeout", @"sessionId": sessionId ?: @"" };
}

static BOOL TLinkJSDStringContains(NSString *haystack, NSString *needle)
{
    return [haystack isKindOfClass:[NSString class]] && [needle isKindOfClass:[NSString class]] && [haystack rangeOfString:needle].location != NSNotFound;
}

static NSDictionary *TLinkJSDRegressionTest(NSString *name, NSString *bundleName, NSString *expectedState, NSString *marker, NSUInteger minBlocked, NSString *root)
{
    NSString *bundlePath = [root stringByAppendingPathComponent:bundleName];
    NSString *scriptPath = [bundlePath stringByAppendingPathComponent:@"main.js"];
    NSString *manifestPath = [bundlePath stringByAppendingPathComponent:@"manifest.json"];
    NSDate *startedAt = [NSDate date];
    NSDictionary *payload = TLinkJSDClientRunScript(scriptPath, bundlePath, TLinkJSDManifestAtPath(manifestPath), 35.0);
    NSString *state = [payload[@"state"] isKindOfClass:[NSString class]] ? payload[@"state"] : @"";
    NSString *logPath = [payload[@"consoleLatestLogPath"] isKindOfClass:[NSString class]] ? payload[@"consoleLatestLogPath"] : @"";
    if (![logPath length] && [payload[@"consoleLogPath"] isKindOfClass:[NSString class]]) logPath = payload[@"consoleLogPath"];
    NSString *logText = [logPath length] ? ([NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil] ?: @"") : @"";
    BOOL expectedOK = [state isEqualToString:expectedState];
    if ([name isEqualToString:@"timeout"] && ([state isEqualToString:@"failed"] || [state isEqualToString:@"cancelled"] || [state isEqualToString:@"timeout"])) expectedOK = YES;
    BOOL markerOK = ![marker length] || (TLinkJSDStringContains(logText, @"[HELPER_TEST_PASS]") && TLinkJSDStringContains(logText, marker));
    BOOL noFailMarker = !TLinkJSDStringContains(logText, @"[HELPER_TEST_FAIL]");
    NSUInteger blocked = [payload[@"blockedRpcCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"blockedRpcCount"] unsignedIntegerValue] : 0;
    BOOL blockedOK = blocked >= minBlocked;
    BOOL noPendingRPC = ![payload[@"pendingNativeRPC"] boolValue];
    NSDictionary *checks = @{
        @"state": @(expectedOK),
        @"marker": @(markerOK),
        @"noFailMarker": @(noFailMarker),
        @"blockedRpcCount": @(blockedOK),
        @"noPendingNativeRPC": @(noPendingRPC),
    };
    BOOL ok = expectedOK && markerOK && noFailMarker && blockedOK && noPendingRPC;
    return @{
        @"ok": @(ok),
        @"test": name ?: @"",
        @"state": state ?: @"",
        @"exitReason": payload[@"exitReason"] ?: @"",
        @"durationMs": payload[@"durationMs"] ?: @((long long)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000.0)),
        @"rpcCount": payload[@"rpcCount"] ?: @0,
        @"blockedRpcCount": payload[@"blockedRpcCount"] ?: @0,
        @"rpcAvgMs": payload[@"rpcAvgMs"] ?: @0,
        @"rpcMaxMs": payload[@"rpcMaxMs"] ?: @0,
        @"evalDurationMs": payload[@"evalDurationMs"] ?: @0,
        @"checks": checks,
        @"logPath": logPath ?: @"",
        @"lastError": payload[@"lastError"] ?: @"",
    };
}

static NSArray *TLinkJSDRegressionNamesForSuite(NSString *suite)
{
    if (![suite length] || [suite isEqualToString:@"safe"]) return @[@"storage", @"frame", @"ocr", @"full"];
    if ([suite isEqualToString:@"phase7"]) return @[@"storage", @"frame", @"ocr", @"full", @"default-compat", @"admin-blocked", @"exception", @"timeout"];
    if ([suite isEqualToString:@"all"]) return @[@"storage", @"frame", @"ocr", @"full", @"default-compat", @"admin-blocked", @"exception", @"timeout"];
    return [suite componentsSeparatedByString:@","];
}

static NSDictionary *TLinkJSDRunRegression(NSString *suite, NSUInteger repeat, NSString *root)
{
    NSDictionary *defs = @{
        @"storage": @{ @"bundle": @"Helper Storage Demo.bdl", @"state": @"completed", @"marker": @"Helper Storage Demo", @"blocked": @0 },
        @"frame": @{ @"bundle": @"Helper Frame Color Demo.bdl", @"state": @"completed", @"marker": @"Helper Frame Color Demo", @"blocked": @0 },
        @"ocr": @{ @"bundle": @"Helper OCR Demo.bdl", @"state": @"completed", @"marker": @"Helper OCR Demo", @"blocked": @0 },
        @"full": @{ @"bundle": @"Helper Full Safe Smoke Demo.bdl", @"state": @"completed", @"marker": @"Helper Full Safe Smoke Demo", @"blocked": @0 },
        @"default-compat": @{ @"bundle": @"Helper Default Experiment Demo.bdl", @"state": @"completed", @"marker": @"Helper Default Experiment Demo", @"blocked": @0 },
        @"admin-blocked": @{ @"bundle": @"Helper Admin Blocked Demo.bdl", @"state": @"completed", @"marker": @"Helper Admin Blocked Demo", @"blocked": @1 },
        @"exception": @{ @"bundle": @"Helper JS Exception Demo.bdl", @"state": @"failed", @"marker": @"", @"blocked": @0 },
        @"timeout": @{ @"bundle": @"Helper Timeout Demo.bdl", @"state": @"failed", @"marker": @"", @"blocked": @0 },
    };
    NSArray *names = TLinkJSDRegressionNamesForSuite([suite lowercaseString]);
    NSMutableArray *results = [NSMutableArray array];
    BOOL allOK = YES;
    NSUInteger count = repeat > 0 ? repeat : 1;
    NSString *examplesRoot = [root length] ? root : @"/var/mobile/Library/TLinkauto/scripts/examples";
    for (NSUInteger i = 0; i < count; i++) {
        for (NSString *rawName in names) {
            NSString *name = [[rawName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
            NSDictionary *def = defs[name];
            NSDictionary *result = nil;
            if (!def) {
                result = @{ @"ok": @NO, @"test": name ?: @"", @"iteration": @(i + 1), @"error": @"unknown_test" };
            } else {
                result = TLinkJSDRegressionTest(name, def[@"bundle"], def[@"state"], def[@"marker"], [def[@"blocked"] unsignedIntegerValue], examplesRoot);
                NSMutableDictionary *mutableResult = [result mutableCopy];
                mutableResult[@"iteration"] = @(i + 1);
                result = mutableResult;
            }
            if (![result[@"ok"] boolValue]) allOK = NO;
            [results addObject:result];
        }
    }
    return @{ @"ok": @(allOK), @"suite": suite ?: @"safe", @"repeat": @(count), @"results": results };
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
            NSDictionary *status = TLinkJSDClientRunScript(scriptPath, bundlePath, manifest, 30.0);
            TLinkJSDPrintJSON(status);
            NSString *state = [status[@"state"] isKindOfClass:[NSString class]] ? status[@"state"] : @"";
            return [state isEqualToString:kTLinkJSHelperStateCompleted] ? 0 : 2;
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
        if (argc >= 3 && strcmp(argv[1], "--client-run-regression") == 0) {
            NSString *suite = [NSString stringWithUTF8String:argv[2]];
            NSUInteger repeat = 1;
            NSString *root = @"/var/mobile/Library/TLinkauto/scripts/examples";
            for (int i = 3; i < argc; i++) {
                if (strcmp(argv[i], "--repeat") == 0 && i + 1 < argc) {
                    repeat = (NSUInteger)MAX(1, atoi(argv[++i]));
                } else if (strcmp(argv[i], "--examples-root") == 0 && i + 1 < argc) {
                    root = [NSString stringWithUTF8String:argv[++i]];
                }
            }
            NSDictionary *report = TLinkJSDRunRegression(suite, repeat, root);
            TLinkJSDPrintJSON(report);
            return [report[@"ok"] boolValue] ? 0 : 2;
        }
        [server run];
    }
    return 0;
}
