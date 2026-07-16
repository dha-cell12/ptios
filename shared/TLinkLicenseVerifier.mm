#import "TLinkLicenseVerifier.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>

static NSString *const kTLinkLicenseDirectory = @"/var/mobile/Library/TLinkauto/license";
static NSString *const kTLinkLicenseLease = @"/var/mobile/Library/TLinkauto/license/lease.json";
static NSString *const kTLinkLicenseDevicePublicKey = @"/var/mobile/Library/TLinkauto/license/device_public_key.bin";
static NSString *const kTLinkLicenseDeviceKeyTag = @"com.tlinkauto.streamcontrol.license-device-key.v1";
static NSDictionary *sTLinkLicenseFeatureStatus = nil;
static NSTimeInterval sTLinkLicenseFeatureStatusAt = 0;

static dispatch_queue_t TLinkLicenseCacheQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tlinkauto.license-verifier-cache", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

NSString *TLinkLicenseDirectoryPath(void)
{
    return kTLinkLicenseDirectory;
}

NSString *TLinkLicenseLeasePath(void)
{
    return kTLinkLicenseLease;
}

NSString *TLinkLicenseDevicePublicKeyPath(void)
{
    return kTLinkLicenseDevicePublicKey;
}

NSString *TLinkLicenseDeviceKeyTag(void)
{
    return kTLinkLicenseDeviceKeyTag;
}

static NSString *TLinkExecutableDirectory(void)
{
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    if (size == 0) return nil;
    char *buffer = (char *)calloc(1, size + 1);
    if (!buffer) return nil;
    NSString *result = nil;
    if (_NSGetExecutablePath(buffer, &size) == 0) {
        result = [[[NSString stringWithUTF8String:buffer] stringByStandardizingPath] stringByDeletingLastPathComponent];
    }
    free(buffer);
    return result;
}

NSDictionary *TLinkLicenseConfiguration(void)
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSString *executableDirectory = TLinkExecutableDirectory();
    if (executableDirectory.length > 0) {
        [candidates addObject:[executableDirectory stringByAppendingPathComponent:@"LicenseConfig.plist"]];
    }
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"LicenseConfig" ofType:@"plist"];
    if (bundlePath.length > 0 && ![candidates containsObject:bundlePath]) {
        [candidates addObject:bundlePath];
    }
    for (NSString *path in candidates) {
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([config isKindOfClass:[NSDictionary class]]) return config;
    }
    return @{};
}

static NSData *TLinkBase64URLDecode(NSString *value)
{
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return nil;
    NSMutableString *base64 = [value mutableCopy];
    [base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    while (base64.length % 4 != 0) [base64 appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

static NSString *TLinkBase64URLEncode(NSData *data)
{
    if (data.length == 0) return @"";
    NSMutableString *value = [[data base64EncodedStringWithOptions:0] mutableCopy];
    [value replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0, value.length)];
    [value replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, value.length)];
    while ([value hasSuffix:@"="]) [value deleteCharactersInRange:NSMakeRange(value.length - 1, 1)];
    return value;
}

static NSString *TLinkSHA256Base64URL(NSData *data)
{
    if (data.length == 0) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return TLinkBase64URLEncode([NSData dataWithBytes:digest length:sizeof(digest)]);
}

static BOOL TLinkLicenseConfigValueUsable(NSString *value)
{
    return value.length > 0 && [value rangeOfString:@"REPLACE_" options:NSCaseInsensitiveSearch].location == NSNotFound;
}

static BOOL TLinkLicenseConfiguredEnforcement(NSDictionary *config)
{
#if defined(TLINK_LICENSE_FORCE_ENFORCEMENT) && TLINK_LICENSE_FORCE_ENFORCEMENT
    return YES;
#else
    return [config[@"LicenseEnforcementEnabled"] boolValue];
#endif
}

BOOL TLinkLicenseEnforcementEnabled(void)
{
    return TLinkLicenseConfiguredEnforcement(TLinkLicenseConfiguration());
}

static SecKeyRef TLinkCreateServerPublicKey(NSDictionary *config) CF_RETURNS_RETAINED
{
    NSString *xString = [config[@"LicensePublicKeyX"] isKindOfClass:[NSString class]] ? config[@"LicensePublicKeyX"] : @"";
    NSString *yString = [config[@"LicensePublicKeyY"] isKindOfClass:[NSString class]] ? config[@"LicensePublicKeyY"] : @"";
    if (!TLinkLicenseConfigValueUsable(xString) || !TLinkLicenseConfigValueUsable(yString)) return nil;
    NSData *x = TLinkBase64URLDecode(xString);
    NSData *y = TLinkBase64URLDecode(yString);
    if (x.length != 32 || y.length != 32) return nil;
    NSMutableData *point = [NSMutableData dataWithLength:65];
    uint8_t *bytes = (uint8_t *)point.mutableBytes;
    bytes[0] = 0x04;
    memcpy(bytes + 1, x.bytes, 32);
    memcpy(bytes + 33, y.bytes, 32);
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @256,
    };
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)point,
                                         (__bridge CFDictionaryRef)attributes,
                                         &error);
    if (error) CFRelease(error);
    return key;
}

static SecKeyRef TLinkCreateDevicePublicKey(NSData *point) CF_RETURNS_RETAINED
{
    if (point.length != 65 || ((const uint8_t *)point.bytes)[0] != 0x04) return nil;
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @256,
    };
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)point,
                                         (__bridge CFDictionaryRef)attributes,
                                         &error);
    if (error) CFRelease(error);
    return key;
}

static BOOL TLinkVerifyDeviceKeyPossession(NSData *publicPoint, NSString **error)
{
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: [kTLinkLicenseDeviceKeyTag dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecReturnRef: @YES,
    };
    CFTypeRef result = NULL;
    OSStatus copyStatus = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (copyStatus != errSecSuccess || !result) {
        if (error) *error = [NSString stringWithFormat:@"license_device_private_key_unavailable status=%d", (int)copyStatus];
        return NO;
    }
    SecKeyRef privateKey = (SecKeyRef)result;
    SecKeyRef publicKey = TLinkCreateDevicePublicKey(publicPoint);
    if (!publicKey) {
        CFRelease(privateKey);
        if (error) *error = @"license_device_public_key_invalid";
        return NO;
    }

    NSData *challenge = [@"tlinkauto-license-local-proof-v1" dataUsingEncoding:NSUTF8StringEncoding];
    CFErrorRef signError = NULL;
    CFDataRef signature = SecKeyCreateSignature(privateKey,
                                                kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                (__bridge CFDataRef)challenge,
                                                &signError);
    CFRelease(privateKey);
    if (!signature) {
        NSString *message = signError ? [(__bridge NSError *)signError localizedDescription] : @"unknown";
        if (signError) CFRelease(signError);
        CFRelease(publicKey);
        if (error) *error = [NSString stringWithFormat:@"license_device_proof_sign_failed %@", message];
        return NO;
    }
    if (signError) CFRelease(signError);

    CFErrorRef verifyError = NULL;
    BOOL verified = SecKeyVerifySignature(publicKey,
                                          kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                          (__bridge CFDataRef)challenge,
                                          signature,
                                          &verifyError);
    CFRelease(signature);
    CFRelease(publicKey);
    if (!verified) {
        NSString *message = verifyError ? [(__bridge NSError *)verifyError localizedDescription] : @"unknown";
        if (verifyError) CFRelease(verifyError);
        if (error) *error = [NSString stringWithFormat:@"license_device_proof_verify_failed %@", message];
        return NO;
    }
    if (verifyError) CFRelease(verifyError);
    return YES;
}

static NSDictionary *TLinkLicenseFailure(NSDictionary *config, NSString *state, NSString *error)
{
    BOOL enforcement = TLinkLicenseConfiguredEnforcement(config);
    NSString *endpoint = [config[@"LicenseEndpoint"] isKindOfClass:[NSString class]] ? config[@"LicenseEndpoint"] : @"";
    NSString *x = [config[@"LicensePublicKeyX"] isKindOfClass:[NSString class]] ? config[@"LicensePublicKeyX"] : @"";
    NSString *y = [config[@"LicensePublicKeyY"] isKindOfClass:[NSString class]] ? config[@"LicensePublicKeyY"] : @"";
    return @{
        @"configured": @(TLinkLicenseConfigValueUsable(endpoint) &&
                          TLinkLicenseConfigValueUsable(x) &&
                          TLinkLicenseConfigValueUsable(y)),
        @"enforcement_enabled": @(enforcement),
        @"effective_access": @(!enforcement),
        @"licensed": @NO,
        @"state": state ?: @"invalid",
        @"error": error ?: @"license_invalid",
        @"endpoint": endpoint,
        @"lease_path": kTLinkLicenseLease,
        @"device_public_key_path": kTLinkLicenseDevicePublicKey,
        @"device_key_proof": @NO,
        @"features": @[],
    };
}

NSDictionary *TLinkLicenseStatusDictionary(void)
{
    NSDictionary *config = TLinkLicenseConfiguration();
    NSString *endpoint = [config[@"LicenseEndpoint"] isKindOfClass:[NSString class]] ? config[@"LicenseEndpoint"] : @"";
    NSString *x = [config[@"LicensePublicKeyX"] isKindOfClass:[NSString class]] ? config[@"LicensePublicKeyX"] : @"";
    NSString *y = [config[@"LicensePublicKeyY"] isKindOfClass:[NSString class]] ? config[@"LicensePublicKeyY"] : @"";
    if (!TLinkLicenseConfigValueUsable(endpoint) ||
        !TLinkLicenseConfigValueUsable(x) ||
        !TLinkLicenseConfigValueUsable(y)) {
        return TLinkLicenseFailure(config, @"not_configured", @"license_config_missing_endpoint_or_public_key");
    }

    NSData *leaseData = [NSData dataWithContentsOfFile:kTLinkLicenseLease];
    if (leaseData.length == 0) return TLinkLicenseFailure(config, @"not_activated", @"license_lease_missing");
    NSDictionary *lease = [NSJSONSerialization JSONObjectWithData:leaseData options:0 error:nil];
    if (![lease isKindOfClass:[NSDictionary class]]) {
        return TLinkLicenseFailure(config, @"invalid", @"license_lease_json_invalid");
    }
    NSString *payloadString = [lease[@"payload"] isKindOfClass:[NSString class]] ? lease[@"payload"] : @"";
    NSString *signatureString = [lease[@"signature"] isKindOfClass:[NSString class]] ? lease[@"signature"] : @"";
    NSString *configuredKeyID = [config[@"LicenseKeyID"] isKindOfClass:[NSString class]] ? config[@"LicenseKeyID"] : @"";
    NSString *leaseKeyID = [lease[@"key_id"] isKindOfClass:[NSString class]] ? lease[@"key_id"] : @"";
    if (configuredKeyID.length > 0 && ![configuredKeyID isEqualToString:leaseKeyID]) {
        return TLinkLicenseFailure(config, @"invalid", @"license_key_id_mismatch");
    }
    if ([lease[@"version"] integerValue] != 1) {
        return TLinkLicenseFailure(config, @"invalid", @"license_version_unsupported");
    }
    NSData *payloadData = TLinkBase64URLDecode(payloadString);
    NSData *signatureData = TLinkBase64URLDecode(signatureString);
    if (payloadData.length == 0 || signatureData.length == 0) {
        return TLinkLicenseFailure(config, @"invalid", @"license_lease_fields_invalid");
    }

    SecKeyRef serverKey = TLinkCreateServerPublicKey(config);
    if (!serverKey) return TLinkLicenseFailure(config, @"invalid", @"license_server_public_key_invalid");
    CFErrorRef verifyError = NULL;
    BOOL signatureValid = SecKeyVerifySignature(serverKey,
                                                kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                (__bridge CFDataRef)payloadData,
                                                (__bridge CFDataRef)signatureData,
                                                &verifyError);
    CFRelease(serverKey);
    NSString *verifyDescription = verifyError ? [(__bridge NSError *)verifyError localizedDescription] : @"";
    if (verifyError) CFRelease(verifyError);
    if (!signatureValid) {
        return TLinkLicenseFailure(config, @"invalid", verifyDescription.length > 0 ? verifyDescription : @"license_signature_invalid");
    }

    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return TLinkLicenseFailure(config, @"invalid", @"license_payload_json_invalid");
    }
    NSString *product = [payload[@"product"] isKindOfClass:[NSString class]] ? payload[@"product"] : @"";
    if (![product isEqualToString:@"tlinkauto"] || [payload[@"version"] integerValue] != 1) {
        return TLinkLicenseFailure(config, @"invalid", @"license_payload_product_or_version_mismatch");
    }
    NSData *devicePublicKey = [NSData dataWithContentsOfFile:kTLinkLicenseDevicePublicKey];
    NSString *expectedDeviceHash = [payload[@"device_key_hash"] isKindOfClass:[NSString class]] ? payload[@"device_key_hash"] : @"";
    NSString *actualDeviceHash = TLinkSHA256Base64URL(devicePublicKey);
    if (devicePublicKey.length == 0 || ![actualDeviceHash isEqualToString:expectedDeviceHash]) {
        return TLinkLicenseFailure(config, @"device_mismatch", @"license_device_key_mismatch");
    }
    NSString *deviceProofError = nil;
    if (!TLinkVerifyDeviceKeyPossession(devicePublicKey, &deviceProofError)) {
        return TLinkLicenseFailure(config, @"device_mismatch", deviceProofError ?: @"license_device_proof_failed");
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval notBefore = [payload[@"not_before"] doubleValue];
    NSTimeInterval expiresAt = [payload[@"expires_at"] doubleValue];
    NSTimeInterval offlineUntil = [payload[@"offline_until"] doubleValue];
    if (notBefore > 0 && now + 60.0 < notBefore) {
        return TLinkLicenseFailure(config, @"not_yet_valid", @"license_not_before_in_future");
    }
    if (offlineUntil <= 0 || now > offlineUntil) {
        return TLinkLicenseFailure(config, @"expired", @"license_offline_grace_expired");
    }

    NSArray *features = [payload[@"features"] isKindOfClass:[NSArray class]] ? payload[@"features"] : @[];
    BOOL enforcement = TLinkLicenseConfiguredEnforcement(config);
    NSString *state = expiresAt > 0 && now > expiresAt ? @"offline_grace" : @"valid";
    return @{
        @"configured": @YES,
        @"enforcement_enabled": @(enforcement),
        @"effective_access": @YES,
        @"licensed": @YES,
        @"state": state,
        @"error": @"",
        @"endpoint": endpoint,
        @"lease_path": kTLinkLicenseLease,
        @"device_public_key_path": kTLinkLicenseDevicePublicKey,
        @"device_key_proof": @YES,
        @"license_id": payload[@"license_id"] ?: @"",
        @"device_id": payload[@"device_id"] ?: @"",
        @"token_id": payload[@"token_id"] ?: @"",
        @"issued_at": payload[@"issued_at"] ?: @0,
        @"expires_at": payload[@"expires_at"] ?: @0,
        @"offline_until": payload[@"offline_until"] ?: @0,
        @"features": features,
        @"key_id": lease[@"key_id"] ?: @"",
        @"device_key_hash": expectedDeviceHash,
    };
}

BOOL TLinkLicenseFeatureAllowed(NSString *feature, NSString **error)
{
    __block NSDictionary *status = nil;
    dispatch_sync(TLinkLicenseCacheQueue(), ^{
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!sTLinkLicenseFeatureStatus || now - sTLinkLicenseFeatureStatusAt >= 5.0) {
            sTLinkLicenseFeatureStatus = TLinkLicenseStatusDictionary();
            sTLinkLicenseFeatureStatusAt = now;
        }
        status = sTLinkLicenseFeatureStatus;
    });
    if (![status[@"enforcement_enabled"] boolValue]) return YES;
    if (![status[@"licensed"] boolValue]) {
        if (error) *error = status[@"error"] ?: @"license_required";
        return NO;
    }
    NSArray *features = [status[@"features"] isKindOfClass:[NSArray class]] ? status[@"features"] : @[];
    if ([features containsObject:@"all"] ||
        feature.length == 0 ||
        [features containsObject:feature]) {
        return YES;
    }
    if (error) *error = [NSString stringWithFormat:@"license_feature_not_enabled feature=%@", feature ?: @"unknown"];
    return NO;
}

void TLinkLicenseInvalidateCache(void)
{
    dispatch_sync(TLinkLicenseCacheQueue(), ^{
        sTLinkLicenseFeatureStatus = nil;
        sTLinkLicenseFeatureStatusAt = 0;
    });
}
