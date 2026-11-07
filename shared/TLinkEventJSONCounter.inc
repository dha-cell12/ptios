// Private to TLinkEventChannel.mm. Synchronous JSON counting retains no chunks.
@interface TLinkEventJSONCountStream : NSOutputStream {
    TLinkEventPreparation::ByteCount _count;
    NSStreamStatus _state;
    NSError *_failure;
    __weak id<NSStreamDelegate> _streamDelegate;
}
@property(nonatomic,readonly) NSUInteger byteCount;
@end
@implementation TLinkEventJSONCountStream
- (instancetype)init {self=[super init];if(self)_state=NSStreamStatusNotOpen;return self;}
- (void)open {if(_state==NSStreamStatusNotOpen)_state=NSStreamStatusOpen;}
- (void)close {_state=NSStreamStatusClosed;}
- (NSInteger)countFailure {
    _failure=[NSError errorWithDomain:@"TLinkEventJSONCount" code:1 userInfo:nil];_state=NSStreamStatusError;return -1;
}
- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)length {
    if(_state!=NSStreamStatusOpen||(!buffer&&length)||length>(NSUInteger)NSIntegerMax||!_count.append(length))return [self countFailure];
    return (NSInteger)length;
}
- (BOOL)hasSpaceAvailable {return _state==NSStreamStatusOpen;}
- (NSStreamStatus)streamStatus {return _state;}
- (NSError *)streamError {return _failure;}
- (NSUInteger)byteCount {return _count.size();}
- (id<NSStreamDelegate>)delegate {return _streamDelegate;}
- (void)setDelegate:(id<NSStreamDelegate>)delegate {_streamDelegate=delegate;}
- (id)propertyForKey:(NSStreamPropertyKey)key {(void)key;return nil;}
- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key {(void)property;(void)key;return NO;}
- (void)scheduleInRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode {(void)loop;(void)mode;}
- (void)removeFromRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode {(void)loop;(void)mode;}
@end
using TLinkEventJSONCountWriter=NSInteger (*)(id,NSOutputStream *,NSError *__autoreleasing *);
static NSInteger TLinkEventJSONCountWrite(id object,NSOutputStream *stream,NSError *__autoreleasing *error){
    return [NSJSONSerialization writeJSONObject:object toStream:stream options:0 error:error];
}
static BOOL TLinkEventJSONCountWithWriter(id object,NSUInteger *size,TLinkEventJSONCountWriter writer){
    if(!size||!writer)return NO;
    NSUInteger count=0;BOOL complete=NO;
    @autoreleasepool {
        TLinkEventJSONCountStream *stream=[TLinkEventJSONCountStream new];if(!stream)return NO;
        @try {
            [stream open];NSError *error=nil;
            const NSInteger written=writer(object,stream,&error);
            if(written>0&&!error&&stream.streamStatus==NSStreamStatusOpen&&stream.byteCount==(NSUInteger)written){count=stream.byteCount;complete=YES;}
        } @finally {[stream close];}
    }
    if(complete)*size=count;
    return complete;
}
static BOOL TLinkEventJSONEncodedSize(id object,NSUInteger *size){
    @try {try {return TLinkEventJSONCountWithWriter(object,size,TLinkEventJSONCountWrite);}catch(...) {}}
    @catch(__unused NSException *exception) {}
    return NO;
}
