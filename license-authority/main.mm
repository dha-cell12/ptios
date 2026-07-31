#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#import "../shared/TLinkLicenseAuthorityClient.h"
#import "../shared/TLinkLicenseVerifier.h"
#import "../shared/TLinkRootfullLicenseBuild.h"

#include <errno.h>
#include <signal.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

static const NSUInteger kTLinkLicenseAuthorityMaxRequest = 4096;

static NSString *TLinkLicenseAuthorityResponse(NSString *line)
{
    NSData *requestData =
        [line dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    id requestObject = [NSJSONSerialization
        JSONObjectWithData:requestData
                   options:0
                     error:nil];
    NSDictionary *request =
        [requestObject isKindOfClass:[NSDictionary class]]
        ? requestObject : nil;
    if (!request) {
        return @"-1;;license_authority_request_invalid\r\n";
    }
    NSString *command = [request[@"command"] isKindOfClass:[NSString class]]
        ? request[@"command"] : @"";
    NSString *nonce = [request[@"nonce"] isKindOfClass:[NSString class]]
        ? request[@"nonce"] : @"";
    if ([request[@"version"] integerValue] !=
            TLINK_LICENSE_AUTHORITY_CONTRACT_VERSION ||
        ![command isEqualToString:@"status"] ||
        nonce.length < 32 ||
        nonce.length > 128) {
        return @"-1;;license_authority_request_invalid\r\n";
    }

    NSMutableDictionary *status =
        [TLinkLicenseStatusDictionary() mutableCopy];
    status[@"source"] = @"rootfull_license_authority_signed_v1";
    status[@"authority_contract_version"] =
        @(TLINK_LICENSE_AUTHORITY_CONTRACT_VERSION);
    status[@"authority_process"] = @"tlinkauto-licensed";
    status[@"authority_proof"] = @1;

    uint64_t issuedAt =
        (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
    NSDictionary *message = @{
        @"version": @(TLINK_LICENSE_AUTHORITY_CONTRACT_VERSION),
        @"nonce": nonce,
        @"issued_at_ms": @(issuedAt),
        @"expires_at_ms": @(issuedAt + 10000),
        @"status": status,
    };
    NSData *messageData = [NSJSONSerialization
        dataWithJSONObject:message
                   options:0
                     error:nil];
    NSString *signatureError = nil;
    NSData *signature =
        TLinkLicenseCreateDeviceSignature(messageData, &signatureError);
    if (messageData.length == 0 || signature.length == 0) {
        return [NSString stringWithFormat:@"-1;;%@\r\n",
            signatureError ?: @"license_authority_sign_failed"];
    }
    NSDictionary *envelope = @{
        @"version": @(TLINK_LICENSE_AUTHORITY_CONTRACT_VERSION),
        @"policy": @"license_authority_signed_status_v1",
        @"message": [messageData base64EncodedStringWithOptions:0],
        @"signature": [signature base64EncodedStringWithOptions:0],
    };
    NSData *envelopeData = [NSJSONSerialization
        dataWithJSONObject:envelope
                   options:0
                     error:nil];
    if (envelopeData.length == 0) {
        return @"-1;;license_authority_encode_failed\r\n";
    }
    return [NSString stringWithFormat:@"0;;%@\r\n",
        [envelopeData base64EncodedStringWithOptions:0]];
}

static void TLinkLicenseAuthorityHandleClient(int client)
{
    struct timeval timeout = {5, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE,
               &noSigPipe, sizeof(noSigPipe));
#endif

    NSMutableData *request = [NSMutableData data];
    uint8_t buffer[512];
    while (request.length < kTLinkLicenseAuthorityMaxRequest) {
        NSUInteger capacity = MIN(
            sizeof(buffer),
            kTLinkLicenseAuthorityMaxRequest - request.length);
        ssize_t received = recv(client, buffer, capacity, 0);
        if (received <= 0) break;
        [request appendBytes:buffer length:(NSUInteger)received];
        if (memchr(buffer, '\n', (size_t)received)) break;
    }
    if (request.length == 0 ||
        request.length >= kTLinkLicenseAuthorityMaxRequest) {
        close(client);
        return;
    }
    NSString *line = [[NSString alloc]
        initWithData:request
            encoding:NSUTF8StringEncoding] ?: @"";
    line = [line stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *response = [TLinkLicenseAuthorityResponse(line)
        dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const uint8_t *bytes = (const uint8_t *)response.bytes;
    NSUInteger remaining = response.length;
    while (remaining > 0) {
        ssize_t sent = send(client, bytes, remaining, 0);
        if (sent <= 0) break;
        bytes += sent;
        remaining -= (NSUInteger)sent;
    }
    close(client);
}

static void TLinkLicenseAuthorityRunServer(void)
{
    [[NSFileManager defaultManager]
        createDirectoryAtPath:@"/var/mobile/Library/TLinkauto/run"
  withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];
    unlink(TLINK_LICENSE_AUTHORITY_SOCKET_PATH);

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) {
        NSLog(@"[TLinkLicenseAuthority] socket failed errno=%d", errno);
        return;
    }
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path,
            TLINK_LICENSE_AUTHORITY_SOCKET_PATH,
            sizeof(address.sun_path));
    if (bind(server,
             (struct sockaddr *)&address,
             sizeof(address)) != 0 ||
        listen(server, 16) != 0) {
        NSLog(@"[TLinkLicenseAuthority] bind/listen failed errno=%d", errno);
        close(server);
        unlink(TLINK_LICENSE_AUTHORITY_SOCKET_PATH);
        return;
    }
    chmod(TLINK_LICENSE_AUTHORITY_SOCKET_PATH, 0660);
    NSLog(@"[TLinkLicenseAuthority] listening at %s",
          TLINK_LICENSE_AUTHORITY_SOCKET_PATH);

    while (true) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
        dispatch_async(
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    TLinkLicenseAuthorityHandleClient(client);
                }
            });
    }
    close(server);
    unlink(TLINK_LICENSE_AUTHORITY_SOCKET_PATH);
}

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        NSLog(@"[TLinkLicenseAuthority] rootfullBuildMode=%s verifierBuildMode=%@",
              TLinkRootfullLicenseBuildMode(),
              TLinkLicenseBuildMode());
        dispatch_async(
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    TLinkLicenseAuthorityRunServer();
                }
            });
        CFRunLoopRun();
    }
    return 0;
}
