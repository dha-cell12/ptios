#import "TLinkPersistenceJSON.h"
#include "TLinkPersistenceJSONQuota.h"
#include "TLinkPersistenceJSONBuffer.h"
#include <memory>

using TLinkPersistenceJSONDataFactory=NSData *(*)(const std::shared_ptr<TLinkPersistenceJSONStorage::Buffer> &);
static NSData *TLinkPersistenceJSONCreateData(const std::shared_ptr<TLinkPersistenceJSONStorage::Buffer> &owner){
    auto storage=owner;
    if(!storage||!storage->size()||!storage->data())return nil;
    return [[NSData alloc] initWithBytesNoCopy:const_cast<uint8_t *>(storage->data()) length:storage->size()
        deallocator:^(void *bytes,NSUInteger length){(void)bytes;(void)length;storage->release();}];
}

@interface TLinkPersistenceJSONStream : NSOutputStream {
    TLinkPersistenceJSONQuota _quota;
    TLinkPersistenceJSONStorage::Buffer _buffer;
    NSUInteger _byteCount;
    NSStreamStatus _state;
    NSError *_failure;
    __weak id<NSStreamDelegate> _streamDelegate;
}
- (instancetype)initWithLimit:(NSUInteger)limit;
- (instancetype)initWithLimit:(NSUInteger)limit allocator:(TLinkPersistenceJSONStorage::Allocator)allocator;
- (NSData *)takeData:(TLinkPersistenceJSONDataFactory)factory;
- (NSUInteger)retainedCapacity;
- (NSData *)takeData;
- (NSUInteger)byteCount;
- (BOOL)failed;
@end
@implementation TLinkPersistenceJSONStream
- (instancetype)initWithLimit:(NSUInteger)limit {
    return [self initWithLimit:limit allocator:TLinkPersistenceJSONStorage::Allocator()];
}
- (instancetype)initWithLimit:(NSUInteger)limit allocator:(TLinkPersistenceJSONStorage::Allocator)allocator {
    self=[super init];
    if(self){_quota=TLinkPersistenceJSONQuota(limit);_buffer=TLinkPersistenceJSONStorage::Buffer(limit,allocator);_state=NSStreamStatusNotOpen;}
    return self;
}
- (void)open {if(_state==NSStreamStatusNotOpen)_state=NSStreamStatusOpen;}
- (void)close {_state=NSStreamStatusClosed;_buffer.release();}
- (NSInteger)fail {
    _quota.fail();_state=NSStreamStatusError;
    _failure=[NSError errorWithDomain:@"TLinkPersistenceJSON" code:1 userInfo:nil];return -1;
}
- (NSInteger)write:(const uint8_t *)bytes maxLength:(NSUInteger)length {
    if(_state!=NSStreamStatusOpen||(!bytes&&length)||length>(NSUInteger)NSIntegerMax||!_quota.append(length))return [self fail];
    if(!_buffer.append(bytes,length))return [self fail];
    _byteCount=_buffer.size();
    return (NSInteger)length;
}
// Permit one write attempt at the exact quota to distinguish EOF from overflow.
- (BOOL)hasSpaceAvailable {return _state==NSStreamStatusOpen&&!_quota.failed();}
- (NSStreamStatus)streamStatus {return _state;}
- (NSError *)streamError {return _failure;}
- (NSUInteger)byteCount {return _byteCount;}
- (NSUInteger)retainedCapacity {return _buffer.capacity();}
- (BOOL)failed {return _quota.failed();}
- (NSData *)takeData {
    return [self takeData:TLinkPersistenceJSONCreateData];
}
- (NSData *)takeData:(TLinkPersistenceJSONDataFactory)factory {
    if(!factory||_state!=NSStreamStatusOpen||_quota.failed()||!_buffer.seal())return nil;
    auto owner=std::make_shared<TLinkPersistenceJSONStorage::Buffer>(std::move(_buffer));
    _state=NSStreamStatusAtEnd;
    return factory(owner);
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
static NSData *TLinkPersistenceJSONWithWriter(id object,NSJSONWritingOptions options,NSUInteger limit,TLinkPersistenceJSONWriter writer,
    TLinkPersistenceJSONDataFactory factory=TLinkPersistenceJSONCreateData,
    TLinkPersistenceJSONStorage::Allocator allocator=TLinkPersistenceJSONStorage::Allocator()){
    if(!writer||!factory)return nil;
    @autoreleasepool {
        TLinkPersistenceJSONStream *stream=[[TLinkPersistenceJSONStream alloc] initWithLimit:limit allocator:allocator];if(!stream)return nil;
        @try {
            [stream open];NSError *error=nil;
            const NSInteger written=writer(object,stream,options,&error);
            if(written<=0||error||stream.failed||stream.streamStatus!=NSStreamStatusOpen||stream.byteCount!=(NSUInteger)written)return nil;
            NSData *result=[stream takeData:factory];
            return result&&result.length==(NSUInteger)written?result:nil;
        } @finally {[stream close];}
    }
}
NSData *TLinkPersistenceJSONData(id object,NSJSONWritingOptions options,NSUInteger limit){
    return TLinkPersistenceJSONWithWriter(object,options,limit,TLinkPersistenceJSONWrite);
}
