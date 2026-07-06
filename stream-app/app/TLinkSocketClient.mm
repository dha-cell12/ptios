#import "TLinkSocketClient.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

@implementation TLinkSocketClient

+ (int)connectSocketWithTimeout:(NSTimeInterval)timeout error:(NSString **)error
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        if (error) *error = [NSString stringWithFormat:@"socket() failed errno=%d", errno];
        return -1;
    }

    struct timeval tv;
    tv.tv_sec = (int)timeout;
    tv.tv_usec = (int)((timeout - tv.tv_sec) * 1000000.0);
    if (tv.tv_sec <= 0 && tv.tv_usec <= 0) {
        tv.tv_sec = 5;
        tv.tv_usec = 0;
    }
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        if (error) *error = [NSString stringWithFormat:@"connect 127.0.0.1:6000 failed errno=%d", errno];
        close(sock);
        return -1;
    }
    return sock;
}

+ (NSString *)sendLineAndRead:(NSString *)line timeout:(NSTimeInterval)timeout
{
    NSString *err = nil;
    int sock = [self connectSocketWithTimeout:timeout error:&err];
    if (sock < 0) return err ?: @"connect failed";

    NSString *payload = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    const char *bytes = [payload UTF8String];
    send(sock, bytes, strlen(bytes), 0);

    NSMutableData *data = [NSMutableData data];
    char buf[2048];
    while (true) {
        ssize_t n = recv(sock, buf, sizeof(buf), 0);
        if (n <= 0) break;
        [data appendBytes:buf length:(NSUInteger)n];
        if (memchr(buf, '\n', (size_t)n)) break;
        if (data.length > 1024 * 1024) break;
    }
    close(sock);

    if (data.length == 0) return [NSString stringWithFormat:@"no response / timeout errno=%d", errno];
    NSString *response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return response ?: @"non-utf8 response";
}

+ (void)sendLineFireAndForget:(NSString *)line
{
    NSString *err = nil;
    int sock = [self connectSocketWithTimeout:2.0 error:&err];
    if (sock < 0) return;

    NSString *payload = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    const char *bytes = [payload UTF8String];
    send(sock, bytes, strlen(bytes), 0);
    close(sock);
}

+ (NSString *)requestTask:(NSInteger)task args:(NSArray<NSString *> *)args timeout:(NSTimeInterval)timeout
{
    NSMutableString *line = [NSMutableString stringWithFormat:@"%ld", (long)task];
    if (args.count > 0) {
        [line appendString:[args componentsJoinedByString:@";;"]];
    }
    [line appendString:@"\n"];
    return [self sendLineAndRead:line timeout:timeout];
}

@end
