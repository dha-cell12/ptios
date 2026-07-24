#import "TLinkLicenseVerifier.h"
#import <Security/Security.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const kTLinkLicenseDirectory = @"/var/mobile/Library/TLinkauto/license";
static NSString *const kTLinkLicenseLease = @"/var/mobile/Library/TLinkauto/license/lease.json";
static NSString *const kTLinkLicenseDevicePublicKey = @"/var/mobile/Library/TLinkauto/license/device_public_key.bin";
static NSString *const kTLinkLicenseDeviceKeyTag = @"com.tlinkauto.streamcontrol.license-device-key.v1";
static NSString *const kTLinkLicenseGeneration = @"/var/mobile/Library/TLinkauto/license/generation";
static NSString *const kTLinkLicenseGenerationLock = @"/var/mobile/Library/TLinkauto/license/generation.lock";
static NSString *const kTLinkLicenseQuarantineDirectory = @"/var/mobile/Library/TLinkauto/license/quarantine";
static NSString *const kTLinkLicenseRecoveryDiagnostics = @"/var/mobile/Library/TLinkauto/license/recovery.plist";
static const NSTimeInterval kTLinkLicenseClockSkewToleranceSeconds = 60.0;
static const char *kTLinkLicenseDarwinNotification = "com.tlinkauto.license.changed";
static NSDictionary *sTLinkLicenseFeatureStatus = nil;
static NSTimeInterval sTLinkLicenseFeatureStatusAt = 0;
static uint64_t sTLinkLicenseFeatureGeneration = 0;
static int sTLinkLicenseNotificationToken = 0;

static dispatch_queue_t TLinkLicenseCacheQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tlinkauto.license-verifier-cache", DISPATCH_QUEUE_SERIAL);
        notify_register_dispatch(kTLinkLicenseDarwinNotification,
                                 &sTLinkLicenseNotificationToken,
                                 dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                 ^(__unused int token) {
            TLinkLicenseInvalidateCache();
        });
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

NSString *TLinkLicenseGenerationPath(void)
{
    return kTLinkLicenseGeneration;
}

uint64_t TLinkLicenseGeneration(void)
{
    NSString *value = [NSString stringWithContentsOfFile:kTLinkLicenseGeneration
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    const char *text = [value UTF8String];
    if (!text || !text[0]) {
        return 0;
    }

    errno = 0;
    char *end = NULL;
    unsigned long long generation = strtoull(text, &end, 10);
    if (errno == ERANGE || end == text) {
        return 0;
    }
    while (*end && isspace((unsigned char)*end)) {
        end++;
    }
    return *end == '\0' && generation > 0 ? (uint64_t)generation : 0;
}

uint64_t TLinkLicenseAdvanceGeneration(void)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:kTLinkLicenseDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    int lockFD = open([kTLinkLicenseGenerationLock fileSystemRepresentation], O_CREAT | O_RDWR, 0666);
    if (lockFD < 0) {
        return TLinkLicenseGeneration();
    }
    chmod([kTLinkLicenseGenerationLock fileSystemRepresentation], 0666);
    flock(lockFD, LOCK_EX);

    uint64_t current = TLinkLicenseGeneration();
    uint64_t next = current == UINT64_MAX ? 1 : current + 1;
    BOOL written = [[NSString stringWithFormat:@"%llu\n", (unsigned long long)next]
        writeToFile:kTLinkLicenseGeneration
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];

    flock(lockFD, LOCK_UN);
    close(lockFD);
    TLinkLicenseInvalidateCache();
    notify_post(kTLinkLicenseDarwinNotification);
    return written ? next : current;
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

static BOOL TLinkBundlePathMatchesApplication(NSString *path)
{
    if (path.length == 0) return NO;
    NSString *plistPath = [path stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    return [info[@"CFBundleIdentifier"] isEqualToString:@"com.tlinkauto.streamcontrol"];
}

static NSString *TLinkBundlePathFromObject(id value)
{
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value path];
    if ([value isKindOfClass:[NSString class]]) return value;
    return nil;
}

static NSString *TLinkBundlePathFromLaunchServices(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *frameworks[] = {
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            "/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
        };
        for (size_t i = 0; i < sizeof(frameworks) / sizeof(frameworks[0]); i++) {
            dlopen(frameworks[i], RTLD_LAZY | RTLD_GLOBAL);
        }
    });

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:proxySelector]) return nil;

    id proxy = nil;
    @try {
        proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass,
                                                    proxySelector,
                                                    @"com.tlinkauto.streamcontrol");
    } @catch (__unused NSException *exception) {
        return nil;
    }
    if (!proxy) return nil;

    NSArray<NSString *> *selectorNames = @[@"bundleURL", @"bundlePath", @"path", @"resourcesDirectoryURL"];
    for (NSString *selectorName in selectorNames) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![proxy respondsToSelector:selector]) continue;
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(proxy, selector);
            NSString *path = TLinkBundlePathFromObject(value);
            if (TLinkBundlePathMatchesApplication(path)) return [path stringByStandardizingPath];
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static NSString *TLinkBundlePathByScanningContainers(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *directCandidates = @[
        @"/Applications/StreamControl.app",
        @"/var/containers/Bundle/Application/StreamControl.app",
        @"/private/var/containers/Bundle/Application/StreamControl.app",
    ];
    for (NSString *candidate in directCandidates) {
        if (TLinkBundlePathMatchesApplication(candidate)) return [candidate stringByStandardizingPath];
    }

    NSArray<NSString *> *roots = @[
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application",
    ];
    for (NSString *root in roots) {
        NSArray<NSString *> *containers = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *container in containers) {
            NSString *containerPath = [root stringByAppendingPathComponent:container];
            NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:containerPath error:nil];
            for (NSString *entry in entries) {
                if (![[[entry pathExtension] lowercaseString] isEqualToString:@"app"]) continue;
                NSString *candidate = [containerPath stringByAppendingPathComponent:entry];
                if (TLinkBundlePathMatchesApplication(candidate)) return [candidate stringByStandardizingPath];
            }
        }
    }
    return nil;
}

NSString *TLinkInstalledApplicationBundlePath(void)
{
    static NSString *cachedPath = nil;
    @synchronized ([NSProcessInfo processInfo]) {
        if (TLinkBundlePathMatchesApplication(cachedPath)) return cachedPath;
        cachedPath = nil;
    }

    NSString *mainBundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *resolvedPath = nil;
    if (TLinkBundlePathMatchesApplication(mainBundlePath)) resolvedPath = [mainBundlePath stringByStandardizingPath];

    if (resolvedPath.length == 0) {
        NSString *executableDirectory = TLinkExecutableDirectory();
        if (TLinkBundlePathMatchesApplication(executableDirectory)) resolvedPath = [executableDirectory stringByStandardizingPath];
    }

    if (resolvedPath.length == 0) resolvedPath = TLinkBundlePathFromLaunchServices();
    if (resolvedPath.length == 0) resolvedPath = TLinkBundlePathByScanningContainers();

    @synchronized ([NSProcessInfo processInfo]) {
        cachedPath = [resolvedPath copy];
    }
    return resolvedPath;
}

NSString *TLinkBundledExecutablePath(NSString *name)
{
    if (name.length == 0 || ![[name lastPathComponent] isEqualToString:name]) return nil;
    NSString *bundlePath = TLinkInstalledApplicationBundlePath();
    NSString *path = [bundlePath stringByAppendingPathComponent:name];
    return [[NSFileManager defaultManager] isExecutableFileAtPath:path] ? path : nil;
}

NSDictionary *TLinkLicenseConfiguration(void)
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSString *executableDirectory = TLinkExecutableDirectory();
    if (executableDirectory.length > 0) {
        [candidates addObject:[executableDirectory stringByAppendingPathComponent:@"LicenseConfig.plist"]];
    }
    NSString *installedBundlePath = TLinkInstalledApplicationBundlePath();
    if (installedBundlePath.length > 0) {
        NSString *installedConfig = [installedBundlePath stringByAppendingPathComponent:@"LicenseConfig.plist"];
        if (![candidates containsObject:installedConfig]) [candidates addObject:installedConfig];
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

typedef unsigned char *(*TLinkCCSHA256Fn)(const void *data, uint32_t length, unsigned char *digest);

static TLinkCCSHA256Fn TLinkResolveSHA256(void)
{
    static TLinkCCSHA256Fn function = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        function = (TLinkCCSHA256Fn)dlsym(RTLD_DEFAULT, "CC_SHA256");
        if (function) return;
        const char *paths[] = {
            "/usr/lib/system/libcommonCrypto.dylib",
            "/usr/lib/libcommonCrypto.dylib",
        };
        for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
            void *handle = dlopen(paths[i], RTLD_LAZY | RTLD_LOCAL);
            if (!handle) continue;
            function = (TLinkCCSHA256Fn)dlsym(handle, "CC_SHA256");
            if (function) break;
        }
    });
    return function;
}

static NSString *TLinkSHA256Base64URL(NSData *data)
{
    if (data.length == 0 || data.length > UINT32_MAX) return nil;
    TLinkCCSHA256Fn sha256 = TLinkResolveSHA256();
    if (!sha256) return nil;
    unsigned char digest[32] = {0};
    if (!sha256(data.bytes, (uint32_t)data.length, digest)) return nil;
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

NSString *TLinkLicenseBuildMode(void)
{
#if defined(TLINK_LICENSE_FORCE_ENFORCEMENT) && TLINK_LICENSE_FORCE_ENFORCEMENT
    return @"enforced_compile_time_v1";
#else
    return @"observe_compile_time_v1";
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
    NSDictionary *recovery = [NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseRecoveryDiagnostics];
    return @{
        @"configured": @(TLinkLicenseConfigValueUsable(endpoint) &&
                          TLinkLicenseConfigValueUsable(x) &&
                          TLinkLicenseConfigValueUsable(y)),
        @"enforcement_enabled": @(enforcement),
        @"build_mode": TLinkLicenseBuildMode(),
        @"effective_access": @(!enforcement),
        @"licensed": @NO,
        @"state": state ?: @"invalid",
        @"error": error ?: @"license_invalid",
        @"endpoint": endpoint,
        @"lease_path": kTLinkLicenseLease,
        @"device_public_key_path": kTLinkLicenseDevicePublicKey,
        @"device_key_proof": @NO,
        @"features": @[],
        @"clock_skew_tolerance_seconds": @(kTLinkLicenseClockSkewToleranceSeconds),
        @"recovery": [recovery isKindOfClass:[NSDictionary class]] ? recovery : @{},
        @"license_generation": @(TLinkLicenseGeneration()),
        @"last_checked_at_ms": @((uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0)),
        @"source": @"shared_verifier_disk",
    };
}

static NSDictionary *TLinkLicenseFailureWithPayload(NSDictionary *config,
                                                     NSString *state,
                                                     NSString *error,
                                                     NSDictionary *payload,
                                                     NSDictionary *lease,
                                                     NSInteger contractVersion)
{
    NSMutableDictionary *status = [TLinkLicenseFailure(config, state, error) mutableCopy];
    NSTimeInterval licenseExpiresAt = [payload[@"license_expires_at"] doubleValue];
    [status addEntriesFromDictionary:@{
        @"license_contract_version": @(contractVersion),
        @"license_id": payload[@"license_id"] ?: @"",
        @"device_id": payload[@"device_id"] ?: @"",
        @"token_id": payload[@"token_id"] ?: @"",
        @"issued_at": payload[@"issued_at"] ?: @0,
        @"expires_at": payload[@"expires_at"] ?: @0,
        @"lease_expires_at": payload[@"expires_at"] ?: @0,
        @"offline_until": payload[@"offline_until"] ?: @0,
        @"license_expires_at": payload[@"license_expires_at"] ?: @0,
        @"lease_policy_seconds": payload[@"lease_policy_seconds"] ?: @0,
        @"offline_grace_policy_seconds": payload[@"offline_grace_policy_seconds"] ?: @0,
        @"renewal_mode": payload[@"renewal_mode"] ?: @"legacy_lease",
        @"license_expiration_mode": licenseExpiresAt > 0 ? @"fixed" : @"perpetual",
        @"features": [payload[@"features"] isKindOfClass:[NSArray class]] ? payload[@"features"] : @[],
        @"key_id": lease[@"key_id"] ?: @"",
        @"device_key_hash": payload[@"device_key_hash"] ?: @"",
    }];
    return status;
}

static NSString *TLinkQuarantineCorruptLease(NSString *reason)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:kTLinkLicenseQuarantineDirectory
  withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];

    int lockFD = open([kTLinkLicenseGenerationLock fileSystemRepresentation], O_CREAT | O_RDWR, 0666);
    if (lockFD < 0) {
        NSDictionary *lockFailure = @{
            @"state": @"quarantine_lock_failed",
            @"reason": reason ?: @"license_corrupt",
            @"errno": @(errno),
            @"source": @"shared_verifier",
        };
        [lockFailure writeToFile:kTLinkLicenseRecoveryDiagnostics atomically:YES];
        return @"";
    }
    chmod([kTLinkLicenseGenerationLock fileSystemRepresentation], 0666);
    flock(lockFD, LOCK_EX);

    uint64_t nowMs = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
    NSString *destination = [kTLinkLicenseQuarantineDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"lease-%llu-%d.json.invalid",
         (unsigned long long)nowMs,
         (int)getpid()]];
    BOOL moved = [fm fileExistsAtPath:kTLinkLicenseLease] &&
        [fm moveItemAtPath:kTLinkLicenseLease toPath:destination error:nil];
    NSDictionary *diagnostics = @{
        @"state": moved ? @"quarantined" : @"quarantine_not_needed_or_failed",
        @"reason": reason ?: @"license_corrupt",
        @"quarantined_at_ms": @(nowMs),
        @"quarantine_path": moved ? destination : @"",
        @"source": @"shared_verifier",
    };
    NSDictionary *existingDiagnostics = [NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseRecoveryDiagnostics];
    if (moved || ![existingDiagnostics isKindOfClass:[NSDictionary class]]) {
        [diagnostics writeToFile:kTLinkLicenseRecoveryDiagnostics atomically:YES];
        chmod([kTLinkLicenseRecoveryDiagnostics fileSystemRepresentation], 0666);
    }

    if (moved) {
        uint64_t current = TLinkLicenseGeneration();
        uint64_t next = current == UINT64_MAX ? 1 : current + 1;
        [[NSString stringWithFormat:@"%llu\n", (unsigned long long)next]
            writeToFile:kTLinkLicenseGeneration
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
    }

    flock(lockFD, LOCK_UN);
    close(lockFD);
    if (moved) notify_post(kTLinkLicenseDarwinNotification);
    return moved ? destination : @"";
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
        TLinkQuarantineCorruptLease(@"license_lease_json_invalid");
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
        TLinkQuarantineCorruptLease(@"license_lease_fields_invalid");
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
        TLinkQuarantineCorruptLease(@"license_signature_invalid");
        return TLinkLicenseFailure(config, @"invalid", verifyDescription.length > 0 ? verifyDescription : @"license_signature_invalid");
    }

    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        TLinkQuarantineCorruptLease(@"license_payload_json_invalid");
        return TLinkLicenseFailure(config, @"invalid", @"license_payload_json_invalid");
    }
    NSString *product = [payload[@"product"] isKindOfClass:[NSString class]] ? payload[@"product"] : @"";
    if (![product isEqualToString:@"tlinkauto"] || [payload[@"version"] integerValue] != 1) {
        return TLinkLicenseFailure(config, @"invalid", @"license_payload_product_or_version_mismatch");
    }
    id contractValue = payload[@"license_contract_version"];
    NSInteger contractVersion = 1;
    if (contractValue && contractValue != [NSNull null]) {
        contractVersion = [contractValue integerValue];
    }
    if (contractVersion != 1) {
        return TLinkLicenseFailure(config, @"invalid", @"license_contract_version_unsupported");
    }
    NSData *devicePublicKey = [NSData dataWithContentsOfFile:kTLinkLicenseDevicePublicKey];
    NSString *expectedDeviceHash = [payload[@"device_key_hash"] isKindOfClass:[NSString class]] ? payload[@"device_key_hash"] : @"";
    NSString *actualDeviceHash = TLinkSHA256Base64URL(devicePublicKey);
    if (devicePublicKey.length > 0 && actualDeviceHash.length == 0) {
        return TLinkLicenseFailureWithPayload(config, @"invalid", @"license_sha256_runtime_unavailable",
                                              payload, lease, contractVersion);
    }
    if (devicePublicKey.length == 0 || ![actualDeviceHash isEqualToString:expectedDeviceHash]) {
        return TLinkLicenseFailureWithPayload(config, @"device_mismatch", @"license_device_key_mismatch",
                                              payload, lease, contractVersion);
    }
    NSString *deviceProofError = nil;
    if (!TLinkVerifyDeviceKeyPossession(devicePublicKey, &deviceProofError)) {
        return TLinkLicenseFailureWithPayload(config, @"device_mismatch",
                                              deviceProofError ?: @"license_device_proof_failed",
                                              payload, lease, contractVersion);
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval notBefore = [payload[@"not_before"] doubleValue];
    NSTimeInterval expiresAt = [payload[@"expires_at"] doubleValue];
    NSTimeInterval offlineUntil = [payload[@"offline_until"] doubleValue];
    NSTimeInterval licenseExpiresAt = [payload[@"license_expires_at"] doubleValue];
    if (notBefore > 0 && now + kTLinkLicenseClockSkewToleranceSeconds < notBefore) {
        return TLinkLicenseFailureWithPayload(config, @"not_yet_valid", @"license_not_before_in_future",
                                              payload, lease, contractVersion);
    }
    if (licenseExpiresAt > 0 && now > licenseExpiresAt) {
        return TLinkLicenseFailureWithPayload(config, @"expired", @"license_expiration_reached",
                                              payload, lease, contractVersion);
    }
    if (offlineUntil <= 0 || now > offlineUntil) {
        return TLinkLicenseFailureWithPayload(config, @"expired", @"license_offline_grace_expired",
                                              payload, lease, contractVersion);
    }

    NSArray *features = [payload[@"features"] isKindOfClass:[NSArray class]] ? payload[@"features"] : @[];
    BOOL enforcement = TLinkLicenseConfiguredEnforcement(config);
    NSString *state = expiresAt > 0 && now > expiresAt ? @"offline_grace" : @"valid";
    return @{
        @"configured": @YES,
        @"enforcement_enabled": @(enforcement),
        @"build_mode": TLinkLicenseBuildMode(),
        @"effective_access": @YES,
        @"licensed": @YES,
        @"state": state,
        @"error": @"",
        @"endpoint": endpoint,
        @"lease_path": kTLinkLicenseLease,
        @"device_public_key_path": kTLinkLicenseDevicePublicKey,
        @"device_key_proof": @YES,
        @"license_contract_version": @(contractVersion),
        @"license_id": payload[@"license_id"] ?: @"",
        @"device_id": payload[@"device_id"] ?: @"",
        @"token_id": payload[@"token_id"] ?: @"",
        @"issued_at": payload[@"issued_at"] ?: @0,
        @"expires_at": payload[@"expires_at"] ?: @0,
        @"lease_expires_at": payload[@"expires_at"] ?: @0,
        @"offline_until": payload[@"offline_until"] ?: @0,
        @"license_expires_at": payload[@"license_expires_at"] ?: @0,
        @"lease_policy_seconds": payload[@"lease_policy_seconds"] ?: @0,
        @"offline_grace_policy_seconds": payload[@"offline_grace_policy_seconds"] ?: @0,
        @"renewal_mode": payload[@"renewal_mode"] ?: @"legacy_lease",
        @"license_expiration_mode": licenseExpiresAt > 0 ? @"fixed" : @"perpetual",
        @"features": features,
        @"clock_skew_tolerance_seconds": @(kTLinkLicenseClockSkewToleranceSeconds),
        @"recovery": @{},
        @"key_id": lease[@"key_id"] ?: @"",
        @"device_key_hash": expectedDeviceHash,
        @"license_generation": @(TLinkLicenseGeneration()),
        @"last_checked_at_ms": @((uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0)),
        @"source": @"shared_verifier_disk",
    };
}

BOOL TLinkLicenseFeatureAllowed(NSString *feature, NSString **error)
{
    __block NSDictionary *status = nil;
    uint64_t generation = TLinkLicenseGeneration();
    dispatch_sync(TLinkLicenseCacheQueue(), ^{
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!sTLinkLicenseFeatureStatus ||
            sTLinkLicenseFeatureGeneration != generation ||
            now - sTLinkLicenseFeatureStatusAt >= 5.0) {
            sTLinkLicenseFeatureStatus = TLinkLicenseStatusDictionary();
            sTLinkLicenseFeatureStatusAt = now;
            sTLinkLicenseFeatureGeneration = generation;
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
        sTLinkLicenseFeatureGeneration = 0;
    });
}
