#import "TLinkAXJSONOutput.h"
#include "TLinkAXJSONQuota.h"
#include "TLinkAXJSONStop.h"
#include "TLinkAXJSONBudget.h"

@interface TLinkAXJSONStream : NSOutputStream {
    NSMutableData *_bytes;
    NSError *_failure;
    NSStreamStatus _state;
    TLinkAXJSONOutput::Quota _quota;
    TLinkNativeBudgetPtr _callerBudget;
    BOOL _outputExceeded;
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
    if (self) { _callerBudget = TLinkCurrentNativeBudget(); _bytes = [NSMutableData data]; _state = NSStreamStatusNotOpen; }
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
    if (TLinkAXJSONOutput::ClassifyStop(_callerBudget).active) return [self failWithCode:4];
    if (!_quota.append(length)) return [self failWithCode:1];
    if (TLinkAXJSONOutput::ClassifyStop(_callerBudget).active) return [self failWithCode:4];
    if (!TLinkAXJSONOutput::AdmitOutput(_callerBudget, _quota.size())) {
        _outputExceeded = YES;
        return [self failWithCode:5];
    }
    if (length) [_bytes appendBytes:buffer length:length];
    if (!_bytes || _bytes.length != _quota.size()) return [self failWithCode:3];
    if (TLinkAXJSONOutput::ClassifyStop(_callerBudget).active) return [self failWithCode:4];
    return (NSInteger)length;
}
// At the exact limit, permit one attempted write to distinguish EOF from
// additional JSON. Any rejected chunk makes the entire result unusable.
-(BOOL)hasSpaceAvailable { return _state == NSStreamStatusOpen && !TLinkAXJSONOutput::ClassifyStop(_callerBudget).active; }
-(NSStreamStatus)streamStatus { return _state; }
-(NSError *)streamError { return _failure; }
-(NSData *)bytes { return _bytes; }
-(BOOL)limitExceeded { return _quota.exceeded() || _outputExceeded; }
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
static bool TLinkAXJSONReportStop(const TLinkNativeBudgetPtr &budget, BOOL *tooLarge, BOOL *stopped) {
    const auto state = TLinkAXJSONOutput::ClassifyStop(budget);
    if (!state.active) return false;
    if (tooLarge) *tooLarge = state.tooLarge;
    if (stopped) *stopped = state.cancelled;
    return true;
}
static bool TLinkAXJSONAdmitOutput(const TLinkNativeBudgetPtr &budget, size_t bytes, BOOL *tooLarge, BOOL *stopped) {
    if (TLinkAXJSONReportStop(budget, tooLarge, stopped)) return false;
    if (!TLinkAXJSONOutput::AdmitOutput(budget, bytes)) {
        if (!TLinkAXJSONReportStop(budget, tooLarge, stopped) && tooLarge) *tooLarge = YES;
        return false;
    }
    return !TLinkAXJSONReportStop(budget, tooLarge, stopped);
}
static NSData *TLinkAXJSONDataWithWriter(id object, BOOL *tooLarge, TLinkAXJSONWriter writer, BOOL *stopped = nullptr) {
    if (tooLarge) *tooLarge = NO;
    if (stopped) *stopped = NO;
    const auto callerBudget = TLinkCurrentNativeBudget();
    if (!TLinkAXJSONAdmitOutput(callerBudget, 0, tooLarge, stopped)) return nil;
    TLinkAXJSONStream *stream = [TLinkAXJSONStream new];
    if (!stream) return nil;
    @try {
        [stream open];
        NSError *error = nil;
        const NSInteger written = writer(object, stream, &error);
        if (TLinkAXJSONReportStop(callerBudget, tooLarge, stopped)) return nil;
        if (stream.limitExceeded) { if (tooLarge) *tooLarge = YES; return nil; }
        if (written <= 0 || error || stream.streamStatus != NSStreamStatusOpen ||
            stream.bytes.length != (NSUInteger)written || stream.acceptedBytes != (size_t)written) return nil;
        if (!TLinkAXJSONAdmitOutput(callerBudget, stream.acceptedBytes, tooLarge, stopped)) return nil;
        NSData *result = [stream.bytes copy];
        if (TLinkAXJSONReportStop(callerBudget, tooLarge, stopped)) return nil;
        return result;
    } @finally {
        [stream close];
    }
}
NSData *TLinkAXBoundedJSONDataWithStop(id object, BOOL *tooLarge, BOOL *stopped) {
    const auto callerBudget = TLinkCurrentNativeBudget();
    NSData *result = nil;
    @autoreleasepool { result = TLinkAXJSONDataWithWriter(object, tooLarge, TLinkAXWriteJSON, stopped); }
    if (TLinkAXJSONReportStop(callerBudget, tooLarge, stopped)) return nil;
    if (result && !TLinkAXJSONAdmitOutput(callerBudget, result.length, tooLarge, stopped)) return nil;
    return result;
}
NSData *TLinkAXBoundedJSONData(id object, BOOL *tooLarge) {
    return TLinkAXBoundedJSONDataWithStop(object, tooLarge, nullptr);
}
