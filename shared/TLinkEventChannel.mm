#import "TLinkEventChannel.h"

#include <atomic>
#include <memory>
#include <notify.h>
#include "TLinkEventPollCore.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <stdint.h>
#include <unistd.h>

NSString * const TLinkEventChannelSchemaV1 = @"event_channel_v1";
NSString * const TLinkEventSchemaV1 = @"tlink_event_v1";

static const NSUInteger kTLinkEventJournalMaxEvents = 256;
static const NSUInteger kTLinkEventPollDefaultTimeoutMs = 20000;
static const NSUInteger kTLinkEventPollMaxTimeoutMs = 25000;
static const NSUInteger kTLinkEventPollDefaultMaxEvents = 16;
static const NSUInteger kTLinkEventPollMaxEvents = 32;
static const uint64_t kTLinkEventReconcileMs = 1000;
static const char *kTLinkEventNotification = "com.tlinkauto.event-channel.changed.v1";
static std::atomic<uint64_t> sTLinkEventJournalReads{0}, sTLinkEventMetadataChecks{0};
static const NSUInteger kTLinkEventPayloadMaxBytes = 4096;
static const int kTLinkEventMaxConcurrentPolls = 8;
static std::atomic<int> sTLinkEventActivePolls(0);

static NSObject *TLinkEventProcessLock(void)
{
    static NSObject *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSObject alloc] init]; });
    return lock;
}

static uint64_t TLinkEventNowMs(void)
{
    return (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

static BOOL TLinkEventParseUnsignedCursor(NSString *text, uint64_t *value)
{
    if (!value) return NO;
    if (text.length == 0) {
        *value = 0;
        return YES;
    }

    const char *utf8 = [text UTF8String];
    if (!utf8) return NO;
    char *end = NULL;
    errno = 0;
    unsigned long long parsed = strtoull(utf8, &end, 10);
    if (errno == ERANGE || end == utf8 || !end || *end != '\0') return NO;
    *value = (uint64_t)parsed;
    return YES;
}

NSString *TLinkEventChannelRootPath(void)
{
    return @"/var/mobile/Library/TLinkauto/event-channel";
}

static NSString *TLinkEventJournalPath(void)
{
    return [TLinkEventChannelRootPath() stringByAppendingPathComponent:@"journal.json"];
}

static NSString *TLinkEventLockPath(void)
{
    return [TLinkEventChannelRootPath() stringByAppendingPathComponent:@"journal.lock"];
}

static void TLinkEventEnsureDirectory(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:TLinkEventChannelRootPath()
   withIntermediateDirectories:YES
                    attributes:@{NSFilePosixPermissions: @0750}
                         error:nil];
    chmod(TLinkEventChannelRootPath().fileSystemRepresentation, 0750);
    lchown(TLinkEventChannelRootPath().fileSystemRepresentation, 501, 501);
}

static int TLinkEventAcquireFileLock(BOOL reader, BOOL nonBlocking)
{
    TLinkEventEnsureDirectory();
    NSString *path = TLinkEventLockPath();
    int fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR, 0640);
    if (fd < 0) return -1;
    chmod(path.fileSystemRepresentation, 0640);
    lchown(path.fileSystemRepresentation, 501, 501);
    int operation = reader ? LOCK_SH : LOCK_EX;
    if (nonBlocking) operation |= LOCK_NB;
    if (flock(fd, operation) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void TLinkEventReleaseFileLock(int fd)
{
    if (fd < 0) return;
    flock(fd, LOCK_UN);
    close(fd);
}

static NSMutableDictionary *TLinkEventReadJournal(void)
{
    sTLinkEventJournalReads.fetch_add(1);
    NSData *data = [NSData dataWithContentsOfFile:TLinkEventJournalPath()];
    id object = data.length > 0
        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]
        : nil;
    if ([object isKindOfClass:[NSDictionary class]] &&
        [object[@"events"] isKindOfClass:[NSArray class]]) {
        return [object mutableCopy];
    }
    return [@{
        @"schema": TLinkEventChannelSchemaV1,
        @"next_sequence": @1,
        @"events": [NSMutableArray array],
    } mutableCopy];
}

static BOOL TLinkEventWriteJournal(NSDictionary *journal)
{
    if (![NSJSONSerialization isValidJSONObject:journal]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:journal options:0 error:nil];
    NSString *path = TLinkEventJournalPath();
    if (!data || ![data writeToFile:path atomically:YES]) return NO;
    chmod(path.fileSystemRepresentation, 0640);
    lchown(path.fileSystemRepresentation, 501, 501);
    return YES;
}

static NSString *TLinkEventToken(NSString *value, NSString *fallback)
{
    NSString *source = [value isKindOfClass:[NSString class]] ? value.lowercaseString : @"";
    NSMutableString *token = [NSMutableString string];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
    for (NSUInteger index = 0; index < source.length && token.length < 64; index++) {
        unichar c = [source characterAtIndex:index];
        if ([allowed characterIsMember:c]) [token appendFormat:@"%C", c];
    }
    return token.length > 0 ? token : fallback;
}

static NSDictionary *TLinkEventBoundedPayload(NSDictionary *payload)
{
    if (![payload isKindOfClass:[NSDictionary class]] ||
        ![NSJSONSerialization isValidJSONObject:payload]) return @{};
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (data.length <= kTLinkEventPayloadMaxBytes) return payload;
    return @{
        @"truncated": @true,
        @"original_bytes": @(data.length),
        @"reason": @"event_payload_limit",
    };
}

NSDictionary *TLinkEventChannelPublish(NSString *runtime,
                                       NSString *topic,
                                       NSString *type,
                                       NSDictionary *payload)
{
    @synchronized (TLinkEventProcessLock()) {
        int lockFd = TLinkEventAcquireFileLock(NO, NO);
        if (lockFd < 0) return @{@"state": @"error", @"error": @"event_journal_lock_failed"};
        NSMutableDictionary *journal = TLinkEventReadJournal();
        NSMutableArray *events = [journal[@"events"] mutableCopy] ?: [NSMutableArray array];
        uint64_t sequence = MAX((uint64_t)1, [journal[@"next_sequence"] unsignedLongLongValue]);
        NSDictionary *event = @{
            @"schema": TLinkEventSchemaV1,
            @"sequence": @(sequence),
            @"event_id": [NSUUID UUID].UUIDString.lowercaseString,
            @"timestamp_ms": @(TLinkEventNowMs()),
            @"runtime": TLinkEventToken(runtime, @"unknown"),
            @"topic": TLinkEventToken(topic, @"system"),
            @"type": TLinkEventToken(type, @"updated"),
            @"payload": TLinkEventBoundedPayload(payload),
        };
        [events addObject:event];
        while (events.count > kTLinkEventJournalMaxEvents) [events removeObjectAtIndex:0];
        journal[@"schema"] = TLinkEventChannelSchemaV1;
        journal[@"next_sequence"] = @(sequence + 1);
        journal[@"events"] = events;
        journal[@"updated_at_ms"] = @(TLinkEventNowMs());
        BOOL persisted = TLinkEventWriteJournal(journal);
        TLinkEventReleaseFileLock(lockFd);
        if (!persisted) return @{@"state": @"error", @"error": @"event_journal_write_failed"};
        notify_post(kTLinkEventNotification); // Wake hint only, after the journal commit and unlock.
        return event;
    }
}

static BOOL TLinkEventTopicMatches(NSString *topic, NSSet<NSString *> *topics)
{
    return topics.count == 0 || [topics containsObject:@"*"] || [topics containsObject:topic ?: @""];
}

static NSDictionary *TLinkEventBatchFromJournal(NSDictionary *journal, uint64_t cursor,
    NSSet<NSString *> *topics, NSUInteger maxEvents, BOOL timedOut)
{
    NSArray *events = [journal[@"events"] isKindOfClass:[NSArray class]] ? journal[@"events"] : @[];
    uint64_t latest = [journal[@"next_sequence"] unsignedLongLongValue];
    latest = latest > 0 ? latest - 1 : 0;
    uint64_t oldest = events.count > 0 ? [events.firstObject[@"sequence"] unsignedLongLongValue] : latest + 1;
    BOOL gap = (events.count > 0 && cursor > 0 && oldest > 0 && cursor < oldest - 1) || cursor > latest;
    NSMutableArray *selected = [NSMutableArray array];
    TLinkEventBatchCursor scan(cursor, maxEvents);
    for (NSDictionary *event in events) {
        auto action = scan.scan([event[@"sequence"] unsignedLongLongValue], TLinkEventTopicMatches(event[@"topic"], topics));
        if (action == TLinkEventBatchCursor::Stop) break;
        if (action == TLinkEventBatchCursor::Select) [selected addObject:event];
    }
    uint64_t nextCursor = scan.nextCursor(latest);
    BOOL hasMore = scan.more;
    NSDictionary *result = @{
        @"schema": TLinkEventChannelSchemaV1,
        @"state": @"ready",
        @"cursor": @(cursor),
        @"next_cursor": @(nextCursor),
        @"oldest_cursor": @(oldest > 0 ? oldest - 1 : 0),
        @"latest_cursor": @(latest),
        @"gap": @(gap),
        @"has_more": @(hasMore),
        @"timed_out": @(timedOut),
        @"events": selected,
    };
    return result;
}

static NSDictionary *TLinkEventParseBody(NSString *body, NSString **error)
{
    NSArray<NSString *> *parts = [body.length > 0 ? body : @"" componentsSeparatedByString:@";;"];
    NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (parts.count > 4 ||
        (parts.count > 0 && [parts[0] rangeOfCharacterFromSet:notDigits].location != NSNotFound) ||
        (parts.count > 1 && ([parts[1] length] == 0 || [parts[1] rangeOfCharacterFromSet:notDigits].location != NSNotFound)) ||
        (parts.count > 2 && ([parts[2] length] == 0 || [parts[2] rangeOfCharacterFromSet:notDigits].location != NSNotFound))) {
        if (error) *error = @"event_request_invalid";
        return @{};
    }
    NSString *cursorText = parts.count > 0 ? parts[0] : @"";
    uint64_t cursor = 0;
    if (!TLinkEventParseUnsignedCursor(cursorText, &cursor)) {
        if (error) *error = @"event_request_invalid";
        return @{};
    }
    NSInteger requestedTimeout = parts.count > 1 ? [parts[1] integerValue] : (NSInteger)kTLinkEventPollDefaultTimeoutMs;
    NSInteger requestedMax = parts.count > 2 ? [parts[2] integerValue] : (NSInteger)kTLinkEventPollDefaultMaxEvents;
    if (requestedTimeout < 0 || requestedTimeout > (NSInteger)kTLinkEventPollMaxTimeoutMs) {
        if (error) *error = @"event_timeout_out_of_range";
        return @{};
    }
    if (requestedMax < 1 || requestedMax > (NSInteger)kTLinkEventPollMaxEvents) {
        if (error) *error = @"event_max_events_out_of_range";
        return @{};
    }
    NSArray *topics = parts.count > 3 && [parts[3] length] > 0
        ? [parts[3] componentsSeparatedByString:@","] : @[@"*"];
    if (topics.count > 16) {
        if (error) *error = @"event_topic_limit_exceeded";
        return @{};
    }
    for (NSString *topic in topics) {
        NSData *bytes = [topic dataUsingEncoding:NSUTF8StringEncoding];
        if (!TLinkEventTopicValid((const char *)bytes.bytes, bytes.length)) {
            if (error) *error = @"event_topic_invalid";
            return @{};
        }
    }
    return @{@"cursor": @(cursor), @"timeout": @(requestedTimeout), @"limit": @(requestedMax), @"topics": topics};
}

// BEGIN event wait adapter.
// One owner/timer per process, no parked worker for each long-poll.
static dispatch_queue_t TLinkEventOwnerQueue(void);
static void TLinkEventRearm(void);
static std::atomic<int> sTLinkEventAuthorizations{0};
static NSMutableSet *sTLinkEventWaiters;
static dispatch_source_t sTLinkEventTimer;
static NSDictionary *sTLinkEventSnapshot;
static NSString *sTLinkEventFingerprint;
static uint64_t sTLinkEventNextReconcile = 0;
static int sTLinkEventNotifyToken = 0;
@implementation TLinkEventPollRequest
- (void)cancel {}
- (BOOL)isCancelled { return NO; }
@end
@interface TLinkEventPendingPoll : TLinkEventPollRequest {
@public
    std::shared_ptr<TLinkEventPollLease> lease;
    TLinkEventPollCompletion completion;
    uint64_t cursor, started, timeout;
    NSUInteger limit;
    NSSet *topics;
    BOOL authorized;
}
@end
@implementation TLinkEventPendingPoll
- (BOOL)isCancelled { return lease && lease->cancelled(); }
- (void)cancel {
    if (lease) lease->cancel(); // Release capacity before owner queue or provider completion.
    dispatch_async(TLinkEventOwnerQueue(), ^{
        [sTLinkEventWaiters removeObject:self]; self->completion = nil; TLinkEventRearm();
    });
}
@end
static NSDictionary *TLinkEventEmptyBatch(uint64_t cursor, NSString *state, NSString *error) {
    return @{@"schema": TLinkEventChannelSchemaV1, @"state": state, @"error": error,
        @"retry_after_ms": @250, @"cursor": @(cursor), @"next_cursor": @(cursor),
        @"oldest_cursor": @0, @"latest_cursor": @0, @"gap": @false, @"has_more": @false,
        @"timed_out": @false, @"events": @[]};
}
static void TLinkEventComplete(TLinkEventPendingPoll *request, NSDictionary *batch, NSString *error) {
    [sTLinkEventWaiters removeObject:request];
    TLinkEventPollCompletion callback = request->completion; request->completion = nil;
    if (request->lease->finish() && !request.isCancelled && callback) callback(request, batch, error);
}
static NSString *TLinkEventFileFingerprint(void) {
    sTLinkEventMetadataChecks.fetch_add(1);
    struct stat info;
    if (stat(TLinkEventJournalPath().fileSystemRepresentation, &info) != 0)
        return [NSString stringWithFormat:@"absent:%d", errno];
    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld:%lld:%ld",
        (unsigned long long)info.st_dev, (unsigned long long)info.st_ino, (long long)info.st_size,
        (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec,
        (long long)info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec];
}
static NSDictionary *TLinkEventLoadSnapshot(BOOL nonBlocking, NSString **fingerprint) {
    int fd = TLinkEventAcquireFileLock(YES, nonBlocking);
    if (fd < 0) return nil;
    NSDictionary *journal = nil;
    @try {
        journal = TLinkEventReadJournal();
        if (fingerprint) *fingerprint = TLinkEventFileFingerprint();
    } @finally { TLinkEventReleaseFileLock(fd); }
    return journal;
}
static void TLinkEventSweep(BOOL forceRead) {
    if (!sTLinkEventWaiters.count) { TLinkEventRearm(); return; }
    uint64_t now = TLinkEventMonotonicMs();
    BOOL ready = NO;
    for (TLinkEventPendingPoll *request in sTLinkEventWaiters) if (request->authorized && !request.isCancelled) ready = YES;
    BOOL loaded = YES, changed = NO;
    if (ready && (forceRead || !sTLinkEventSnapshot || ![TLinkEventFileFingerprint() isEqual:sTLinkEventFingerprint])) {
        NSString *fingerprint = nil;
        NSDictionary *journal = TLinkEventLoadSnapshot(YES, &fingerprint); // Never park the owner on flock.
        loaded = journal != nil;
        if (loaded) { sTLinkEventSnapshot = journal; sTLinkEventFingerprint = fingerprint; changed = YES; }
    }
    for (TLinkEventPendingPoll *request in [sTLinkEventWaiters allObjects]) {
        if (request.isCancelled) { [sTLinkEventWaiters removeObject:request]; request->completion = nil; continue; }
        BOOL expired = TLinkEventPollExpired(request->started, now, request->authorized ? request->timeout : 5000);
        if (!request->authorized) {
            if (expired) TLinkEventComplete(request, nil, @"event_poll_authorization_timeout");
            continue;
        }
        if (!loaded || !sTLinkEventSnapshot) {
            if (expired) TLinkEventComplete(request, nil, @"event_journal_unavailable");
            continue;
        }
        if (!changed && !expired) continue;
        NSDictionary *batch = TLinkEventBatchFromJournal(sTLinkEventSnapshot, request->cursor, request->topics, request->limit, expired);
        if ([batch[@"next_cursor"] unsignedLongLongValue] != request->cursor || [batch[@"events"] count] ||
            [batch[@"gap"] boolValue] || expired) TLinkEventComplete(request, batch, nil);
    }
    sTLinkEventNextReconcile = now + kTLinkEventReconcileMs;
    TLinkEventRearm();
}
static void TLinkEventRearm(void) {
    if (!sTLinkEventWaiters.count) {
        dispatch_source_set_timer(sTLinkEventTimer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
        sTLinkEventSnapshot = nil; sTLinkEventFingerprint = nil; sTLinkEventNextReconcile = 0; return;
    }
    uint64_t now = TLinkEventMonotonicMs();
    uint64_t delay = !sTLinkEventNextReconcile ? kTLinkEventReconcileMs :
        (sTLinkEventNextReconcile > now ? sTLinkEventNextReconcile - now : 0);
    for (TLinkEventPendingPoll *request in sTLinkEventWaiters) {
        uint64_t elapsed = now >= request->started ? now - request->started : 0;
        uint64_t budget = request->authorized ? request->timeout : 5000;
        uint64_t remaining = elapsed < budget ? budget - elapsed : 0;
        if (remaining < delay) delay = remaining;
    }
    dispatch_source_set_timer(sTLinkEventTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, NSEC_PER_MSEC * 10);
}
static dispatch_queue_t TLinkEventOwnerQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.tlinkauto.event-wait", DISPATCH_QUEUE_SERIAL);
        sTLinkEventWaiters = [NSMutableSet set];
        sTLinkEventTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(sTLinkEventTimer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
        dispatch_source_set_event_handler(sTLinkEventTimer, ^{ @autoreleasepool { TLinkEventSweep(NO); } });
        dispatch_resume(sTLinkEventTimer);
        // Register before any initial read. Notifications are hints; the journal is authoritative.
        notify_register_dispatch(kTLinkEventNotification, &sTLinkEventNotifyToken, queue, ^(int token) {
            (void)token; @autoreleasepool { TLinkEventSweep(YES); }
        });
    });
    return queue;
}
TLinkEventPollRequest *TLinkEventChannelBeginPoll(NSString *body, TLinkEventPollAuthorization authorization, TLinkEventPollCompletion completion) {
    TLinkEventPendingPoll *request = [TLinkEventPendingPoll new];
    request->lease = std::make_shared<TLinkEventPollLease>(sTLinkEventActivePolls, kTLinkEventMaxConcurrentPolls);
    request->started = TLinkEventMonotonicMs(); request->completion = [completion copy];
    NSString *error = nil;
    NSDictionary *options = TLinkEventParseBody(body, &error);
    request->cursor = [options[@"cursor"] unsignedLongLongValue]; request->timeout = [options[@"timeout"] unsignedLongLongValue];
    request->limit = [options[@"limit"] unsignedIntegerValue];
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *topic in options[@"topics"]) [set addObject:topic.lowercaseString];
    request->topics = [set copy];
    auto authLease = authorization && !error && request->lease->admitted()
        ? std::make_shared<TLinkEventPollLease>(sTLinkEventAuthorizations) : std::shared_ptr<TLinkEventPollLease>();
    dispatch_async(TLinkEventOwnerQueue(), ^{
        @autoreleasepool {
            if (request.isCancelled) { request->completion = nil; return; }
            if (error) { TLinkEventComplete(request, nil, error); return; }
            if (!request->lease->admitted() || (authLease && !authLease->admitted())) {
                TLinkEventComplete(request, TLinkEventEmptyBatch(request->cursor, @"busy", @"event_poll_capacity_reached"), nil); return;
            }
            [sTLinkEventWaiters addObject:request];
            if (!authorization) { request->authorized = YES; TLinkEventSweep(YES); return; }
            TLinkEventRearm();
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                @autoreleasepool {
                    NSString *denial = nil;
                    @try { if (!request.isCancelled) denial = authorization(); }
                    @catch (NSException *exception) { (void)exception; denial = @"event_poll_authorization_failed"; }
                    authLease->finish();
                    dispatch_async(TLinkEventOwnerQueue(), ^{
                        if (request.isCancelled || ![sTLinkEventWaiters containsObject:request]) return;
                        if (denial.length) { TLinkEventComplete(request, nil, denial); TLinkEventRearm(); return; }
                        request->started = TLinkEventMonotonicMs(); request->authorized = YES; TLinkEventSweep(YES);
                    });
                }
            });
        }
    });
    return request;
}
// Compatibility callers may block their own worker; TCP/JSON/remote adapters use BeginPoll.
NSDictionary *TLinkEventChannelPollBody(NSString *body, NSString **error) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSDictionary *batch = nil; __block NSString *failure = nil;
    TLinkEventChannelBeginPoll(body, nil, ^(TLinkEventPollRequest *request, NSDictionary *value, NSString *reason) {
        (void)request; batch = value; failure = reason; dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (error) *error = failure;
    return batch ?: @{};
}
NSDictionary *TLinkEventChannelPoll(uint64_t cursor, NSArray<NSString *> *topics, NSUInteger timeoutMs, NSUInteger maxEvents) {
    NSMutableArray *normalized = [NSMutableArray array];
    for (NSString *topic in topics ?: @[]) {
        NSString *token = [topic isEqual:@"*"] ? @"*" : TLinkEventToken(topic, @"");
        if (token.length) [normalized addObject:token];
    }
    NSString *body = [NSString stringWithFormat:@"%llu;;%lu;;%lu;;%@", (unsigned long long)cursor,
        (unsigned long)MIN(timeoutMs, kTLinkEventPollMaxTimeoutMs),
        (unsigned long)(maxEvents ? MIN(maxEvents, kTLinkEventPollMaxEvents) : kTLinkEventPollDefaultMaxEvents), [normalized componentsJoinedByString:@","]];
    return TLinkEventChannelPollBody(body, NULL);
}
// END event wait adapter.
NSDictionary *TLinkEventChannelStatus(void)
{
    NSDictionary *journal = TLinkEventLoadSnapshot(NO, NULL);
    NSDictionary *batch = journal ? TLinkEventBatchFromJournal(journal, UINT64_MAX, [NSSet set], 1, NO) : @{};
    return @{
        @"schema": TLinkEventChannelSchemaV1, @"state": @"implemented", @"transport": @"task95_long_poll_v1",
        @"journal_max_events": @(kTLinkEventJournalMaxEvents), @"poll_timeout_max_ms": @(kTLinkEventPollMaxTimeoutMs),
        @"poll_max_events": @(kTLinkEventPollMaxEvents), @"max_concurrent_polls": @(kTLinkEventMaxConcurrentPolls),
        @"latest_cursor": batch[@"latest_cursor"] ?: @0, @"active_polls": @(sTLinkEventActivePolls.load()),
        @"active_authorizations": @(sTLinkEventAuthorizations.load()), @"authorization_timeout_ms": @5000,
        @"journal_read_count": @(sTLinkEventJournalReads.load()), @"metadata_check_count": @(sTLinkEventMetadataChecks.load()),
        @"wait_strategy": @"darwin_notify_async_v1", @"reconcile_interval_ms": @(kTLinkEventReconcileMs),
        @"root_path": TLinkEventChannelRootPath(),
    };
}
