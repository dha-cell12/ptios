#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <dispatch/dispatch.h>
#include <atomic>
#include <mutex>
#include <thread>
#include <cassert>
#include <cstdio>
#include <cstring>
#import "../shared/TLinkLicenseVerifier.h"
static std::atomic<uint64_t> generation{1}, verifies{0};
static std::atomic<bool> pauseVerify{false};
static dispatch_semaphore_t entered, resumeVerify;
static NSString *buildMode = @"fixture-v1";
uint64_t TLinkLicenseGeneration(void) { return generation.load(); }
NSString *TLinkLicenseBuildMode(void) { return buildMode; }
static bool FixtureVerifySignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef message, CFDataRef signature, CFErrorRef *error) {
    verifies.fetch_add(1);
    if (pauseVerify.exchange(false)) {
        dispatch_semaphore_signal(entered);
        assert(dispatch_semaphore_wait(resumeVerify, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    }
    return SecKeyVerifySignature(key, algorithm, message, signature, error);
}
#include "LicenseArtifactUnderTest.inc"
static SecKeyRef privateKey() CF_RETURNS_RETAINED;
static SecKeyRef privateKey() {
    NSDictionary *attributes = @{(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256};
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, NULL); assert(key); return key;
}
static NSDictionary *configuration(SecKeyRef key) {
    SecKeyRef pub = SecKeyCopyPublicKey(key); assert(pub);
    NSData *point = CFBridgingRelease(SecKeyCopyExternalRepresentation(pub, NULL)); CFRelease(pub);
    assert(point.length == 65);
    return @{@"LicensePublicKeyX": [[point subdataWithRange:NSMakeRange(1,32)] base64EncodedStringWithOptions:0],
        @"LicensePublicKeyY": [[point subdataWithRange:NSMakeRange(33,32)] base64EncodedStringWithOptions:0], @"LicenseKeyID": @"key-a"};
}
static NSData *sign(SecKeyRef key, NSData *message) {
    NSData *signature = CFBridgingRelease(SecKeyCreateSignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)message, NULL));
    assert(signature.length); return signature;
}
static void pauseNext() { entered = dispatch_semaphore_create(0); resumeVerify = dispatch_semaphore_create(0); pauseVerify.store(true); }
static void awaitPaused() { assert(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0); }
int main(int argc, char **argv) {
    assert(argc == 2);
    @autoreleasepool {
        fputs("License artifacts: real P-256 signatures, content/key/generation/epoch separation\n", stderr);
        SecKeyRef key = privateKey(), otherKey = privateKey();
        NSDictionary *config = configuration(key), *wrongKey = configuration(otherKey);
        NSData *message = [@"signed lease fixture" dataUsingEncoding:NSUTF8StringEncoding], *signature = sign(key,message);
        assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); assert(verifies.load() == 1);
        for (unsigned n=0;n<1000;++n) assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL));
        assert(verifies.load() == 1);
        NSMutableData *changed = [message mutableCopy]; ((uint8_t *)changed.mutableBytes)[0] ^= 1;
        assert(!TLinkLicenseVerifyServerArtifact(config,changed,signature,NULL));
        assert(!TLinkLicenseVerifyServerArtifact(config,changed,signature,NULL)); assert(verifies.load() == 3);
        NSMutableData *badSignature = [signature mutableCopy]; ((uint8_t *)badSignature.mutableBytes)[0] ^= 1;
        assert(!TLinkLicenseVerifyServerArtifact(config,message,badSignature,NULL));
        assert(!TLinkLicenseVerifyServerArtifact(wrongKey,message,signature,NULL));
        NSString *error = nil; assert(!TLinkLicenseVerifyServerArtifact(@{},message,signature,&error));
        assert([error isEqual:@"license_server_public_key_invalid"]);
        uint64_t baseline = verifies.load();
        NSMutableDictionary *renamed = [config mutableCopy]; renamed[@"LicenseKeyID"] = @"key-b";
        assert(TLinkLicenseVerifyServerArtifact(renamed,message,signature,NULL)); assert(verifies.load() == baseline + 1);
        assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); assert(verifies.load() == baseline + 2);
        generation.store(2); assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); assert(verifies.load() == baseline + 3);
        TLinkLicenseInvalidateArtifacts(); assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); assert(verifies.load() == baseline + 4);
        buildMode = @"fixture-v2"; assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); assert(verifies.load() == baseline + 5);
        NSData *anotherSignature = sign(key,message); // A different DER signature must also be verified.
        baseline = verifies.load(); assert(TLinkLicenseVerifyServerArtifact(config,message,anotherSignature,NULL));
        if (![anotherSignature isEqualToData:signature]) assert(verifies.load() == baseline + 1);
        fputs("License artifacts: invalidation/mutable-input races cannot poison a cache entry\n", stderr);
        TLinkLicenseInvalidateArtifacts(); pauseNext();
        std::atomic<bool> valid{false};
        std::thread old([&] { @autoreleasepool { valid.store(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); } });
        awaitPaused(); TLinkLicenseInvalidateArtifacts(); dispatch_semaphore_signal(resumeVerify); old.join(); assert(valid.load());
        baseline = verifies.load(); assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); assert(verifies.load() == baseline + 1);
        TLinkLicenseInvalidateArtifacts(); pauseNext(); NSMutableData *mutableMessage = [message mutableCopy];
        std::thread mutation([&] { @autoreleasepool { valid.store(TLinkLicenseVerifyServerArtifact(config,mutableMessage,signature,NULL)); } });
        awaitPaused(); ((uint8_t *)mutableMessage.mutableBytes)[0] ^= 1; dispatch_semaphore_signal(resumeVerify); mutation.join(); assert(valid.load());
        baseline = verifies.load(); assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); assert(verifies.load() == baseline);
        assert(!TLinkLicenseVerifyServerArtifact(config,mutableMessage,signature,NULL));
        TLinkLicenseInvalidateArtifacts(); pauseNext();
        std::thread movedGeneration([&] { @autoreleasepool { valid.store(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); } });
        awaitPaused(); generation.fetch_add(1); dispatch_semaphore_signal(resumeVerify); movedGeneration.join(); assert(valid.load());
        baseline = verifies.load(); assert(TLinkLicenseVerifyServerArtifact(config,message,signature,NULL)); assert(verifies.load() == baseline + 1);
        NSMutableData *large = [NSMutableData dataWithLength:1024*1024+1]; NSData *largeSignature = sign(key,large);
        baseline = verifies.load(); assert(TLinkLicenseVerifyServerArtifact(config,large,largeSignature,NULL));
        assert(TLinkLicenseVerifyServerArtifact(config,large,largeSignature,NULL)); assert(verifies.load() == baseline + 2);
        fputs("License artifacts: real plist replacements/deletion and cache invalidation\n", stderr);
        NSString *path = [[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"Config.plist"];
        NSData *one = [NSPropertyListSerialization dataWithPropertyList:@{@"value": @"one"} format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        NSData *two = [NSPropertyListSerialization dataWithPropertyList:@{@"value": @"two"} format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        assert(one.length == two.length && [one writeToFile:path atomically:NO]);
        assert([TLinkLicenseConfigurationAtPath(path)[@"value"] isEqual:@"one"]);
        baseline = sTLinkLicenseConfigHits.load(); assert([TLinkLicenseConfigurationAtPath(path)[@"value"] isEqual:@"one"]);
        assert(sTLinkLicenseConfigHits.load() == baseline + 1);
        NSDictionary *before = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        assert([two writeToFile:path atomically:NO]);
        assert([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: before[NSFileModificationDate]} ofItemAtPath:path error:NULL]);
        assert([TLinkLicenseConfigurationAtPath(path)[@"value"] isEqual:@"two"]);
        generation.fetch_add(1); baseline = sTLinkLicenseConfigHits.load(); (void)TLinkLicenseConfigurationAtPath(path); assert(sTLinkLicenseConfigHits.load() == baseline);
        TLinkLicenseInvalidateArtifacts(); (void)TLinkLicenseConfigurationAtPath(path); assert(sTLinkLicenseConfigHits.load() == baseline);
        NSString *otherPath = [path stringByAppendingString:@".other"]; assert([two writeToFile:otherPath atomically:NO]);
        (void)TLinkLicenseConfigurationAtPath(otherPath); assert(sTLinkLicenseConfigHits.load() == baseline);
        assert([NSFileManager.defaultManager removeItemAtPath:otherPath error:NULL]); assert(!TLinkLicenseConfigurationAtPath(otherPath));
        assert([[@"broken" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO]); assert(!TLinkLicenseConfigurationAtPath(path));
        assert([TLinkLicenseArtifactPerformance()[@"signature_hit_count"] unsignedLongLongValue] >= 1000);
        CFRelease(key); CFRelease(otherKey);
        puts("License artifacts passed: real P-256 verification, invalid signatures, key/build/generation/epoch changes, stale insertions, mutable inputs, oversize uncached verification and exact plist content changes.");
    }
}
