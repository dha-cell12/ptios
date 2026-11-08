#import "TLinkPersistenceJSON.h"
#include "TLinkPersistenceJSONQuota.h"

@interface TLinkPersistenceJSONStream : NSOutputStream {
    TLinkPersistenceJSONQuota _quota;
    NSMutableData *_data;
    NSStreamStatus _state;
    NSError *_failure;
    __weak id<NSStreamDelegate> _streamDelegate;
}
- (instancetype)initWithLimit:(NSUInteger)limit;
- (NSData *)takeData;
- (NSUInteger)byteCount;
- (BOOL)failed;
@end
@implementation TLinkPersistenceJSONStream
- (instancetype)initWithLimit:(NSUInteger)limit {
    self=[super init];if(self){_quota=TLinkPersistenceJSONQuota(limit);_data=[NSMutableData data];_state=NSStreamStatusNotOpen;if(!_data)return nil;}return self;
}
- (void)open {if(_state==NSStreamStatusNotOpen)_state=NSStreamStatusOpen;}
- (void)close {_state=NSStreamStatusClosed;_data=nil;}
- (NSInteger)fail {
    _quota.fail();_state=NSStreamStatusError;
    _failure=[NSError errorWithDomain:@"TLinkPersistenceJSON" code:1 userInfo:nil];return -1;
}
- (NSInteger)write:(const uint8_t *)bytes maxLength:(NSUInteger)length {
    if(_state!=NSStreamStatusOpen||(!bytes&&length)||length>(NSUInteger)NSIntegerMax||!_quota.append(length))return [self fail];
    if(length)[_data appendBytes:bytes length:length];
    return (NSInteger)length;
}
// Permit one write attempt at the exact quota to distinguish EOF from overflow.
- (BOOL)hasSpaceAvailable {return _state==NSStreamStatusOpen&&!_quota.failed();}
- (NSStreamStatus)streamStatus {return _state;}
- (NSError *)streamError {return _failure;}
- (NSUInteger)byteCount {return _quota.size();}
- (BOOL)failed {return _quota.failed();}
- (NSData *)takeData {
    if(_state!=NSStreamStatusOpen||_quota.failed())return nil;
    NSData *result=_data;_data=nil;_state=NSStreamStatusAtEnd;return result;
}
- (id<NSStreamDelegate>)delegate {return _streamDelegate;}
- (void)setDelegate:(id<NSStreamDelegate>)delegate {_streamDelegate=delegate;}
- (id)propertyForKey:(NSStreamPropertyKey)key {(void)key;return nil;}
- (BOOL)setProperty:(id)value forKey:(NSStreamPropertyKey)key {(void)value;(void)key;return NO;}
- (void)scheduleInRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode {(void)loop;(void)mode;}
- (void)removeFromRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode {(void)loop;(void)mode;}
@end

using TLinkPersistenceJSONWriter=NSInteger (*)(id,NSOutputStream *,NSJSONWritingOptions,NSError *__autoreleasing *);
static NSInteger TLinkPersistenceJSONWrite(id object,NSOutputStream *stream,NSJSONWritingOptions options,NSError *__autoreleasing *error){
    return [NSJSONSerialization writeJSONObject:object toStream:stream options:options error:error];
}
static NSData *TLinkPersistenceJSONWithWriter(id object,NSJSONWritingOptions options,NSUInteger limit,TLinkPersistenceJSONWriter writer){
    if(!writer)return nil;
    @autoreleasepool {
        TLinkPersistenceJSONStream *stream=[[TLinkPersistenceJSONStream alloc] initWithLimit:limit];if(!stream)return nil;
        @try {
            [stream open];NSError *error=nil;
            const NSInteger written=writer(object,stream,options,&error);
            if(written<=0||error||stream.failed||stream.streamStatus!=NSStreamStatusOpen||stream.byteCount!=(NSUInteger)written)return nil;
            return [stream takeData];
        } @finally {[stream close];}
    }
}
NSData *TLinkPersistenceJSONData(id object,NSJSONWritingOptions options,NSUInteger limit){
    return TLinkPersistenceJSONWithWriter(object,options,limit,TLinkPersistenceJSONWrite);
}
