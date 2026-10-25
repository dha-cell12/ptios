#import "TLinkHelperRPCFingerprint.h"
#import <CommonCrypto/CommonDigest.h>

static bool TLinkHelperRPCSHAUpdate(void *context,const uint8_t *bytes,size_t length){
    return CC_SHA256_Update(static_cast<CC_SHA256_CTX *>(context),bytes,static_cast<CC_LONG>(length))==1;
}
@interface TLinkHelperRPCDigestStream : NSOutputStream {
    CC_SHA256_CTX _tlinkHash;
    TLinkHelperRPCDigestFeed _tlinkFeed;
    NSStreamStatus _tlinkStatus;
    NSError *_tlinkError;
    __weak id<NSStreamDelegate> _tlinkDelegate;
}
- (void)fail;
- (bool)finishDigest:(TLinkHelperRPCFingerprintDigest &)digest;
- (TLinkHelperRPCFingerprintStats)fingerprintStats;
@end
@implementation TLinkHelperRPCDigestStream
- (instancetype)init {
    self=[super init];
    if(self){_tlinkStatus=NSStreamStatusNotOpen;if(CC_SHA256_Init(&_tlinkHash)!=1)[self fail];}
    return self;
}
- (void)fail {
    _tlinkStatus=NSStreamStatusError;
    _tlinkError=[NSError errorWithDomain:@"com.tlinkauto.helper-rpc-fingerprint" code:1
                              userInfo:@{NSLocalizedDescriptionKey:@"fingerprint stream failed or exceeded byte limit"}];
}
- (void)open {if(_tlinkStatus==NSStreamStatusNotOpen)_tlinkStatus=NSStreamStatusOpen;}
- (void)close {_tlinkStatus=NSStreamStatusClosed;}
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)length {
    if(_tlinkStatus!=NSStreamStatusOpen||!_tlinkFeed.append(buffer,length,TLinkHelperRPCSHAUpdate,&_tlinkHash)){
        [self fail];return -1;
    }
    return static_cast<NSInteger>(length);
}
- (BOOL)hasSpaceAvailable {return _tlinkStatus==NSStreamStatusOpen;}
- (NSStreamStatus)streamStatus {return _tlinkStatus;}
- (NSError *)streamError {return _tlinkError;}
- (id<NSStreamDelegate>)delegate {return _tlinkDelegate;}
- (void)setDelegate:(id<NSStreamDelegate>)delegate {_tlinkDelegate=delegate;}
- (id)propertyForKey:(NSString *)key {(void)key;return nil;}
- (BOOL)setProperty:(id)property forKey:(NSString *)key {(void)property;(void)key;return false;}
- (void)scheduleInRunLoop:(NSRunLoop *)loop forMode:(NSString *)mode {(void)loop;(void)mode;}
- (void)removeFromRunLoop:(NSRunLoop *)loop forMode:(NSString *)mode {(void)loop;(void)mode;}
- (bool)finishDigest:(TLinkHelperRPCFingerprintDigest &)digest {
    if(_tlinkStatus!=NSStreamStatusOpen||!_tlinkFeed.finish())return false;
    TLinkHelperRPCFingerprintDigest candidate;
    if(CC_SHA256_Final(candidate.data(),&_tlinkHash)!=1){[self fail];return false;}
    digest=candidate;_tlinkStatus=NSStreamStatusAtEnd;return true;
}
- (TLinkHelperRPCFingerprintStats)fingerprintStats {
    auto stats=_tlinkFeed.stats();stats.failed=stats.failed||_tlinkError!=nil;return stats;
}
@end
bool TLinkHelperRPCFingerprint(NSArray *arguments,TLinkHelperRPCFingerprintDigest &digest,TLinkHelperRPCFingerprintStats *stats){
    @autoreleasepool {
        TLinkHelperRPCDigestStream *stream=[[TLinkHelperRPCDigestStream alloc] init];bool ok=false;
        @try {
            [stream open];
            const NSInteger count=[NSJSONSerialization writeJSONObject:arguments toStream:stream options:NSJSONWritingSortedKeys error:nil];
            ok=count>0&&static_cast<size_t>(count)==[stream fingerprintStats].bytes&&[stream finishDigest:digest];
        } @catch(NSException *exception){(void)exception;ok=false;}
        @finally {
            if(stats){*stats=[stream fingerprintStats];stats->failed=stats->failed||!ok;}
            [stream close];
        }
        return ok;
    }
}
