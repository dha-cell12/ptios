// macOS-only: execute the extracted production dispatch/ARC adapter, without UIKit or a script engine.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include "../shared/TLinkSchedulerState.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <unistd.h>

static std::atomic_bool busy{false}, blockLicense{false}, licenseAllowed{true};
static std::atomic_int admissionChecks{0}, licenseChecks{0}, launches{0};
static dispatch_semaphore_t launched, gateEntered, gateRelease;
static BOOL canStartScriptPlaying(void) { ++admissionChecks; return !busy.load(); }
static BOOL TLinkSchedulerScriptLaunchAllowed(NSString *source) {
    assert(![NSThread isMainThread] && [source isEqualToString:@"scheduler_timer"]);
    ++licenseChecks;
    if (blockLicense.load()) {
        dispatch_semaphore_signal(gateEntered);
        assert(dispatch_semaphore_wait(gateRelease, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    }
    return licenseAllowed.load();
}
static int playScript(UInt8 *path, NSError **error) {
    assert(![NSThread isMainThread] && path && error);
    ++launches;
    dispatch_semaphore_signal(launched);
    return 0;
}
static void setLastScriptError(NSString *message) { (void)message; assert(false); }
NSString* TLinkSetTimer(NSString *name, NSString *intervalText, BOOL repeat, NSString *script, NSError **error);
NSString* TLinkRemoveTimer(NSString *name, NSError **error);
#include "SchedulerRuntimeUnderTest.inc"

static void set(NSString *payload) {
    NSError *error = nil;
    assert(setTimerFromRawData((UInt8 *)payload.UTF8String, &error) != nil && !error);
}
static void remove(NSString *name) {
    NSError *error = nil;
    assert(removeTimerFromRawData((UInt8 *)name.UTF8String, &error) != nil && !error);
}
static size_t count() {
    __block size_t size = 0;
    schedulerPerformSync(^{ size = timerRegistry.size(); });
    return size;
}
static void waitUntilConsumed() {
    for (int attempt = 0; attempt < 400 && count() != 0; ++attempt) usleep(5000);
    assert(count() == 0);
}
int main() { @autoreleasepool {
    launched = dispatch_semaphore_create(0);
    gateEntered = dispatch_semaphore_create(0);
    gateRelease = dispatch_semaphore_create(0);
    set(@"valid;;3600;;1;;/script");
    for (NSString *payload in @[@"valid;;0.001;;1;;/script", @"x;;nan;;0;;/script", @"x;;inf;;0;;/script",
                               @"x;;1oops;;1;;/script", @"x;;0;;0;;/script", @";;1;;1;;/script", @"x;;1;;1;;"]) {
        NSError *error = nil;
        assert(setTimerFromRawData((UInt8 *)payload.UTF8String, &error) == nil && error);
        assert(count() == 1); // Failed replacements leave the valid timer intact.
    }
    remove(@"valid");
    assert(count() == 0);

    dispatch_apply(8, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t client) {
        (void)client;
        @autoreleasepool {
            for (int i = 0; i < 1000; ++i) { set(@"shared;;3600;;1;;/script"); remove(@"shared"); }
        }
    });
    remove(@"shared");
    assert(count() == 0 && launches == 0);

    busy = true;
    set(@"once;;0.005;;0;;/script");
    waitUntilConsumed();
    assert(licenseChecks == 0 && launches == 0);
    const int before = admissionChecks.load();
    set(@"repeat;;1;;1;;/script");
    for (int attempt = 0; attempt < 500 && admissionChecks.load() == before; ++attempt) usleep(5000);
    remove(@"repeat");
    assert(admissionChecks.load() > before && licenseChecks == 0 && launches == 0);

    busy = false;
    set(@"once;;0.005;;0;;/script");
    assert(dispatch_semaphore_wait(launched, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    assert(count() == 0 && licenseChecks == 1 && launches == 1);

    licenseAllowed = false;
    set(@"denied;;0.005;;0;;/script");
    waitUntilConsumed();
    assert(licenseChecks == 2 && launches == 1);
    licenseAllowed = true;

    // remove cannot ACK while an already-admitted callback is still preparing its launch.
    blockLicense = true;
    set(@"gated;;0.005;;0;;/script");
    assert(dispatch_semaphore_wait(gateEntered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    dispatch_semaphore_t removing = dispatch_semaphore_create(0), removed = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            dispatch_semaphore_signal(removing);
            remove(@"gated");
            dispatch_semaphore_signal(removed);
        }
    });
    assert(dispatch_semaphore_wait(removing, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    assert(dispatch_semaphore_wait(removed, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)) != 0);
    dispatch_semaphore_signal(gateRelease);
    assert(dispatch_semaphore_wait(removed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    assert(count() == 0 && launches == 2);
    std::puts("Scheduler dispatch/ARC passed: 8,000 concurrent set/remove cycles, real timer delivery, busy admission and committed remove ACK.");
} }
