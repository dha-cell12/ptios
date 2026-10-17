#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <arpa/inet.h>
#include <spawn.h>
#include <sys/wait.h>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <thread>
#include <functional>
#include <atomic>
#include "../shared/TLinkEventChannel.h"
#include <notify.h>
extern char **environ;
static bool suppressNotify = false;
static std::atomic<bool> ignoreNotifications{false};
static uint32_t FixtureRegisterNotification(const char *name, int *token, dispatch_queue_t queue, void (^handler)(int)) {
    uint32_t result = notify_register_dispatch(name,token,queue,^(int value) { if (!ignoreNotifications.load()) handler(value); });
    assert(result == NOTIFY_STATUS_OK); return result;
}
static uint32_t FixtureNotifyPost(const char *name) { return suppressNotify ? 0 : notify_post(name); }
#include "EventChannelUnderTest.inc"
static dispatch_queue_t socketQueue() { static dispatch_queue_t q = dispatch_queue_create("test.event-socket", DISPATCH_QUEUE_SERIAL); return q; }
static dispatch_queue_t POCSocketQueue() { return socketQueue(); }
@interface ZXClientContext : NSObject
@property(nonatomic, assign) CFWriteStreamRef writeStream;
@property(nonatomic, assign) BOOL eventPollPending;
@property(nonatomic, strong) TLinkEventPollRequest *eventPollRequest;
@end
@implementation ZXClientContext
@end
@interface POCClientContext : ZXClientContext
@end
@implementation POCClientContext
@end
static NSMutableArray *wireWrites;
static void zx_writeAll(CFWriteStreamRef stream, NSData *data) { assert(stream && data); [wireWrites addObject:data]; }
static void POCWriteAll(CFWriteStreamRef stream, NSData *data) { zx_writeAll(stream,data); }
static NSData *zx_dataFromCString(const char *s) { return [NSData dataWithBytes:s length:strlen(s)]; }
static NSData *TLinkSuccess(NSString *text) { return [[NSString stringWithFormat:@"0;;%@\r\n",text] dataUsingEncoding:NSUTF8StringEncoding]; }
static NSData *TLinkError(NSString *text) { return [[NSString stringWithFormat:@"-1;;%@\r\n",text] dataUsingEncoding:NSUTF8StringEncoding]; }
static std::atomic<bool> allowed{true};
static std::atomic<unsigned> late{0};
static BOOL TLinkRootfullLicenseTaskAllowed(int task, NSString **denial) { assert(task == 95); if (!allowed && denial) *denial = @"-1;;license_required\r\n"; return allowed.load(); }
static BOOL TLinkLicenseFeatureAllowed(NSString *feature, NSString **error) { assert([feature isEqual:@"automation"]); if (!allowed && error) *error = @"license_required"; return allowed.load(); }
static NSData *TLinkLicenseDeniedResponse(int, NSString *, NSString *error) { return TLinkError(error); }
static const NSUInteger kMaxBuffer = 65536;
#include "EventConstantsUnderTest.inc"
#include "EventJSONUnderTest.inc"
#include "EventRootSocketUnderTest.inc"
#include "EventBodyUnderTest.inc"
#include "EventTrollSocketUnderTest.inc"
static void waitFor(std::function<bool()> condition) {
    uint64_t until = TLinkEventMonotonicMs() + 6000;
    while (!condition()) { assert(TLinkEventMonotonicMs() < until); std::this_thread::sleep_for(std::chrono::milliseconds(2)); }
}
static NSString *body(uint64_t cursor, unsigned timeout = 25000, unsigned limit = 8, NSString *topics = @"script.run") {
    return [NSString stringWithFormat:@"%llu;;%u;;%u;;%@",(unsigned long long)cursor,timeout,limit,topics];
}
static uint64_t publish(NSString *topic = @"script.run") { return [TLinkEventChannelPublish(@"fixture",topic,@"updated",@{})[@"sequence"] unsignedLongLongValue]; }
static NSDictionary *poll(uint64_t cursor, unsigned limit = 8) { NSString *error = nil; NSDictionary *batch = TLinkEventChannelPollBody(body(cursor,0,limit), &error); assert(!error); return batch; }
static NSDictionary *decodeLegacy(NSData *data) {
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    assert([line hasPrefix:@"0;;"] && [line hasSuffix:@"\r\n"]);
    NSData *json = [[NSData alloc] initWithBase64EncodedString:[line substringWithRange:NSMakeRange(3,line.length - 5)] options:0];
    NSDictionary *batch = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL]; assert(batch); return batch;
}
static void childPublish(const char *executable, const char *mode) {
    pid_t pid; char *args[] = {const_cast<char *>(executable), const_cast<char *>(mode), nullptr};
    assert(posix_spawn(&pid, executable, nullptr, nullptr, args, environ) == 0);
    int status; assert(waitpid(pid,&status,0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);
}
int main(int argc, char **argv) { @autoreleasepool {
    (void)kZXLegacyMaxBufferSize;
    if (argc > 1) { suppressNotify = strcmp(argv[1],"quiet") == 0; assert(publish()); return 0; }
    uint64_t one = publish(), unrelated = publish(@"other"), three = publish(), tail = publish(@"other");
    assert(one && unrelated == one + 1 && three == one + 2 && tail == one + 3);
    NSDictionary *batch = poll(0,1); assert([batch[@"has_more"] boolValue] && [batch[@"next_cursor"] unsignedLongLongValue] == unrelated);
    batch = poll(unrelated,1); assert(![batch[@"has_more"] boolValue] && [batch[@"next_cursor"] unsignedLongLongValue] == tail && [batch[@"events"] count] == 1);
    NSString *error = nil; (void)TLinkEventChannelPollBody(@"0;;0;;8;;a*b",&error); assert([error isEqual:@"event_topic_invalid"]);
    error = nil; (void)TLinkEventChannelPollBody(@"18446744073709551616;;0;;8;;*",&error); assert([error isEqual:@"event_request_invalid"]);
    fputs("Event runtime: quiet wait, cross-process notification and lost-hint reconciliation\n",stderr);
    dispatch_semaphore_t delivered = dispatch_semaphore_create(0);
    __block NSDictionary *received = nil;
    TLinkEventPollRequest *request = TLinkEventChannelBeginPoll(body(tail),nil,^(TLinkEventPollRequest *,NSDictionary *value,NSString *reason) { assert(!reason); received = value; dispatch_semaphore_signal(delivered); });
    dispatch_sync(TLinkEventOwnerQueue(), ^{});
    uint64_t reads = sTLinkEventJournalReads.load(); std::this_thread::sleep_for(std::chrono::milliseconds(350));
    assert(sTLinkEventJournalReads.load() == reads);
    childPublish(argv[0],"publish");
    assert(dispatch_semaphore_wait(delivered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0 && [received[@"events"] count] == 1);
    uint64_t latest = [received[@"next_cursor"] unsignedLongLongValue];
    ignoreNotifications = true;
    request = TLinkEventChannelBeginPoll(body(latest),nil,^(TLinkEventPollRequest *,NSDictionary *value,NSString *reason) { assert(!reason); received = value; dispatch_semaphore_signal(delivered); });
    dispatch_sync(TLinkEventOwnerQueue(), ^{}); childPublish(argv[0],"quiet");
    assert(dispatch_semaphore_wait(delivered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0 && [received[@"events"] count] == 1);
    latest = [received[@"next_cursor"] unsignedLongLongValue]; ignoreNotifications = false;
    fputs("Event runtime: eight disconnects return capacity even with writer contention\n",stderr);
    int fd = TLinkEventAcquireFileLock(NO,NO); assert(fd >= 0);
    NSMutableArray *pending = [NSMutableArray array];
    for (unsigned n = 0; n < 8; ++n) [pending addObject:TLinkEventChannelBeginPoll(body(latest),nil,^(TLinkEventPollRequest *,NSDictionary *,NSString *) { late.fetch_add(1); })];
    dispatch_sync(TLinkEventOwnerQueue(), ^{}); assert(sTLinkEventActivePolls == 8);
    __block NSDictionary *busy = nil;
    TLinkEventChannelBeginPoll(body(latest),nil,^(TLinkEventPollRequest *,NSDictionary *value,NSString *) { busy = value; dispatch_semaphore_signal(delivered); });
    assert(dispatch_semaphore_wait(delivered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0 && [busy[@"state"] isEqual:@"busy"]);
    for (TLinkEventPollRequest *pollRequest in pending) [pollRequest cancel]; assert(sTLinkEventActivePolls == 0);
    request = TLinkEventChannelBeginPoll(body(latest),nil,^(TLinkEventPollRequest *,NSDictionary *,NSString *) { late.fetch_add(1); });
    assert(sTLinkEventActivePolls == 1); [request cancel]; TLinkEventReleaseFileLock(fd);
    dispatch_sync(TLinkEventOwnerQueue(), ^{}); assert(late == 0 && sTLinkEventActivePolls == 0);
    fputs("Event runtime: cancellation during blocked authorization and fresh admission\n",stderr);
    dispatch_semaphore_t entered = dispatch_semaphore_create(0), release = dispatch_semaphore_create(0);
    request = TLinkEventChannelBeginPoll(body(latest),^NSString *{
        dispatch_semaphore_signal(entered); assert(dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0); return nil;
    },^(TLinkEventPollRequest *,NSDictionary *,NSString *) { late.fetch_add(1); });
    assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0); [request cancel]; assert(sTLinkEventActivePolls == 0);
    batch = poll(latest); assert([batch[@"timed_out"] boolValue]);
    dispatch_semaphore_signal(release); waitFor([] { return sTLinkEventAuthorizations == 0; });
    dispatch_sync(TLinkEventOwnerQueue(), ^{}); assert(late == 0);
    // Released poll slots cannot spawn unbounded authorization workers during disconnect churn.
    pending = [NSMutableArray array];
    for (unsigned n = 0; n < 8; ++n) [pending addObject:TLinkEventChannelBeginPoll(body(latest),^NSString *{
        dispatch_semaphore_signal(entered); assert(dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)) == 0); return nil;
    },^(TLinkEventPollRequest *,NSDictionary *,NSString *) { late.fetch_add(1); })];
    for (unsigned n = 0; n < 8; ++n) assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0);
    for (TLinkEventPollRequest *entry in pending) [entry cancel]; assert(sTLinkEventActivePolls == 0 && sTLinkEventAuthorizations == 8);
    TLinkEventChannelBeginPoll(body(latest),^NSString *{ assert(false); return nil; },^(TLinkEventPollRequest *,NSDictionary *value,NSString *reason) {
        assert(!reason && [value[@"state"] isEqual:@"busy"]); dispatch_semaphore_signal(delivered);
    });
    assert(dispatch_semaphore_wait(delivered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0);
    for (unsigned n = 0; n < 8; ++n) dispatch_semaphore_signal(release);
    waitFor([] { return sTLinkEventAuthorizations == 0; }); dispatch_sync(TLinkEventOwnerQueue(), ^{}); assert(late == 0);
    // Timer disarms without idle metadata or journal work.
    uint64_t metadata = sTLinkEventMetadataChecks.load(); reads = sTLinkEventJournalReads.load();
    std::this_thread::sleep_for(std::chrono::milliseconds(1200)); assert(metadata == sTLinkEventMetadataChecks && reads == sTLinkEventJournalReads);
    uint64_t started = TLinkEventMonotonicMs();
    batch = TLinkEventChannelPollBody(body(latest,80),NULL);
    assert([batch[@"timed_out"] boolValue] && TLinkEventMonotonicMs() - started >= 80 && TLinkEventMonotonicMs() - started < 3000);
    // Publication immediately after registration cannot be lost before the initial read.
    for (unsigned n = 0; n < 30; ++n) {
        TLinkEventChannelBeginPoll(body(latest),nil,^(TLinkEventPollRequest *,NSDictionary *value,NSString *reason) {
            assert(!reason && [value[@"events"] count] == 1); received = value; dispatch_semaphore_signal(delivered);
        });
        latest = publish();
        assert(dispatch_semaphore_wait(delivered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0);
        assert([received[@"next_cursor"] unsignedLongLongValue] == latest);
    }
    fputs("Event runtime: actual root legacy/JSON, TrollStore and remote task-95 adapters\n",stderr);
    wireWrites = [NSMutableArray array]; ZXClientContext *root = [ZXClientContext new]; root.writeStream = (CFWriteStreamRef)(uintptr_t)1;
    dispatch_sync(socketQueue(), ^{ zx_deferLegacyEventPoll(root,body(latest,0)); });
    waitFor([] { __block BOOL done; dispatch_sync(socketQueue(), ^{ done = wireWrites.count == 1; }); return (bool)done; });
    dispatch_sync(socketQueue(), ^{ assert([decodeLegacy(wireWrites.lastObject)[@"timed_out"] boolValue]); [wireWrites removeAllObjects]; zx_deferLegacyEventPoll(root,body(latest)); [root.eventPollRequest cancel]; root.eventPollRequest = nil; root.eventPollPending = NO; zx_deferJSONEventPoll(root,body(latest,0),@42); });
    waitFor([] { __block BOOL done; dispatch_sync(socketQueue(), ^{ done = wireWrites.count == 1; }); return (bool)done; });
    dispatch_sync(socketQueue(), ^{
        NSData *wire = wireWrites.lastObject; assert(wire.length > 10);
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:[wire subdataWithRange:NSMakeRange(10,wire.length-10)] options:0 error:NULL];
        assert([object[@"id"] isEqual:@42] && [object[@"ok"] boolValue]);
        [wireWrites removeAllObjects]; zx_deferLegacyEventPoll(root,body(latest));
        [root.eventPollRequest cancel]; root.eventPollRequest = nil; root.writeStream = NULL; root.eventPollPending = NO;
    });
    POCClientContext *troll = [POCClientContext new]; troll.writeStream = (CFWriteStreamRef)(uintptr_t)2;
    dispatch_sync(socketQueue(), ^{ POCDeferEventPoll(troll,body(latest,0)); });
    waitFor([] { __block BOOL done; dispatch_sync(socketQueue(), ^{ done = wireWrites.count == 1; }); return (bool)done; });
    dispatch_sync(socketQueue(), ^{ assert([decodeLegacy(wireWrites.lastObject)[@"timed_out"] boolValue]); [wireWrites removeAllObjects]; });
    allowed = false; dispatch_sync(socketQueue(), ^{ POCDeferEventPoll(troll,body(latest,0)); });
    waitFor([] { __block BOOL done; dispatch_sync(socketQueue(), ^{ done = wireWrites.count == 1; }); return (bool)done; });
    dispatch_sync(socketQueue(), ^{ assert([[[NSString alloc] initWithData:wireWrites.lastObject encoding:NSUTF8StringEncoding] hasPrefix:@"-1;;license_required"]); [wireWrites removeAllObjects]; }); allowed = true;
    NSData *remoteLine = [[@"95;;" stringByAppendingFormat:@"%@\r\n",body(latest,0)] dataUsingEncoding:NSUTF8StringEncoding];
    TLinkBeginRemoteEventPoll(remoteLine,^(TLinkEventPollRequest *,NSData *response) { assert([decodeLegacy(response)[@"timed_out"] boolValue]); dispatch_semaphore_signal(delivered); });
    assert(dispatch_semaphore_wait(delivered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0);
    assert(sTLinkEventActivePolls == 0);
    // Retention/gap remains authoritative after rollover.
    for (unsigned n = 0; n < 260; ++n) publish(); batch = poll(1); assert([batch[@"gap"] boolValue] && [batch[@"events"] count] == 8);
    waitFor([] { return sTLinkEventAuthorizations == 0; });
    dispatch_sync(TLinkEventOwnerQueue(), ^{ assert(!sTLinkEventWaiters.count); dispatch_source_cancel(sTLinkEventTimer); notify_cancel(sTLinkEventNotifyToken); });
    puts("Event Foundation passed: real journal/locks, cross-process and missed notifications, quiet/idle I/O, eight cancellations, blocked authorization, deadlines, pagination/gap and root/TrollStore/remote wire adapters.");
} }
