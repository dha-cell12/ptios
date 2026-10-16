#include "Scheduler.h"
#include "Common.h"
#include "Play.h"
#include "RuntimeUtils.h"
#import "../shared/TLinkRootfullLicensePolicy.h"

#import <UIKit/UIKit.h>
#include <atomic>
#include "../shared/TLinkSchedulerState.h"
#import "../shared/TLinkAutoLaunchConfig.h"

static NSString *const kAutoLaunchFileName = @"autolaunch.plist";
struct TLinkSchedulerTimer {
    dispatch_source_t source;
    NSString *script;
    void cancel() { dispatch_source_cancel(source); }
};
static TLinkSchedulerRegistry<TLinkSchedulerTimer> timerRegistry;
static char schedulerQueueKey;

static dispatch_queue_t schedulerQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.tlinkauto.scheduler", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, &schedulerQueueKey, &schedulerQueueKey, NULL);
    });
    return queue;
}

static void schedulerPerformSync(dispatch_block_t operation)
{
    dispatch_queue_t queue = schedulerQueue();
    if (dispatch_get_specific(&schedulerQueueKey)) operation();
    else dispatch_sync(queue, operation);
}

static NSError *schedulerError(NSString *message)
{
    return [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"-1;;%@\r\n", message]}];
}
// Scheduler license diagnostics.
static std::atomic<uint64_t> sTLinkSchedulerLicenseCheckCount{0};
static std::atomic<uint64_t> sTLinkSchedulerLicenseDeniedCount{0};

BOOL TLinkSchedulerScriptLaunchAllowed(NSString *source)
{
    sTLinkSchedulerLicenseCheckCount.fetch_add(1);
    NSString *denial = nil;
    if (TLinkRootfullLicenseComponentAllowed(@"script",
                                             source ?: @"scheduler",
                                             &denial)) {
        return YES;
    }

    sTLinkSchedulerLicenseDeniedCount.fetch_add(1);
    NSString *message = [NSString stringWithFormat:
        @"scheduler launch blocked by license source=%@ %@",
        source ?: @"scheduler",
        denial ?: @"license_required"];
    setLastScriptError(message);
    NSLog(@"com.tlinkauto.scheduler: %@", message);
    return NO;
}

NSDictionary *TLinkSchedulerLicenseDiagnostics(void)
{
    return @{
        @"heartbeat": @"launch_time_recheck",
        @"check_count": @(sTLinkSchedulerLicenseCheckCount.load()),
        @"denied_count": @(sTLinkSchedulerLicenseDeniedCount.load()),
    };
}

static NSString* autoLaunchFilePath(void)
{
    return [getDocumentRoot() stringByAppendingPathComponent:kAutoLaunchFileName];
}

static NSMutableDictionary* loadAutoLaunchConfig(void)
{
    NSString *path = autoLaunchFilePath();
    NSMutableDictionary *config = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!config)
    {
        config = [NSMutableDictionary dictionary];
    }
    return config;
}

NSString* setAutoLaunchFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *payload = eventData ? [NSString stringWithUTF8String:(char*)eventData] : nil;
    NSArray *data = [payload componentsSeparatedByString:@";;"];
    if ([data count] < 3)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Auto launch requires name, script, enabled.\r\n"}];
        }
        return nil;
    }

    NSString *name = data[0];
    NSString *script = data[1];
    BOOL enabled = [data[2] intValue] != 0;

    NSError *updateError = nil;
    if (!TLinkAutoLaunchSetEntry(autoLaunchFilePath(), name,
                                @{@"script": script, @"enabled": @(enabled)}, &updateError)) {
        if (error) *error = schedulerError(updateError.localizedDescription ?: @"Failed to update auto launch config.");
        return nil;
    }
    if (error) *error = nil;
    return @"";
}

NSString* listAutoLaunch(NSError **error)
{
    NSMutableDictionary *config = loadAutoLaunchConfig();
    NSMutableArray<NSString*> *entries = [NSMutableArray array];
    [config enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *obj, BOOL *stop) {
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        NSString *script = [obj[@"script"] isKindOfClass:[NSString class]] ? obj[@"script"] : @"";
        NSString *enabled = [obj[@"enabled"] respondsToSelector:@selector(boolValue)] && [obj[@"enabled"] boolValue] ? @"1" : @"0";
        [entries addObject:[NSString stringWithFormat:@"%@,,%@,,%@", key, script, enabled]];
    }];
    return [entries componentsJoinedByString:@";;"];
}

// Registry mutation, timer callbacks, admission and synchronous launch preparation share
// one background owner. No config/license work is performed by a main-run-loop timer.
static void schedulerTimerFired(const std::string &name, uint64_t generation)
{
    timerRegistry.fire(name, generation, !canStartScriptPlaying(), [](const TLinkSchedulerTimer &timer) {
        NSString *script = timer.script;
        if (!TLinkSchedulerScriptLaunchAllowed(@"scheduler_timer")) return;
        // Another ingress may have started a script while the license gate was running.
        if (!canStartScriptPlaying()) return;
        NSError *err = nil;
        playScript((UInt8*)[script UTF8String], &err);
        if (err) setLastScriptError(err.localizedDescription ?: @"scheduler script launch failed");
    });
}

NSString* setTimerFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *payload = eventData ? [NSString stringWithUTF8String:(char*)eventData] : nil;
    NSArray *data = [payload componentsSeparatedByString:@";;"];
    if (data.count < 4) {
        if (error) *error = schedulerError(@"Timer requires name, interval, repeat, script.");
        return nil;
    }
    NSString *name = data[0];
    NSString *script = data[3];
    BOOL repeat = [data[2] intValue] != 0;
    double interval = 0;
    NSScanner *scanner = [NSScanner scannerWithString:data[1]];
    uint64_t intervalNs = 0;
    if (![scanner scanDouble:&interval] || !scanner.isAtEnd ||
        !TLinkSchedulerInterval(interval, repeat, &intervalNs)) {
        if (error) *error = schedulerError(@"Timer interval must be finite and positive; repeating timers require at least 1 second.");
        return nil;
    }
    if (name.length == 0 || script.length == 0) {
        if (error) *error = schedulerError(@"Timer name and script are required.");
        return nil;
    }
    const std::string timerName(name.UTF8String);
    __block NSError *result = nil;
    schedulerPerformSync(^{
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, schedulerQueue());
        if (!source) { result = schedulerError(@"Unable to create timer."); return; }
        const uint64_t generation = timerRegistry.set(timerName, TLinkSchedulerTimer{source, script}, repeat);
        if (generation == 0) {
            dispatch_source_cancel(source);
            dispatch_resume(source); // Balance the initial suspension even on setup failure.
            result = schedulerError(@"Timer generation exhausted.");
            return;
        }
        dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNs),
                                  repeat ? intervalNs : DISPATCH_TIME_FOREVER, TLinkSchedulerLeeway(intervalNs));
        dispatch_source_set_event_handler(source, ^{
            @autoreleasepool { schedulerTimerFired(timerName, generation); }
        });
        dispatch_resume(source);
    });
    if (error) *error = result;
    return result ? nil : @"";
}

NSString* removeTimerFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *name = eventData ? [NSString stringWithUTF8String:(char*)eventData] : nil;
    if (name.length == 0) {
        if (error) *error = schedulerError(@"Timer name is required.");
        return nil;
    }
    const std::string timerName(name.UTF8String);
    schedulerPerformSync(^{ timerRegistry.remove(timerName); });
    if (error) *error = nil;
    return @"";
}

NSString* keepAwakeFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *value = [NSString stringWithFormat:@"%s", eventData];
    BOOL enabled = [value intValue] != 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = enabled;
    });
    return @"";
}

NSString* stopScriptFromRawData(NSError **error)
{
    stopScriptPlaying(error);
    return @"";
}
