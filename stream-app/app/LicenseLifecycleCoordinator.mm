#import "LicenseLifecycleCoordinator.h"
#import "LicenseManager.h"
#import "TLinkSocketClient.h"
#import "../../shared/TLinkLicenseVerifier.h"
#include <math.h>
#include <stdlib.h>

NSString *const SCLicenseLifecycleDidChangeNotification = @"SCLicenseLifecycleDidChangeNotification";

static NSString *const kTLinkLicenseLifecycleDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/license_lifecycle.plist";
static const NSTimeInterval kTLinkLicenseRefreshWindow = 6.0 * 60.0 * 60.0;
static const NSTimeInterval kTLinkLicenseBackoffBase = 60.0;
static const NSTimeInterval kTLinkLicenseBackoffMaximum = 6.0 * 60.0 * 60.0;

@interface SCLicenseLifecycleCoordinator ()
@property(nonatomic, strong) SCLicenseManager *manager;
@property(nonatomic, assign, getter=isRequestInFlight) BOOL requestInFlight;
@property(nonatomic, copy) NSString *operationKind;
@property(nonatomic, strong) NSMutableArray *pendingRefreshCompletions;
@end

@implementation SCLicenseLifecycleCoordinator

+ (instancetype)sharedCoordinator
{
    static SCLicenseLifecycleCoordinator *coordinator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [[SCLicenseLifecycleCoordinator alloc] init];
    });
    return coordinator;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _manager = [SCLicenseManager sharedManager];
        _pendingRefreshCompletions = [NSMutableArray array];
    }
    return self;
}

- (NSString *)diagnosticsPath
{
    return kTLinkLicenseLifecycleDiagnosticsPath;
}

- (uint64_t)nowMilliseconds
{
    return (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

- (NSDictionary *)diagnostics
{
    NSMutableDictionary *state = [[NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseLifecycleDiagnosticsPath] mutableCopy];
    if (!state) state = [NSMutableDictionary dictionary];
    @synchronized (self) {
        state[@"request_in_flight"] = @(self.requestInFlight);
        state[@"operation"] = self.operationKind ?: @"none";
    }
    state[@"path"] = kTLinkLicenseLifecycleDiagnosticsPath;
    return state;
}

- (void)updateDiagnostics:(NSDictionary *)values
{
    if (values.count == 0) return;
    @synchronized (self) {
        NSString *directory = [kTLinkLicenseLifecycleDiagnosticsPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSMutableDictionary *state = [[NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseLifecycleDiagnosticsPath] mutableCopy];
        if (!state) state = [NSMutableDictionary dictionary];
        [state addEntriesFromDictionary:values];
        state[@"mode"] = @"foreground_bg_single_flight_backoff_v1";
        state[@"updated_at_ms"] = @([self nowMilliseconds]);
        [state writeToFile:kTLinkLicenseLifecycleDiagnosticsPath atomically:YES];
    }
}

- (void)deliverCompletion:(SCLicenseLifecycleCompletion)completion success:(BOOL)success message:(NSString *)message
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(success, message ?: @"");
    });
}

- (BOOL)beginOperation:(NSString *)kind completion:(SCLicenseLifecycleCompletion)completion
{
    @synchronized (self) {
        if (self.requestInFlight) {
            if ([kind isEqualToString:@"refresh"] && [self.operationKind isEqualToString:@"refresh"] && completion) {
                [self.pendingRefreshCompletions addObject:[completion copy]];
            } else {
                [self deliverCompletion:completion success:NO message:@"license_request_in_progress"];
            }
            return NO;
        }
        self.requestInFlight = YES;
        self.operationKind = kind ?: @"unknown";
        if ([kind isEqualToString:@"refresh"] && completion) {
            [self.pendingRefreshCompletions addObject:[completion copy]];
        }
    }
    [self updateDiagnostics:@{
        @"request_in_flight": @YES,
        @"operation": kind ?: @"unknown",
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCLicenseLifecycleDidChangeNotification object:self];
    });
    return YES;
}

- (void)finishOperation:(NSString *)kind success:(BOOL)success message:(NSString *)message completion:(SCLicenseLifecycleCompletion)completion
{
    NSArray *refreshCompletions = nil;
    @synchronized (self) {
        if ([kind isEqualToString:@"refresh"]) {
            refreshCompletions = [self.pendingRefreshCompletions copy];
            [self.pendingRefreshCompletions removeAllObjects];
        }
        self.requestInFlight = NO;
        self.operationKind = @"none";
    }
    [self updateDiagnostics:@{
        @"request_in_flight": @NO,
        @"operation": @"none",
    }];
    if ([kind isEqualToString:@"refresh"]) {
        for (id value in refreshCompletions) {
            SCLicenseLifecycleCompletion callback = (SCLicenseLifecycleCompletion)value;
            [self deliverCompletion:callback success:success message:message];
        }
    } else {
        [self deliverCompletion:completion success:success message:message];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCLicenseLifecycleDidChangeNotification object:self];
    });
}

- (void)publishLicenseChange:(NSString *)reason
{
    TLinkLicenseInvalidateCache();
    uint64_t generation = TLinkLicenseGeneration();
    [self updateDiagnostics:@{
        @"last_change_at_ms": @([self nowMilliseconds]),
        @"last_change_reason": reason ?: @"unknown",
        @"license_generation": @(generation),
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCLicenseLifecycleDidChangeNotification
                                                            object:self
                                                          userInfo:@{@"reason": reason ?: @"unknown"}];
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:76 args:@[@"reload"] timeout:2.0];
        [self updateDiagnostics:@{
            @"streamd_invalidate_at_ms": @([self nowMilliseconds]),
            @"streamd_invalidate_response": response ?: @"no_response",
        }];
        if (![response hasPrefix:@"0;;"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *retry = [TLinkSocketClient requestTask:76 args:@[@"reload"] timeout:2.0];
                [self updateDiagnostics:@{
                    @"streamd_invalidate_retry_at_ms": @([self nowMilliseconds]),
                    @"streamd_invalidate_retry_response": retry ?: @"no_response",
                }];
            });
        }
    });
}

- (BOOL)automaticRefreshNeededForStatus:(NSDictionary *)status reason:(NSString **)reason
{
    NSString *state = [status[@"state"] isKindOfClass:[NSString class]] ? status[@"state"] : @"invalid";
    if ([state isEqualToString:@"offline_grace"]) {
        if (reason) *reason = @"offline_grace_refresh_required";
        return YES;
    }
    if (![state isEqualToString:@"valid"]) {
        if (reason) *reason = [NSString stringWithFormat:@"state_%@_does_not_auto_refresh", state];
        return NO;
    }
    NSTimeInterval expiresAt = [status[@"expires_at"] doubleValue];
    NSTimeInterval remaining = expiresAt - [[NSDate date] timeIntervalSince1970];
    if (expiresAt <= 0 || remaining > kTLinkLicenseRefreshWindow) {
        if (reason) *reason = @"lease_outside_six_hour_refresh_window";
        return NO;
    }
    if (reason) *reason = @"lease_inside_six_hour_refresh_window";
    return YES;
}

- (BOOL)backoffAllowsAttempt:(NSString **)reason
{
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseLifecycleDiagnosticsPath];
    uint64_t nextAttempt = [state[@"next_attempt_at_ms"] unsignedLongLongValue];
    uint64_t now = [self nowMilliseconds];
    if (nextAttempt > now) {
        if (reason) *reason = [NSString stringWithFormat:@"refresh_backoff_until_%llu",
                              (unsigned long long)nextAttempt];
        return NO;
    }
    return YES;
}

- (void)recordRefreshFailure:(NSString *)message trigger:(NSString *)trigger
{
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kTLinkLicenseLifecycleDiagnosticsPath];
    NSInteger failures = MIN(16, [existing[@"consecutive_failures"] integerValue] + 1);
    NSInteger exponent = MIN(8, failures - 1);
    NSTimeInterval delay = MIN(kTLinkLicenseBackoffMaximum,
                               kTLinkLicenseBackoffBase * pow(2.0, (double)exponent));
    uint32_t jitterValue = arc4random_uniform(4001);
    double jitter = 0.8 + ((double)jitterValue / 10000.0);
    uint64_t nextAttempt = [self nowMilliseconds] + (uint64_t)(delay * jitter * 1000.0);
    [self updateDiagnostics:@{
        @"last_result": @"failed",
        @"last_error": message ?: @"license_refresh_failed",
        @"last_trigger": trigger ?: @"unknown",
        @"consecutive_failures": @(failures),
        @"next_attempt_at_ms": @(nextAttempt),
    }];
}

- (void)refreshForTrigger:(NSString *)trigger force:(BOOL)force completion:(SCLicenseLifecycleCompletion)completion
{
    NSDictionary *status = [self.manager localStatus];
    NSString *decision = nil;
    if (!force && ![self automaticRefreshNeededForStatus:status reason:&decision]) {
        [self updateDiagnostics:@{
            @"last_decision_at_ms": @([self nowMilliseconds]),
            @"last_decision": decision ?: @"refresh_not_needed",
            @"last_trigger": trigger ?: @"unknown",
        }];
        [self deliverCompletion:completion success:YES message:decision ?: @"license_refresh_not_needed"];
        return;
    }
    if (!force && ![self backoffAllowsAttempt:&decision]) {
        [self updateDiagnostics:@{
            @"last_decision_at_ms": @([self nowMilliseconds]),
            @"last_decision": decision ?: @"refresh_backoff_active",
            @"last_trigger": trigger ?: @"unknown",
        }];
        [self deliverCompletion:completion success:YES message:decision ?: @"license_refresh_backoff_active"];
        return;
    }
    if (![self beginOperation:@"refresh" completion:completion]) return;
    [self updateDiagnostics:@{
        @"last_attempt_at_ms": @([self nowMilliseconds]),
        @"last_trigger": trigger ?: @"unknown",
        @"last_decision": force ? @"manual_force_refresh" : (decision ?: @"automatic_refresh"),
    }];
    [self.manager refreshLeaseWithCompletion:^(BOOL success, NSString *message) {
        if (success) {
            [self updateDiagnostics:@{
                @"last_success_at_ms": @([self nowMilliseconds]),
                @"last_result": @"success",
                @"last_error": @"",
                @"consecutive_failures": @0,
                @"next_attempt_at_ms": @0,
            }];
            [self publishLicenseChange:@"refresh"];
        } else {
            [self recordRefreshFailure:message trigger:trigger];
        }
        [self finishOperation:@"refresh" success:success message:message completion:nil];
    }];
}

- (void)handleApplicationLaunch
{
    [self updateDiagnostics:@{
        @"last_launch_at_ms": @([self nowMilliseconds]),
        @"lifecycle_policy": @"refresh_valid_under_6h_or_offline_grace",
    }];
    [self refreshForTrigger:@"app_launch" force:NO completion:nil];
}

- (void)handleApplicationDidBecomeActive
{
    [self updateDiagnostics:@{@"last_foreground_at_ms": @([self nowMilliseconds])}];
    [self refreshForTrigger:@"app_foreground" force:NO completion:nil];
}

- (void)performBackgroundRefreshWithCompletion:(SCLicenseLifecycleCompletion)completion
{
    [self updateDiagnostics:@{@"last_background_trigger_at_ms": @([self nowMilliseconds])}];
    [self refreshForTrigger:@"bg_task" force:NO completion:completion];
}

- (void)activateLicenseKey:(NSString *)licenseKey completion:(SCLicenseLifecycleCompletion)completion
{
    if (![self beginOperation:@"activate" completion:nil]) {
        [self deliverCompletion:completion success:NO message:@"license_request_in_progress"];
        return;
    }
    [self.manager activateLicenseKey:licenseKey completion:^(BOOL success, NSString *message) {
        [self updateDiagnostics:@{
            @"last_activation_at_ms": @([self nowMilliseconds]),
            @"last_activation_result": success ? @"success" : @"failed",
            @"last_activation_error": success ? @"" : (message ?: @"license_activation_failed"),
        }];
        if (success) [self publishLicenseChange:@"activation"];
        [self finishOperation:@"activate" success:success message:message completion:completion];
    }];
}

- (void)refreshManuallyWithCompletion:(SCLicenseLifecycleCompletion)completion
{
    [self refreshForTrigger:@"manual" force:YES completion:completion];
}

- (void)deactivateWithCompletion:(SCLicenseLifecycleCompletion)completion
{
    if (![self beginOperation:@"deactivate" completion:nil]) {
        [self deliverCompletion:completion success:NO message:@"license_request_in_progress"];
        return;
    }
    [self.manager deactivateLeaseWithCompletion:^(BOOL success, NSString *message) {
        [self updateDiagnostics:@{
            @"last_deactivation_at_ms": @([self nowMilliseconds]),
            @"last_deactivation_result": success ? @"success" : @"failed",
            @"last_deactivation_error": success ? @"" : (message ?: @"license_deactivation_failed"),
        }];
        if (success) [self publishLicenseChange:@"deactivation"];
        [self finishOperation:@"deactivate" success:success message:message completion:completion];
    }];
}

- (BOOL)removeLocalLease:(NSError **)error
{
    @synchronized (self) {
        if (self.requestInFlight) {
            if (error) {
                *error = [NSError errorWithDomain:@"TLinkLicense"
                                              code:70
                                          userInfo:@{NSLocalizedDescriptionKey: @"license_request_in_progress"}];
            }
            return NO;
        }
    }
    BOOL removed = [self.manager removeLocalLease:error];
    if (removed) [self publishLicenseChange:@"remove_local_lease"];
    return removed;
}

@end
