#import "TLinkJSHelperServer.h"
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
#import "../shared/TLinkJSFileHandle.h"
#include "../shared/TLinkHelperRPCIdentity.h"
#include "../shared/TLinkHelperSocketIO.h"
#include "../shared/TLinkHelperRequestDeadline.h"
#include "../shared/TLinkHelperClientAdmission.h"
#include "../shared/TLinkHelperCommandGate.h"
#include "../shared/TLinkHelperChangeWait.h"
#include "../shared/TLinkHelperWaitPeer.h"
#import "../shared/TLinkRootfullLicensePolicy.h"
#import <JavaScriptCore/JavaScriptCore.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <math.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <signal.h>
#include <atomic>

static NSString * const kTLinkJSHelperSocketPath = @"/var/mobile/Library/TLinkauto/run/js-helper.sock";
static NSString * const kTLinkJSHelperPidPath = @"/var/mobile/Library/TLinkauto/run/js-helper.pid";
static NSString * const kTLinkJSHelperVersion = @"1.2.0";
static const unsigned long long kTLinkJSHelperMaxBundleFileBytes = 512 * 1024;
static const unsigned long long kTLinkJSHelperMaxStorageFileBytes = 512 * 1024;
static const unsigned long long kTLinkJSHelperMaxConsoleLogBytes = 512 * 1024;
static const NSUInteger kTLinkJSHelperMaxOpenFiles = 32;
static const double kTLinkJSHelperWatchdogInterval = 0.1;

typedef bool (*TLinkJSHelperShouldTerminateCallback)(JSContextRef ctx, void *opaque);
typedef void (*TLinkJSHelperSetExecutionTimeLimitFn)(JSContextGroupRef group, double limit, TLinkJSHelperShouldTerminateCallback callback, void *opaque);
typedef void (*TLinkJSHelperClearExecutionTimeLimitFn)(JSContextGroupRef group);

struct TLinkJSHelperCancelState {
    std::atomic<bool> stopped;
};

static bool TLinkJSHelperShouldTerminate(JSContextRef ctx, void *opaque) {
    (void)ctx;
    TLinkJSHelperCancelState *state = (TLinkJSHelperCancelState *)opaque;
    return state && state->stopped.load(std::memory_order_acquire);
}

@interface TLinkJSHelperServer () {
    TLinkJSHelperCancelState *_cancelState;
    TLinkHelperClientAdmission _clientAdmission;
    TLinkHelperCommandGate _clientCommandOwner;
    TLinkHelperChangeWait _statusChanges;
    TLinkJSHelperSetExecutionTimeLimitFn _setExecutionTimeLimit;
    TLinkJSHelperClearExecutionTimeLimitFn _clearExecutionTimeLimit;
}
@property(nonatomic, copy) NSString *helperInstanceId;
@property(nonatomic, strong) NSDate *startedAt;
@property(nonatomic, strong) dispatch_queue_t executionQueue;
@property(nonatomic, strong) dispatch_queue_t clientQueue;
@property(nonatomic, strong) NSCondition *sleepCondition;
@property(nonatomic, assign) BOOL sessionCompletionCommitted;
@property(nonatomic, assign) BOOL sessionWorkerActive; // rpcCondition owns lifecycle + RPC slot
@property(nonatomic, copy) NSString *activeSessionId;
@property(nonatomic, copy) NSString *activeRunId;
@property(nonatomic, copy) NSString *activeState;
@property(nonatomic, strong) NSDate *activeStartedAt;
@property(nonatomic, strong) NSDate *activeEndedAt;
@property(nonatomic, copy) NSString *activeExitReason;
@property(atomic, assign) NSUInteger nativeRPCCount;
@property(atomic, assign) NSUInteger nativeRPCFailedCount;
@property(atomic, assign) NSUInteger nativeRPCBlockedCount;
@property(atomic, assign) NSUInteger storageOpsCount;
@property(atomic, assign) double nativeRPCTotalMs;
@property(atomic, assign) double nativeRPCMaxMs;
@property(nonatomic, assign) double evalDurationMs;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, copy) NSString *lastConsoleLogPath;
@property(nonatomic, copy) NSString *lastConsoleLatestLogPath;
@property(nonatomic, strong) NSCondition *rpcCondition;
@property(nonatomic, copy) NSDictionary *pendingNativeRequest;
@property(nonatomic, copy) NSDictionary *nativeResponse;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, TLinkJSFileHandle *> *activeFileHandles;
@property(nonatomic, assign) NSUInteger nextFileHandleId;
@property(nonatomic, strong) dispatch_source_t licenseHeartbeat;
@property(nonatomic, copy) NSString *licenseHeartbeatSessionId;
@property(atomic, assign) NSUInteger licenseHeartbeatCheckCount;
@property(atomic, assign) NSUInteger licenseRevocationCount;
@end

@implementation TLinkJSHelperServer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _helperInstanceId = [[NSUUID UUID] UUIDString];
        _startedAt = [NSDate date];
        _executionQueue = dispatch_queue_create("com.tlinkauto.js-helper.execution", DISPATCH_QUEUE_SERIAL);
        _clientQueue = dispatch_queue_create("com.tlinkauto.js-helper.clients", DISPATCH_QUEUE_CONCURRENT);
        _sleepCondition = [[NSCondition alloc] init];
        _rpcCondition = [[NSCondition alloc] init];
        _activeFileHandles = [NSMutableDictionary dictionary];
        _nextFileHandleId = 1;
        _activeState = kTLinkJSHelperStateIdle;
        _cancelState = new TLinkJSHelperCancelState();
        _cancelState->stopped.store(false, std::memory_order_relaxed);
        _setExecutionTimeLimit = (TLinkJSHelperSetExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
        _clearExecutionTimeLimit = (TLinkJSHelperClearExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
    }
    return self;
}

- (void)dealloc
{
    if (self.licenseHeartbeat) dispatch_source_cancel(self.licenseHeartbeat);
    for (TLinkJSFileHandle *handle in self.activeFileHandles.allValues) [handle close];
    delete _cancelState;
}

static NSString *TLinkJSHelperSanitizeFileComponent(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return @"script";
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
    NSString *joined = [[value componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"_"];
    return [joined length] > 0 ? joined : @"script";
}

static int TLinkJSHelperHardwareKeyType(NSString *key) {
    NSString *k = [(key ? key : @"") lowercaseString];
    if ([k isEqualToString:@"home"]) return 1;
    if ([k isEqualToString:@"volume-up"] || [k isEqualToString:@"volumeup"]) return 2;
    if ([k isEqualToString:@"volume-down"] || [k isEqualToString:@"volumedown"]) return 3;
    if ([k isEqualToString:@"lock"] || [k isEqualToString:@"power"]) return 4;
    return -1;
}

static int TLinkJSHelperHardwareKeyAction(NSString *action) {
    NSString *a = [(action ? action : @"") lowercaseString];
    if ([a isEqualToString:@"up"]) return 0;
    if ([a isEqualToString:@"down"]) return 1;
    return -1;
}

static int TLinkJSHelperTouchIndicatorAction(NSString *action) {
    NSString *a = [(action ? action : @"") lowercaseString];
    if ([a isEqualToString:@"show"]) return 1;
    if ([a isEqualToString:@"hide"]) return 0;
    if ([a isEqualToString:@"reload"]) return 2;
    return -1;
}

// BEGIN helper session ownership.
- (BOOL)sessionIsBusy
{
    [self.rpcCondition lock];
    @try { return self.sessionWorkerActive; } @finally { [self.rpcCondition unlock]; }
}
- (BOOL)ownsSessionId:(NSString *)sessionId
{
    [self.rpcCondition lock];
    @try {return self.sessionWorkerActive && [self.activeSessionId isEqualToString:sessionId];}
    @finally {[self.rpcCondition unlock];}
}
- (BOOL)beginSessionId:(NSString *)sessionId runId:(NSString *)runId
{
    [self.rpcCondition lock];
    @try {
        if (self.sessionWorkerActive) return false;
        self.sessionWorkerActive=true;self.sessionCompletionCommitted=false;
        self.activeSessionId=sessionId;self.activeRunId=runId;
        self.activeStartedAt=[NSDate date];self.activeEndedAt=nil;self.activeExitReason=@"";
        self.nativeRPCCount=0;self.nativeRPCFailedCount=0;self.nativeRPCBlockedCount=0;self.storageOpsCount=0;
        self.nativeRPCTotalMs=0;self.nativeRPCMaxMs=0;self.evalDurationMs=0;
        self.lastError=@"";self.lastConsoleLogPath=@"";self.lastConsoleLatestLogPath=@"";
        self.pendingNativeRequest=nil;self.nativeResponse=nil;
        self.activeState=kTLinkJSHelperStateStarting;
        _cancelState->stopped.store(false,std::memory_order_release);
        [self publishStatusChange];return true;
    } @finally { [self.rpcCondition unlock]; }
}
- (void)setPathsForSessionId:(NSString *)sessionId logPath:(NSString *)logPath latestPath:(NSString *)latestPath
{
    [self.rpcCondition lock];
    @try {
        if (self.sessionWorkerActive && !self.sessionCompletionCommitted && [self.activeSessionId isEqualToString:sessionId]) {
            self.lastConsoleLogPath=logPath;self.lastConsoleLatestLogPath=latestPath;
        }
    } @finally {[self.rpcCondition unlock];}
}
- (BOOL)markRunningSessionId:(NSString *)sessionId logPath:(NSString *)logPath latestPath:(NSString *)latestPath
{
    [self.rpcCondition lock];
    @try {
        if (!self.sessionWorkerActive || ![self.activeSessionId isEqualToString:sessionId] ||
            _cancelState->stopped.load(std::memory_order_acquire) || ![self.activeState isEqualToString:kTLinkJSHelperStateStarting]) return false;
        self.lastConsoleLogPath=logPath;self.lastConsoleLatestLogPath=latestPath;
        self.activeState=kTLinkJSHelperStateRunning;[self publishStatusChange];return true;
    } @finally { [self.rpcCondition unlock]; }
}
- (void)recordSessionId:(NSString *)sessionId error:(NSString *)text durationMs:(double)duration
{
    [self.rpcCondition lock];
    @try {
        if (!self.sessionWorkerActive || self.sessionCompletionCommitted || ![self.activeSessionId isEqualToString:sessionId]) return;
        if (text) self.lastError=text;
        if (duration>=0) self.evalDurationMs=duration;
    } @finally { [self.rpcCondition unlock]; }
}
- (NSString *)requestStopForSessionId:(NSString *)sessionId reason:(NSString *)reason errorText:(NSString *)errorText
{
    BOOL wake=false;
    [self.rpcCondition lock];
    @try {
        if (sessionId && self.activeSessionId && ![self.activeSessionId isEqualToString:sessionId]) return @"session_mismatch";
        if (self.sessionWorkerActive && ([self.activeState isEqualToString:kTLinkJSHelperStateStarting] || [self.activeState isEqualToString:kTLinkJSHelperStateRunning])) {
            self.activeState=kTLinkJSHelperStateStopping;
            if (reason) {self.activeExitReason=reason;self.licenseRevocationCount++;}
            if (errorText) self.lastError=errorText;
            _cancelState->stopped.store(true,std::memory_order_release);
            [self publishStatusChange];[self.rpcCondition broadcast];wake=true;
        }
    } @finally { [self.rpcCondition unlock]; }
    if (wake) {[self.sleepCondition lock];[self.sleepCondition broadcast];[self.sleepCondition unlock];}
    return nil;
}
- (NSDictionary *)completeSessionId:(NSString *)sessionId state:(NSString *)state reason:(NSString *)reason errorText:(NSString *)errorText
{
    [self.rpcCondition lock];
    @try {
        if (!self.sessionWorkerActive || self.sessionCompletionCommitted || ![self.activeSessionId isEqualToString:sessionId]) return nil;
        self.sessionCompletionCommitted=true;
        const bool cancelled=_cancelState->stopped.load(std::memory_order_acquire);
        self.activeState=cancelled?kTLinkJSHelperStateCancelled:(state ?: kTLinkJSHelperStateFailed);
        if (![self.activeExitReason length]) self.activeExitReason=cancelled?@"cancelled":(reason ?: @"unknown");
        self.activeEndedAt=[NSDate date];
        if (errorText.length && ![self.activeExitReason isEqualToString:@"license_revoked_during_execution"]) self.lastError=errorText;
        self.pendingNativeRequest=nil;self.nativeResponse=nil;
        NSDictionary *summary=@{@"state":self.activeState,@"exitReason":self.activeExitReason,
            @"runId":self.activeRunId ?: @"",@"durationMs":@((long long)(self.activeStartedAt?[self.activeEndedAt timeIntervalSinceDate:self.activeStartedAt]*1000.0:0)),
            @"rpcCount":@(self.nativeRPCCount),@"rpcFailedCount":@(self.nativeRPCFailedCount),@"blockedRpcCount":@(self.nativeRPCBlockedCount),
            @"storageOpsCount":@(self.storageOpsCount),@"rpcAvgMs":@(self.nativeRPCCount?self.nativeRPCTotalMs/(double)self.nativeRPCCount:0),
            @"rpcMaxMs":@(self.nativeRPCMaxMs),@"evalDurationMs":@(self.evalDurationMs),@"lastError":self.lastError ?: @""};
        [self publishStatusChange];[self.rpcCondition broadcast];return summary;
    } @finally { [self.rpcCondition unlock]; }
}
- (void)retireSessionId:(NSString *)sessionId
{
    [self.rpcCondition lock];
    @try {
        if (!self.sessionWorkerActive || ![self.activeSessionId isEqualToString:sessionId]) return;
        if (!self.sessionCompletionCommitted) {
            self.activeState=kTLinkJSHelperStateFailed;self.activeExitReason=@"helper_cleanup_incomplete";self.activeEndedAt=[NSDate date];
            self.pendingNativeRequest=nil;self.nativeResponse=nil;self.sessionCompletionCommitted=true;
            [self.rpcCondition broadcast];
        }
        self.sessionWorkerActive=false;[self publishStatusChange];
    } @finally { [self.rpcCondition unlock]; }
}
// END helper session ownership.

// BEGIN helper change publication.
- (void)publishStatusChange { _statusChanges.publish(); }
// END helper change publication.

- (NSDictionary *)statusPayload
{
    // Capture BEFORE reading state/slot: a concurrent later publication must wake this cursor.
    const uint64_t changeSequence = _statusChanges.sequence();
    const auto clients = _clientAdmission.stats();
    NSUInteger openFiles=0,heartbeatChecks=0,revocations=0;BOOL heartbeatActive=false;
    @synchronized (self) {
        openFiles=self.activeFileHandles.count;heartbeatActive=self.licenseHeartbeat!=nil;
        heartbeatChecks=self.licenseHeartbeatCheckCount;revocations=self.licenseRevocationCount;
    }
    [self.rpcCondition lock];
    @try {
        NSTimeInterval uptimeMs = [[NSDate date] timeIntervalSinceDate:self.startedAt] * 1000.0;
        NSDate *durationEnd = self.activeEndedAt ?: [NSDate date];
        long long startedAtMs = self.activeStartedAt ? (long long)([self.activeStartedAt timeIntervalSince1970] * 1000.0) : 0;
        long long endedAtMs = self.activeEndedAt ? (long long)([self.activeEndedAt timeIntervalSince1970] * 1000.0) : 0;
        long long durationMs = self.activeStartedAt ? (long long)([durationEnd timeIntervalSinceDate:self.activeStartedAt] * 1000.0) : 0;
        NSMutableDictionary *payload = [@{
            @"state": self.activeState ?: kTLinkJSHelperStateIdle,
            @"sessionWorkerActive": @(self.sessionWorkerActive),
            @"sessionSnapshotContract": @"lifecycle_rpc_owner_v1",
            @"changeSequence": @(changeSequence),
            @"changeWaitContract": @"session_native_rpc_v1",
            @"changeWaitPeerEOFContract": @"cancel_v1",
            @"changeWaitersActive": @(_statusChanges.waiters()),
            @"changeWaitersLimit": @(TLinkHelperChangeWait::Limit),
            @"changeWaitMaxMs": @(TLinkHelperChangeWait::MaxWaitMs),
            @"socketClientsActive": @(clients.active),
            @"socketClientsLimit": @(clients.limit),
            @"socketClientsRejected": @(clients.rejected),
            @"activeSessionId": self.activeSessionId ?: [NSNull null],
            @"runId": self.activeRunId ?: @"",
            @"uptimeMs": @((long long)uptimeMs),
            @"startedAtMs": @(startedAtMs),
            @"endedAtMs": @(endedAtMs),
            @"durationMs": @(durationMs),
            @"exitReason": self.activeExitReason ?: @"",
            @"rpcCount": @(self.nativeRPCCount),
            @"rpcFailedCount": @(self.nativeRPCFailedCount),
            @"blockedRpcCount": @(self.nativeRPCBlockedCount),
            @"storageOpsCount": @(self.storageOpsCount),
            @"openFileHandles": @(openFiles),
            @"rpcAvgMs": @(self.nativeRPCCount > 0 ? (self.nativeRPCTotalMs / (double)self.nativeRPCCount) : 0),
            @"rpcMaxMs": @(self.nativeRPCMaxMs),
            @"evalDurationMs": @(self.evalDurationMs),
            @"lastError": self.lastError ?: @"",
            @"consoleLogPath": self.lastConsoleLogPath ?: @"",
            @"consoleLatestLogPath": self.lastConsoleLatestLogPath ?: @"",
            @"licenseHeartbeatActive": @(heartbeatActive),
            @"licenseHeartbeatIntervalMs": @1000,
            @"licenseHeartbeatCheckCount": @(heartbeatChecks),
            @"licenseRevocationCount": @(revocations),
        } mutableCopy];
        const bool dispatchable=[self.activeState isEqualToString:kTLinkJSHelperStateRunning] && self.pendingNativeRequest != nil;
        payload[@"pendingNativeRPC"] = @(dispatchable);
        if (dispatchable) {
            payload[@"nativeRPCRequest"] = self.pendingNativeRequest;
        }
        return [payload copy];
    } @finally { [self.rpcCondition unlock]; }
}

- (void)stopLicenseHeartbeatForSessionId:(NSString *)sessionId
{
    @synchronized (self) {
        if (sessionId.length > 0 &&
            self.licenseHeartbeatSessionId.length > 0 &&
            ![sessionId isEqualToString:self.licenseHeartbeatSessionId]) {
            return;
        }
        if (self.licenseHeartbeat) {
            dispatch_source_cancel(self.licenseHeartbeat);
            self.licenseHeartbeat = nil;
        }
        self.licenseHeartbeatSessionId = nil;
    }
}

- (void)startLicenseHeartbeatForSessionId:(NSString *)sessionId
{
    if (sessionId.length == 0) return;
    [self stopLicenseHeartbeatForSessionId:nil];

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0,
                                                     0,
                                                     dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    if (!timer) return;
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              NSEC_PER_SEC,
                              100 * NSEC_PER_MSEC);
    __weak TLinkJSHelperServer *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        TLinkJSHelperServer *strongSelf = weakSelf;
        if (!strongSelf) return;
        @synchronized (strongSelf) {
            if (![strongSelf.licenseHeartbeatSessionId isEqualToString:sessionId]) return;
            strongSelf.licenseHeartbeatCheckCount++;
        }

        NSString *denial = nil;
        if (TLinkRootfullLicenseComponentAllowed(@"script",
                                                 @"script_helper",
                                                 &denial)) {
            return;
        }

        @synchronized (strongSelf) {
            if (![strongSelf.licenseHeartbeatSessionId isEqualToString:sessionId]) return;
        }
        [strongSelf requestStopForSessionId:sessionId reason:@"license_revoked_during_execution"
            errorText:[NSString stringWithFormat:@"license_revoked_during_execution %@",denial ?: @"license_required"]];
        NSLog(@"tlinkauto-jsd: license_revoked_during_execution session=%@ denial=%@",sessionId,denial ?: @"license_required");
        [strongSelf stopLicenseHeartbeatForSessionId:sessionId];
    });

    @synchronized (self) {
        self.licenseHeartbeat = timer;
        self.licenseHeartbeatSessionId = sessionId;
    }
    dispatch_resume(timer);
}

- (NSString *)licenseDenialForComponent:(NSString *)component
{
    NSString *denial = nil;
    if (TLinkRootfullLicenseComponentAllowed(@"script",
                                             component ?: @"script_helper",
                                             &denial)) {
        return nil;
    }
    return denial ?: @"-1;;license_required component=script_helper feature=script";
}

- (NSDictionary *)executeNativeRPCMethod:(NSString *)method arguments:(NSArray *)arguments sessionId:(NSString *)sessionId
{
    if (![method isKindOfClass:[NSString class]] || [method length] == 0) {
        return @{ @"ok": @NO, @"error": @"native RPC method is required" };
    }
    NSDate *rpcStartedAt = [NSDate date];
    NSString *requestId = [[NSUUID UUID] UUIDString];
    NSDictionary *request = @{
        kTLinkJSHelperKeyRequestId: requestId,
        @"method": method,
        @"arguments": arguments ?: @[],
        @"sessionId": sessionId ?: @"",
        @"helperInstanceId": self.helperInstanceId,
    };
    NSTimeInterval nativeRPCTimeout = [method isEqualToString:@"zoom"] ? 7.0 : 5.0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:nativeRPCTimeout];
    [self.rpcCondition lock];
    @try {
        if (![self.activeSessionId isEqualToString:sessionId]) {
            return @{@"ok":@(false),@"error":@"native RPC unavailable"};
        }
        self.nativeRPCCount++;
        while (self.pendingNativeRequest && !_cancelState->stopped.load(std::memory_order_acquire)) {
            if (![self.rpcCondition waitUntilDate:deadline]) break;
        }
        if (self.pendingNativeRequest || _cancelState->stopped.load(std::memory_order_acquire) ||
            ![self.activeSessionId isEqualToString:sessionId]) {
            double elapsedMs = [[NSDate date] timeIntervalSinceDate:rpcStartedAt] * 1000.0;
            self.nativeRPCTotalMs += elapsedMs;
            if (elapsedMs > self.nativeRPCMaxMs) self.nativeRPCMaxMs = elapsedMs;
            self.nativeRPCFailedCount++;

            return @{ @"ok": @NO, @"error": @"native RPC unavailable" };
        }
        self.nativeResponse = nil;
        self.pendingNativeRequest = request;
        [self publishStatusChange];
        NSLog(@"tlinkauto-jsd rpc: request method=%@ id=%@", method, requestId);
        [self.rpcCondition broadcast];
        while (!_cancelState->stopped.load(std::memory_order_acquire) &&
               [self.pendingNativeRequest[@"requestId"] isEqualToString:requestId] &&
               [self.pendingNativeRequest[@"sessionId"] isEqualToString:sessionId]) {
            NSDictionary *response = self.nativeResponse;
            if (response) {
                self.nativeResponse = nil;
                self.pendingNativeRequest = nil;
                [self publishStatusChange];
                double elapsedMs = [[NSDate date] timeIntervalSinceDate:rpcStartedAt] * 1000.0;
                self.nativeRPCTotalMs += elapsedMs;
                if (elapsedMs > self.nativeRPCMaxMs) self.nativeRPCMaxMs = elapsedMs;
                BOOL responseOK = [response[@"ok"] boolValue];
                if (!responseOK) {
                    self.nativeRPCFailedCount++;
                    NSString *err = [response[@"error"] isKindOfClass:[NSString class]] ? response[@"error"] : @"";
                    if ([err rangeOfString:@"blocked by policy"].location != NSNotFound) self.nativeRPCBlockedCount++;
                }
                NSLog(@"tlinkauto-jsd rpc: response id=%@ ok=%d", requestId, responseOK);
                [self.rpcCondition broadcast];

                return response;
            }
            if (![self.rpcCondition waitUntilDate:deadline]) break;
        }
        if ([self.pendingNativeRequest[@"requestId"] isEqualToString:requestId] &&
            [self.pendingNativeRequest[@"sessionId"] isEqualToString:sessionId]) {
            self.pendingNativeRequest = nil;
            self.nativeResponse = nil;
            [self publishStatusChange];
        }
        double elapsedMs = [[NSDate date] timeIntervalSinceDate:rpcStartedAt] * 1000.0;
        self.nativeRPCTotalMs += elapsedMs;
        if (elapsedMs > self.nativeRPCMaxMs) self.nativeRPCMaxMs = elapsedMs;
        self.nativeRPCFailedCount++;
        [self.rpcCondition broadcast];
        return @{ @"ok": @NO, @"error": @"native RPC timed out" };
    } @finally {[self.rpcCondition unlock];}
}

// BEGIN helper RPC slot cleanup.
- (void)clearNativeRPCForSessionId:(NSString *)sessionId
{
    [self.rpcCondition lock];
    if (!self.pendingNativeRequest || [self.pendingNativeRequest[@"sessionId"] isEqualToString:sessionId]) {
        const bool changed = self.pendingNativeRequest != nil || self.nativeResponse != nil;
        self.pendingNativeRequest = nil;
        self.nativeResponse = nil;
        if (changed) [self publishStatusChange];
    }
    [self.rpcCondition broadcast];
    [self.rpcCondition unlock];
}
// END helper RPC slot cleanup.

- (NSString *)consoleLogPathForBundlePath:(NSString *)bundlePath runId:(NSString *)runId latest:(BOOL)latest
{
    NSString *dir = [bundlePath stringByAppendingPathComponent:@"_logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    if (latest) return [dir stringByAppendingPathComponent:@"latest-helper.log"];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-helper.log", TLinkJSHelperSanitizeFileComponent(runId)]];
}

- (void)appendLine:(NSString *)line toPath:(NSString *)path
{
    if (![line isKindOfClass:[NSString class]] || ![path isKindOfClass:[NSString class]] || [path length] == 0) return;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkJSHelperMaxConsoleLogBytes) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @finally {
        [handle closeFile];
    }
}

- (NSDictionary *)bundleTextForRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    NSString *root = [[bundlePath stringByStandardizingPath] stringByResolvingSymlinksInPath];
    if (![root isKindOfClass:[NSString class]] || [root length] == 0) return @{ @"ok": @NO, @"error": @"bundle path is unavailable" };
    if (![relativePath isKindOfClass:[NSString class]] || [relativePath length] == 0) return @{ @"ok": @NO, @"error": @"module path is required" };
    if ([relativePath hasPrefix:@"/"] || [relativePath rangeOfString:@"\0"].location != NSNotFound) return @{ @"ok": @NO, @"error": @"module path must be bundle-relative" };
    NSString *candidate = [[[root stringByAppendingPathComponent:relativePath] stringByStandardizingPath] stringByResolvingSymlinksInPath];
    NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
    if (![candidate hasPrefix:prefix]) return @{ @"ok": @NO, @"error": @"module path escapes bundle" };
    NSString *extension = [[candidate pathExtension] lowercaseString];
    if (!([extension isEqualToString:@"js"] || [extension isEqualToString:@"json"])) return @{ @"ok": @NO, @"error": @"module extension must be .js or .json" };
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:candidate error:nil];
    if (!attrs) return @{ @"ok": @NO, @"error": @"module file not found", @"path": candidate ?: @"" };
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkJSHelperMaxBundleFileBytes) return @{ @"ok": @NO, @"error": @"module file is too large", @"path": candidate ?: @"" };
    NSError *err = nil;
    NSString *source = [NSString stringWithContentsOfFile:candidate encoding:NSUTF8StringEncoding error:&err];
    if (!source) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to read module", @"path": candidate ?: @"" };
    return @{ @"ok": @YES, @"path": candidate, @"id": [candidate substringFromIndex:[prefix length]] ?: relativePath, @"source": source };
}


- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)relativePath
                                        bundlePath:(NSString *)bundlePath
                                           writing:(BOOL)writing
                                      createParent:(BOOL)createParent
{
    NSString *root = [[bundlePath stringByStandardizingPath] stringByResolvingSymlinksInPath];
    if (![root isKindOfClass:[NSString class]] || [root length] == 0) return @{ @"ok": @NO, @"error": @"script_session_unavailable" };
    if (![relativePath isKindOfClass:[NSString class]] || [relativePath length] == 0) return @{ @"ok": @NO, @"error": @"storage_missing_path" };
    if ([relativePath hasPrefix:@"/"]) return @{ @"ok": @NO, @"error": @"storage_path_must_be_relative" };
    if ([relativePath rangeOfString:@"\0"].location != NSNotFound) return @{ @"ok": @NO, @"error": @"storage_path_contains_nul" };
    NSString *candidate = [[[root stringByAppendingPathComponent:relativePath] stringByStandardizingPath] stringByResolvingSymlinksInPath];
    NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
    if (![candidate hasPrefix:prefix]) return @{ @"ok": @NO, @"error": @"storage_path_outside_bundle" };
    if (writing) {
        NSString *name = [candidate lastPathComponent];
        if ([name isEqualToString:@"manifest.json"] || [name isEqualToString:@"info.plist"] ||
            [[[candidate pathExtension] lowercaseString] isEqualToString:@"js"]) {
            return @{ @"ok": @NO, @"error": @"storage_path_is_protected" };
        }
    }
    if (createParent) {
        NSString *dir = [candidate stringByDeletingLastPathComponent];
        NSError *mkdirError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
            return @{ @"ok": @NO, @"error": mkdirError.localizedDescription ?: @"failed to create parent directory", @"path": candidate ?: @"" };
        }
    }
    return @{ @"ok": @YES, @"path": candidate ?: @"" };
}

- (NSDictionary *)readTextAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    NSDictionary *resolved = [self bundleStoragePathForRelativePath:relativePath bundlePath:bundlePath writing:NO createParent:NO];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *path = resolved[@"path"];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attrs) return @{ @"ok": @NO, @"error": @"file not found", @"path": path ?: @"" };
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkJSHelperMaxStorageFileBytes) return @{ @"ok": @NO, @"error": @"file is too large", @"path": path ?: @"" };
    NSError *err = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if (!text) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to read file", @"path": path ?: @"" };
    return @{ @"ok": @YES, @"path": path ?: @"", @"text": text ?: @"" };
}

- (NSDictionary *)writeText:(NSString *)text atRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    NSDictionary *resolved = [self bundleStoragePathForRelativePath:relativePath bundlePath:bundlePath writing:YES createParent:YES];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *path = resolved[@"path"];
    NSString *safeText = [text isKindOfClass:[NSString class]] ? text : [text description];
    safeText = safeText ?: @"";
    NSData *data = [safeText dataUsingEncoding:NSUTF8StringEncoding];
    if ([data length] > kTLinkJSHelperMaxStorageFileBytes) return @{ @"ok": @NO, @"error": @"text is too large", @"path": path ?: @"" };
    NSError *err = nil;
    BOOL ok = [safeText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to write file", @"path": path ?: @"" };
    return @{ @"ok": @YES, @"path": path ?: @"", @"bytes": @([data length]) };
}

- (void)closeActiveFileHandles
{
    NSArray<TLinkJSFileHandle *> *handles = nil;
    @synchronized (self) {
        handles = [self.activeFileHandles.allValues copy];
        [self.activeFileHandles removeAllObjects];
    }
    for (TLinkJSFileHandle *handle in handles) [handle close];
}

- (JSValue *)openFileAtRelativePath:(NSString *)relativePath
                               mode:(NSString *)mode
                         bundlePath:(NSString *)bundlePath
                            context:(JSContext *)context
                          sessionId:(NSString *)sessionId
{
    self.storageOpsCount++;
    NSString *openMode = mode.length > 0 ? mode : @"r";
    if (!TLinkJSFileModeIsValid(openMode)) {
        return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"invalid_file_mode", @"mode": openMode} inContext:context];
    }
    BOOL writing = TLinkJSFileModeWrites(openMode);
    NSDictionary *resolved = [self bundleStoragePathForRelativePath:relativePath
                                                          bundlePath:bundlePath
                                                             writing:writing
                                                        createParent:writing];
    if (![resolved[@"ok"] boolValue]) return [JSValue valueWithObject:resolved inContext:context];
    NSString *path = resolved[@"path"] ?: @"";

    __block NSUInteger handleId = 0;
    @synchronized (self) {
        if (self.activeFileHandles.count >= kTLinkJSHelperMaxOpenFiles) {
            return [JSValue valueWithObject:@{@"ok": @NO, @"error": @"too_many_open_files", @"limit": @(kTLinkJSHelperMaxOpenFiles)} inContext:context];
        }
        handleId = self.nextFileHandleId++;
    }
    NSString *openError = nil;
    TLinkJSFileHandle *handle = [TLinkJSFileHandle openPath:path
                                                      mode:openMode
                                                  handleId:handleId
                                          maxTransferBytes:(NSUInteger)kTLinkJSHelperMaxStorageFileBytes
                                                     error:&openError];
    if (!handle) {
        return [JSValue valueWithObject:@{@"ok": @NO, @"error": openError ?: @"file_open_failed", @"path": path, @"mode": openMode} inContext:context];
    }
    @synchronized (self) {
        self.activeFileHandles[@(handleId)] = handle;
    }
    __weak TLinkJSHelperServer *weakSelf = self;
    NSString *ownerSessionId = [sessionId copy];
    return TLinkJSFileHandleCreateJSObject(context, handle, ^(NSUInteger closedId) {
        TLinkJSHelperServer *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.rpcCondition lock];
        @try {
            if (![strongSelf.activeSessionId isEqualToString:ownerSessionId]) return;
            @synchronized (strongSelf) {[strongSelf.activeFileHandles removeObjectForKey:@(closedId)];}
        } @finally {[strongSelf.rpcCondition unlock];}
    });
}

- (NSDictionary *)readJSONAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    NSDictionary *textResult = [self readTextAtRelativePath:relativePath bundlePath:bundlePath];
    if (![textResult[@"ok"] boolValue]) return textResult;
    NSData *data = [textResult[@"text"] dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&err] : nil;
    if (!value) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to parse JSON", @"path": textResult[@"path"] ?: @"" };
    return @{ @"ok": @YES, @"path": textResult[@"path"] ?: @"", @"value": value };
}

- (NSDictionary *)writeJSONValue:(id)value atRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    id object = [value isKindOfClass:[JSValue class]] ? [(JSValue *)value toObject] : value;
    if ([object isKindOfClass:[NSNull class]]) object = nil;
    if (!object || ![NSJSONSerialization isValidJSONObject:object]) return @{ @"ok": @NO, @"error": @"writeJSON(path, value) requires a JSON-serializable object or array" };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&err];
    if (!data) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to encode JSON" };
    if ([data length] > kTLinkJSHelperMaxStorageFileBytes) return @{ @"ok": @NO, @"error": @"JSON is too large" };
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
    return [self writeText:text atRelativePath:relativePath bundlePath:bundlePath];
}

- (NSDictionary *)fileExistsAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    NSDictionary *resolved = [self bundleStoragePathForRelativePath:relativePath bundlePath:bundlePath writing:NO createParent:NO];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *path = resolved[@"path"];
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    return @{ @"ok": @YES, @"path": path ?: @"", @"exists": @(exists), @"directory": @(exists && isDir) };
}

- (NSDictionary *)deleteFileAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    NSDictionary *resolved = [self bundleStoragePathForRelativePath:relativePath bundlePath:bundlePath writing:YES createParent:NO];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *path = resolved[@"path"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return @{ @"ok": @YES, @"path": path ?: @"", @"deleted": @NO };
    NSError *err = nil;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
    if (!ok) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to delete file", @"path": path ?: @"" };
    return @{ @"ok": @YES, @"path": path ?: @"", @"deleted": @YES };
}

- (BOOL)interruptibleSleepMs:(double)ms context:(JSContext *)context
{
    if (!isfinite(ms) || ms < 0) {
        context.exception = [JSValue valueWithNewErrorFromMessage:@"sleep(ms) requires a finite non-negative number" inContext:context];
        return NO;
    }
    if (ms > 24.0 * 60.0 * 60.0 * 1000.0) ms = 24.0 * 60.0 * 60.0 * 1000.0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(ms / 1000.0)];
    [self.sleepCondition lock];
    while (!_cancelState->stopped.load(std::memory_order_acquire)) {
        if (![self.sleepCondition waitUntilDate:deadline]) break;
    }
    [self.sleepCondition unlock];
    if (_cancelState->stopped.load(std::memory_order_acquire)) {
        context.exception = [JSValue valueWithNewErrorFromMessage:@"Script aborted" inContext:context];
        return NO;
    }
    return YES;
}

- (void)finishSessionId:(NSString *)sessionId state:(NSString *)state reason:(NSString *)reason errorText:(NSString *)errorText logPath:(NSString *)logPath latestPath:(NSString *)latestPath
{
    if (![self ownsSessionId:sessionId]) return;
    [self stopLicenseHeartbeatForSessionId:sessionId];
    [self closeActiveFileHandles];
    NSDictionary *summary=[self completeSessionId:sessionId state:state reason:reason errorText:errorText];
    if (!summary) return;
    NSData *json=[NSJSONSerialization dataWithJSONObject:summary options:0 error:nil];
    NSString *body=json?[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]:[summary description];
    NSString *line=[NSString stringWithFormat:@"[%@][%@][summary] %@\n",[NSDate date],summary[@"runId"],body ?: @"{}"];
    if (logPath.length) [self appendLine:line toPath:logPath];
    if (latestPath.length) [self appendLine:line toPath:latestPath];
    NSLog(@"tlinkauto-jsd: finished session=%@ state=%@ reason=%@",sessionId,summary[@"state"],summary[@"exitReason"]);
}

// BEGIN helper owned execution.
- (void)runOwnedSessionId:(NSString *)sessionId scriptPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest runId:(NSString *)runId
{
    if (![self ownsSessionId:sessionId]) return;
    @try {
        try {
            @try {[self runSessionId:sessionId scriptPath:scriptPath bundlePath:bundlePath manifest:manifest runId:runId];}
            @catch (NSException *exception) {
                [self finishSessionId:sessionId state:kTLinkJSHelperStateFailed reason:@"helper_exception" errorText:exception.reason logPath:nil latestPath:nil];
            }
        } catch (...) {
            [self finishSessionId:sessionId state:kTLinkJSHelperStateFailed reason:@"helper_cpp_exception" errorText:@"C++ exception" logPath:nil latestPath:nil];
        }
    } @finally {
        @try {[self stopLicenseHeartbeatForSessionId:sessionId];[self closeActiveFileHandles];}
        @finally {[self retireSessionId:sessionId];}
    }
}
// END helper owned execution.

- (void)runSessionId:(NSString *)sessionId scriptPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest runId:(NSString *)runId
{
    @autoreleasepool {
        NSLog(@"tlinkauto-jsd: starting session=%@ script=%@ bundle=%@", sessionId, scriptPath, bundlePath);
        [self closeActiveFileHandles];
        @synchronized (self) {self.activeFileHandles=[NSMutableDictionary dictionary];self.nextFileHandleId=1;}
        NSString *logPath = [self consoleLogPathForBundlePath:bundlePath runId:runId latest:NO];
        NSString *latestPath = [self consoleLogPathForBundlePath:bundlePath runId:runId latest:YES];
        [self setPathsForSessionId:sessionId logPath:logPath latestPath:latestPath];

        NSString *header = [NSString stringWithFormat:@"[%@] helper run %@ started\n", [NSDate date], runId];
        [header writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [header writeToFile:latestPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSError *readError = nil;
        NSString *script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:&readError];
        if (!script) {
            NSString *err = readError.localizedDescription ?: @"failed to read script";
            [self finishSessionId:sessionId state:kTLinkJSHelperStateFailed reason:@"read_script_failed" errorText:err logPath:logPath latestPath:latestPath];
            return;
        }

        if (![self markRunningSessionId:sessionId logPath:logPath latestPath:latestPath]) {
            [self finishSessionId:sessionId state:kTLinkJSHelperStateCancelled reason:@"cancelled" errorText:nil logPath:logPath latestPath:latestPath];return;
        }
        [self startLicenseHeartbeatForSessionId:sessionId];
        NSLog(@"tlinkauto-jsd: evaluating session=%@", sessionId);
        JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
        JSContext *ctx = [[JSContext alloc] initWithVirtualMachine:vm];
        __weak TLinkJSHelperServer *weakSelf = self;
        ctx.exceptionHandler = ^(JSContext *context, JSValue *exception) {
            context.exception = exception;
            NSString *text=[exception toString] ?: @"JavaScript exception";
            [weakSelf recordSessionId:sessionId error:text durationMs:-1];
            NSLog(@"tlinkauto-jsd: exception session=%@ error=%@", sessionId, text);
        };
        ctx[@"manifest"] = manifest ?: @{};
        ctx[@"sleep"] = ^(double ms) {
            [weakSelf interruptibleSleepMs:ms context:[JSContext currentContext]];
        };
        ctx[@"_tlinkautoLog"] = ^(NSString *level, NSString *message) {
            NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\n", [NSDate date], runId ?: @"", level ?: @"log", message ?: @""];
            [weakSelf appendLine:line toPath:logPath];
            [weakSelf appendLine:line toPath:latestPath];
            NSLog(@"tlinkauto-jsd[%@][%@]: %@", runId ?: @"", level ?: @"log", message ?: @"");
        };
        ctx[@"_tlinkautoLoadBundleText"] = ^NSDictionary *(NSString *relativePath) {
            return [weakSelf bundleTextForRelativePath:relativePath bundlePath:bundlePath];
        };
        JSValue *device = [JSValue valueWithNewObjectInContext:ctx];
        device[@"runtimeInfo"] = ^NSDictionary *{
            return @{
                @"engine": @"JavaScriptCore",
                @"runtimeLocation": @"helper",
                @"effectiveRuntimeLocation": @"helper",
                @"apiVersion": @1,
                @"helperInstanceId": weakSelf.helperInstanceId ?: @"",
                @"sessionId": sessionId ?: @"",
                @"runId": runId ?: @"",
                @"consoleLogPath": logPath ?: @"",
                @"consoleLatestLogPath": latestPath ?: @"",
                @"nativeAPIs": @NO,
                @"nativeRPC": @YES,
                @"storageLocal": @YES,
                @"fileHandleAPI": @YES,
                @"fileHandleModes": @[@"r", @"rb", @"r+", @"rb+", @"w", @"wb", @"w+", @"wb+", @"a", @"ab", @"a+", @"ab+"],
                @"maxOpenFiles": @(kTLinkJSHelperMaxOpenFiles),
                @"maxFileTransferBytes": @(kTLinkJSHelperMaxStorageFileBytes),
                @"frameHandleRPC": @YES,
                @"imageHandleRPC": @YES,
                @"ocrRPC": @YES,
                @"autoReleaseHandles": @YES,
            };
        };
        device[@"toast"] = ^NSDictionary *(NSString *message, NSDictionary *options) {
            return [weakSelf executeNativeRPCMethod:@"toast" arguments:@[message ?: @"", options ?: @{}] sessionId:sessionId];
        };
        device[@"tap"] = ^NSDictionary *(double x, double y) {
            return [weakSelf executeNativeRPCMethod:@"tap" arguments:@[@(x), @(y)] sessionId:sessionId];
        };
        device[@"swipe"] = ^NSDictionary *(double x1, double y1, double x2, double y2, double duration) {
            return [weakSelf executeNativeRPCMethod:@"swipe" arguments:@[@(x1), @(y1), @(x2), @(y2), @(duration)] sessionId:sessionId];
        };
        device[@"longPress"] = ^NSDictionary *(double x, double y, double duration) {
            return [weakSelf executeNativeRPCMethod:@"longPress" arguments:@[@(x), @(y), @(duration)] sessionId:sessionId];
        };
        device[@"gesture"] = ^NSDictionary *(NSArray *points, NSDictionary *options) {
            return [weakSelf executeNativeRPCMethod:@"gesture" arguments:@[points ?: @[], options ?: @{}] sessionId:sessionId];
        };
        device[@"zoom"] = ^NSDictionary *(double centerX, double centerY, double startRadius, double endRadius, NSDictionary *options) {
            return [weakSelf executeNativeRPCMethod:@"zoom"
                                          arguments:@[@(centerX), @(centerY), @(startRadius), @(endRadius), options ?: @{}]
                                          sessionId:sessionId];
        };
        device[@"pickColor"] = ^NSDictionary *(double x, double y) {
            return [weakSelf executeNativeRPCMethod:@"pickColor" arguments:@[@(x), @(y)] sessionId:sessionId];
        };
        device[@"getScreenSize"] = ^NSDictionary *{
            return [weakSelf executeNativeRPCMethod:@"getScreenSize" arguments:@[] sessionId:sessionId];
        };
        device[@"screenshotTo"] = ^NSDictionary *(NSString *path) {
            return [weakSelf executeNativeRPCMethod:@"screenshotTo" arguments:@[path ?: @""] sessionId:sessionId];
        };
        device[@"screenshotRegion"] = ^NSDictionary *(NSString *path, NSDictionary *options) {
            return [weakSelf executeNativeRPCMethod:@"screenshotRegion" arguments:@[path ?: @"", options ?: @{}] sessionId:sessionId];
        };
        device[@"frontMostAppId"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"frontMostAppId" arguments:@[] sessionId:sessionId]; };
        device[@"frontMostPid"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"frontMostPid" arguments:@[] sessionId:sessionId]; };
        device[@"orientation"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"orientation" arguments:@[] sessionId:sessionId]; };
        device[@"openApp"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"openApp" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"killApp"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"killApp" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"appState"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"appState" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"appInfo"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"appInfo" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"appPid"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"appPid" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"appPaths"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"appPaths" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"listBundles"] = ^NSDictionary *(BOOL withInfo) { return [weakSelf executeNativeRPCMethod:@"listBundles" arguments:@[@(withInfo)] sessionId:sessionId]; };
        device[@"openUrl"] = ^NSDictionary *(NSString *url) { return [weakSelf executeNativeRPCMethod:@"openUrl" arguments:@[url ?: @""] sessionId:sessionId]; };
        device[@"wifi"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@55, @"enabled", [NSNull null]] sessionId:sessionId]; };
        device[@"setWifi"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@55, @"enabled", @(enabled)] sessionId:sessionId]; };
        device[@"bluetooth"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@56, @"enabled", [NSNull null]] sessionId:sessionId]; };
        device[@"setBluetooth"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@56, @"enabled", @(enabled)] sessionId:sessionId]; };
        device[@"airplaneMode"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@57, @"enabled", [NSNull null]] sessionId:sessionId]; };
        device[@"setAirplaneMode"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@57, @"enabled", @(enabled)] sessionId:sessionId]; };
        device[@"cellularData"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@58, @"enabled", [NSNull null]] sessionId:sessionId]; };
        device[@"setCellularData"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@58, @"enabled", @(enabled)] sessionId:sessionId]; };
        device[@"rootDir"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"rootDir" arguments:@[] sessionId:sessionId]; };
        device[@"currentDir"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"currentDir" arguments:@[] sessionId:sessionId]; };
        device[@"botPath"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"botPath" arguments:@[] sessionId:sessionId]; };
        device[@"info"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"info" arguments:@[] sessionId:sessionId]; };
        device[@"batteryInfo"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"batteryInfo" arguments:@[] sessionId:sessionId]; };
        device[@"alert"] = ^NSDictionary *(NSString *title, NSString *message, int duration) { return [weakSelf executeNativeRPCMethod:@"alert" arguments:@[title ?: @"TLinkauto", message ?: @"", @(duration)] sessionId:sessionId]; };
        device[@"dialog"] = ^NSDictionary *(NSDictionary *options) {
            options = [options isKindOfClass:[NSDictionary class]] ? options : @{};
            return [weakSelf executeNativeRPCMethod:@"dialog" arguments:@[options[@"title"] ?: @"TLinkauto", options[@"message"] ?: @"", options[@"ok"] ?: @"OK", options[@"cancel"] ?: @"Cancel"] sessionId:sessionId];
        };
        device[@"clearDialogValues"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"clearDialogValues" arguments:@[] sessionId:sessionId]; };
        device[@"showKeyboard"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@2, @"2"] sessionId:sessionId]; };
        device[@"hideKeyboard"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@2, @"1"] sessionId:sessionId]; };
        device[@"insertText"] = ^NSDictionary *(NSString *text) { return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@1, text ?: @""] sessionId:sessionId]; };
        device[@"deleteCharacters"] = ^NSDictionary *(int count) { return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@4, [NSString stringWithFormat:@"%d", count > 0 ? count : 1]] sessionId:sessionId]; };
        device[@"moveCursor"] = ^NSDictionary *(int offset) { return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@3, [NSString stringWithFormat:@"%d", offset]] sessionId:sessionId]; };
        device[@"pasteFromClipboard"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@5, [NSNull null]] sessionId:sessionId]; };
        device[@"getClipboardText"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@6, [NSNull null]] sessionId:sessionId]; };
        device[@"setClipboardText"] = ^NSDictionary *(NSString *text) { return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@7, text ?: @""] sessionId:sessionId]; };
        device[@"setClipboardImage"] = ^NSDictionary *(NSString *path) {
            NSString *safePath = [(path ?: @"") stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
            safePath = [safePath stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            if ([safePath length] > 2048) safePath = [safePath substringToIndex:2048];
            return [weakSelf executeNativeRPCMethod:@"keyboard" arguments:@[@8, [NSString stringWithFormat:@"file;;%@", safePath]] sessionId:sessionId];
        };
        device[@"readText"] = ^NSDictionary *(NSString *path) { return [weakSelf readTextAtRelativePath:path bundlePath:bundlePath]; };
        device[@"writeText"] = ^NSDictionary *(NSString *path, NSString *text) { return [weakSelf writeText:text atRelativePath:path bundlePath:bundlePath]; };
        device[@"openFile"] = ^JSValue *(NSString *path, NSString *mode) {
            JSContext *currentContext = [JSContext currentContext] ?: ctx;
            return [weakSelf openFileAtRelativePath:path
                                               mode:mode
                                         bundlePath:bundlePath
                                            context:currentContext
                                          sessionId:sessionId];
        };
        device[@"readJSON"] = ^NSDictionary *(NSString *path) { return [weakSelf readJSONAtRelativePath:path bundlePath:bundlePath]; };
        device[@"writeJSON"] = ^NSDictionary *(NSString *path, id value) { return [weakSelf writeJSONValue:value atRelativePath:path bundlePath:bundlePath]; };
        device[@"fileExists"] = ^NSDictionary *(NSString *path) { return [weakSelf fileExistsAtRelativePath:path bundlePath:bundlePath]; };
        device[@"deleteFile"] = ^NSDictionary *(NSString *path) { return [weakSelf deleteFileAtRelativePath:path bundlePath:bundlePath]; };
        device[@"captureFrame"] = ^NSDictionary *(NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"captureFrame" arguments:@[options ?: @{}] sessionId:sessionId]; };
        device[@"releaseFrame"] = ^NSDictionary *(int frameId) { return [weakSelf executeNativeRPCMethod:@"releaseFrame" arguments:@[@(frameId)] sessionId:sessionId]; };
        device[@"releaseAllFrames"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"releaseAllFrames" arguments:@[] sessionId:sessionId]; };
        device[@"framePickColor"] = ^NSDictionary *(int frameId, double x, double y, NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"framePickColor" arguments:@[@(frameId), @(x), @(y), options ?: @{}] sessionId:sessionId]; };
        device[@"framePickColors"] = ^NSDictionary *(int frameId, NSArray *points, NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"framePickColors" arguments:@[@(frameId), points ?: @[], options ?: @{}] sessionId:sessionId]; };
        device[@"frameFindColor"] = ^NSDictionary *(int frameId, NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"frameFindColor" arguments:@[@(frameId), options ?: @{}] sessionId:sessionId]; };
        device[@"frameIsColors"] = ^NSDictionary *(int frameId, NSArray *points, NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"frameIsColors" arguments:@[@(frameId), points ?: @[], options ?: @{}] sessionId:sessionId]; };
        device[@"frameFindMultiColor"] = ^NSDictionary *(int frameId, NSArray *points, NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"frameFindMultiColor" arguments:@[@(frameId), points ?: @[], options ?: @{}] sessionId:sessionId]; };
        device[@"openImage"] = ^NSDictionary *(NSString *path) { return [weakSelf executeNativeRPCMethod:@"openImage" arguments:@[path ?: @""] sessionId:sessionId]; };
        device[@"captureImage"] = ^NSDictionary *(double x, double y, double width, double height) { return [weakSelf executeNativeRPCMethod:@"captureImage" arguments:@[@(x), @(y), @(width), @(height)] sessionId:sessionId]; };
        device[@"releaseImage"] = ^NSDictionary *(int imageId) { return [weakSelf executeNativeRPCMethod:@"releaseImage" arguments:@[@(imageId)] sessionId:sessionId]; };
        device[@"findImageInFrame"] = ^NSDictionary *(int frameId, int imageId, NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"findImageInFrame" arguments:@[@(frameId), @(imageId), options ?: @{}] sessionId:sessionId]; };
        device[@"ocrLanguages"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"ocrLanguages" arguments:@[] sessionId:sessionId]; };
        device[@"ocrFrame"] = ^NSDictionary *(int frameId, NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"ocrFrame" arguments:@[@(frameId), options ?: @{}] sessionId:sessionId]; };
        device[@"ocr"] = ^NSDictionary *(NSDictionary *options) { return [weakSelf executeNativeRPCMethod:@"ocr" arguments:@[options ?: @{}] sessionId:sessionId]; };
        device[@"hardwareKey"] = ^NSDictionary *(NSString *key, NSString *action) {
            return [weakSelf executeNativeRPCMethod:@"hardwareKey" arguments:@[@(TLinkJSHelperHardwareKeyAction(action)), @(TLinkJSHelperHardwareKeyType(key))] sessionId:sessionId];
        };
        device[@"pressHardwareKey"] = ^NSDictionary *(NSString *key) {
            return [weakSelf executeNativeRPCMethod:@"pressHardwareKey" arguments:@[@(TLinkJSHelperHardwareKeyType(key))] sessionId:sessionId];
        };
        device[@"keepAwake"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"keepAwake" arguments:@[@(enabled)] sessionId:sessionId]; };
        device[@"touchIndicator"] = ^NSDictionary *(NSString *action) { return [weakSelf executeNativeRPCMethod:@"touchIndicator" arguments:@[@(TLinkJSHelperTouchIndicatorAction(action))] sessionId:sessionId]; };
        device[@"runShell"] = ^NSDictionary *(NSString *command, double timeoutSeconds) { return [weakSelf executeNativeRPCMethod:@"runShell" arguments:@[command ?: @"", @(timeoutSeconds)] sessionId:sessionId]; };
        ctx[@"device"] = device;
        NSString *consolePrelude = @"(function(){function fmt(args){return Array.prototype.map.call(args,function(v){try{if(typeof v==='string')return v;return JSON.stringify(v);}catch(e){return String(v);}}).join(' ');}this.console={log:function(){_tlinkautoLog('log',fmt(arguments));},info:function(){_tlinkautoLog('info',fmt(arguments));},warn:function(){_tlinkautoLog('warn',fmt(arguments));},error:function(){_tlinkautoLog('error',fmt(arguments));}};})();";
        NSString *modulePrelude = @"(function(){var cache=Object.create(null);var stack=[];function dirname(p){var i=p.lastIndexOf('/');return i>=0?p.slice(0,i):'';}function normalize(base,req){if(typeof req!=='string'||!req)throw new Error('module path is required');var input=req;if(req.indexOf('./')===0||req.indexOf('../')===0)input=(base?dirname(base)+'/':'')+req;var out=[];input.split('/').forEach(function(part){if(!part||part==='.')return;if(part==='..')out.pop();else out.push(part);});return out.join('/');}function candidates(id){if(/\\.(js|json)$/.test(id))return[id];return[id+'.js',id+'.json',id+'/index.js'];}function loadRecord(id){var last='';var list=candidates(id);for(var i=0;i<list.length;i++){var rec=_tlinkautoLoadBundleText(list[i]);if(rec&&rec.ok)return rec;last=rec&&rec.error?rec.error:'module not found';}throw new Error('Cannot load module '+id+': '+last);}this.require=function(request){var id=normalize(stack.length?stack[stack.length-1]:'',request);var rec=loadRecord(id);if(cache[rec.id])return cache[rec.id].exports;var module={id:rec.id,filename:rec.path,exports:{}};cache[rec.id]=module;if(/\\.json$/.test(rec.id)){module.exports=JSON.parse(rec.source);return module.exports;}stack.push(rec.id);try{var fn=new Function('exports','module','require','device','sleep',rec.source+'\\n//# sourceURL='+rec.path);fn(module.exports,module,this.require,device,sleep);}finally{stack.pop();}return module.exports;};this.include=function(request){var id=normalize(stack.length?stack[stack.length-1]:'',request);var rec=loadRecord(id);return(0,eval)(rec.source+'\\n//# sourceURL='+rec.path);};})();";
        JSContextGroupRef group = JSContextGetGroup([ctx JSGlobalContextRef]);
        if (_setExecutionTimeLimit) _setExecutionTimeLimit(group, kTLinkJSHelperWatchdogInterval, TLinkJSHelperShouldTerminate, _cancelState);
        NSDate *evalStartedAt = [NSDate date];
        @try {
            NSLog(@"tlinkauto-jsd: evaluate console prelude session=%@", sessionId);
            [ctx evaluateScript:consolePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto-helper://console-prelude.js"]];
            if (!ctx.exception) {
                NSLog(@"tlinkauto-jsd: evaluate module prelude session=%@", sessionId);
                [ctx evaluateScript:modulePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto-helper://module-prelude.js"]];
            }
            if (!ctx.exception) {
                NSLog(@"tlinkauto-jsd: evaluate main script session=%@", sessionId);
                [ctx evaluateScript:script withSourceURL:[NSURL fileURLWithPath:scriptPath]];
            }
        } @finally {
            [self recordSessionId:sessionId error:nil durationMs:[[NSDate date] timeIntervalSinceDate:evalStartedAt]*1000.0];
            if (_clearExecutionTimeLimit) _clearExecutionTimeLimit(group);
            [self stopLicenseHeartbeatForSessionId:sessionId];
            [self closeActiveFileHandles];
        }
        NSString *state=ctx.exception?kTLinkJSHelperStateFailed:kTLinkJSHelperStateCompleted;
        NSString *reason=ctx.exception?@"failed":@"normal";
        [self finishSessionId:sessionId state:state reason:reason errorText:ctx.exception?[ctx.exception toString]:nil logPath:logPath latestPath:latestPath];
    }
}

- (NSDictionary *)runScriptDirectAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest
{
    NSString *licenseDenial = [self licenseDenialForComponent:@"script_helper_direct"];
    if (licenseDenial) {
        [self.rpcCondition lock];
        @try {if (!self.sessionWorkerActive) {self.activeState=kTLinkJSHelperStateFailed;self.activeExitReason=@"license_required";self.lastError=licenseDenial;[self publishStatusChange];}}
        @finally {[self.rpcCondition unlock];}
        return [self statusPayload];
    }
    NSString *sessionId = [[NSUUID UUID] UUIDString];
    NSString *runId = [[NSUUID UUID] UUIDString];
    if (![self beginSessionId:sessionId runId:runId]) return [self statusPayload];
    [self runOwnedSessionId:sessionId scriptPath:scriptPath bundlePath:bundlePath manifest:manifest ?: @{} runId:runId];
    return [self statusPayload];
}

- (NSDictionary *)startWithRequest:(NSDictionary *)request
{
    if ([self sessionIsBusy]) return [self errorEnvelopeForRequest:request message:@"helper_busy"];
    NSDictionary *payload = [request[kTLinkJSHelperKeyPayload] isKindOfClass:[NSDictionary class]] ? request[kTLinkJSHelperKeyPayload] : @{};
    NSString *scriptPath = [payload[@"scriptPath"] isKindOfClass:[NSString class]] ? payload[@"scriptPath"] : @"";
    NSString *bundlePath = [payload[@"bundlePath"] isKindOfClass:[NSString class]] ? payload[@"bundlePath"] : @"";
    NSDictionary *manifest = [payload[@"manifest"] isKindOfClass:[NSDictionary class]] ? payload[@"manifest"] : @{};
    if (![scriptPath length] || ![bundlePath length]) return [self errorEnvelopeForRequest:request message:@"scriptPath and bundlePath are required"];
    NSString *licenseDenial = [self licenseDenialForComponent:@"script_helper_start"];
    if (licenseDenial) return [self errorEnvelopeForRequest:request message:licenseDenial];
    NSString *sessionId = [[NSUUID UUID] UUIDString];
    NSString *runId = [[NSUUID UUID] UUIDString];
    if (![self beginSessionId:sessionId runId:runId]) return [self errorEnvelopeForRequest:request message:@"helper_busy"];
    dispatch_async(self.executionQueue, ^{
        [self runOwnedSessionId:sessionId scriptPath:scriptPath bundlePath:bundlePath manifest:manifest runId:runId];
    });
    return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStart helperInstanceId:self.helperInstanceId sessionId:sessionId requestId:request[kTLinkJSHelperKeyRequestId] payload:[self statusPayload]];
}

- (NSDictionary *)errorEnvelopeForRequest:(NSDictionary *)request message:(NSString *)message
{
    NSMutableDictionary *env = [[TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdError
                                                           helperInstanceId:self.helperInstanceId
                                                                  sessionId:request[kTLinkJSHelperKeySessionId]
                                                                  requestId:request[kTLinkJSHelperKeyRequestId]
                                                                    payload:@{}] mutableCopy];
    env[kTLinkJSHelperKeyError] = @{ @"message": message ?: @"unknown_error" };
    return env;
}

- (NSDictionary *)handleEnvelope:(NSDictionary *)request
{
    NSError *validationError = nil;
    if (![TLinkJSHelperProtocol validateEnvelope:request error:&validationError]) {
        return [self errorEnvelopeForRequest:request ?: @{} message:validationError.localizedDescription ?: @"invalid_envelope"];
    }

    NSString *command = request[kTLinkJSHelperKeyCommand];
    id requestedHelper = request[kTLinkJSHelperKeyHelperInstanceId];
    if (requestedHelper && ![requestedHelper isEqual:self.helperInstanceId])
        return [self errorEnvelopeForRequest:request message:@"helper_instance_mismatch"];

    NSTimeInterval uptimeMs = [[NSDate date] timeIntervalSinceDate:self.startedAt] * 1000.0;
    if ([command isEqualToString:kTLinkJSHelperCmdHandshake]) {
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdHandshake
                                         helperInstanceId:self.helperInstanceId
                                                sessionId:request[kTLinkJSHelperKeySessionId]
                                                requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:@{
            @"helperVersion": kTLinkJSHelperVersion,
            @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
            @"state": kTLinkJSHelperStateIdle,
            @"uptimeMs": @((long long)uptimeMs),
            @"capabilities": @{
                @"javascriptcore": @YES,
                @"pureJavaScriptExecution": @YES,
                @"changeWaitContract": @"session_native_rpc_v1",
                @"changeWaitPeerEOFContract": @"cancel_v1",
                @"sessionSnapshotContract": @"lifecycle_rpc_owner_v1",
                @"executionTimeLimit": @(_setExecutionTimeLimit != NULL && _clearExecutionTimeLimit != NULL),
                @"hardKillRecovery": @NO,
                @"nativeRPC": @YES,
                @"structuredConsole": @NO,
                @"oneActiveSession": @YES,
                @"storageLocal": @YES,
                @"frameHandleRPC": @YES,
                @"imageHandleRPC": @YES,
                @"ocrRPC": @YES,
                @"autoReleaseHandles": @YES,
            },
        }];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdStatus]) {
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStatus
                                          helperInstanceId:self.helperInstanceId
                                                 sessionId:request[kTLinkJSHelperKeySessionId]
                                                 requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:[self statusPayload]];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdStart]) {
        return [self startWithRequest:request];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdStop]) {
        NSString *requestedSessionId = request[kTLinkJSHelperKeySessionId];
        NSString *rejection=[self requestStopForSessionId:requestedSessionId reason:nil errorText:nil];
        if (rejection) return [self errorEnvelopeForRequest:request message:rejection];
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStop
                                         helperInstanceId:self.helperInstanceId
                                                sessionId:request[kTLinkJSHelperKeySessionId]
                                                requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:[self statusPayload]];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdNativeRPCResponse]) {
        return [self acceptNativeRPCResponse:request];
    }
    return [self errorEnvelopeForRequest:request message:@"unsupported_command"];
}

// BEGIN helper RPC response admission.
- (NSDictionary *)acceptNativeRPCResponse:(NSDictionary *)request
{
    [self.rpcCondition lock];
    NSString *rejection = nil;
    BOOL duplicate = false;
    @try {
        rejection = TLinkHelperRPCResponseError(self.helperInstanceId, self.activeSessionId, self.pendingNativeRequest,
                                               request, _cancelState->stopped.load(std::memory_order_acquire));
        if (!rejection) {
            duplicate = self.nativeResponse != nil;
            if (!duplicate) self.nativeResponse = request[@"payload"][@"result"];
            [self.rpcCondition broadcast];
        }
    } @finally { [self.rpcCondition unlock]; }
    if (rejection) return [self errorEnvelopeForRequest:request message:rejection];
    return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdNativeRPCResponse
                                     helperInstanceId:self.helperInstanceId
                                            sessionId:request[kTLinkJSHelperKeySessionId]
                                            requestId:request[kTLinkJSHelperKeyRequestId]
                                              payload:@{kTLinkJSHelperKeyRequestId:request[@"payload"][@"requestId"],
                                                        @"result":@{@"ok":@(true),@"accepted":@(true),@"duplicate":@(duplicate)}}];
}
// END helper RPC response admission.

// BEGIN helper socket client admission.
- (void)enqueueClient:(int)client acceptedAt:(uint64_t)acceptedAt
{
    TLinkHelperIO::Socket descriptor(client);
    auto lease = _clientAdmission.acquire(client, acceptedAt, [](int fd){ (void)::close(fd); });
    if (!lease) return;
    (void)descriptor.release(); // The lease owns the descriptor until the worker takes it.
    dispatch_async(self.clientQueue, ^{
        @autoreleasepool {
            try {
                @try {
                    const TLinkHelperIO::Deadline deadline(lease->acceptedAt(), TLinkHelperIO::ServerTimeoutMs);
                    if (lease->isOpen() && deadline.remaining(TLinkHelperIO::nowMs())) {
                        const int fd = lease->takeDescriptor();
                        if (fd >= 0) [self handleClient:fd acceptedAt:lease->acceptedAt()];
                    }
                } @catch (NSException *exception) {
                    NSLog(@"tlinkauto-jsd: client exception %@", exception.name);
                }
            } catch (...) { NSLog(@"tlinkauto-jsd: client C++ exception"); }
        }
        lease->finish(); // Release capacity only after handler/I/O and its autorelease pool finish.
        // Lease destruction also covers callbacks discarded before execution.
    });
}
// END helper socket client admission.

// BEGIN helper change wait handler.
- (NSDictionary *)waitForChangeRequest:(NSDictionary *)request deadline:(const TLinkHelperIO::Deadline &)deadline client:(int)client
{
    using namespace TLinkHelperIO;
    uint64_t after=0,waitMs=0,issued=0,expires=0;bool hasDeadline=false;
    const auto identity=TLinkHelperRPCIdentityFrom(request[@"helperInstanceId"],request[@"sessionId"],request[@"requestId"]);
    if (!TLinkHelperReadChangeWait(request,after,waitMs) || !TLinkHelperReadSenderDeadline(request,hasDeadline,issued,expires) || !hasDeadline ||
        !TLinkHelperRPCIdentity::valid(identity.helper) || !TLinkHelperRPCIdentity::valid(identity.session) || !TLinkHelperRPCIdentity::valid(identity.request))
        return [self errorEnvelopeForRequest:request message:@"invalid_wait_request"];
    {
        TLinkHelperCommandGate::Cancellation queuedCancellation;
        TLinkHelperWaitPeer queuedPeer(_clientCommandOwner,queuedCancellation);
        if(request[@"waitPeerEOFContract"]&&!queuedPeer.start(client))
            return [self errorEnvelopeForRequest:request message:@"change_wait_busy"];
        auto command=_clientCommandOwner.acquire(deadline,&queuedCancellation);
        queuedPeer.stop(); // Join callbacks before checking cancellation and entering the owner.
        if (!command || _clientCommandOwner.cancelled(queuedCancellation) || !deadline.remaining(nowMs()) || !_clientAdmission.isOpen()) return nil;
        if (![request[@"helperInstanceId"] isEqual:self.helperInstanceId]) return [self errorEnvelopeForRequest:request message:@"helper_instance_mismatch"];
        [self.rpcCondition lock];
        BOOL matches=false;
        @try {matches=[request[@"sessionId"] isEqual:self.activeSessionId];} @finally {[self.rpcCondition unlock];}
        if (!matches) return [self errorEnvelopeForRequest:request message:@"session_mismatch"];
    } // Never retain the command owner while waiting for publication.
    const uint64_t now=nowMs();
    if (deadline.remaining(now)<=TLinkHelperChangeWait::OutputReserveMs) return nil;
    Deadline waitDeadline(now,static_cast<int>(waitMs));
    waitDeadline.end=std::min(waitDeadline.end,deadline.end-TLinkHelperChangeWait::OutputReserveMs);
    TLinkHelperChangeWait::Cancellation cancellation;
    TLinkHelperWaitPeer peer(_statusChanges,cancellation);
    if(request[@"waitPeerEOFContract"]&&!peer.start(client))
        return [self errorEnvelopeForRequest:request message:@"change_wait_busy"];
    const auto result=_statusChanges.wait(after,waitDeadline,&cancellation);
    peer.stop(); // Join before this method returns to the socket owner/finally close.
    if (!deadline.remaining(nowMs())) return nil;
    using C=TLinkHelperChangeWait::Code;
    if (result.code==C::Cancelled) return nil;
    if (result.code==C::Busy) return [self errorEnvelopeForRequest:request message:@"change_wait_busy"];
    if (result.code==C::Stopped) return [self errorEnvelopeForRequest:request message:@"change_wait_stopped"];
    if (result.code==C::InvalidCursor) return [self errorEnvelopeForRequest:request message:@"change_cursor_ahead"];
    return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdWaitForChange helperInstanceId:self.helperInstanceId
        sessionId:request[@"sessionId"] requestId:request[@"requestId"]
        payload:@{@"sequence":@(result.sequence),@"changed":@(result.code==C::Changed),@"reason":result.code==C::Changed?@"changed":@"timeout"}];
}
// END helper change wait handler.

// BEGIN helper socket client ownership.
- (void)handleClient:(int)client
{
    [self handleClient:client acceptedAt:TLinkHelperIO::nowMs()];
}
- (void)handleClient:(int)client acceptedAt:(uint64_t)acceptedAt
{
    using namespace TLinkHelperIO;
    Socket socket(client);
    Deadline deadline(acceptedAt, ServerTimeoutMs);
    @autoreleasepool {
        @try {
            if (!socket.prepare().ok()) return;
            std::vector<uint8_t> frame;
            if (!readFrame(posixOps(), socket.fd(), frame, deadline).ok()) return;
            NSData *requestData = [NSData dataWithBytes:frame.data() length:frame.size()];
            NSError *err = nil;
            NSDictionary *request = [TLinkJSHelperProtocol deserializeEnvelope:requestData error:&err];
            if (!deadline.remaining(nowMs())) return;
            bool hasDeadline=false;uint64_t issued=0,expires=0;
            if (request && (!TLinkHelperReadSenderDeadline(request,hasDeadline,issued,expires) ||
                (hasDeadline && !constrainToSender(deadline,issued,expires,nowMs())))) return;
            NSDictionary *response = nil;
            if ([request[@"command"] isEqualToString:kTLinkJSHelperCmdWaitForChange]) {
                response = [self waitForChangeRequest:request deadline:deadline client:socket.fd()];
            } else {
                auto command=_clientCommandOwner.acquire(deadline);
                if (!command ||
                    !deadline.remaining(nowMs()) || !_clientAdmission.isOpen()) return;
                response = request ? [self handleEnvelope:request] : [self errorEnvelopeForRequest:@{} message:err.localizedDescription ?: @"invalid_json"];
            } // Release the command owner before serialization and potentially slow socket output.
            if (!deadline.remaining(nowMs())) return;
            NSData *responseData = [TLinkJSHelperProtocol serializeEnvelope:response error:nil];
            if (responseData.length > MaxFrameBytes) {
                response = [self errorEnvelopeForRequest:request ?: @{} message:@"frame_too_large"];
                responseData = [TLinkJSHelperProtocol serializeEnvelope:response error:nil];
            }
            if (responseData) (void)writeFrame(posixOps(), socket.fd(), static_cast<const uint8_t *>(responseData.bytes), responseData.length, deadline);
        } @finally { socket.close(); }
    }
}
// END helper socket client ownership.

- (void)run
{
    NSString *runDir = [kTLinkJSHelperSocketPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:runDir withIntermediateDirectories:YES attributes:nil error:nil];

    int pidFd = open([kTLinkJSHelperPidPath fileSystemRepresentation], O_CREAT | O_EXCL | O_WRONLY, 0644);
    if (pidFd < 0 && errno == EEXIST) {
        NSString *pidText = [NSString stringWithContentsOfFile:kTLinkJSHelperPidPath encoding:NSUTF8StringEncoding error:nil];
        pid_t existingPid = (pid_t)[pidText intValue];
        if (existingPid > 0 && existingPid != getpid() && kill(existingPid, 0) == 0) {
            NSLog(@"tlinkauto-jsd: helper pid %d is already running", existingPid);
            return;
        }
        unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
        pidFd = open([kTLinkJSHelperPidPath fileSystemRepresentation], O_CREAT | O_EXCL | O_WRONLY, 0644);
    }
    if (pidFd < 0) {
        NSLog(@"tlinkauto-jsd: pid file create failed: %d", errno);
        return;
    }

    NSString *pidLine = [NSString stringWithFormat:@"%d", getpid()];
    NSData *pidData = [pidLine dataUsingEncoding:NSUTF8StringEncoding];
    if (pidData) write(pidFd, pidData.bytes, pidData.length);

    unlink([kTLinkJSHelperSocketPath fileSystemRepresentation]);

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) {
        NSLog(@"tlinkauto-jsd: socket failed: %d", errno);
        close(pidFd);
        unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [kTLinkJSHelperSocketPath fileSystemRepresentation], sizeof(addr.sun_path) - 1);
    if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        NSLog(@"tlinkauto-jsd: bind failed: %d", errno);
        close(server);
        close(pidFd);
        unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
        return;
    }
    chmod([kTLinkJSHelperSocketPath fileSystemRepresentation], 0666);
    chmod([kTLinkJSHelperPidPath fileSystemRepresentation], 0644);
    if (listen(server, 8) != 0) {
        NSLog(@"tlinkauto-jsd: listen failed: %d", errno);
        close(server);
        close(pidFd);
        unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
        return;
    }

    NSLog(@"tlinkauto-jsd: ready instance=%@ socket=%@", self.helperInstanceId, kTLinkJSHelperSocketPath);
    while (true) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            NSLog(@"tlinkauto-jsd: accept failed: %d", errno);
            break;
        }
        [self enqueueClient:client acceptedAt:TLinkHelperIO::nowMs()];
    }
    _statusChanges.stop();
    _clientCommandOwner.stop();
    _clientAdmission.stop(); // Queued/parsed clients cannot begin new commands after listener shutdown.
    close(server);
    unlink([kTLinkJSHelperSocketPath fileSystemRepresentation]);
    close(pidFd);
    unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
}

@end
