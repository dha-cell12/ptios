#include "Record.h"
#include "Common.h"
#include "Config.h"
#include "AlertBox.h"
#include "Screen.h"
#include "SocketServer.h"
#include "../shared/TLinkRecorder.h"
#include <atomic>
#include <cfloat>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// Snapshot UIKit/private app metadata before entering the owner. The owner and writer
// never synchronously wait for main, including when a main-thread caller waits for stop.
static NSDictionary *zx_recordingMetadata(void) {
    __block NSDictionary *result = nil;
    dispatch_block_t snapshot = ^{
        @try {
            SpringBoard *springboard = (SpringBoard *)[UIApplication sharedApplication];
            SBApplication *app = [springboard _accessibilityFrontMostApplication];
            result = @{@"width": @([Screen getScreenWidth]), @"height": @([Screen getScreenHeight]),
                @"Orientation": @([springboard _frontMostAppOrientation]).stringValue,
                @"FrontApp": app.bundleIdentifier ?: @"com.apple.springboard"};
        } @catch (__unused NSException *exception) { result = nil; }
    };
    if ([NSThread isMainThread]) snapshot(); else dispatch_sync(dispatch_get_main_queue(), snapshot);
    return result;
}
static std::atomic<uintptr_t> zx_recordingIndicatorRequested{0};
static UIWindow *zx_recordingWindow;
static void zx_recordingSetIndicator(uintptr_t generation) {
    zx_recordingIndicatorRequested.store(generation);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (zx_recordingIndicatorRequested.load() != generation) return;
        zx_recordingWindow.hidden = true;
        zx_recordingWindow = nil;
        if (!generation) return;
        zx_recordingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        zx_recordingWindow.windowLevel = UIWindowLevelStatusBar;
        zx_recordingWindow.backgroundColor = [UIColor clearColor];
        zx_recordingWindow.userInteractionEnabled = false;
        UIView *circle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        circle.layer.cornerRadius = 10; circle.backgroundColor = [UIColor redColor];
        [zx_recordingWindow addSubview:circle]; zx_recordingWindow.hidden = false;
    });
}
static void zx_recordingFailureAlert(NSString *message) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        showAlertBox(@"Recording failed", message, 999);
    });
}

// BEGIN recorder owner implementation (compiled with Foundation/HID/file doubles by macOS CI).
static NSError *zx_recordingError(NSString *message) {
    return [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n", message]}];
}
static void zx_recordingKeepAlive(void *info) { (void)info; }
@class TLinkRecorder;
static void recordIOHIDEventCallback(void *, void *, IOHIDEventQueueRef, IOHIDEventRef);
@interface TLinkRecorder : NSObject {
@public
    TLinkRecorderBuffer _buffer;
    TLinkRecorderEncoder _encoder;
    TLinkRecorderBytes _bytes;
    NSThread *_ownerThread;
    CFRunLoopRef _ownerLoop;
    IOHIDEventSystemClientRef _client;
    bool _registered, _scheduled;
    uintptr_t _generation;
    double _width, _height;
    dispatch_queue_t _writer;
    dispatch_source_t _drainSource, _flushTimer;
    // These four fields are writer-queue-only.
    int _fd;
    uintptr_t _writerGeneration;
    NSString *_writerError;
    bool _failurePosted;
    // Owner-only metadata and completion error; busy queries use the core's short lock.
    NSMutableDictionary *_info;
    NSString *_directory;
    NSError *_lastError;
}
+ (instancetype)shared;
- (void)performOwner:(dispatch_block_t)operation wait:(bool)wait;
- (NSString *)startOnOwner:(NSDictionary *)metadata error:(NSError **)error;
- (void)stopOnOwner:(uintptr_t)generation failure:(NSError *)failure;
- (void)drainOnWriter:(uintptr_t)generation;
- (void)writerFailed:(uintptr_t)generation message:(NSString *)message;
- (void)acceptEvent:(IOHIDEventRef)parent generation:(uintptr_t)generation time:(uint64_t)timeNs;
@end
@implementation TLinkRecorder
+ (instancetype)shared {
    static TLinkRecorder *recorder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ recorder = [[TLinkRecorder alloc] init]; });
    return recorder;
}
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _fd = -1;
    _writer = dispatch_queue_create("com.tlinkauto.recording.writer", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    __weak TLinkRecorder *weakOwner = self;
    _ownerThread = [[NSThread alloc] initWithBlock:^{
        TLinkRecorder *owner = weakOwner;
        if (!owner) { dispatch_semaphore_signal(ready); return; }
        @autoreleasepool {
            CFRunLoopSourceContext context = {};
            context.perform = zx_recordingKeepAlive;
            CFRunLoopSourceRef keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context);
            if (keepAlive) {
                owner->_ownerLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
                CFRunLoopAddSource(owner->_ownerLoop, keepAlive, kCFRunLoopDefaultMode);
                CFRelease(keepAlive);
            }
            dispatch_semaphore_signal(ready);
            if (!owner->_ownerLoop) return;
        }
        // One named process-lifetime owner, sleeping in CF's event wait when idle.
        // Never park a shared GCD worker or nest a run loop per recording.
        while (true) { @autoreleasepool { CFRunLoopRunInMode(kCFRunLoopDefaultMode, DBL_MAX, true); } }
    }];
    _ownerThread.name = @"com.tlinkauto.recording.owner";
    [_ownerThread start];
    dispatch_semaphore_wait(ready, DISPATCH_TIME_FOREVER);
    return self;
}
- (void)performOwner:(dispatch_block_t)operation wait:(bool)wait {
    if ([NSThread currentThread] == _ownerThread) { operation(); return; }
    if (!_ownerLoop) return;
    dispatch_semaphore_t done = wait ? dispatch_semaphore_create(0) : nil;
    __block NSException *exception = nil;
    CFRunLoopPerformBlock(_ownerLoop, kCFRunLoopDefaultMode, ^{
        @autoreleasepool {
            @try { operation(); }
            @catch (NSException *caught) { exception = caught; }
            @finally { if (done) dispatch_semaphore_signal(done); }
        }
    });
    CFRunLoopWakeUp(_ownerLoop);
    if (done) {
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        if (exception) @throw exception;
    }
}
- (void)writerFailed:(uintptr_t)generation message:(NSString *)message {
    if (!_writerError) _writerError = message;
    _buffer.stop(generation, TLinkRecorderFailure::Write);
    if (_failurePosted) return;
    _failurePosted = true;
    // Never synchronously wait for the owner: stop may be waiting for this writer.
    [self performOwner:^{
        if (self->_generation != generation || !self->_buffer.busy()) return;
        [self stopOnOwner:generation failure:zx_recordingError(message)];
        zx_recordingFailureAlert(self->_lastError.localizedDescription);
    } wait:false];
}
- (void)drainOnWriter:(uintptr_t)generation {
    if (_writerGeneration != generation || _fd < 0 || _writerError) return;
    TLinkRecordEvent events[256];
    auto writeBytes = [self](const char *bytes, size_t length) { return write(self->_fd, bytes, length); };
    size_t count;
    while ((count = _buffer.take(generation, events, 256)) != 0) {
        for (size_t i = 0; i < count; ++i) {
            if (!_encoder.encode(events[i], [&](const char *data, size_t length) {
                return _bytes.append(data, length, writeBytes);
            })) { [self writerFailed:generation message:@"Unable to write the recording; saved data is incomplete."]; return; }
        }
    }
    if (!_bytes.flush(writeBytes)) [self writerFailed:generation message:@"Unable to flush recording bytes; saved data is incomplete."];
}
- (NSString *)startOnOwner:(NSDictionary *)metadata error:(NSError **)error {
    const uintptr_t generation = _buffer.reserve();
    if (!generation) { if (error) *error = zx_recordingError(@"Recording is already starting, running or stopping."); return nil; }
    _generation = generation; _lastError = nil; _directory = nil; _info = nil;
    NSError *failure = nil;
    NSString *rawPath = nil;
    int opened = -1;
    @try {
        _width = [metadata[@"width"] doubleValue]; _height = [metadata[@"height"] doubleValue];
        if (!metadata || !std::isfinite(_width) || !std::isfinite(_height) || _width <= 0 || _height <= 0 ||
            _width > 9999.9 || _height > 9999.9) failure = zx_recordingError(@"Cannot get valid recording screen dimensions.");
        if (!failure) {
            _client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
            if (!_client) failure = zx_recordingError(@"Unable to create the recording HID client.");
        }
        if (!failure) {
            NSString *root = [getScriptsFolder() stringByAppendingPathComponent:@RECORDING_FILE_FOLDER_NAME];
            NSError *folderError = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:true attributes:nil error:&folderError])
                failure = zx_recordingError(folderError.localizedDescription ?: @"Unable to create the recording folder.");
            if (!failure) {
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init]; formatter.dateFormat = @"yyMMddHHmmss";
                NSString *stem = [NSString stringWithFormat:@"%@-%@", [formatter stringFromDate:[NSDate date]], [NSUUID UUID].UUIDString];
                NSString *directory = [root stringByAppendingPathComponent:[stem stringByAppendingString:@".tl"]];
                // mkdir/open are exclusive: never reuse/truncate a same-second recording.
                if (mkdir(directory.fileSystemRepresentation, 0755) != 0) failure = zx_recordingError(@"Unable to create a unique recording package.");
                else {
                    _directory = directory;
                    _info = [@{@"Entry":[stem stringByAppendingString:@".raw"], @"Orientation":metadata[@"Orientation"] ?: @"-1",
                        @"FrontApp":metadata[@"FrontApp"] ?: @"com.apple.springboard", @"RecordingStatus":@"recording"} mutableCopy];
                    if (![_info writeToFile:[directory stringByAppendingPathComponent:@"info.plist"] atomically:true])
                        failure = zx_recordingError(@"Unable to write recording metadata.");
                    rawPath = [directory stringByAppendingPathComponent:_info[@"Entry"]];
                    if (!failure) {
                        opened = open(rawPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644);
                        if (opened < 0) failure = zx_recordingError(@"Unable to open the recording file.");
                    }
                }
            }
        }
        if (!failure) {
            const uint64_t startNs = TLinkRecorderNowNs();
            const int fd = opened;
            dispatch_sync(_writer, ^{
                self->_fd = fd; self->_writerGeneration = generation; self->_writerError = nil;
                self->_failurePosted = false; self->_encoder.reset(startNs); self->_bytes.reset();
            });
            opened = -1; // Writer exclusively owns the descriptor from here through close.
            _drainSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, _writer);
            _flushTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _writer);
            if (!_drainSource || !_flushTimer) failure = zx_recordingError(@"Unable to create recording flush sources.");
            // All created sources are resumed before any cancellation/teardown path.
            if (_drainSource) {
                dispatch_source_set_event_handler(_drainSource, ^{ [self drainOnWriter:generation]; });
                dispatch_resume(_drainSource);
            }
            if (_flushTimer) {
                dispatch_source_set_timer(_flushTimer, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
                dispatch_source_set_event_handler(_flushTimer, ^{ [self drainOnWriter:generation]; });
                dispatch_resume(_flushTimer);
            }
        }
        if (!failure) {
            _buffer.activate(generation);
            IOHIDEventSystemClientRegisterEventCallback(_client, recordIOHIDEventCallback, (__bridge void *)self, (void *)generation);
            _registered = true;
            IOHIDEventSystemClientScheduleWithRunLoop(_client, _ownerLoop, kCFRunLoopDefaultMode);
            _scheduled = true;
            zx_recordingSetIndicator(generation);
        }
    } @catch (NSException *exception) { failure = zx_recordingError(exception.reason ?: @"Unable to start recording."); }
    if (opened >= 0) close(opened);
    if (failure) {
        [self stopOnOwner:generation failure:failure];
        if (error) *error = _lastError;
        return nil;
    }
    return _directory;
}
- (void)stopOnOwner:(uintptr_t)generation failure:(NSError *)failure {
    if (generation != _generation || !_buffer.busy()) return;
    _buffer.stop(generation); // Reject callbacks before releasing HID ownership.
    if (_client) {
        if (_registered) IOHIDEventSystemClientUnregisterEventCallback(_client);
        if (_scheduled) IOHIDEventSystemClientUnscheduleWithRunLoop(_client, _ownerLoop, kCFRunLoopDefaultMode);
        CFRelease(_client); _client = NULL; _registered = _scheduled = false;
    }
    if (_drainSource) { dispatch_source_cancel(_drainSource); _drainSource = nil; }
    if (_flushTimer) { dispatch_source_cancel(_flushTimer); _flushTimer = nil; }
    __block NSString *ioError = nil;
    dispatch_sync(_writer, ^{
        if (self->_writerGeneration != generation) return;
        [self drainOnWriter:generation];
        ioError = self->_writerError;
        if (self->_fd >= 0) {
            if (fsync(self->_fd) != 0 && !ioError) ioError = @"Unable to synchronize the recording file.";
            // Do not retry close on EINTR: the descriptor may already have been consumed.
            if (close(self->_fd) != 0 && !ioError) ioError = @"Unable to close the recording file.";
        }
        self->_fd = -1; self->_writerGeneration = 0; self->_bytes.reset();
    });
    if (!failure && ioError) failure = zx_recordingError(ioError);
    if (!failure && _buffer.failure() != TLinkRecorderFailure::None)
        failure = zx_recordingError(@"Recording stopped because its bounded buffer filled or an invalid touch was received; saved data is incomplete.");
    if (_info && _directory) {
        _info[@"RecordingStatus"] = failure ? @"failed" : @"complete";
        if (failure) _info[@"RecordingError"] = failure.localizedDescription;
        if (![_info writeToFile:[_directory stringByAppendingPathComponent:@"info.plist"] atomically:true] && !failure)
            failure = zx_recordingError(@"Unable to commit recording completion metadata.");
    }
    _lastError = failure;
    zx_recordingSetIndicator(0);
    _buffer.finish(generation, failure != nil); // Idle is published only after drain/fsync/close.
}
- (void)acceptEvent:(IOHIDEventRef)parent generation:(uintptr_t)generation time:(uint64_t)timeNs {
    if (CFRunLoopGetCurrent() != _ownerLoop || !_client || !_buffer.accepts(generation) || !parent ||
        IOHIDEventGetType(parent) != kIOHIDEventTypeDigitizer) return;
    CFArrayRef children = IOHIDEventGetChildren(parent); // Borrowed for this callback only.
    const CFIndex count = children ? CFArrayGetCount(children) : 0;
    TLinkRecordEvent records[20]; size_t accepted = 0;
    bool valid = count >= 0 && count <= 20;
    for (CFIndex i = 0; valid && i < count; ++i) {
        IOHIDEventRef child = (IOHIDEventRef)CFArrayGetValueAtIndex(children, i);
        if (!child) { valid = false; break; }
        const int touch = IOHIDEventGetIntegerValue(child, (IOHIDEventField)kIOHIDEventFieldDigitizerTouch);
        const int mask = IOHIDEventGetIntegerValue(child, (IOHIDEventField)kIOHIDEventFieldDigitizerEventMask);
        const int type = (touch == 1 && (mask & 2)) ? 1 : ((touch == 1 && (mask & 4)) ? 2 : ((!touch && (mask & 2)) ? 0 : -1));
        if (type < 0) continue;
        valid = TLinkMakeRecordEvent(timeNs, type,
            IOHIDEventGetIntegerValue(child, (IOHIDEventField)kIOHIDEventFieldDigitizerIndex),
            IOHIDEventGetFloatValue(child, (IOHIDEventField)kIOHIDEventFieldDigitizerX),
            IOHIDEventGetFloatValue(child, (IOHIDEventField)kIOHIDEventFieldDigitizerY), _width, _height, &records[accepted]);
        if (valid) ++accepted;
    }
    if (!valid) _buffer.stop(generation, TLinkRecorderFailure::InvalidEvent);
    else if (accepted && _buffer.append(generation, records, accepted)) {
        if (_buffer.pending() >= 256 && _drainSource) dispatch_source_merge_data(_drainSource, 1);
        return;
    } else if (!accepted) return;
    // Overflow/invalid event is fail-stop, not a dropped MOVE or silent loss of DOWN/UP.
    CFRunLoopPerformBlock(_ownerLoop, kCFRunLoopDefaultMode, ^{
        if (self->_generation != generation || !self->_buffer.busy()) return;
        [self stopOnOwner:generation failure:nil];
        zx_recordingFailureAlert(self->_lastError.localizedDescription);
    });
    CFRunLoopWakeUp(_ownerLoop);
}
@end
static void recordIOHIDEventCallback(void *target, void *refcon, IOHIDEventQueueRef queue, IOHIDEventRef parent) {
    const uint64_t timeNs = TLinkRecorderNowNs(); // One arrival sample, before parsing/enqueue/I/O.
    (void)queue;
    TLinkRecorder *recorder = (__bridge TLinkRecorder *)target;
    [recorder acceptEvent:parent generation:(uintptr_t)refcon time:timeNs];
}
NSString *startRecordingWithError(NSError **error) {
    if (error) *error = nil;
    TLinkRecorder *recorder = [TLinkRecorder shared];
    if (!recorder->_ownerLoop) { if (error) *error = zx_recordingError(@"Recording owner is unavailable."); return nil; }
    if (recorder->_buffer.busy()) { if (error) *error = zx_recordingError(@"Recording is already starting, running or stopping."); return nil; }
    NSDictionary *metadata = zx_recordingMetadata();
    __block NSString *path = nil;
    __block NSError *failure = nil;
    [recorder performOwner:^{ path = [recorder startOnOwner:metadata error:&failure]; } wait:true];
    if (error) *error = failure;
    return path;
}
void startRecording(CFWriteStreamRef requestClient, NSError **error) {
    NSString *path = startRecordingWithError(error);
    // Legacy C API retains its path-only notification, synchronously on the caller.
    // Task 14 formats its single status/path envelope using the returned path instead.
    if (path && requestClient) notifyClient((UInt8 *)path.UTF8String, requestClient);
}
static NSError *zx_stopRecordingGeneration(TLinkRecorder *recorder, uintptr_t generation) {
    if (!recorder->_ownerLoop) return zx_recordingError(@"Recording owner is unavailable.");
    __block NSError *failure = nil;
    [recorder performOwner:^{
        if (recorder->_generation != generation) {
            failure = zx_recordingError(@"A newer recording owns the recorder; stale stop was ignored.");
            return;
        }
        [recorder stopOnOwner:generation failure:nil];
        failure = recorder->_lastError;
    } wait:true];
    return failure;
}
void stopRecordingWithError(NSError **error) {
    TLinkRecorder *recorder = [TLinkRecorder shared];
    NSError *failure = zx_stopRecordingGeneration(recorder, recorder->_buffer.generation());
    if (error) *error = failure;
}
void stopRecordingAsync(void (^completion)(NSError *)) {
    TLinkRecorder *recorder = [TLinkRecorder shared];
    const uintptr_t generation = recorder->_buffer.generation();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *failure = zx_stopRecordingGeneration(recorder, generation);
        if (completion) completion(failure);
    });
}
void stopRecording(void) {
    NSError *failure = nil; stopRecordingWithError(&failure);
    if (failure) zx_recordingFailureAlert(failure.localizedDescription);
}
Boolean isRecordingStart(void) { return [TLinkRecorder shared]->_buffer.busy(); }
// END recorder owner implementation.
