#import "TLinkJSHelperClient.h"
#import "TLinkJSHelperProtocol.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

static NSString * const kTLinkJSHelperSocketPath = @"/var/mobile/Library/TLinkauto/run/js-helper.sock";

@implementation TLinkJSHelperClient

- (NSDictionary *)requestCommand:(NSString *)command timeoutMs:(int)timeoutMs
{
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) return @{ @"ok": @NO, @"error": @"socket_failed" };

    struct timeval tv;
    tv.tv_sec = timeoutMs / 1000;
    tv.tv_usec = (timeoutMs % 1000) * 1000;
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

    NSString *requestId = [[NSUUID UUID] UUIDString];
    NSDictionary *envelope = [TLinkJSHelperProtocol envelopeWithCommand:command helperInstanceId:nil sessionId:nil requestId:requestId payload:@{}];
    NSMutableData *requestData = [[TLinkJSHelperProtocol serializeEnvelope:envelope error:nil] mutableCopy];
    if (!requestData) {
        close(sock);
        return @{ @"ok": @NO, @"error": @"serialize_failed" };
    }
    const uint8_t newline = '\n';
    [requestData appendBytes:&newline length:1];

    const uint8_t *bytes = (const uint8_t *)requestData.bytes;
    NSUInteger remaining = requestData.length;
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
            if (responseData.length > 1024 * 1024) break;
            const uint8_t *responseBytes = (const uint8_t *)responseData.bytes;
            if (memchr(responseBytes, '\n', responseData.length)) break;
            continue;
        }
        break;
    }
    close(sock);
    if (responseData.length == 0) return @{ @"ok": @NO, @"error": @"empty_response" };

    NSError *err = nil;
    NSDictionary *response = [TLinkJSHelperProtocol deserializeEnvelope:responseData error:&err];
    if (!response) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"invalid_response" };
    if (response[kTLinkJSHelperKeyError]) return @{ @"ok": @NO, @"response": response, @"error": response[kTLinkJSHelperKeyError] };
    return @{ @"ok": @YES, @"response": response };
}

- (NSDictionary *)handshakeWithTimeoutMs:(int)timeoutMs
{
    return [self requestCommand:kTLinkJSHelperCmdHandshake timeoutMs:timeoutMs];
}

- (NSDictionary *)statusWithTimeoutMs:(int)timeoutMs
{
    return [self requestCommand:kTLinkJSHelperCmdStatus timeoutMs:timeoutMs];
}

@end
