#import "TLinkAdaptiveStreaming.h"
#import "TLinkEventChannel.h"

#include <fcntl.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

NSString * const TLinkAdaptiveStreamingSchemaV1 = @"adaptive_streaming_v1";

static const NSUInteger kTLinkAdaptiveFeedbackMaxBytes = 16384;
static const uint64_t kTLinkAdaptiveFeedbackFreshMs = 5000;
static const uint64_t kTLinkAdaptiveFeedbackMinimumIntervalMs = 750;
static const uint64_t kTLinkAdaptiveChangeCooldownMs = 5000;
static const NSInteger kTLinkAdaptiveRecoveryGoodSamples = 4;

static NSString *TLinkAdaptiveRoot(void) { return @"/var/mobile/Library/TLinkauto/adaptive-streaming"; }
static NSString *TLinkAdaptiveStatePath(void) { return [TLinkAdaptiveRoot() stringByAppendingPathComponent:@"state.json"]; }
static NSString *TLinkAdaptiveLockPath(void) { return [TLinkAdaptiveRoot() stringByAppendingPathComponent:@"state.lock"]; }
static uint64_t TLinkAdaptiveNowMs(void) { return (uint64_t)(NSDate.date.timeIntervalSince1970 * 1000.0); }
static NSObject *TLinkAdaptiveProcessLock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static void TLinkAdaptiveEnsureRoot(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:TLinkAdaptiveRoot()
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0750}
                                                    error:nil];
    chmod(TLinkAdaptiveRoot().fileSystemRepresentation, 0750);
    lchown(TLinkAdaptiveRoot().fileSystemRepresentation, 501, 501);
}

static int TLinkAdaptiveAcquireLock(void) {
    TLinkAdaptiveEnsureRoot();
    int fd = open(TLinkAdaptiveLockPath().fileSystemRepresentation, O_CREAT | O_RDWR, 0640);
    if (fd < 0) return -1;
    chmod(TLinkAdaptiveLockPath().fileSystemRepresentation, 0640);
    lchown(TLinkAdaptiveLockPath().fileSystemRepresentation, 501, 501);
    if (flock(fd, LOCK_EX) != 0) { close(fd); return -1; }
    return fd;
}

static void TLinkAdaptiveReleaseLock(int fd) {
    if (fd < 0) return;
    flock(fd, LOCK_UN);
    close(fd);
}

static NSMutableDictionary *TLinkAdaptiveReadState(void) {
    NSData *data = [NSData dataWithContentsOfFile:TLinkAdaptiveStatePath()];
    id value = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    if ([value isKindOfClass:[NSDictionary class]] && [value[@"sessions"] isKindOfClass:[NSDictionary class]]) {
        return [value mutableCopy];
    }
    return [@{ @"schema": TLinkAdaptiveStreamingSchemaV1, @"sessions": [NSMutableDictionary dictionary] } mutableCopy];
}

static BOOL TLinkAdaptiveWriteState(NSDictionary *state) {
    if (![NSJSONSerialization isValidJSONObject:state]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    if (!data || ![data writeToFile:TLinkAdaptiveStatePath() atomically:YES]) return NO;
    chmod(TLinkAdaptiveStatePath().fileSystemRepresentation, 0640);
    lchown(TLinkAdaptiveStatePath().fileSystemRepresentation, 501, 501);
    return YES;
}

static NSString *TLinkAdaptiveKey(NSString *runtime, NSInteger port) {
    return [NSString stringWithFormat:@"%@-%ld", runtime.lowercaseString ?: @"unknown", (long)port];
}

static double TLinkAdaptiveNumber(id value, double fallback, double minimum, double maximum) {
    if (![value respondsToSelector:@selector(doubleValue)]) return fallback;
    double number = [value doubleValue];
    if (!isfinite(number)) return fallback;
    return MAX(minimum, MIN(maximum, number));
}

static NSString *TLinkAdaptiveLevelName(NSInteger level) {
    return level >= 2 ? @"survival" : (level == 1 ? @"balanced" : @"high");
}

static NSMutableDictionary *TLinkAdaptiveSession(NSMutableDictionary *state,
                                                  NSString *runtime,
                                                  NSInteger port,
                                                  BOOL create) {
    NSMutableDictionary *sessions = [state[@"sessions"] mutableCopy] ?: [NSMutableDictionary dictionary];
    state[@"sessions"] = sessions;
    NSString *key = TLinkAdaptiveKey(runtime, port);
    NSMutableDictionary *session = [sessions[key] mutableCopy];
    if (!session && create) {
        session = [@{
            @"runtime": runtime ?: @"unknown", @"port": @(port), @"level": @0,
            @"level_name": @"high", @"good_samples": @0, @"poor_samples": @0,
            @"feedback_count": @0, @"adaptation_count": @0, @"recovery_count": @0,
            @"recovery_failure_count": @0, @"active": @false,
        } mutableCopy];
    }
    if (session) sessions[key] = session;
    return session;
}

static void TLinkAdaptivePublishChange(NSDictionary *session, NSString *type, NSString *reason) {
    TLinkEventChannelPublish(session[@"runtime"] ?: @"unknown", @"stream.health", type, @{
        @"port": session[@"port"] ?: @0,
        @"profile": session[@"profile"] ?: @"unknown",
        @"level": session[@"level_name"] ?: @"high",
        @"reason": reason ?: @"unknown",
        @"target_fps": session[@"target_fps"] ?: @0,
        @"target_bitrate": session[@"target_bitrate"] ?: @0,
    });
}

NSDictionary *TLinkAdaptiveStreamingSubmitFeedback(NSString *runtime,
                                                    NSString *base64Body,
                                                    NSString **error) {
    if (base64Body.length == 0 || base64Body.length > kTLinkAdaptiveFeedbackMaxBytes * 2) {
        if (error) *error = @"adaptive_feedback_invalid";
        return @{};
    }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64Body options:0];
    id raw = data.length <= kTLinkAdaptiveFeedbackMaxBytes
        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![raw isKindOfClass:[NSDictionary class]]) {
        if (error) *error = @"adaptive_feedback_invalid";
        return @{};
    }
    NSDictionary *input = raw;
    if (![input[@"schema"] isEqualToString:@"stream_feedback_v1"]) {
        if (error) *error = @"adaptive_feedback_schema_invalid";
        return @{};
    }
    id rawPort = input[@"port"];
    NSInteger port = [rawPort respondsToSelector:@selector(integerValue)] ? [rawPort integerValue] : 0;
    if (port < 7001 || port > 7006 || fabs([rawPort doubleValue] - (double)port) > 0.001) {
        if (error) *error = @"adaptive_feedback_port_invalid";
        return @{};
    }
    uint64_t now = TLinkAdaptiveNowMs();
    NSDictionary *feedback = @{
        @"schema": @"stream_feedback_v1", @"received_at_ms": @(now), @"port": @(port),
        @"fps": @(TLinkAdaptiveNumber(input[@"fps"], 0, 0, 120)),
        @"kbps": @(TLinkAdaptiveNumber(input[@"kbps"], 0, 0, 50000)),
        @"decode_queue": @(TLinkAdaptiveNumber(input[@"decode_queue"], 0, 0, 128)),
        @"dropped": @(TLinkAdaptiveNumber(input[@"dropped"], 0, 0, 1000000000)),
        @"total_approx_ms": @(TLinkAdaptiveNumber(input[@"total_approx_ms"], 0, 0, 60000)),
        @"stalled": @([input[@"stalled"] boolValue]),
        @"source": @"webtango_zxh2_v1",
    };
    @synchronized (TLinkAdaptiveProcessLock()) {
        int fd = TLinkAdaptiveAcquireLock();
        if (fd < 0) { if (error) *error = @"adaptive_state_lock_failed"; return @{}; }
        NSMutableDictionary *state = TLinkAdaptiveReadState();
        NSMutableDictionary *session = TLinkAdaptiveSession(state, runtime, port, YES);
        uint64_t previousFeedbackAt = [session[@"feedback"][@"received_at_ms"] unsignedLongLongValue];
        if (previousFeedbackAt > 0 && now >= previousFeedbackAt &&
            now - previousFeedbackAt < kTLinkAdaptiveFeedbackMinimumIntervalMs) {
            TLinkAdaptiveReleaseLock(fd);
            return @{ @"schema": TLinkAdaptiveStreamingSchemaV1, @"state": @"throttled",
                      @"port": @(port), @"retry_after_ms": @(kTLinkAdaptiveFeedbackMinimumIntervalMs) };
        }
        session[@"feedback"] = feedback;
        session[@"feedback_count"] = @([session[@"feedback_count"] unsignedLongLongValue] + 1);
        state[@"updated_at_ms"] = @(now);
        BOOL saved = TLinkAdaptiveWriteState(state);
        TLinkAdaptiveReleaseLock(fd);
        if (!saved) { if (error) *error = @"adaptive_state_write_failed"; return @{}; }
    }
    return @{ @"schema": TLinkAdaptiveStreamingSchemaV1, @"state": @"accepted", @"port": @(port), @"received_at_ms": @(now) };
}

NSDictionary *TLinkAdaptiveStreamingDecision(NSString *runtime,
                                              NSInteger port,
                                              NSInteger baseFPS,
                                              NSInteger minimumFPS,
                                              NSInteger baseBitrate,
                                              NSInteger thermalFPS,
                                              NSInteger thermalBitrate) {
    uint64_t now = TLinkAdaptiveNowMs();
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    @synchronized (TLinkAdaptiveProcessLock()) {
        int fd = TLinkAdaptiveAcquireLock();
        if (fd < 0) return @{ @"level": @0, @"level_name": @"high", @"target_fps": @(thermalFPS), @"target_bitrate": @(thermalBitrate), @"reason": @"state_lock_failed", @"changed": @false };
        NSMutableDictionary *state = TLinkAdaptiveReadState();
        NSMutableDictionary *session = TLinkAdaptiveSession(state, runtime, port, YES);
        NSDictionary *feedback = [session[@"feedback"] isKindOfClass:[NSDictionary class]] ? session[@"feedback"] : nil;
        uint64_t feedbackAt = [feedback[@"received_at_ms"] unsignedLongLongValue];
        BOOL fresh = feedback && now >= feedbackAt && now - feedbackAt <= kTLinkAdaptiveFeedbackFreshMs;
        NSInteger level = [session[@"level"] integerValue];
        NSInteger previousLevel = level;
        NSString *reason = fresh ? @"feedback_healthy" : @"feedback_stale";
        uint64_t lastProcessed = [session[@"last_processed_feedback_at_ms"] unsignedLongLongValue];
        BOOL newSample = fresh && feedbackAt > lastProcessed;
        if (!fresh && [session[@"active"] boolValue] && lastProcessed > 0 && now - lastProcessed > kTLinkAdaptiveFeedbackFreshMs * 2) {
            // Missing feedback must not leave a previously degraded session at
            // full quality forever. Use balanced as a conservative ceiling.
            level = MAX(level, 1);
            reason = @"feedback_stale_fail_safe";
        }
        NSInteger good = [session[@"good_samples"] integerValue];
        NSInteger poor = [session[@"poor_samples"] integerValue];
        if (newSample) {
            double latency = [feedback[@"total_approx_ms"] doubleValue];
            double queue = [feedback[@"decode_queue"] doubleValue];
            double fps = [feedback[@"fps"] doubleValue];
            BOOL severe = [feedback[@"stalled"] boolValue] || queue >= 8 || latency >= 350;
            BOOL degraded = severe || queue >= 4 || latency >= 180 || (fps > 0 && fps < MAX(4.0, baseFPS * 0.55));
            BOOL healthy = !degraded && queue <= 1 && latency <= 110 && (fps == 0 || fps >= MAX(4.0, baseFPS * 0.70));
            if (degraded) { poor++; good = 0; reason = severe ? @"feedback_severe" : @"feedback_degraded"; }
            else if (healthy) { good++; poor = 0; reason = @"feedback_healthy"; }
            else { good = 0; poor = 0; reason = @"feedback_neutral"; }
            uint64_t lastChange = [session[@"last_change_at_ms"] unsignedLongLongValue];
            BOOL cooldownElapsed = lastChange == 0 || now - lastChange >= kTLinkAdaptiveChangeCooldownMs;
            if (cooldownElapsed && ((severe && poor >= 1) || poor >= 2) && level < 2) {
                level++;
                poor = 0;
            } else if (cooldownElapsed && good >= kTLinkAdaptiveRecoveryGoodSamples && level > 0) {
                level--;
                good = 0;
                reason = @"feedback_recovered";
            }
            session[@"last_processed_feedback_at_ms"] = @(feedbackAt);
        }
        double fpsFactor = level == 0 ? 1.0 : (level == 1 ? 0.70 : 0.45);
        double bitrateFactor = level == 0 ? 1.0 : (level == 1 ? 0.65 : 0.35);
        NSInteger targetFPS = MAX(minimumFPS, MIN(thermalFPS, (NSInteger)floor(baseFPS * fpsFactor)));
        NSInteger targetBitrate = MAX(200000, MIN(thermalBitrate, (NSInteger)floor(baseBitrate * bitrateFactor)));
        BOOL changed = level != previousLevel;
        NSInteger previousTargetFPS = [session[@"target_fps"] integerValue];
        NSInteger previousTargetBitrate = [session[@"target_bitrate"] integerValue];
        BOOL previousFresh = [session[@"feedback_fresh"] boolValue];
        session[@"level"] = @(level);
        session[@"level_name"] = TLinkAdaptiveLevelName(level);
        session[@"good_samples"] = @(good);
        session[@"poor_samples"] = @(poor);
        session[@"feedback_fresh"] = @(fresh);
        session[@"target_fps"] = @(targetFPS);
        session[@"target_bitrate"] = @(targetBitrate);
        session[@"last_reason"] = reason;
        session[@"last_decision_at_ms"] = @(now);
        if (changed) {
            session[@"last_change_at_ms"] = @(now);
            session[@"adaptation_count"] = @([session[@"adaptation_count"] unsignedLongLongValue] + 1);
        }
        BOOL shouldPersist = newSample || changed || previousTargetFPS != targetFPS ||
            previousTargetBitrate != targetBitrate || previousFresh != fresh;
        if (shouldPersist) {
            state[@"updated_at_ms"] = @(now);
            TLinkAdaptiveWriteState(state);
        }
        result = [@{ @"schema": TLinkAdaptiveStreamingSchemaV1, @"level": @(level),
                     @"level_name": TLinkAdaptiveLevelName(level), @"target_fps": @(targetFPS),
                     @"target_bitrate": @(targetBitrate), @"reason": reason, @"changed": @(changed),
                     @"feedback_fresh": @(fresh) } mutableCopy];
        NSDictionary *published = changed ? [session copy] : nil;
        TLinkAdaptiveReleaseLock(fd);
        if (published) TLinkAdaptivePublishChange(published, level > previousLevel ? @"degraded" : @"recovered", reason);
    }
    return result;
}

void TLinkAdaptiveStreamingSessionStarted(NSString *runtime, NSInteger port, NSString *profile,
                                          NSInteger width, NSInteger height, NSInteger baseFPS, NSInteger baseBitrate) {
    @synchronized (TLinkAdaptiveProcessLock()) {
        int fd = TLinkAdaptiveAcquireLock(); if (fd < 0) return;
        NSMutableDictionary *state = TLinkAdaptiveReadState();
        NSMutableDictionary *session = TLinkAdaptiveSession(state, runtime, port, YES);
        [session addEntriesFromDictionary:@{ @"active": @true, @"profile": profile ?: @"unknown",
            @"width": @(width), @"height": @(height), @"base_fps": @(baseFPS),
            @"base_bitrate": @(baseBitrate), @"started_at_ms": @(TLinkAdaptiveNowMs()),
            @"ended_at_ms": @0, @"end_reason": @"", @"level": @0, @"level_name": @"high",
            @"good_samples": @0, @"poor_samples": @0 }];
        [session removeObjectForKey:@"feedback"];
        [session removeObjectForKey:@"last_processed_feedback_at_ms"];
        [session removeObjectForKey:@"last_change_at_ms"];
        TLinkAdaptiveWriteState(state); NSDictionary *copy = [session copy]; TLinkAdaptiveReleaseLock(fd);
        TLinkAdaptivePublishChange(copy, @"started", @"client_connected");
    }
}

void TLinkAdaptiveStreamingSessionEnded(NSString *runtime, NSInteger port, NSString *reason) {
    @synchronized (TLinkAdaptiveProcessLock()) {
        int fd = TLinkAdaptiveAcquireLock(); if (fd < 0) return;
        NSMutableDictionary *state = TLinkAdaptiveReadState();
        NSMutableDictionary *session = TLinkAdaptiveSession(state, runtime, port, YES);
        session[@"active"] = @false; session[@"ended_at_ms"] = @(TLinkAdaptiveNowMs());
        session[@"end_reason"] = reason ?: @"closed";
        TLinkAdaptiveWriteState(state); NSDictionary *copy = [session copy]; TLinkAdaptiveReleaseLock(fd);
        TLinkAdaptivePublishChange(copy, @"ended", reason ?: @"closed");
    }
}

void TLinkAdaptiveStreamingRecordRecovery(NSString *runtime, NSInteger port, NSString *reason, BOOL succeeded) {
    @synchronized (TLinkAdaptiveProcessLock()) {
        int fd = TLinkAdaptiveAcquireLock(); if (fd < 0) return;
        NSMutableDictionary *state = TLinkAdaptiveReadState();
        NSMutableDictionary *session = TLinkAdaptiveSession(state, runtime, port, YES);
        NSString *counter = succeeded ? @"recovery_count" : @"recovery_failure_count";
        session[counter] = @([session[counter] unsignedLongLongValue] + 1);
        session[@"last_recovery_at_ms"] = @(TLinkAdaptiveNowMs());
        session[@"last_recovery_reason"] = reason ?: @"unknown";
        TLinkAdaptiveWriteState(state); NSDictionary *copy = [session copy]; TLinkAdaptiveReleaseLock(fd);
        TLinkAdaptivePublishChange(copy, succeeded ? @"self_healed" : @"recovery_failed", reason ?: @"unknown");
    }
}

NSDictionary *TLinkAdaptiveStreamingStatus(NSString *runtime) {
    @synchronized (TLinkAdaptiveProcessLock()) {
        int fd = TLinkAdaptiveAcquireLock();
        if (fd < 0) return @{ @"schema": TLinkAdaptiveStreamingSchemaV1, @"state": @"error", @"error": @"adaptive_state_lock_failed" };
        NSDictionary *state = TLinkAdaptiveReadState();
        NSMutableArray *sessions = [NSMutableArray array];
        for (NSDictionary *session in [state[@"sessions"] allValues]) {
            if ([session[@"runtime"] isEqualToString:runtime]) [sessions addObject:session];
        }
        [sessions sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"port"] compare:b[@"port"]];
        }];
        TLinkAdaptiveReleaseLock(fd);
        return @{ @"schema": TLinkAdaptiveStreamingSchemaV1, @"state": @"implemented",
            @"policy": @"feedback_hysteresis_v1", @"feedback_transport": @"task94_base64_json_v1",
            @"levels": @[@"high", @"balanced", @"survival"], @"feedback_fresh_ms": @(kTLinkAdaptiveFeedbackFreshMs),
            @"feedback_minimum_interval_ms": @(kTLinkAdaptiveFeedbackMinimumIntervalMs),
            @"change_cooldown_ms": @(kTLinkAdaptiveChangeCooldownMs), @"max_encoder_restarts_per_session": @3,
            @"max_client_reconnect_attempts": @6,
            @"sessions": sessions, @"device_validated": @false };
    }
}
