#import "BackgroundServiceScheduler.h"
#import "LicenseLifecycleCoordinator.h"
#import "StreamSupervisor.h"
#import <BackgroundTasks/BackgroundTasks.h>
#include "../../shared/TLinkBackgroundTaskRun.h"

static NSString *const kTLinkBackgroundRefreshIdentifier = @"com.tlinkauto.streamcontrol.refresh";
static NSString *const kTLinkBackgroundProcessingIdentifier = @"com.tlinkauto.streamcontrol.processing";
static NSString *const kTLinkBackgroundDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/background_service_scheduler.plist";
static const NSTimeInterval kTLinkRefreshDelay = 15.0 * 60.0;
static const NSTimeInterval kTLinkProcessingDelay = 30.0 * 60.0;
static const NSTimeInterval kTLinkTaskTimeout = 22.0;

@interface SCBackgroundServiceScheduler ()
@property(nonatomic, strong) SCStreamSupervisor *supervisor;
@property(nonatomic, strong) SCLicenseLifecycleCoordinator *licenseCoordinator;
@property(nonatomic, assign) BOOL refreshRegistered;
@property(nonatomic, assign) BOOL processingRegistered;
- (void)scheduleRefreshForReason:(NSString *)reason;
- (void)scheduleProcessingForReason:(NSString *)reason;
- (void)handleTask:(BGTask *)task kind:(NSString *)kind;
@end

@implementation SCBackgroundServiceScheduler

- (instancetype)initWithSupervisor:(SCStreamSupervisor *)supervisor
                 licenseCoordinator:(SCLicenseLifecycleCoordinator *)licenseCoordinator
{
    self = [super init];
    if (self) {
        _supervisor = supervisor;
        _licenseCoordinator = licenseCoordinator;
    }
    return self;
}

- (NSString *)diagnosticsPath
{
    return kTLinkBackgroundDiagnosticsPath;
}

- (uint64_t)nowMilliseconds
{
    return (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

- (void)updateDiagnostics:(NSDictionary<NSString *, id> *)values
{
    if (values.count == 0) return;
    @synchronized (self) {
        NSString *directory = [kTLinkBackgroundDiagnosticsPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSMutableDictionary *state = [[NSDictionary dictionaryWithContentsOfFile:kTLinkBackgroundDiagnosticsPath] mutableCopy];
        if (!state) state = [NSMutableDictionary dictionary];
        [state addEntriesFromDictionary:values];
        state[@"mode"] = @"best_effort_bgtaskscheduler_after_first_launch";
        state[@"updated_at_ms"] = @([self nowMilliseconds]);
        [state writeToFile:kTLinkBackgroundDiagnosticsPath atomically:YES];
    }
}

- (void)registerTasks
{
    if (self.refreshRegistered || self.processingRegistered) return;

    __weak SCBackgroundServiceScheduler *weakSelf = self;
    BOOL refreshRegistered = [[BGTaskScheduler sharedScheduler]
        registerForTaskWithIdentifier:kTLinkBackgroundRefreshIdentifier
                           usingQueue:nil
                        launchHandler:^(BGTask *task) {
        [weakSelf handleTask:task kind:@"refresh"];
    }];
    BOOL processingRegistered = [[BGTaskScheduler sharedScheduler]
        registerForTaskWithIdentifier:kTLinkBackgroundProcessingIdentifier
                           usingQueue:nil
                        launchHandler:^(BGTask *task) {
        [weakSelf handleTask:task kind:@"processing"];
    }];
    self.refreshRegistered = refreshRegistered;
    self.processingRegistered = processingRegistered;
    [self updateDiagnostics:@{
        @"registered_at_ms": @([self nowMilliseconds]),
        @"refresh_registered": @(refreshRegistered),
        @"processing_registered": @(processingRegistered),
    }];
    NSLog(@"[StreamControl][BackgroundService] registered refresh=%d processing=%d",
          refreshRegistered ? 1 : 0, processingRegistered ? 1 : 0);
}

- (void)scheduleRefreshForReason:(NSString *)reason
{
    if (!self.refreshRegistered) return;
    BGAppRefreshTaskRequest *request = [[BGAppRefreshTaskRequest alloc]
        initWithIdentifier:kTLinkBackgroundRefreshIdentifier];
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:kTLinkRefreshDelay];
    [[BGTaskScheduler sharedScheduler] cancelTaskRequestWithIdentifier:kTLinkBackgroundRefreshIdentifier];
    NSError *error = nil;
    BOOL submitted = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
    [self updateDiagnostics:@{
        @"refresh_submit_at_ms": @([self nowMilliseconds]),
        @"refresh_earliest_at_ms": @([self nowMilliseconds] + (uint64_t)(kTLinkRefreshDelay * 1000.0)),
        @"refresh_submit_reason": reason ?: @"unknown",
        @"refresh_submit_ok": @(submitted),
        @"refresh_submit_error": error.localizedDescription ?: @"",
        @"refresh_submit_error_code": error ? @(error.code) : @0,
    }];
}

- (void)scheduleProcessingForReason:(NSString *)reason
{
    if (!self.processingRegistered) return;
    BGProcessingTaskRequest *request = [[BGProcessingTaskRequest alloc]
        initWithIdentifier:kTLinkBackgroundProcessingIdentifier];
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:kTLinkProcessingDelay];
    request.requiresNetworkConnectivity = NO;
    request.requiresExternalPower = NO;
    [[BGTaskScheduler sharedScheduler] cancelTaskRequestWithIdentifier:kTLinkBackgroundProcessingIdentifier];
    NSError *error = nil;
    BOOL submitted = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
    [self updateDiagnostics:@{
        @"processing_submit_at_ms": @([self nowMilliseconds]),
        @"processing_earliest_at_ms": @([self nowMilliseconds] + (uint64_t)(kTLinkProcessingDelay * 1000.0)),
        @"processing_submit_reason": reason ?: @"unknown",
        @"processing_submit_ok": @(submitted),
        @"processing_submit_error": error.localizedDescription ?: @"",
        @"processing_submit_error_code": error ? @(error.code) : @0,
    }];
}

- (void)scheduleRecoveryTasksForReason:(NSString *)reason
{
    if (!self.refreshRegistered && !self.processingRegistered) {
        [self updateDiagnostics:@{
            @"schedule_skipped_at_ms": @([self nowMilliseconds]),
            @"schedule_skipped_reason": @"task_handlers_not_registered",
        }];
        return;
    }
    [self scheduleRefreshForReason:reason ?: @"unknown"];
    [self scheduleProcessingForReason:reason ?: @"unknown"];
}

- (void)handleTask:(BGTask *)task kind:(NSString *)kind
{
    if ([kind isEqualToString:@"processing"]) {
        [self scheduleProcessingForReason:@"handler_reschedule"];
    } else {
        [self scheduleRefreshForReason:@"handler_reschedule"];
    }

    uint64_t firedAt = [self nowMilliseconds];
    [self updateDiagnostics:@{
        @"last_fired_at_ms": @(firedAt),
        @"last_fired_kind": kind ?: @"unknown",
        @"last_result": @"running",
    }];

    // BEGIN owned background task run.
    __weak SCBackgroundServiceScheduler *weakSelf = self;
    auto run = std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success, NSString *detail, NSDictionary *license) {
        task.expirationHandler = nil;
        [task setTaskCompletedWithSuccess:success];
        SCBackgroundServiceScheduler *scheduler = weakSelf;
        NSMutableDictionary *values = [@{
            @"last_completed_at_ms": @([scheduler nowMilliseconds]),
            @"last_completed_kind": kind ?: @"unknown",
            @"last_result": success ? @"success" : @"failed",
            @"last_detail": detail ?: @"",
        } mutableCopy];
        if (license) [values addEntriesFromDictionary:license];
        [scheduler updateDiagnostics:values];
        NSLog(@"[StreamControl][BackgroundService] %@ completed success=%d detail=%@",
              kind, success ? 1 : 0, detail ?: @"");
    });

    @try {
        try {
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
            if (!timer) {
                run->finish(NO, @"background_task_watchdog_unavailable", nil);
                return;
            }
            dispatch_source_set_timer(timer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
            dispatch_source_set_event_handler(timer, ^{
                run->finish(NO, @"license_refresh_or_streamd_ensure_timeout_22s", nil);
            });
            dispatch_resume(timer);
            run->installTimer(timer);
            task.expirationHandler = ^{
                run->finish(NO, @"ios_expired_task_before_license_refresh_and_streamd_probe_completed", nil);
            };
            // Expiration may have won while its handler was being installed.
            if (run->finished()) task.expirationHandler = nil;
            run->arm((int64_t)(kTLinkTaskTimeout * NSEC_PER_SEC));

            void (^ensureService)(BOOL, NSString *) = ^(BOOL licenseSuccess, NSString *licenseDetail) {
                if (!run->beginEnsure()) return;
                @try {
                    try {
                        SCBackgroundServiceScheduler *scheduler = weakSelf;
                        if (!scheduler) {
                            run->finish(NO, @"background_scheduler_unavailable", nil);
                            return;
                        }
                        [scheduler.supervisor ensureServiceWithStartPermission:^BOOL {
                            return run->beginSupervisor();
                        } completion:^(BOOL running, NSString *detail) {
                            NSString *combined = [NSString stringWithFormat:@"license=%@ streamd=%@",
                                licenseDetail ?: @"unknown", detail ?: @"streamd_ensure_completed_without_detail"];
                            run->finish(licenseSuccess && running, combined, @{
                                @"last_license_result": licenseSuccess ? @"success_or_skipped" : @"failed",
                                @"last_license_detail": licenseDetail ?: @"",
                            });
                        }];
                    } catch (...) {
                        run->finish(NO, @"background_streamd_ensure_exception", nil);
                    }
                } @catch (NSException *exception) {
                    (void)exception;
                    run->finish(NO, @"background_streamd_ensure_exception", nil);
                }
            };
            if (!run->beginRefresh()) return;
            if (self.licenseCoordinator) {
                id<SCLicenseRefreshSubscription> subscription =
                    [self.licenseCoordinator subscribeToBackgroundRefreshWithCompletion:ensureService];
                if (!subscription) {
                    run->finish(NO, @"license_refresh_subscription_unavailable", nil);
                    return;
                }
                run->installCleanup(^{ [subscription cancel]; });
            } else {
                ensureService(YES, @"license_coordinator_unavailable_skipped");
            }
        } catch (...) {
            run->finish(NO, @"background_task_setup_or_refresh_exception", nil);
        }
    } @catch (NSException *exception) {
        (void)exception;
        run->finish(NO, @"background_task_setup_or_refresh_exception", nil);
    }
    // END owned background task run.
}

@end
