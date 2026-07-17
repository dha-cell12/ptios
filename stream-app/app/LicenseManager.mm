#import "LicenseManager.h"
#import "../../shared/TLinkLicenseVerifier.h"
#import <Security/Security.h>

static NSString *const kTLinkLicenseDeviceKeyModePath = @"/var/mobile/Library/TLinkauto/license/device_key_mode";
static NSString *const kTLinkLicenseRecoveryDiagnosticsPath = @"/var/mobile/Library/TLinkauto/license/recovery.plist";

@implementation SCLicenseManager

+ (instancetype)sharedManager
{
    static SCLicenseManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[SCLicenseManager alloc] init];
    });
    return manager;
}

- (NSDictionary *)localStatus
{
    NSMutableDictionary *status = [TLinkLicenseStatusDictionary() mutableCopy];
    NSString *mode = [NSString stringWithContentsOfFile:kTLinkLicenseDeviceKeyModePath
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    status[@"device_key_mode"] = [mode stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"none";
    SecKeyRef privateKey = [self copyExistingDevicePrivateKey];
    BOOL privateKeyPresent = privateKey != nil;
    if (privateKey) CFRelease(privateKey);
    BOOL publicKeyPresent = [[NSFileManager defaultManager] fileExistsAtPath:TLinkLicenseDevicePublicKeyPath()];
    BOOL leasePresent = [[NSFileManager defaultManager] fileExistsAtPath:TLinkLicenseLeasePath()];
    status[@"device_private_key_present"] = @(privateKeyPresent);
    status[@"device_public_key_present"] = @(publicKeyPresent);
    status[@"lease_present"] = @(leasePresent);
    BOOL deviceMismatch = [status[@"state"] isEqualToString:@"device_mismatch"];
    if (privateKeyPresent && (!publicKeyPresent || deviceMismatch)) {
        status[@"recovery_action"] = @"repair_device_public_key";
    } else if (leasePresent && !privateKeyPresent) {
        status[@"recovery_action"] = @"deactivate_old_device_or_admin_reset";
    } else if ([status[@"recovery"] isKindOfClass:[NSDictionary class]] &&
               [status[@"recovery"] count] > 0) {
        status[@"recovery_action"] = @"reactivate_after_quarantine";
    } else {
        status[@"recovery_action"] = @"none";
    }
    return status;
}

- (NSData *)base64URLDecode:(NSString *)value
{
    if (value.length == 0) return nil;
    NSMutableString *base64 = [value mutableCopy];
    [base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    while (base64.length % 4 != 0) [base64 appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

- (NSString *)base64URLEncode:(NSData *)data
{
    if (data.length == 0) return @"";
    NSMutableString *value = [[data base64EncodedStringWithOptions:0] mutableCopy];
    [value replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0, value.length)];
    [value replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, value.length)];
    while ([value hasSuffix:@"="]) [value deleteCharactersInRange:NSMakeRange(value.length - 1, 1)];
    return value;
}

- (NSString *)diagnosticMessageForError:(NSError *)error fallback:(NSString *)fallback
{
    if (!error) return fallback ?: @"license_error";
    NSString *serverMessage = error.localizedDescription ?: @"";
    if ([serverMessage isEqualToString:@"device_limit_reached"]) {
        NSDictionary *server = [error.userInfo[@"server_response"] isKindOfClass:[NSDictionary class]]
            ? error.userInfo[@"server_response"]
            : @{};
        return [NSString stringWithFormat:@"device_limit_reached active=%@ max=%@ deactivate_the_old_device_or_request_an_admin_device_reset",
                server[@"active_devices"] ?: @"?",
                server[@"max_devices"] ?: @"?"];
    }
    if ([serverMessage isEqualToString:@"device_not_active"] ||
        [serverMessage isEqualToString:@"device_revoked"]) {
        return @"device_not_active reactivate_this_device_or_request_an_admin_reset";
    }
    return [NSString stringWithFormat:@"domain=%@ code=%ld message=%@",
            error.domain ?: @"unknown",
            (long)error.code,
            error.localizedDescription ?: fallback ?: @"license_error"];
}

- (NSData *)deviceKeyTagData
{
    return [TLinkLicenseDeviceKeyTag() dataUsingEncoding:NSUTF8StringEncoding];
}

- (SecKeyRef)copyExistingDevicePrivateKey CF_RETURNS_RETAINED
{
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: [self deviceKeyTagData],
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecReturnRef: @YES,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    return status == errSecSuccess ? (SecKeyRef)result : nil;
}

- (SecKeyRef)createDevicePrivateKeyWithSecureEnclave:(BOOL)secureEnclave
                                               error:(NSError **)error CF_RETURNS_RETAINED
{
    NSMutableDictionary *privateAttributes = [@{
        (__bridge id)kSecAttrIsPermanent: @YES,
        (__bridge id)kSecAttrApplicationTag: [self deviceKeyTagData],
    } mutableCopy];
    CFErrorRef accessError = NULL;
    if (secureEnclave) {
        SecAccessControlRef access = SecAccessControlCreateWithFlags(
            NULL,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAccessControlPrivateKeyUsage,
            &accessError);
        if (!access) {
            if (error) *error = CFBridgingRelease(accessError);
            return nil;
        }
        privateAttributes[(__bridge id)kSecAttrAccessControl] = (__bridge id)access;
        CFRelease(access);
    } else {
        privateAttributes[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    }

    NSMutableDictionary *attributes = [@{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecPrivateKeyAttrs: privateAttributes,
    } mutableCopy];
    if (secureEnclave) {
        attributes[(__bridge id)kSecAttrTokenID] = (__bridge id)kSecAttrTokenIDSecureEnclave;
    }
    CFErrorRef createError = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &createError);
    if (!key && error) *error = CFBridgingRelease(createError);
    else if (createError) CFRelease(createError);
    return key;
}

- (SecKeyRef)copyOrCreateDevicePrivateKeyWithMode:(NSString **)mode error:(NSError **)error CF_RETURNS_RETAINED
{
    SecKeyRef existing = [self copyExistingDevicePrivateKey];
    if (existing) {
        NSString *savedMode = [NSString stringWithContentsOfFile:kTLinkLicenseDeviceKeyModePath
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
        if (mode) *mode = [savedMode stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"existing";
        return existing;
    }

    NSError *secureError = nil;
    SecKeyRef key = [self createDevicePrivateKeyWithSecureEnclave:YES error:&secureError];
    NSString *createdMode = @"secure_enclave";
    if (!key) {
        key = [self createDevicePrivateKeyWithSecureEnclave:NO error:error];
        createdMode = @"keychain_software_fallback";
    }
    if (!key) {
        if (error && !*error) *error = secureError;
        return nil;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:TLinkLicenseDirectoryPath()
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [createdMode writeToFile:kTLinkLicenseDeviceKeyModePath
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];
    if (mode) *mode = createdMode;
    return key;
}

- (NSDictionary *)devicePublicJWKForPrivateKey:(SecKeyRef)privateKey error:(NSError **)error
{
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (!publicKey) {
        if (error) *error = [NSError errorWithDomain:@"TLinkLicense" code:10 userInfo:@{NSLocalizedDescriptionKey: @"device_public_key_unavailable"}];
        return nil;
    }
    CFErrorRef copyError = NULL;
    NSData *point = CFBridgingRelease(SecKeyCopyExternalRepresentation(publicKey, &copyError));
    CFRelease(publicKey);
    if (point.length != 65 || ((const uint8_t *)point.bytes)[0] != 0x04) {
        if (error) {
            *error = copyError
                ? CFBridgingRelease(copyError)
                : [NSError errorWithDomain:@"TLinkLicense" code:11 userInfo:@{NSLocalizedDescriptionKey: @"device_public_key_format_invalid"}];
        } else if (copyError) {
            CFRelease(copyError);
        }
        return nil;
    }
    if (copyError) CFRelease(copyError);

    [[NSFileManager defaultManager] createDirectoryAtPath:TLinkLicenseDirectoryPath()
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSError *writeError = nil;
    if (![point writeToFile:TLinkLicenseDevicePublicKeyPath() options:NSDataWritingAtomic error:&writeError]) {
        if (error) *error = writeError ?: [NSError errorWithDomain:@"TLinkLicense"
                                                              code:12
                                                          userInfo:@{NSLocalizedDescriptionKey: @"device_public_key_write_failed"}];
        return nil;
    }
    NSData *x = [point subdataWithRange:NSMakeRange(1, 32)];
    NSData *y = [point subdataWithRange:NSMakeRange(33, 32)];
    return @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": [self base64URLEncode:x],
        @"y": [self base64URLEncode:y],
    };
}

- (NSURL *)URLForPath:(NSString *)path error:(NSError **)error
{
    NSDictionary *config = TLinkLicenseConfiguration();
    NSString *endpoint = [config[@"LicenseEndpoint"] isKindOfClass:[NSString class]] ? config[@"LicenseEndpoint"] : @"";
    if (endpoint.length == 0 || [endpoint containsString:@"REPLACE_"]) {
        if (error) *error = [NSError errorWithDomain:@"TLinkLicense" code:20 userInfo:@{NSLocalizedDescriptionKey: @"license_endpoint_not_configured"}];
        return nil;
    }
    NSString *base = [endpoint hasSuffix:@"/"] ? [endpoint substringToIndex:endpoint.length - 1] : endpoint;
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:path ?: @""]];
    if (!url && error) *error = [NSError errorWithDomain:@"TLinkLicense" code:21 userInfo:@{NSLocalizedDescriptionKey: @"license_endpoint_invalid"}];
    return url;
}

- (void)postPath:(NSString *)path
            body:(NSDictionary *)body
      completion:(void (^)(NSDictionary *response, NSError *error))completion
{
    NSError *urlError = nil;
    NSURL *url = [self URLForPath:path error:&urlError];
    if (!url) {
        if (completion) completion(nil, urlError);
        return;
    }
    NSError *jsonError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:&jsonError];
    if (!json) {
        if (completion) completion(nil, jsonError);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:20.0];
    request.HTTPMethod = @"POST";
    request.HTTPBody = json;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        if (networkError) {
            if (completion) completion(nil, networkError);
            return;
        }
        NSDictionary *object = data.length > 0
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]
            : nil;
        NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? [(NSHTTPURLResponse *)response statusCode]
            : 0;
        if (![object isKindOfClass:[NSDictionary class]] || statusCode < 200 || statusCode >= 300 || ![object[@"ok"] boolValue]) {
            NSString *message = [object[@"error"] isKindOfClass:[NSString class]] ? object[@"error"] : @"license_server_error";
            NSError *serverError = [NSError errorWithDomain:@"TLinkLicense"
                                                       code:statusCode
                                                   userInfo:@{
                                                       NSLocalizedDescriptionKey: message,
                                                       @"server_response": [object isKindOfClass:[NSDictionary class]] ? object : @{},
                                                   }];
            if (completion) completion(object, serverError);
            return;
        }
        if (completion) completion(object, nil);
    }];
    [task resume];
}

- (BOOL)saveLease:(NSDictionary *)lease error:(NSError **)error
{
    if (![lease isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"TLinkLicense" code:30 userInfo:@{NSLocalizedDescriptionKey: @"license_response_missing_lease"}];
        return NO;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:lease options:0 error:error];
    if (!data) return NO;
    [[NSFileManager defaultManager] createDirectoryAtPath:TLinkLicenseDirectoryPath()
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    BOOL saved = [data writeToFile:TLinkLicenseLeasePath() options:NSDataWritingAtomic error:error];
    if (saved) {
        [[NSFileManager defaultManager] removeItemAtPath:kTLinkLicenseRecoveryDiagnosticsPath error:nil];
        TLinkLicenseAdvanceGeneration();
    }
    return saved;
}

- (void)activateLicenseKey:(NSString *)licenseKey
                completion:(void (^)(BOOL success, NSString *message))completion
{
    NSString *normalized = [[[licenseKey ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        uppercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (normalized.length < 8) {
        if (completion) completion(NO, @"license_key_too_short");
        return;
    }
    NSError *keyError = nil;
    NSString *mode = nil;
    SecKeyRef privateKey = [self copyOrCreateDevicePrivateKeyWithMode:&mode error:&keyError];
    if (!privateKey) {
        if (completion) completion(NO, keyError.localizedDescription ?: @"device_key_create_failed");
        return;
    }
    NSError *publicError = nil;
    NSDictionary *publicJWK = [self devicePublicJWKForPrivateKey:privateKey error:&publicError];
    if (!publicJWK) {
        CFRelease(privateKey);
        if (completion) completion(NO, publicError.localizedDescription ?: @"device_public_key_failed");
        return;
    }

    [self postPath:@"/v1/challenge"
              body:@{@"license_key": normalized, @"device_public_key": publicJWK}
        completion:^(NSDictionary *challengeResponse, NSError *challengeError) {
        if (challengeError) {
            CFRelease(privateKey);
            if (completion) completion(NO, [self diagnosticMessageForError:challengeError
                                                                   fallback:@"license_challenge_failed"]);
            return;
        }
        NSString *challenge = [challengeResponse[@"challenge"] isKindOfClass:[NSString class]] ? challengeResponse[@"challenge"] : @"";
        NSString *challengeId = [challengeResponse[@"challenge_id"] isKindOfClass:[NSString class]] ? challengeResponse[@"challenge_id"] : @"";
        CFErrorRef signError = NULL;
        NSData *signature = CFBridgingRelease(SecKeyCreateSignature(
            privateKey,
            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            (__bridge CFDataRef)[challenge dataUsingEncoding:NSUTF8StringEncoding],
            &signError));
        CFRelease(privateKey);
        if (!signature) {
            NSString *message = signError ? [(__bridge NSError *)signError localizedDescription] : @"device_challenge_sign_failed";
            if (signError) CFRelease(signError);
            if (completion) completion(NO, message);
            return;
        }
        if (signError) CFRelease(signError);
        [self postPath:@"/v1/activate"
                  body:@{
                      @"license_key": normalized,
                      @"challenge_id": challengeId,
                      @"device_public_key": publicJWK,
                      @"signature": [self base64URLEncode:signature],
                  }
            completion:^(NSDictionary *activateResponse, NSError *activateError) {
            if (activateError) {
                if (completion) completion(NO, [self diagnosticMessageForError:activateError
                                                                       fallback:@"license_activation_failed"]);
                return;
            }
            NSError *saveError = nil;
            if (![self saveLease:activateResponse[@"lease"] error:&saveError]) {
                if (completion) completion(NO, saveError.localizedDescription ?: @"license_lease_save_failed");
                return;
            }
            NSDictionary *status = [self localStatus];
            BOOL valid = [status[@"licensed"] boolValue];
            if (completion) completion(valid, valid
                ? [NSString stringWithFormat:@"activated device_key=%@", mode ?: @"unknown"]
                : (status[@"error"] ?: @"license_verify_failed_after_activation"));
        }];
    }];
}

- (void)refreshLeaseWithCompletion:(void (^)(BOOL success, NSString *message))completion
{
    NSData *data = [NSData dataWithContentsOfFile:TLinkLicenseLeasePath()];
    NSDictionary *lease = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![lease isKindOfClass:[NSDictionary class]]) {
        if (completion) completion(NO, @"license_lease_missing");
        return;
    }
    NSString *payload = [lease[@"payload"] isKindOfClass:[NSString class]] ? lease[@"payload"] : @"";
    SecKeyRef privateKey = [self copyExistingDevicePrivateKey];
    if (!privateKey || payload.length == 0) {
        if (privateKey) CFRelease(privateKey);
        if (completion) completion(NO, @"license_device_private_key_or_payload_missing");
        return;
    }
    CFErrorRef signError = NULL;
    NSData *deviceSignature = CFBridgingRelease(SecKeyCreateSignature(
        privateKey,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)[payload dataUsingEncoding:NSUTF8StringEncoding],
        &signError));
    CFRelease(privateKey);
    if (!deviceSignature) {
        NSString *message = signError ? [(__bridge NSError *)signError localizedDescription] : @"license_refresh_sign_failed";
        if (signError) CFRelease(signError);
        if (completion) completion(NO, message);
        return;
    }
    if (signError) CFRelease(signError);
    [self postPath:@"/v1/refresh"
              body:@{
                  @"lease": lease,
                  @"device_signature": [self base64URLEncode:deviceSignature],
              }
        completion:^(NSDictionary *response, NSError *networkError) {
        if (networkError) {
            if (completion) completion(NO, [self diagnosticMessageForError:networkError
                                                                   fallback:@"license_refresh_failed"]);
            return;
        }
        NSError *saveError = nil;
        BOOL saved = [self saveLease:response[@"lease"] error:&saveError];
        if (completion) completion(saved, saved ? @"license_refreshed" : (saveError.localizedDescription ?: @"license_refresh_save_failed"));
    }];
}

- (void)deactivateLeaseWithCompletion:(void (^)(BOOL success, NSString *message))completion
{
    NSData *data = [NSData dataWithContentsOfFile:TLinkLicenseLeasePath()];
    NSDictionary *lease = data.length > 0
        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]
        : nil;
    if (![lease isKindOfClass:[NSDictionary class]]) {
        if (completion) completion(NO, @"license_lease_missing");
        return;
    }
    NSString *payload = [lease[@"payload"] isKindOfClass:[NSString class]] ? lease[@"payload"] : @"";
    SecKeyRef privateKey = [self copyExistingDevicePrivateKey];
    if (!privateKey || payload.length == 0) {
        if (privateKey) CFRelease(privateKey);
        if (completion) completion(NO, @"license_device_private_key_or_payload_missing");
        return;
    }
    CFErrorRef signError = NULL;
    NSData *deviceSignature = CFBridgingRelease(SecKeyCreateSignature(
        privateKey,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)[payload dataUsingEncoding:NSUTF8StringEncoding],
        &signError));
    CFRelease(privateKey);
    if (!deviceSignature) {
        NSString *message = signError
            ? [(__bridge NSError *)signError localizedDescription]
            : @"license_deactivate_sign_failed";
        if (signError) CFRelease(signError);
        if (completion) completion(NO, message);
        return;
    }
    if (signError) CFRelease(signError);

    [self postPath:@"/v1/deactivate"
              body:@{
                  @"lease": lease,
                  @"device_signature": [self base64URLEncode:deviceSignature],
              }
        completion:^(NSDictionary *response, NSError *networkError) {
        (void)response;
        if (networkError) {
            if (completion) completion(NO, [self diagnosticMessageForError:networkError
                                                                   fallback:@"license_deactivate_failed"]);
            return;
        }
        NSError *removeError = nil;
        BOOL removed = [self removeLocalLease:&removeError];
        if (completion) completion(removed,
                                   removed ? @"license_device_deactivated"
                                           : (removeError.localizedDescription ?: @"license_local_lease_remove_failed"));
    }];
}

- (BOOL)removeLocalLease:(NSError **)error
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:TLinkLicenseLeasePath()]) return YES;
    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:TLinkLicenseLeasePath() error:error];
    if (removed) TLinkLicenseAdvanceGeneration();
    return removed;
}

- (BOOL)repairDevicePublicKey:(NSError **)error
{
    SecKeyRef privateKey = [self copyExistingDevicePrivateKey];
    if (!privateKey) {
        if (error) {
            *error = [NSError errorWithDomain:@"TLinkLicense"
                                         code:40
                                     userInfo:@{NSLocalizedDescriptionKey: @"device_private_key_missing_deactivate_or_admin_reset_required"}];
        }
        return NO;
    }
    NSData *before = [NSData dataWithContentsOfFile:TLinkLicenseDevicePublicKeyPath()];
    NSError *publicError = nil;
    NSDictionary *jwk = [self devicePublicJWKForPrivateKey:privateKey error:&publicError];
    CFRelease(privateKey);
    if (![jwk isKindOfClass:[NSDictionary class]]) {
        if (error) *error = publicError;
        return NO;
    }
    NSData *after = [NSData dataWithContentsOfFile:TLinkLicenseDevicePublicKeyPath()];
    if (after.length != 65) {
        if (error) {
            *error = [NSError errorWithDomain:@"TLinkLicense"
                                         code:41
                                     userInfo:@{NSLocalizedDescriptionKey: @"device_public_key_repair_verification_failed"}];
        }
        return NO;
    }
    if (![before isEqualToData:after]) TLinkLicenseAdvanceGeneration();
    return YES;
}

@end
