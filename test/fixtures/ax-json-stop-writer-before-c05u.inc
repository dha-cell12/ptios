#import "TLinkAXJSONOutput.h"
#include "TLinkAXJSONQuota.h"

@interface TLinkAXJSONStream : NSOutputStream {
    NSMutableData *_bytes;
    NSError *_failure;
    NSStreamStatus _state;
    TLinkAXJSONOutput::Quota _quota;
    __weak id<NSStreamDelegate> _streamDelegate;
}
@property(nonatomic,readonly) NSData *bytes;
@property(nonatomic,readonly) BOOL limitExceeded;
@property(nonatomic,readonly) size_t acceptedBytes;
@end

@implementation TLinkAXJSONStream
// Internal synchronous sink; it never schedules asynchronous stream events.
-(instancetype)init {
    self = [super init];
    if (self) { _bytes = [NSMutableData data]; _state = NSStreamStatusNotOpen; }
    return self;
}
-(void)open { if (_state == NSStreamStatusNotOpen) _state = NSStreamStatusOpen; }
-(void)close { _state = NSStreamStatusClosed; }
-(NSInteger)failWithCode:(NSInteger)code {
    _failure = [NSError errorWithDomain:@"TLinkAXJSONOutput" code:code userInfo:nil];
    _state = NSStreamStatusError;
    return -1;
}
-(NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)length {
    if (_state != NSStreamStatusOpen || (!buffer && length)) return [self failWithCode:2];
    if (!_quota.append(length)) return [self failWithCode:1];
    if (length) [_bytes appendBytes:buffer length:length];
    if (!_bytes || _bytes.length != _quota.size()) return [self failWithCode:3];
    return (NSInteger)length;
}
// At the exact limit, permit one attempted write to distinguish EOF from
// additional JSON. Any rejected chunk makes the entire result unusable.
-(BOOL)hasSpaceAvailable { return _state == NSStreamStatusOpen; }
-(NSStreamStatus)streamStatus { return _state; }
-(NSError *)streamError { return _failure; }
-(NSData *)bytes { return _bytes; }
-(BOOL)limitExceeded { return _quota.exceeded(); }
-(size_t)acceptedBytes { return _quota.size(); }
-(id<NSStreamDelegate>)delegate { return _streamDelegate; }
-(void)setDelegate:(id<NSStreamDelegate>)delegate { _streamDelegate = delegate; }
-(id)propertyForKey:(NSStreamPropertyKey)key { (void)key; return nil; }
-(BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key { (void)property; (void)key; return NO; }
-(void)scheduleInRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode { (void)runLoop; (void)mode; }
-(void)removeFromRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode { (void)runLoop; (void)mode; }
@end

using TLinkAXJSONWriter = NSInteger (*)(id, NSOutputStream *, NSError *__autoreleasing *);
static NSInteger TLinkAXWriteJSON(id object, NSOutputStream *stream, NSError *__autoreleasing *error) {
    return [NSJSONSerialization writeJSONObject:object toStream:stream options:0 error:error];
}
static NSData *TLinkAXJSONDataWithWriter(id object, BOOL *tooLarge, TLinkAXJSONWriter writer) {
    if (tooLarge) *tooLarge = NO;
    TLinkAXJSONStream *stream = [TLinkAXJSONStream new];
    if (!stream) return nil;
    @try {
        [stream open];
        NSError *error = nil;
        const NSInteger written = writer(object, stream, &error);
        if (stream.limitExceeded) { if (tooLarge) *tooLarge = YES; return nil; }
        if (written <= 0 || error || stream.streamStatus != NSStreamStatusOpen ||
            stream.bytes.length != (NSUInteger)written || stream.acceptedBytes != (size_t)written) return nil;
        return [stream.bytes copy];
    } @finally {
        [stream close];
    }
}
NSData *TLinkAXBoundedJSONData(id object, BOOL *tooLarge) {
    NSData *result = nil;
    @autoreleasepool { result = TLinkAXJSONDataWithWriter(object, tooLarge, TLinkAXWriteJSON); }
    return result;
}
