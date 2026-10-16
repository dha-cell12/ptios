// macOS: actual Foundation/CF owner, writer sources and file lifecycle; fake HID/UI only.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#include "../shared/TLinkRecorder.h"
#include <atomic>
#include <cassert>
#include <cfloat>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string>
#include <vector>
using IOHIDEventSystemClientRef = CFMutableDictionaryRef;
using IOHIDEventRef = const void *;
using IOHIDEventQueueRef = void *;
using IOHIDEventField = int;
using IOHIDEventSystemClientEventCallback = void (*)(void *, void *, IOHIDEventQueueRef, IOHIDEventRef);
enum { kIOHIDEventTypeDigitizer = 11, kIOHIDEventFieldDigitizerTouch, kIOHIDEventFieldDigitizerEventMask,
       kIOHIDEventFieldDigitizerIndex, kIOHIDEventFieldDigitizerX, kIOHIDEventFieldDigitizerY };
@interface TestHIDEvent : NSObject
@property(nonatomic) int type;
@property(nonatomic) int touch;
@property(nonatomic) int mask;
@property(nonatomic) int finger;
@property(nonatomic) double x;
@property(nonatomic) double y;
@property(nonatomic, strong) NSArray *children;
@end
@implementation TestHIDEvent
@end
static NSString *scriptsRoot;
static std::atomic_int created{0}, released{0}, alerts{0}, closes{0}, winners{0};
static std::atomic_bool failCreate{false}, failOpen{false}, failWrite{false}, failSync{false}, failClose{false}, blockWrite{false};
static dispatch_semaphore_t writeEntered, writeRelease;
static IOHIDEventSystemClientEventCallback registeredCallback;
static void *registeredTarget, *registeredRefcon;
static CFRunLoopRef scheduledLoop;
static NSString *getScriptsFolder() { return scriptsRoot; }
#define RECORDING_FILE_FOLDER_NAME "recording"
static NSDictionary *zx_recordingMetadata() { return @{@"width":@256, @"height":@512, @"Orientation":@"1", @"FrontApp":@"test.app"}; }
static void zx_recordingSetIndicator(uintptr_t generation) { (void)generation; }
static void zx_recordingFailureAlert(NSString *message) { assert(message.length); ++alerts; }
static std::string repliedPath;
static int notifyClient(UInt8 *bytes, CFWriteStreamRef stream) {
    assert(stream && bytes); repliedPath = reinterpret_cast<char *>(bytes); return static_cast<int>(repliedPath.size());
}
static IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator) {
    assert(![NSThread isMainThread]);
    if (failCreate.exchange(false)) return nullptr;
    auto client = CFDictionaryCreateMutable(allocator, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(client, CFSTR("testClient"), kCFBooleanTrue); ++created; return client;
}
static void IOHIDEventSystemClientRegisterEventCallback(IOHIDEventSystemClientRef client,
    IOHIDEventSystemClientEventCallback callback, void *target, void *refcon) {
    assert(client && ![NSThread isMainThread]);
    registeredCallback = callback; registeredTarget = target; registeredRefcon = refcon;
}
static void IOHIDEventSystemClientScheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef loop, CFStringRef mode) {
    assert(client && loop == CFRunLoopGetCurrent() && mode == kCFRunLoopDefaultMode); scheduledLoop = loop;
}
static void IOHIDEventSystemClientUnregisterEventCallback(IOHIDEventSystemClientRef client) {
    assert(client && CFRunLoopGetCurrent() == scheduledLoop); registeredCallback = nullptr;
}
static void IOHIDEventSystemClientUnscheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef loop, CFStringRef mode) {
    assert(client && loop == scheduledLoop && loop == CFRunLoopGetCurrent() && mode == kCFRunLoopDefaultMode);
    scheduledLoop = nullptr;
}
static void testCFRelease(CFTypeRef object) {
    if (CFGetTypeID(object) == CFDictionaryGetTypeID() && CFDictionaryContainsKey((CFDictionaryRef)object, CFSTR("testClient"))) ++released;
    CFRelease(object);
}
static int IOHIDEventGetType(IOHIDEventRef event) { return ((__bridge TestHIDEvent *)event).type; }
static CFArrayRef IOHIDEventGetChildren(IOHIDEventRef event) { return (__bridge CFArrayRef)((__bridge TestHIDEvent *)event).children; }
static int IOHIDEventGetIntegerValue(IOHIDEventRef reference, IOHIDEventField field) {
    TestHIDEvent *event = (__bridge TestHIDEvent *)reference;
    if (field == kIOHIDEventFieldDigitizerTouch) return event.touch;
    if (field == kIOHIDEventFieldDigitizerEventMask) return event.mask;
    assert(field == kIOHIDEventFieldDigitizerIndex); return event.finger;
}
static double IOHIDEventGetFloatValue(IOHIDEventRef reference, IOHIDEventField field) {
    TestHIDEvent *event = (__bridge TestHIDEvent *)reference;
    assert(field == kIOHIDEventFieldDigitizerX || field == kIOHIDEventFieldDigitizerY);
    return field == kIOHIDEventFieldDigitizerX ? event.x : event.y;
}
static int testOpen(const char *path, int flags, mode_t mode) {
    if (failOpen.exchange(false)) { errno = EACCES; return -1; } return open(path, flags, mode);
}
static ssize_t testWrite(int fd, const void *bytes, size_t length) {
    if (blockWrite.exchange(false)) {
        dispatch_semaphore_signal(writeEntered);
        assert(dispatch_semaphore_wait(writeRelease, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0);
    }
    if (failWrite.exchange(false)) { errno = ENOSPC; return -1; }
    return write(fd, bytes, length);
}
static int testSync(int fd) { if (failSync.exchange(false)) { errno = EIO; return -1; } return fsync(fd); }
static int testClose(int fd) { ++closes; const int result = close(fd); if (failClose.exchange(false)) { errno = EIO; return -1; } return result; }
#define open testOpen
#define write testWrite
#define fsync testSync
#define close testClose
#define CFRelease testCFRelease
#include "RecorderUnderTest.inc"
#undef open
#undef write
#undef fsync
#undef close
#undef CFRelease
static void recordingStartTaskUnderTest(CFWriteStreamRef writeStreamRef) {
#include "RecorderStartTaskUnderTest.inc"
}

static void wait(dispatch_semaphore_t semaphore) {
    assert(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0);
}
static NSString *start() {
    NSError *error = nil;
    startRecording((CFWriteStreamRef)(uintptr_t)1, &error); assert(!error && isRecordingStart());
    assert(!repliedPath.empty()); return [NSString stringWithUTF8String:repliedPath.c_str()];
}
static NSDictionary *info(NSString *path) { return [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"info.plist"]]; }
static int touchCount(NSString *path) {
    NSDictionary *metadata = info(path); assert(metadata);
    NSString *raw = [NSString stringWithContentsOfFile:[path stringByAppendingPathComponent:metadata[@"Entry"]] encoding:NSUTF8StringEncoding error:nil];
    assert(raw); int count = 0;
    for (NSString *line in [raw componentsSeparatedByString:@"\n"]) if ([line hasPrefix:@"101"]) ++count;
    return count;
}
static TestHIDEvent *parent() {
    TestHIDEvent *child = [TestHIDEvent new]; child.touch = 1; child.mask = 2; child.finger = 19; child.x = 0.5; child.y = 0.5;
    TestHIDEvent *event = [TestHIDEvent new]; event.type = kIOHIDEventTypeDigitizer; event.children = @[child]; return event;
}
static void emit(int count) {
    TLinkRecorder *recorder = [TLinkRecorder shared];
    [recorder performOwner:^{
        TestHIDEvent *event = parent();
        assert(registeredCallback && registeredTarget == (__bridge void *)recorder && registeredRefcon == (void *)recorder->_generation);
        for (int i = 0; i < count; ++i)
            registeredCallback(registeredTarget, registeredRefcon, nullptr, (__bridge void *)event);
    } wait:true];
}
int main(int argc, const char **argv) { @autoreleasepool {
    assert(argc == 2); scriptsRoot = [NSString stringWithUTF8String:argv[1]];
    writeEntered = dispatch_semaphore_create(0); writeRelease = dispatch_semaphore_create(0);
    TLinkRecorder *recorder = [TLinkRecorder shared]; assert(!isRecordingStart());
    recordingStartTaskUnderTest((CFWriteStreamRef)(uintptr_t)1);
    NSString *envelope = [NSString stringWithUTF8String:repliedPath.c_str()];
    assert([envelope hasPrefix:@"0;;"] && [envelope hasSuffix:@"\r\n"]);
    NSError *replyError = nil; stopRecordingWithError(&replyError); assert(!replyError);
    NSString *path = start(); emit(1000);
    NSError *error = nil; stopRecordingWithError(&error);
    assert(!error && !isRecordingStart() && created == released && touchCount(path) == 1000);
    assert([info(path)[@"RecordingStatus"] isEqualToString:@"complete"]);
    // Same-second starts are exclusive packages, including main-thread API callers.
    NSString *second = start(); assert(![path isEqualToString:second]);
    const uintptr_t old = recorder->_buffer.generation();
    stopRecordingWithError(&error); assert(!error);
    NSString *third = start();
    [recorder performOwner:^{
        TestHIDEvent *event = parent();
        recordIOHIDEventCallback((__bridge void *)recorder, (void *)old, nullptr, (__bridge void *)event);
    } wait:true];
    assert(zx_stopRecordingGeneration(recorder, old) && isRecordingStart());
    stopRecordingWithError(&error); assert(!error && touchCount(third) == 0);
    // A stop cannot publish idle or acknowledge while the writer is blocked.
    path = start(); blockWrite = true; emit(256); wait(writeEntered);
    auto done = dispatch_semaphore_create(0); __block NSError *stopError = nil;
    stopRecordingAsync(^(NSError *failure) { stopError = failure; dispatch_semaphore_signal(done); });
    assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)) != 0);
    assert(isRecordingStart());
    startRecording(nullptr, &error); assert(error);
    dispatch_semaphore_signal(writeRelease); wait(done);
    assert(!stopError && !isRecordingStart() && touchCount(path) == 256 && created == released);
    // Exhaust bounded pending storage while a batch is in flight; retained prefix is marked failed.
    path = start(); blockWrite = true; emit(256); wait(writeEntered); emit(5000);
    assert(isRecordingStart() && recorder->_buffer.pending() <= TLinkRecorderBuffer::Capacity);
    dispatch_semaphore_signal(writeRelease);
    [recorder performOwner:^{} wait:true];
    assert(!isRecordingStart() && [info(path)[@"RecordingStatus"] isEqualToString:@"failed"] && alerts >= 1);
    for (auto *fault : {&failWrite, &failSync, &failClose}) {
        path = start(); *fault = true; emit(1); stopRecordingWithError(&error);
        assert(error && !isRecordingStart() && created == released);
        assert([info(path)[@"RecordingStatus"] isEqualToString:@"failed"]);
    }
    failCreate = true; startRecording(nullptr, &error); assert(error && !isRecordingStart() && created == released);
    failOpen = true; startRecording(nullptr, &error); assert(error && !isRecordingStart() && created == released);
    // Exactly one simultaneous starter wins; no handle/client escapes teardown.
    dispatch_group_t group = dispatch_group_create(); winners = 0;
    for (int i = 0; i < 8; ++i) dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool { NSError *failure = nil; startRecording(nullptr, &failure); if (!failure) ++winners; }
    });
    assert(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0);
    assert(winners == 1 && isRecordingStart()); stopRecordingWithError(&error); assert(!error);
    for (int i = 0; i < 20; ++i) { startRecording(nullptr, &error); assert(!error); emit(2); stopRecordingWithError(&error); assert(!error); }
    assert(!isRecordingStart() && created == released && closes > 20);
    std::puts("Recorder Foundation/CF owner passed: exact drain/close ACK, run-loop/client balance, stale callbacks/stops, bounded overflow, I/O faults, concurrent starts and repeated lifecycles.");
} }
