#import "TLinkLicenseAuthorityClient.h"

#import "TLinkLicenseVerifier.h"

#import <Security/Security.h>

#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

static const NSUInteger kTLinkLicenseAuthorityMaxResponse = 1024 * 1024;

static SecKeyRef TLinkLicenseAuthorityCreatePublicKey(
    NSData *point) CF_RETURNS_RETAINED
{
    if (point.length != 65 ||
        ((const uint8_t *)point.bytes)[0] != 0x04) {
        return nil;
    }
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType:
            (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass:
            (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @256,
    };
    CFErrorRef createError = NULL;
    SecKeyRef key = SecKeyCreateWithData(
        (__bridge CFDataRef)point,
        (__bridge CFDictionaryRef)attributes,
        &createError);
    if (createError) CFRelease(createError);
    return key;
}

static BOOL TLinkLicenseAuthoritySendAll(
    int socketFD,
    const uint8_t *bytes,
    NSUInteger length)
{
    while (length > 0) {
        ssize_t sent = send(socketFD, bytes, length, 0);
        if (sent <= 0) return NO;
        bytes += sent;
        length -= (NSUInteger)sent;
    }
    return YES;
}

static NSData *TLinkLicenseAuthorityExchange(
    NSData *request,
    NSString **error)
{
    int socketFD = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socketFD < 0) {
        if (error) *error = @"license_authority_socket_failed";
        return nil;
    }
    struct timeval timeout = {3, 0};
    setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE,
               &noSigPipe, sizeof(noSigPipe));
#endif

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path,
            TLINK_LICENSE_AUTHORITY_SOCKET_PATH,
            sizeof(address.sun_path));
    if (connect(socketFD,
                (struct sockaddr *)&address,
                sizeof(address)) != 0) {
        close(socketFD);
        if (error) *error = @"license_authority_unavailable";
        return nil;
    }

    NSMutableData *wireRequest = [request mutableCopy];
    const uint8_t newline = '\n';
    [wireRequest appendBytes:&newline length:1];
    if (!TLinkLicenseAuthoritySendAll(
            socketFD,
            (const uint8_t *)wireRequest.bytes,
            wireRequest.length)) {
        close(socketFD);
        if (error) *error = @"license_authority_send_failed";
        return nil;
    }

    NSMutableData *response = [NSMutableData data];
    uint8_t buffer[4096];
    while (response.length < kTLinkLicenseAuthorityMaxResponse) {
        ssize_t received = recv(socketFD, buffer, sizeof(buffer), 0);
        if (received <= 0) break;
        [response appendBytes:buffer length:(NSUInteger)received];
        if (memchr(buffer, '\n', (size_t)received)) break;
    }
    close(socketFD);
    if (response.length == 0 ||
        response.length >= kTLinkLicenseAuthorityMaxResponse) {
        if (error) *error = @"license_authority_response_missing_or_too_large";
        return nil;
    }
    return response;
}

NSDictionary *TLinkLicenseAuthorityStatus(NSString **error)
{
    uint8_t nonceBytes[32];
    if (SecRandomCopyBytes(
            kSecRandomDefault,
            sizeof(nonceBytes),
            nonceBytes) != errSecSuccess) {
        if (error) *error = @"license_authority_nonce_failed";
        return nil;
    }
    NSString *nonce = [[NSData dataWithBytes:nonceBytes
                                      length:sizeof(nonceBytes)]
        base64EncodedStringWithOptions:0];
    NSDictionary *requestObject = @{
        @"version": @(TLINK_LICENSE_AUTHORITY_CONTRACT_VERSION),
        @"command": @"status",
        @"nonce": nonce,
    };
    NSData *request = [NSJSONSerialization
        dataWithJSONObject:requestObject
                   options:0
                     error:nil];
    NSString *exchangeError = nil;
    NSData *wireResponse =
        TLinkLicenseAuthorityExchange(request, &exchangeError);
    if (!wireResponse) {
        if (error) *error = exchangeError ?: @"license_authority_unavailable";
        return nil;
    }

    NSString *line = [[NSString alloc]
        initWithData:wireResponse
            encoding:NSUTF8StringEncoding];
    line = [line stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![line hasPrefix:@"0;;"]) {
        if (error) {
            *error = [line hasPrefix:@"-1;;"]
                ? [line substringFromIndex:4]
                : @"license_authority_invalid_response";
        }
        return nil;
    }
    NSData *envelopeData = [[NSData alloc]
        initWithBase64EncodedString:[line substringFromIndex:3]
                            options:0];
    id envelopeObject = [NSJSONSerialization
        JSONObjectWithData:envelopeData ?: [NSData data]
                   options:0
                     error:nil];
    NSDictionary *envelope =
        [envelopeObject isKindOfClass:[NSDictionary class]]
        ? envelopeObject : nil;
    if (!envelope) {
        if (error) *error = @"license_authority_envelope_invalid";
        return nil;
    }
    NSData *messageData = [[NSData alloc]
        initWithBase64EncodedString:
            ([envelope[@"message"] isKindOfClass:[NSString class]]
                ? envelope[@"message"] : @"")
                            options:0];
    NSData *signature = [[NSData alloc]
        initWithBase64EncodedString:
            ([envelope[@"signature"] isKindOfClass:[NSString class]]
                ? envelope[@"signature"] : @"")
                            options:0];
    if (messageData.length == 0 || signature.length == 0) {
        if (error) *error = @"license_authority_envelope_invalid";
        return nil;
    }

    NSData *publicPoint =
        [NSData dataWithContentsOfFile:TLinkLicenseDevicePublicKeyPath()];
    NSString *anchorError = nil;
    if (!TLinkLicenseDevicePublicKeyAnchored(publicPoint, &anchorError)) {
        if (error) {
            *error = anchorError
                ?: @"license_authority_public_key_not_lease_anchored";
        }
        return nil;
    }
    SecKeyRef publicKey =
        TLinkLicenseAuthorityCreatePublicKey(publicPoint);
    if (!publicKey) {
        if (error) *error = @"license_authority_public_key_invalid";
        return nil;
    }
    CFErrorRef verifyError = NULL;
    BOOL signatureValid = SecKeyVerifySignature(
        publicKey,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)messageData,
        (__bridge CFDataRef)signature,
        &verifyError);
    CFRelease(publicKey);
    if (verifyError) CFRelease(verifyError);
    if (!signatureValid) {
        if (error) *error = @"license_authority_signature_invalid";
        return nil;
    }

    id messageObject = [NSJSONSerialization
        JSONObjectWithData:messageData
                   options:0
                     error:nil];
    NSDictionary *message =
        [messageObject isKindOfClass:[NSDictionary class]]
        ? messageObject : nil;
    if (!message) {
        if (error) *error = @"license_authority_message_invalid";
        return nil;
    }
    uint64_t issuedAt = [message[@"issued_at_ms"] unsignedLongLongValue];
    uint64_t expiresAt = [message[@"expires_at_ms"] unsignedLongLongValue];
    uint64_t now =
        (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
    BOOL timeValid =
        issuedAt > 0 &&
        expiresAt > issuedAt &&
        expiresAt - issuedAt <= 15000 &&
        issuedAt <= now + 5000 &&
        now <= expiresAt + 1000;
    NSDictionary *status = [message[@"status"]
        isKindOfClass:[NSDictionary class]]
        ? message[@"status"] : nil;
    if ([message[@"version"] integerValue] !=
            TLINK_LICENSE_AUTHORITY_CONTRACT_VERSION ||
        ![message[@"nonce"] isEqualToString:nonce] ||
        !timeValid ||
        !status) {
        if (error) *error = @"license_authority_proof_invalid_or_expired";
        return nil;
    }
    return status;
}
