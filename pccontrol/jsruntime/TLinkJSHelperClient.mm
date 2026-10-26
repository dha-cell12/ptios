#import "TLinkJSHelperClient.h"
#import "TLinkJSHelperProtocol.h"
#include "../../shared/TLinkHelperRPCIdentity.h"
#include "../../shared/TLinkHelperSocketIO.h"
#include "../../shared/TLinkHelperRequestDeadline.h"
#include "../../shared/TLinkHelperChangeWait.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

static NSString * const kTLinkJSHelperSocketPath = @"/var/mobile/Library/TLinkauto/run/js-helper.sock";

@interface TLinkJSHelperClient ()
@property(nonatomic, copy) NSString *boundHelperInstanceId;
@property(nonatomic, copy) TLinkJSHelperCancellationCheck cancellationCheck;
@end

struct TLinkJSHelperCancellationContext {
    TLinkJSHelperCancellationCheck check;
    static bool cancelled(void *opaque){auto &self=*static_cast<TLinkJSHelperCancellationContext *>(opaque);return self.check&&self.check();}
};

@implementation TLinkJSHelperClient

- (NSDictionary *)requestCommand:(NSString *)command payload:(NSDictionary *)payload sessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs
{
    using namespace TLinkHelperIO;
    const uint64_t issuedAt = nowMs();
    const Deadline deadline(issuedAt, timeoutMs);
    if (!deadline.valid) return TLinkHelperIOFailure({Code::InvalidTimeout});
    TLinkJSHelperCancellationContext cancellation{[self.cancellationCheck copy]};
    if (cancellation.cancelled(&cancellation)) return @{@"ok":@(false),@"error":@"cancelled"};
    CancellableOps cancellable(posixOps(),&cancellation,TLinkJSHelperCancellationContext::cancelled);
    const Ops ops=cancellation.check?cancellable.ops():posixOps();
    NSString *requestId = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *envelope = [[TLinkJSHelperProtocol envelopeWithCommand:command helperInstanceId:self.boundHelperInstanceId sessionId:sessionId requestId:requestId payload:payload ?: @{}] mutableCopy];
    envelope[@"requestDeadline"] = TLinkHelperSenderDeadline(issuedAt, deadline);
    // This client keeps its write side open until reply/cancel. Old helpers ignore
    // this envelope extension; new helpers may release a wait as soon as we close.
    if ([command isEqualToString:kTLinkJSHelperCmdWaitForChange]) envelope[@"waitPeerEOFContract"]=@"cancel_v1";
    NSData *requestData = [TLinkJSHelperProtocol serializeEnvelope:envelope error:nil];
    if (!requestData) return @{ @"ok": @(false), @"error": @"serialize_failed" };
    if (requestData.length > MaxFrameBytes) return TLinkHelperIOFailure({Code::TooLarge});
    Socket socket(::socket(AF_UNIX, SOCK_STREAM, 0));
    if (socket.fd() < 0) return TLinkHelperIOFailure({Code::Setup, errno});
    Result io = socket.prepare();
    if (!io.ok()) return TLinkHelperIOFailure(io);
    std::vector<uint8_t> responseBytes;
    @try {
        io = connectUnix(socket, [kTLinkJSHelperSocketPath fileSystemRepresentation], deadline, ops);
        if (io.ok()) io = writeFrame(ops, socket.fd(), static_cast<const uint8_t *>(requestData.bytes), requestData.length, deadline);
        if (io.ok()) io = readFrame(ops, socket.fd(), responseBytes, deadline);
    } @finally { socket.close(); }
    if (cancellation.cancelled(&cancellation)) return @{@"ok":@(false),@"error":@"cancelled"};
    if (!io.ok()) return TLinkHelperIOFailure(io);
    NSData *responseData = [NSData dataWithBytes:responseBytes.data() length:responseBytes.size()];
    if (!deadline.remaining(nowMs())) return TLinkHelperIOFailure({Code::Timeout});

    NSError *err = nil;
    NSDictionary *response = [TLinkJSHelperProtocol deserializeEnvelope:responseData error:&err];
    if (!response) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"invalid_response" };
    if (!deadline.remaining(nowMs())) return TLinkHelperIOFailure({Code::Timeout});
    if (cancellation.cancelled(&cancellation)) return @{@"ok":@(false),@"error":@"cancelled"};
    NSString *identityError = TLinkHelperRPCReplyError(response, command, requestId, sessionId, self.boundHelperInstanceId);
    if (identityError) return @{ @"ok": @(false), @"error": identityError };
    if (response[kTLinkJSHelperKeyError]) return @{ @"ok": @NO, @"response": response, @"error": response[kTLinkJSHelperKeyError] };
    if ([command isEqualToString:kTLinkJSHelperCmdStart]) {
        identityError = TLinkHelperRPCStartError(response);
        if (identityError) return @{ @"ok": @(false), @"error": identityError };
        self.boundHelperInstanceId = response[kTLinkJSHelperKeyHelperInstanceId];
    }
    return @{ @"ok": @YES, @"response": response };
}

- (NSDictionary *)handshakeWithTimeoutMs:(int)timeoutMs
{
    return [self requestCommand:kTLinkJSHelperCmdHandshake payload:@{} sessionId:nil timeoutMs:timeoutMs];
}

- (NSDictionary *)statusWithTimeoutMs:(int)timeoutMs
{
    return [self requestCommand:kTLinkJSHelperCmdStatus payload:@{} sessionId:nil timeoutMs:timeoutMs];
}

- (NSDictionary *)startScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest timeoutMs:(int)timeoutMs
{
    return [self requestCommand:kTLinkJSHelperCmdStart
                        payload:@{ @"scriptPath": scriptPath ?: @"", @"bundlePath": bundlePath ?: @"", @"manifest": manifest ?: @{} }
                      sessionId:nil
                      timeoutMs:timeoutMs];
}

- (NSDictionary *)statusForSessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs
{
    return [self requestCommand:kTLinkJSHelperCmdStatus payload:@{} sessionId:sessionId timeoutMs:timeoutMs];
}

- (NSDictionary *)waitForChangeAfterSequence:(uint64_t)sequence sessionId:(NSString *)sessionId waitMs:(int)waitMs timeoutMs:(int)timeoutMs
{
    if (!self.boundHelperInstanceId) return @{@"ok":@(false),@"error":@"helper_not_bound"};
    if (sequence>TLinkHelperIO::MaxWireTime || waitMs<=0 || waitMs>TLinkHelperChangeWait::MaxWaitMs ||
        !TLinkHelperRPCIdentity::valid(TLinkHelperRPCIdentityBytes(sessionId)))
        return @{@"ok":@(false),@"error":@"invalid_wait_request"};
    return [self requestCommand:kTLinkJSHelperCmdWaitForChange payload:@{@"afterSequence":@(sequence),@"waitMs":@(waitMs)} sessionId:sessionId timeoutMs:timeoutMs];
}

- (NSDictionary *)stopSessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs
{
    return [self requestCommand:kTLinkJSHelperCmdStop payload:@{} sessionId:sessionId timeoutMs:timeoutMs];
}

- (NSDictionary *)sendNativeRPCResponse:(NSDictionary *)result requestId:(NSString *)requestId sessionId:(NSString *)sessionId timeoutMs:(int)timeoutMs
{
    return [self requestCommand:kTLinkJSHelperCmdNativeRPCResponse
                        payload:@{ kTLinkJSHelperKeyRequestId: requestId ?: @"", @"result": result ?: @{} }
                      sessionId:sessionId
                      timeoutMs:timeoutMs];
}

@end
