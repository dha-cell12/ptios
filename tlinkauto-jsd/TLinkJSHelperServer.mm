#import "TLinkJSHelperServer.h"
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static NSString * const kTLinkJSHelperSocketPath = @"/var/mobile/Library/TLinkauto/run/js-helper.sock";
static NSString * const kTLinkJSHelperVersion = @"1.0.0";

@interface TLinkJSHelperServer ()
@property(nonatomic, copy) NSString *helperInstanceId;
@property(nonatomic, strong) NSDate *startedAt;
@end

@implementation TLinkJSHelperServer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _helperInstanceId = [[NSUUID UUID] UUIDString];
        _startedAt = [NSDate date];
    }
    return self;
}

- (NSDictionary *)errorEnvelopeForRequest:(NSDictionary *)request message:(NSString *)message
{
    NSMutableDictionary *env = [[TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdError
                                                           helperInstanceId:self.helperInstanceId
                                                                  sessionId:request[kTLinkJSHelperKeySessionId]
                                                                  requestId:request[kTLinkJSHelperKeyRequestId]
                                                                    payload:@{}] mutableCopy];
    env[kTLinkJSHelperKeyError] = @{ @"message": message ?: @"unknown_error" };
    return env;
}

- (NSDictionary *)handleEnvelope:(NSDictionary *)request
{
    NSError *validationError = nil;
    if (![TLinkJSHelperProtocol validateEnvelope:request error:&validationError]) {
        return [self errorEnvelopeForRequest:request ?: @{} message:validationError.localizedDescription ?: @"invalid_envelope"];
    }

    NSString *command = request[kTLinkJSHelperKeyCommand];
    NSTimeInterval uptimeMs = [[NSDate date] timeIntervalSinceDate:self.startedAt] * 1000.0;
    if ([command isEqualToString:kTLinkJSHelperCmdHandshake]) {
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdHandshake
                                         helperInstanceId:self.helperInstanceId
                                                sessionId:request[kTLinkJSHelperKeySessionId]
                                                requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:@{
            @"helperVersion": kTLinkJSHelperVersion,
            @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
            @"state": kTLinkJSHelperStateIdle,
            @"uptimeMs": @((long long)uptimeMs),
            @"capabilities": @{
                @"javascriptcore": @NO,
                @"executionTimeLimit": @NO,
                @"hardKillRecovery": @NO,
                @"nativeRPC": @NO,
                @"structuredConsole": @NO,
                @"oneActiveSession": @YES,
            },
        }];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdStatus]) {
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStatus
                                         helperInstanceId:self.helperInstanceId
                                                sessionId:request[kTLinkJSHelperKeySessionId]
                                                requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:@{
            @"state": kTLinkJSHelperStateIdle,
            @"activeSessionId": [NSNull null],
            @"uptimeMs": @((long long)uptimeMs),
        }];
    }
    return [self errorEnvelopeForRequest:request message:@"unsupported_command"];
}

- (NSData *)readAllFromClient:(int)client
{
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];
    while (true) {
        ssize_t n = read(client, buffer, sizeof(buffer));
        if (n > 0) {
            [data appendBytes:buffer length:(NSUInteger)n];
            if (data.length > 1024 * 1024) break;
            if (memchr(buffer, '\n', (size_t)n)) break;
            continue;
        }
        break;
    }
    return data;
}

- (void)handleClient:(int)client
{
    @autoreleasepool {
        NSData *requestData = [self readAllFromClient:client];
        NSError *err = nil;
        NSDictionary *request = [TLinkJSHelperProtocol deserializeEnvelope:requestData error:&err];
        NSDictionary *response = request ? [self handleEnvelope:request] : [self errorEnvelopeForRequest:@{} message:err.localizedDescription ?: @"invalid_json"];
        NSMutableData *responseData = [[TLinkJSHelperProtocol serializeEnvelope:response error:nil] mutableCopy];
        if (responseData) {
            const uint8_t newline = '\n';
            [responseData appendBytes:&newline length:1];
            const uint8_t *bytes = (const uint8_t *)responseData.bytes;
            NSUInteger remaining = responseData.length;
            while (remaining > 0) {
                ssize_t written = write(client, bytes, remaining);
                if (written <= 0) break;
                bytes += written;
                remaining -= (NSUInteger)written;
            }
        }
        close(client);
    }
}

- (void)run
{
    NSString *runDir = [kTLinkJSHelperSocketPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:runDir withIntermediateDirectories:YES attributes:nil error:nil];
    unlink([kTLinkJSHelperSocketPath fileSystemRepresentation]);

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) {
        NSLog(@"tlinkauto-jsd: socket failed: %d", errno);
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [kTLinkJSHelperSocketPath fileSystemRepresentation], sizeof(addr.sun_path) - 1);
    if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        NSLog(@"tlinkauto-jsd: bind failed: %d", errno);
        close(server);
        return;
    }
    chmod([kTLinkJSHelperSocketPath fileSystemRepresentation], 0666);
    if (listen(server, 8) != 0) {
        NSLog(@"tlinkauto-jsd: listen failed: %d", errno);
        close(server);
        return;
    }

    NSLog(@"tlinkauto-jsd: ready instance=%@ socket=%@", self.helperInstanceId, kTLinkJSHelperSocketPath);
    while (true) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            NSLog(@"tlinkauto-jsd: accept failed: %d", errno);
            break;
        }
        [self handleClient:client];
    }
    close(server);
}

@end
