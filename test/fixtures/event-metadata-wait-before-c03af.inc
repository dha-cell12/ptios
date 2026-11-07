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
static NSDictionary *TLinkEventLoadSnapshot(BOOL nonBlocking, NSString **fingerprint, NSString **error) {
    int fd = -1;
    NSDictionary *journal = nil;
    if (fingerprint) *fingerprint = nil;
    if (error) *error = nil;
    @try { try {
        fd = TLinkEventAcquireFileLock(YES, nonBlocking);
        if (fd < 0) { if (error) *error = @"event_journal_unavailable"; return nil; }
        NSString *readError = nil;
        journal = TLinkEventReadJournal(&readError);
        if (!journal) { if (error) *error = readError; return nil; }
        if (fingerprint) *fingerprint = TLinkEventFileFingerprint();
    } catch (...) { if (error) *error = @"event_journal_exception"; return nil; } }
    @catch (__unused NSException *exception) { if (error) *error = @"event_journal_exception"; return nil; }
    @finally { TLinkEventReleaseFileLock(fd); }
    return journal;
}
static void TLinkEventSweep(BOOL forceRead) {
    if (!sTLinkEventWaiters.count) { TLinkEventRearm(); return; }
    uint64_t now = TLinkEventMonotonicMs();
    BOOL ready = NO;
    for (TLinkEventPendingPoll *request in sTLinkEventWaiters) if (request->authorized && !request.isCancelled) ready = YES;
    BOOL loaded = YES, changed = NO;
    NSString *readError = nil;
    if (ready && (forceRead || !sTLinkEventSnapshot || ![TLinkEventFileFingerprint() isEqual:sTLinkEventFingerprint])) {
        NSString *fingerprint = nil;
        NSDictionary *journal = TLinkEventLoadSnapshot(YES, &fingerprint, &readError); // Never park the owner on flock.
        loaded = journal != nil;
        if (loaded) { sTLinkEventSnapshot = journal; sTLinkEventFingerprint = fingerprint; changed = YES; }
        else { sTLinkEventSnapshot = nil; sTLinkEventFingerprint = nil; }
    }
    for (TLinkEventPendingPoll *request in [sTLinkEventWaiters allObjects]) {
        if (request.isCancelled) { [sTLinkEventWaiters removeObject:request]; request->completion = nil; continue; }
        BOOL expired = TLinkEventPollExpired(request->started, now, request->authorized ? request->timeout : 5000);
        if (!request->authorized) {
            if (expired) TLinkEventComplete(request, nil, @"event_poll_authorization_timeout");
            continue;
        }
        if (!loaded || !sTLinkEventSnapshot) {
            if (readError && ![readError isEqualToString:@"event_journal_unavailable"])
                TLinkEventComplete(request, nil, readError);
            else if (expired) TLinkEventComplete(request, nil, @"event_journal_unavailable");
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
