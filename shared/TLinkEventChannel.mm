#import "TLinkEventChannel.h"

#include <atomic>
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
static const NSUInteger kTLinkEventPollIntervalUs = 100000;
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

static int TLinkEventAcquireFileLock(void)
{
    TLinkEventEnsureDirectory();
    NSString *path = TLinkEventLockPath();
    int fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR, 0640);
    if (fd < 0) return -1;
    chmod(path.fileSystemRepresentation, 0640);
    lchown(path.fileSystemRepresentation, 501, 501);
    if (flock(fd, LOCK_EX) != 0) {
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
    NSData *data = [NSData dataWithContentsOfFile:TLinkEventJournalPath()];
    id object = data.length > 0
        ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]
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
        int lockFd = TLinkEventAcquireFileLock();
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
        return event;
    }
}

static BOOL TLinkEventTopicMatches(NSString *topic, NSSet<NSString *> *topics)
{
    return topics.count == 0 || [topics containsObject:@"*"] || [topics containsObject:topic ?: @""];
}

static NSDictionary *TLinkEventReadBatch(uint64_t cursor,
                                         NSSet<NSString *> *topics,
                                         NSUInteger maxEvents,
                                         BOOL timedOut)
{
    int lockFd = TLinkEventAcquireFileLock();
    if (lockFd < 0) {
        return @{
            @"schema": TLinkEventChannelSchemaV1,
            @"state": @"error",
            @"error": @"event_journal_lock_failed",
            @"cursor": @(cursor),
            @"next_cursor": @(cursor),
            @"oldest_cursor": @0,
            @"latest_cursor": @0,
            @"gap": @false,
            @"has_more": @false,
            @"timed_out": @false,
            @"events": @[],
        };
    }
    NSMutableDictionary *journal = TLinkEventReadJournal();
    NSArray *events = [journal[@"events"] isKindOfClass:[NSArray class]] ? journal[@"events"] : @[];
    uint64_t latest = [journal[@"next_sequence"] unsignedLongLongValue];
    latest = latest > 0 ? latest - 1 : 0;
    uint64_t oldest = events.count > 0 ? [events.firstObject[@"sequence"] unsignedLongLongValue] : latest + 1;
    BOOL gap = (events.count > 0 && cursor > 0 && oldest > 0 && cursor < oldest - 1) || cursor > latest;
    NSMutableArray *selected = [NSMutableArray array];
    for (NSDictionary *event in events) {
        uint64_t sequence = [event[@"sequence"] unsignedLongLongValue];
        if (sequence <= cursor) continue;
        if (!TLinkEventTopicMatches(event[@"topic"], topics)) continue;
        [selected addObject:event];
        if (selected.count >= maxEvents) break;
    }
    uint64_t nextCursor = selected.count > 0
        ? [selected.lastObject[@"sequence"] unsignedLongLongValue]
        : latest;
    BOOL hasMore = NO;
    if (selected.count >= maxEvents) {
        for (NSDictionary *event in events) {
            uint64_t sequence = [event[@"sequence"] unsignedLongLongValue];
            if (sequence > nextCursor && TLinkEventTopicMatches(event[@"topic"], topics)) {
                hasMore = YES;
                break;
            }
        }
    }
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
    TLinkEventReleaseFileLock(lockFd);
    return result;
}

NSDictionary *TLinkEventChannelPoll(uint64_t cursor,
                                    NSArray<NSString *> *topics,
                                    NSUInteger timeoutMs,
                                    NSUInteger maxEvents)
{
    timeoutMs = MIN(timeoutMs, kTLinkEventPollMaxTimeoutMs);
    maxEvents = maxEvents == 0 ? kTLinkEventPollDefaultMaxEvents : MIN(maxEvents, kTLinkEventPollMaxEvents);
    NSMutableSet *topicSet = [NSMutableSet set];
    for (id value in topics ?: @[]) {
        NSString *rawTopic = [value isKindOfClass:[NSString class]] ? value : @"";
        NSString *topic = [rawTopic isEqualToString:@"*"] ? @"*" : TLinkEventToken(rawTopic, @"");
        if (topic.length > 0) [topicSet addObject:topic];
    }

    int active = sTLinkEventActivePolls.fetch_add(1, std::memory_order_relaxed) + 1;
    if (active > kTLinkEventMaxConcurrentPolls) {
        sTLinkEventActivePolls.fetch_sub(1, std::memory_order_relaxed);
        return @{
            @"schema": TLinkEventChannelSchemaV1,
            @"state": @"busy",
            @"error": @"event_poll_capacity_reached",
            @"retry_after_ms": @250,
            @"cursor": @(cursor),
            @"next_cursor": @(cursor),
            @"oldest_cursor": @0,
            @"latest_cursor": @0,
            @"gap": @false,
            @"has_more": @false,
            @"timed_out": @false,
            @"events": @[],
        };
    }

    uint64_t startedAt = TLinkEventNowMs();
    NSDictionary *result = nil;
    do {
        BOOL timedOut = TLinkEventNowMs() - startedAt >= timeoutMs;
        result = TLinkEventReadBatch(cursor, topicSet, maxEvents, timedOut);
        if (![result[@"state"] isEqualToString:@"ready"] ||
            [result[@"next_cursor"] unsignedLongLongValue] > cursor ||
            [result[@"events"] count] > 0 || [result[@"gap"] boolValue] || timedOut || timeoutMs == 0) break;
        usleep((useconds_t)kTLinkEventPollIntervalUs);
    } while (YES);
    sTLinkEventActivePolls.fetch_sub(1, std::memory_order_relaxed);
    return result ?: @{};
}

NSDictionary *TLinkEventChannelPollBody(NSString *body, NSString **error)
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
    NSRegularExpression *topicPattern = [NSRegularExpression regularExpressionWithPattern:@"^(\\*|[A-Za-z0-9._-]{1,64})$"
                                                                                   options:0
                                                                                     error:nil];
    for (NSString *topic in topics) {
        if ([topicPattern numberOfMatchesInString:topic options:0 range:NSMakeRange(0, topic.length)] != 1) {
            if (error) *error = @"event_topic_invalid";
            return @{};
        }
    }
    return TLinkEventChannelPoll(cursor, topics, (NSUInteger)requestedTimeout, (NSUInteger)requestedMax);
}

NSDictionary *TLinkEventChannelStatus(void)
{
    NSDictionary *batch = TLinkEventReadBatch(UINT64_MAX, [NSSet set], 1, NO);
    return @{
        @"schema": TLinkEventChannelSchemaV1,
        @"state": @"implemented",
        @"transport": @"task95_long_poll_v1",
        @"journal_max_events": @(kTLinkEventJournalMaxEvents),
        @"poll_timeout_max_ms": @(kTLinkEventPollMaxTimeoutMs),
        @"poll_max_events": @(kTLinkEventPollMaxEvents),
        @"max_concurrent_polls": @(kTLinkEventMaxConcurrentPolls),
        @"latest_cursor": batch[@"latest_cursor"] ?: @0,
        @"active_polls": @(sTLinkEventActivePolls.load(std::memory_order_relaxed)),
        @"root_path": TLinkEventChannelRootPath(),
    };
}
