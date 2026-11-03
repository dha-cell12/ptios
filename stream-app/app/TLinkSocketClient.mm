#import "TLinkSocketClient.h"
#include "../../shared/TLinkAppTaskIO.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

// BEGIN bounded app task request.
static NSString *TLinkAppTaskRequest(NSString *line, NSTimeInterval timeout, BOOL readReply)
{
    if (!TLinkAppTaskIO::timeoutMs(timeout)) return @"invalid timeout";
    const auto baseIO = TLinkHelperIO::posixOps();
    const auto budget = TLinkAppTaskIO::window(baseIO.now(baseIO.context), timeout);
    if (!budget.remaining(baseIO.now(baseIO.context))) return [NSString stringWithFormat:@"no response / timeout errno=%d", ETIMEDOUT];
    TLinkVPNBrokerClientIO::BoundedOps bounded(baseIO, budget);
    const auto io = bounded.ops();
    TLinkHelperIO::Socket descriptor(socket(AF_INET, SOCK_STREAM, 0));
    if (descriptor.fd() < 0) return [NSString stringWithFormat:@"socket() failed errno=%d", errno];
    const auto prepared = descriptor.prepare();
    if (!prepared.ok()) return [NSString stringWithFormat:@"socket() failed errno=%d", prepared.error];
    NSString *payload = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    const char *bytes = [payload UTF8String];
    if (!bytes) return @"invalid command";
    auto connectOps = TLinkVPNBrokerClientIO::posixConnectOps();
    connectOps.begin = [](void *, int fd, int &error) {
        sockaddr_in address{}; address.sin_family = AF_INET; address.sin_port = htons(6000);
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
        const int result = ::connect(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address));
        if (result < 0) error = errno;
        return result;
    };
    auto reply = TLinkAppTaskIO::request(io, connectOps, descriptor.fd(),
        reinterpret_cast<const uint8_t *>(bytes), strlen(bytes), readReply, budget);
    descriptor.close();
    using Stage = TLinkAppTaskIO::Stage;
    const int error = TLinkAppTaskIO::nativeError(reply.result);
    if (reply.stage == Stage::Connect) return [NSString stringWithFormat:@"connect 127.0.0.1:6000 failed errno=%d", error];
    if (reply.stage == Stage::Send) return [NSString stringWithFormat:@"send failed errno=%d", error];
    if (reply.stage == Stage::Read) return [NSString stringWithFormat:@"no response / timeout errno=%d", error];
    if (!budget.remaining(io.now(io.context))) return [NSString stringWithFormat:@"no response / timeout errno=%d", ETIMEDOUT];
    if (!readReply) return @"";
    NSString *response = [[NSString alloc] initWithBytes:reply.bytes.data() length:reply.bytes.size() encoding:NSUTF8StringEncoding];
    if (!budget.remaining(io.now(io.context))) return [NSString stringWithFormat:@"no response / timeout errno=%d", ETIMEDOUT];
    return response ?: @"non-utf8 response";
}
// END bounded app task request.

@implementation TLinkSocketClient

+ (NSString *)sendLineAndRead:(NSString *)line timeout:(NSTimeInterval)timeout
{
    return TLinkAppTaskRequest(line, timeout, YES);
}

+ (void)sendLineFireAndForget:(NSString *)line
{
    (void)TLinkAppTaskRequest(line, 2.0, NO);
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
