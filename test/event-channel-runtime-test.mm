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
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include <set>
#include <stdexcept>
#include "../shared/TLinkEventChannel.h"
#include <notify.h>
extern char **environ;
static bool suppressNotify = false;
static std::atomic<bool> ignoreNotifications{false};
static uint32_t FixtureRegisterNotification(const char *name, int *token, dispatch_queue_t queue, void (^handler)(int)) {
    uint32_t result = notify_register_dispatch(name,token,queue,^(int value) { if (!ignoreNotifications.load()) handler(value); });
    assert(result == NOTIFY_STATUS_OK); return result;
}
static std::atomic<unsigned> fixturePosts{0},fixtureWrites{0},fixturePublishReads{0};
static std::atomic<unsigned> fixtureCStringConversions{0},fixtureLegacyParses{0},fixtureBatchEncodes{0};
static std::atomic<unsigned> fixtureSuccessStringConversions{0};
static NSData *fixtureBatchJSONOverride;
static unsigned fixtureBatchEncodeFault=0;
static NSDictionary *fixtureSyncBatch;
static NSString *fixtureSyncError;
static unsigned fixtureSyncPolls=0;
static std::atomic<unsigned> fixtureReadFault{0},fixtureWriteFault{0};
static std::atomic<bool> fixtureReaderLockDenied{false};
static thread_local std::set<int> fixtureEventLocks;
static thread_local std::set<int> fixtureEventFds;
static std::atomic<unsigned> fixtureLiveEventFds{0},fixtureLockPermissions{0};
static bool fixtureLockStatFault=false;
static NSString *fixtureEventRootOverride;
static std::function<void()> fixtureAfterLock;
static int FixtureEventOpen(const char *path,int flags,mode_t mode) {
    assert(flags==(O_CREAT|O_RDWR|O_NOFOLLOW|O_NONBLOCK)&&mode==0640);
    const int fd=::open(path,flags,mode);if(fd>=0){assert(fixtureEventFds.insert(fd).second);++fixtureLiveEventFds;}return fd;
}
static int FixtureEventLockStat(int fd,struct stat *info) {
    assert(fixtureEventFds.count(fd));if(fixtureLockStatFault){errno=EIO;return -1;}return ::fstat(fd,info);
}
static int FixtureEventFchmod(int fd,mode_t mode) {assert(fixtureEventLocks.count(fd)&&mode==0640);++fixtureLockPermissions;return ::fchmod(fd,mode);}
static int FixtureEventFchown(int fd,uid_t uid,gid_t gid) {assert(fixtureEventLocks.count(fd)&&uid==501&&gid==501);++fixtureLockPermissions;return ::fchown(fd,uid,gid);}

static uint32_t FixtureNotifyPost(const char *name) { assert(fixtureEventLocks.empty());++fixturePosts;return suppressNotify ? 0 : notify_post(name); }
static int FixtureEventFlock(int fd,int operation) {
    if((operation&LOCK_SH)&&fixtureReaderLockDenied.load()){errno=EWOULDBLOCK;return -1;}
    const int result=::flock(fd,operation);
    if(!result){if(operation==LOCK_UN)assert(fixtureEventLocks.erase(fd)==1);else{assert(fixtureEventLocks.insert(fd).second);if(fixtureAfterLock)fixtureAfterLock();}}
    return result;
}
static thread_local std::set<int> fixtureJournalFds;
static std::atomic<unsigned> fixtureLiveJournalFds{0},fixtureJournalOpens{0},fixtureJournalReads{0},fixtureJournalAllocations{0};
static std::atomic<uint64_t> fixtureJournalBytes{0};
static std::atomic<unsigned> fixtureJournalOpenFault{0},fixtureJournalStatFault{0},fixtureJournalReadFault{0};
static int FixtureEventClose(int fd) {
    assert(!fixtureEventLocks.count(fd));
    if(fixtureJournalFds.erase(fd))--fixtureLiveJournalFds;
    else{assert(fixtureEventFds.erase(fd)==1);--fixtureLiveEventFds;}
    return ::close(fd);
}
static int FixtureJournalOpen(const char *path,int flags) {
    assert(fixtureEventLocks.size()==1&&flags==(O_RDONLY|O_NOFOLLOW|O_NONBLOCK));++fixtureJournalOpens;
    if(fixtureJournalOpenFault){errno=fixtureJournalOpenFault==1?EACCES:EMFILE;return -1;}
    const int fd=::open(path,flags);if(fd>=0){assert(fixtureJournalFds.insert(fd).second);++fixtureLiveJournalFds;}return fd;
}
static int FixtureJournalStat(int fd,struct stat *info) {
    assert(fixtureJournalFds.count(fd));if(fixtureJournalStatFault==1){errno=EIO;return -1;}
    const int result=::fstat(fd,info);
    if(!result&&fixtureJournalStatFault==2)info->st_size=4*1024*1024+1;
    if(!result&&fixtureJournalStatFault==3)info->st_size=-1;return result;
}
static NSMutableData *FixtureJournalBuffer(NSUInteger length,NSUInteger limit) {
    assert(length<=limit);++fixtureJournalAllocations;return [NSMutableData dataWithLength:length];
}
static ssize_t FixtureJournalRead(int fd,void *bytes,size_t count) {
    assert(fixtureJournalFds.count(fd)&&count>0&&count<=65536);++fixtureJournalReads;
    if(fixtureJournalReadFault==1){fixtureJournalReadFault=6;errno=EINTR;return -1;}
    if(fixtureJournalReadFault==2){errno=EIO;return -1;}
    if(fixtureJournalReadFault==3)return 0;
    if(fixtureJournalReadFault==4)[NSException raise:@"EventFixture" format:@"journal read failed"];
    if(fixtureJournalReadFault==5)throw std::runtime_error("journal read failed");
    if(fixtureJournalReadFault==7&&count==1){*(uint8_t *)bytes=0;++fixtureJournalBytes;return 1;}
    const ssize_t got=::read(fd,bytes,fixtureJournalReadFault==6?MIN(count,(size_t)17):count);
    if(got>0)fixtureJournalBytes+=(uint64_t)got;return got;
}
static NSData *TLinkEventReadJournalData(BOOL *missing,NSString **error);
static NSData *FixtureEventReadData(BOOL *missing,NSString **error) {
    assert(fixtureEventLocks.size()==1);++fixturePublishReads;
    if(fixtureReadFault==4)[NSException raise:@"EventFixture" format:@"read failed"];
    if(fixtureReadFault==5)throw std::runtime_error("read failed");
    if(fixtureReadFault){*error=@"event_journal_read_failed";return nil;}
    return TLinkEventReadJournalData(missing,error);
}
static BOOL FixtureEventWrite(NSData *data,NSString *path) {
    assert(fixtureEventLocks.size()==1);++fixtureWrites;
    if(fixtureWriteFault==1)return NO;
    if(fixtureWriteFault==2)[NSException raise:@"EventFixture" format:@"write failed"];
    if(fixtureWriteFault==3)throw std::runtime_error("write failed");
    const BOOL result=[data writeToFile:path atomically:YES];
    if(fixtureWriteFault==4)return NO;
    if(fixtureWriteFault==5)[NSException raise:@"EventFixture" format:@"post-write failed"];
    if(fixtureWriteFault==6)throw std::runtime_error("post-write failed");return result;
}
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
static NSData *zx_dataFromCString(const char *s) { ++fixtureCStringConversions;return [NSData dataWithBytes:s length:strlen(s)]; }
static NSData *TLinkSuccess(NSString *text) { ++fixtureSuccessStringConversions;return [[NSString stringWithFormat:@"0;;%@\r\n",text] dataUsingEncoding:NSUTF8StringEncoding]; }
static NSData *TLinkError(NSString *text) { return [[NSString stringWithFormat:@"-1;;%@\r\n",text] dataUsingEncoding:NSUTF8StringEncoding]; }
static std::atomic<bool> allowed{true};
static std::atomic<unsigned> late{0};
static BOOL TLinkRootfullLicenseTaskAllowed(int task, NSString **denial) { assert(task == 95); if (!allowed && denial) *denial = @"-1;;license_required\r\n"; return allowed.load(); }
static BOOL TLinkLicenseFeatureAllowed(NSString *feature, NSString **error) { assert([feature isEqual:@"automation"]); if (!allowed && error) *error = @"license_required"; return allowed.load(); }
static NSData *TLinkLicenseDeniedResponse(int, NSString *, NSString *error) { return TLinkError(error); }
static const NSUInteger kMaxBuffer = 65536;
#include "EventConstantsUnderTest.inc"
#include "EventJSONUnderTest.inc"
static NSDictionary *FixtureEventLegacyJSON(NSData *legacy,NSNumber *requestId) {
    ++fixtureLegacyParses;return zx_jsonResponseFromLegacy(legacy,requestId);
}
static NSData *FixtureEventBatchJSON(NSDictionary *batch) {
    ++fixtureBatchEncodes;
    if(fixtureBatchEncodeFault==1)return nil;
    if(fixtureBatchEncodeFault==2)return [NSData data];
    if(fixtureBatchEncodeFault==3)[NSException raise:@"EventFixture" format:@"batch encode failed"];
    if(fixtureBatchEncodeFault==4)throw std::runtime_error("batch encode failed");
    return fixtureBatchJSONOverride ?: [NSJSONSerialization dataWithJSONObject:batch options:0 error:nil];
}
#include "EventLegacyBatchUnderTest.inc"
#include "EventLegacyTrollBatchUnderTest.inc"
#include "EventWireUnderTest.inc"
static NSDictionary *FixtureEventSyncPoll(NSString *body,NSString **error) {
    assert([body isEqual:@"fixture"]);++fixtureSyncPolls;*error=fixtureSyncError;return fixtureSyncBatch;
}
#include "EventSyncUnderTest.inc"
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
static NSData *fixtureJournalData(NSDictionary *journal) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:journal options:0 error:nil];assert(data);return data;
}
static NSDictionary *fixtureStoredEvent(uint64_t sequence) {
    return @{@"schema":TLinkEventSchemaV1,@"sequence":@(sequence),@"timestamp_ms":@0,@"event_id":@"existing-event",
        @"runtime":@"fixture",@"topic":@"script.run",@"type":@"updated",@"payload":@{@"kept":@(YES)}};
}
static NSDictionary *fixtureJournal(uint64_t next,NSArray *events) {
    return @{@"schema":TLinkEventChannelSchemaV1,@"next_sequence":@(next),@"events":events,@"extra":@{@"kept":@"ảnh 测试"}};
}
static void fixtureOtherOwnerCanLock() {
    const char *path=TLinkEventLockPath().fileSystemRepresentation;int descriptors[2];assert(::pipe(descriptors)==0);
    const pid_t child=::fork();assert(child>=0);
    if(!child){
        ::close(descriptors[0]);const int fd=::open(path,O_RDWR);int result=fd>=0?::flock(fd,LOCK_EX|LOCK_NB):-1;
        const char ok=result==0?'Y':'N';if(!result)::flock(fd,LOCK_UN);if(fd>=0)::close(fd);
        if(::write(descriptors[1],&ok,1)!=1)::_exit(2);::close(descriptors[1]);::_exit(0);
    }
    ::close(descriptors[1]);char ok=0;assert(::read(descriptors[0],&ok,1)==1&&ok=='Y');::close(descriptors[0]);
    int status=0;assert(::waitpid(child,&status,0)==child&&WIFEXITED(status)&&WEXITSTATUS(status)==0);
}
static void fixtureRejectedPublication(NSString *code,NSData *expected,unsigned attemptedWrites=0) {
    const unsigned posts=fixturePosts.load(),writes=fixtureWrites.load(),reads=fixturePublishReads.load();
    NSDictionary *reply=TLinkEventChannelPublish(@"fixture",@"script.run",@"updated",@{@"new":@1});
    assert([reply[@"state"] isEqual:@"error"]&&[reply[@"error"] isEqual:code]&&reply.count==2);
    assert(fixturePosts==posts&&fixtureWrites==writes+attemptedWrites&&fixturePublishReads==reads+1&&fixtureEventLocks.empty());
    if(expected)assert([expected isEqual:[NSData dataWithContentsOfFile:TLinkEventJournalPath()]]);
    fixtureOtherOwnerCanLock();
}
static void fixtureCheckedPublicationCases() {
    // Run before the async owner exists; all files are under the runner's private temporary root.
    TLinkEventEnsureDirectory();NSString *path=TLinkEventJournalPath();NSFileManager *fm=[NSFileManager defaultManager];
    NSDictionary *first=fixtureStoredEvent(7),*second=fixtureStoredEvent(8),*healthy=fixtureJournal(9,@[first,second]);
    NSData *bytes=fixtureJournalData(healthy);
    assert(![fm fileExistsAtPath:path]);const unsigned initial=fixturePosts.load();assert(publish()==1&&fixturePosts==initial+1);
    assert([bytes writeToFile:path atomically:YES]);NSDictionary *appended=TLinkEventChannelPublish(@"Fixture",@"Script.Run",@"Updated",@{@"new":@1});
    assert([appended[@"sequence"] unsignedLongLongValue]==9&&[appended[@"runtime"] isEqual:@"fixture"]&&[appended[@"topic"] isEqual:@"script.run"]);
    NSDictionary *stored=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];
    assert([stored[@"next_sequence"] unsignedLongLongValue]==10&&[stored[@"events"][0] isEqual:first]&&[stored[@"events"][1] isEqual:second]&&[stored[@"extra"] isEqual:healthy[@"extra"]]);
    NSMutableArray *bad=[NSMutableArray arrayWithArray:@[@{},@{@"schema":TLinkEventChannelSchemaV1},@{@"schema":@"other",@"next_sequence":@9,@"events":@[]}]];
    for(id value in @[@0,@(-1),@1.5,@(YES),@"9",[NSNull null]]){NSMutableDictionary *item=[healthy mutableCopy];item[@"next_sequence"]=value;[bad addObject:item];}
    for(id value in @[@1,[NSNull null],@{},@[@1]]){NSMutableDictionary *item=[healthy mutableCopy];item[@"events"]=value;[bad addObject:item];}
    for(id value in @[@0,@(-1),@7.5,@(YES),@"7",[NSNull null],@9,@6]){
        NSMutableDictionary *event=[first mutableCopy];event[@"sequence"]=value;[bad addObject:fixtureJournal(9,@[event,second])];
    }
    [bad addObject:fixtureJournal(9,@[second,first])];[bad addObject:fixtureJournal(9,@[first,first])];
    [bad addObject:fixtureJournal(10,@[first,second])]; // latest retained does not precede next
    for(NSString *key in @[@"schema",@"event_id",@"runtime",@"topic",@"type",@"payload",@"timestamp_ms"]){
        for(id value in @[[NSNull null],@""]){NSMutableDictionary *event=[first mutableCopy];event[key]=value;[bad addObject:fixtureJournal(9,@[event,second])];}
    }
    NSMutableArray *over=[NSMutableArray array];for(unsigned n=1;n<=257;++n)[over addObject:fixtureStoredEvent(n)];[bad addObject:fixtureJournal(258,over)];
    for(NSDictionary *item in bad){NSData *invalid=fixtureJournalData(item);assert([invalid writeToFile:path atomically:YES]);fixtureRejectedPublication(@"event_journal_invalid",invalid);}
    for(NSString *text in @[@"",@"not-json",@"[]",@"null",@"{\"schema\":"]){NSData *invalid=[text dataUsingEncoding:NSUTF8StringEncoding];assert([invalid writeToFile:path atomically:YES]);fixtureRejectedPublication(@"event_journal_invalid",invalid);}
    // An unsigned out-of-range JSON number must not wrap into a reused cursor.
    NSData *overflow=[@"{\"schema\":\"event_channel_v1\",\"next_sequence\":18446744073709551616,\"events\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
    assert([overflow writeToFile:path atomically:YES]);fixtureRejectedPublication(@"event_journal_invalid",overflow);
    assert([bytes writeToFile:path atomically:YES]);
    for(unsigned fault=1;fault<=5;++fault){fixtureReadFault=fault;fixtureRejectedPublication(fault<4?@"event_journal_read_failed":@"event_journal_exception",bytes);fixtureReadFault=0;}
    assert([fm removeItemAtPath:path error:nil]&&[fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
    fixtureRejectedPublication(@"event_journal_read_failed",nil);BOOL directory=NO;assert([fm fileExistsAtPath:path isDirectory:&directory]&&directory);
    assert([fm removeItemAtPath:path error:nil]);
    // Both ordinary writer failure and exceptions retain no success notification.
    for(unsigned fault=1;fault<=6;++fault){
        assert([bytes writeToFile:path atomically:YES]);const unsigned posts=fixturePosts.load(),writes=fixtureWrites.load();fixtureWriteFault=fault;
        NSDictionary *reply=TLinkEventChannelPublish(@"fixture",@"script.run",@"updated",@{});fixtureWriteFault=0;
        assert([reply[@"error"] isEqual:(fault==1||fault==4)?@"event_journal_write_failed":@"event_journal_exception"]&&fixturePosts==posts&&fixtureWrites==writes+1&&fixtureEventLocks.empty());
        fixtureOtherOwnerCanLock();
        NSDictionary *now=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];
        assert([now[@"next_sequence"] unsignedLongLongValue]==(fault<=3?9:10));
        // Retrying reads the actual disk outcome, not an in-memory cursor or cached reset.
        assert(publish()==(fault<=3?9:10)&&fixturePosts==posts+1);
    }
    // Preserve an explicitly restored empty history's nonzero cursor; max is terminal, not a rollover.
    assert([fixtureJournalData(fixtureJournal(500,@[])) writeToFile:path atomically:YES]&&publish()==500);
    assert([fixtureJournalData(fixtureJournal(UINT64_MAX-1,@[])) writeToFile:path atomically:YES]);
    assert(publish()==UINT64_MAX-1);NSData *terminal=[NSData dataWithContentsOfFile:path];fixtureRejectedPublication(@"event_journal_sequence_exhausted",terminal);
    // Explicit repair permits publishing again, without replaying any failed publication.
    assert([bytes writeToFile:path atomically:YES]&&publish()==9);
    assert([fm removeItemAtPath:path error:nil]); // Original B06 cases start at the genuine missing-file bootstrap.
    assert(fixtureEventLocks.empty());
    puts("Event publication passed: missing-only bootstrap, retained sequence/schema/shape authority, malformed/read/NS/C++ preservation, UINT64 exhaustion, writer pre/post-effect failures, no false notification, real lock release and explicit repair. Read-only corruption/epoch/power-loss recovery remains pending.");
}
static void fixtureReadFailure(uint64_t cursor,NSString *code,NSData *expected) {
    const unsigned writes=fixtureWrites.load(),posts=fixturePosts.load();
    NSDictionary *status=TLinkEventChannelStatus();
    assert([status[@"state"] isEqual:@"error"]&&[status[@"error"] isEqual:code]&&[status[@"transport"] isEqual:@"task95_long_poll_v1"]);
    NSString *error=nil;NSDictionary *batch=TLinkEventChannelPollBody(body(cursor,0),&error);
    assert([error isEqual:code]&&!batch.count&&sTLinkEventActivePolls==0);
    dispatch_sync(TLinkEventOwnerQueue(),^{assert(fixtureEventLocks.empty()&&!sTLinkEventSnapshot&&!sTLinkEventWaiters.count);});
    assert(fixtureEventLocks.empty()&&fixtureWrites==writes&&fixturePosts==posts&&[expected isEqual:[NSData dataWithContentsOfFile:TLinkEventJournalPath()]]);
    fixtureOtherOwnerCanLock();
}
static void fixtureCheckedReadCases(uint64_t cursor) {
    const bool savedNotify=suppressNotify;suppressNotify=true; // Use owner barriers/gates, without leaving late hints for B06 quiet-read checks.
    NSString *path=TLinkEventJournalPath();NSData *healthy=[NSData dataWithContentsOfFile:path];assert(healthy);
    NSData *invalid=[@"not-json" dataUsingEncoding:NSUTF8StringEncoding];
    // Missing is a genuine empty bootstrap, not an error, and read-only calls never create journal JSON.
    const unsigned initialWrites=fixtureWrites.load(),initialPosts=fixturePosts.load();
    assert([[NSFileManager defaultManager] removeItemAtPath:path error:nil]);
    assert([TLinkEventChannelStatus()[@"state"] isEqual:@"implemented"]);
    NSString *bootstrapError=nil;NSDictionary *bootstrap=TLinkEventChannelPollBody(body(0,0),&bootstrapError);
    assert(!bootstrapError&&[bootstrap[@"state"] isEqual:@"ready"]&&[bootstrap[@"next_cursor"] unsignedLongLongValue]==0);
    assert(![[NSFileManager defaultManager] fileExistsAtPath:path]&&fixtureWrites==initialWrites&&fixturePosts==initialPosts);
    // Publication exhaustion does not prohibit reading the last valid cursor.
    assert([fixtureJournalData(fixtureJournal(UINT64_MAX,@[])) writeToFile:path atomically:YES]);
    NSDictionary *terminal=TLinkEventChannelPollBody(body(UINT64_MAX-1,0),&bootstrapError);
    assert(!bootstrapError&&[terminal[@"state"] isEqual:@"ready"]&&[terminal[@"latest_cursor"] unsignedLongLongValue]==UINT64_MAX-1);
    assert([healthy writeToFile:path atomically:YES]);
    NSArray *malformed=@[@{},@{@"schema":TLinkEventChannelSchemaV1,@"next_sequence":@1,@"events":@[@1]},
        fixtureJournal(0,@[]),fixtureJournal(3,@[fixtureStoredEvent(1)]),fixtureJournal(4,@[fixtureStoredEvent(2),fixtureStoredEvent(1)])];
    for(NSDictionary *journal in malformed){NSData *bad=fixtureJournalData(journal);assert([bad writeToFile:path atomically:YES]);fixtureReadFailure(cursor,@"event_journal_invalid",bad);}
    assert([invalid writeToFile:path atomically:YES]);fixtureReadFailure(cursor,@"event_journal_invalid",invalid);
    assert([healthy writeToFile:path atomically:YES]);
    for(unsigned fault=1;fault<=5;++fault){fixtureReadFault=fault;fixtureReadFailure(cursor,fault<4?@"event_journal_read_failed":@"event_journal_exception",healthy);fixtureReadFault=0;}
    fixtureReaderLockDenied=true;fixtureReadFailure(cursor,@"event_journal_unavailable",healthy);fixtureReaderLockDenied=false;
    // Authorization denial precedes journal access, including while storage is corrupt.
    assert([invalid writeToFile:path atomically:YES]);const unsigned reads=fixturePublishReads.load();
    dispatch_semaphore_t denied=dispatch_semaphore_create(0);
    TLinkEventChannelBeginPoll(body(cursor,0),^NSString *{return @"fixture_denied";},^(TLinkEventPollRequest *,NSDictionary *value,NSString *reason){
        assert(!value&&[reason isEqual:@"fixture_denied"]);dispatch_semaphore_signal(denied);
    });
    assert(dispatch_semaphore_wait(denied,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0&&fixturePublishReads==reads&&sTLinkEventActivePolls==0);
    assert([healthy writeToFile:path atomically:YES]);
    // Keep an unauthorized waiter so Rearm cannot hide missing cache invalidation when the ready poll leaves.
    for(bool hard:{true,false}){
        dispatch_semaphore_t entered=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0),readyDone=dispatch_semaphore_create(0),authDone=dispatch_semaphore_create(0);
        __block unsigned readyCalls=0;__block NSDictionary *recovered=nil;
        TLinkEventPollRequest *auth=TLinkEventChannelBeginPoll(body(cursor),^NSString *{
            dispatch_semaphore_signal(entered);assert(dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);return nil;
        },^(TLinkEventPollRequest *,NSDictionary *value,NSString *reason){assert(!reason&&[value[@"events"] count]==1);recovered=value;dispatch_semaphore_signal(authDone);});
        assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        TLinkEventPollRequest *ready=TLinkEventChannelBeginPoll(body(cursor),nil,^(TLinkEventPollRequest *,NSDictionary *value,NSString *reason){
            ++readyCalls;assert(hard&&!value&&[reason isEqual:@"event_journal_invalid"]);dispatch_semaphore_signal(readyDone);
        });
        dispatch_sync(TLinkEventOwnerQueue(),^{assert(sTLinkEventSnapshot&&sTLinkEventWaiters.count==2);});
        if(hard)assert([invalid writeToFile:path atomically:YES]);else fixtureReaderLockDenied=true;
        dispatch_sync(TLinkEventOwnerQueue(),^{TLinkEventSweep(YES);assert(!sTLinkEventSnapshot&&!sTLinkEventFingerprint);});
        if(hard){assert(dispatch_semaphore_wait(readyDone,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0&&readyCalls==1);}
        else{assert(!readyCalls&&sTLinkEventActivePolls==2);[ready cancel];}
        dispatch_sync(TLinkEventOwnerQueue(),^{assert(sTLinkEventWaiters.count==1&&!sTLinkEventSnapshot);});
        fixtureReaderLockDenied=false;assert([healthy writeToFile:path atomically:YES]);
        const uint64_t sequence=publish();assert(sequence==cursor+1);dispatch_semaphore_signal(release);
        assert(dispatch_semaphore_wait(authDone,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0&&[recovered[@"next_cursor"] unsignedLongLongValue]==sequence&&!auth.isCancelled);
        dispatch_sync(TLinkEventOwnerQueue(),^{assert(!sTLinkEventWaiters.count&&!sTLinkEventSnapshot);});
        assert(sTLinkEventActivePolls==0&&sTLinkEventAuthorizations==0&&[healthy writeToFile:path atomically:YES]);
    }
    // Real lock contention retains the timeout/unavailable policy, without serving an old snapshot.
    const int writer=TLinkEventAcquireFileLock(NO,NO);assert(writer>=0);NSString *error=nil;uint64_t started=TLinkEventMonotonicMs();
    NSDictionary *batch=TLinkEventChannelPollBody(body(cursor,60),&error);TLinkEventReleaseFileLock(writer);
    assert([error isEqual:@"event_journal_unavailable"]&&!batch.count&&TLinkEventMonotonicMs()-started>=60&&sTLinkEventActivePolls==0);
    // Corruption errors flow through existing legacy/JSON/TrollStore/remote encoders with no ready batch.
    assert([invalid writeToFile:path atomically:YES]);wireWrites=[NSMutableArray array];
    ZXClientContext *root=[ZXClientContext new];root.writeStream=(CFWriteStreamRef)(uintptr_t)1;
    dispatch_sync(socketQueue(),^{zx_deferLegacyEventPoll(root,body(cursor,0));});
    waitFor([]{__block BOOL done;dispatch_sync(socketQueue(),^{done=wireWrites.count==1;});return (bool)done;});
    dispatch_sync(socketQueue(),^{
        NSString *line=[[NSString alloc] initWithData:wireWrites[0] encoding:NSUTF8StringEncoding];assert([line isEqual:@"-1;;event_journal_invalid\r\n"]);
        [wireWrites removeAllObjects];zx_deferJSONEventPoll(root,body(cursor,0),@42);
    });
    waitFor([]{__block BOOL done;dispatch_sync(socketQueue(),^{done=wireWrites.count==1;});return (bool)done;});
    dispatch_sync(socketQueue(),^{
        NSData *wire=wireWrites[0];assert(wire.length>10);
        NSDictionary *value=[NSJSONSerialization JSONObjectWithData:[wire subdataWithRange:NSMakeRange(10,wire.length-10)] options:0 error:nil];
        assert([value[@"id"] isEqual:@42]&&![value[@"ok"] boolValue]&&[value[@"error"] isEqual:@"event_journal_invalid"]);[wireWrites removeAllObjects];
    });
    POCClientContext *troll=[POCClientContext new];troll.writeStream=(CFWriteStreamRef)(uintptr_t)2;
    dispatch_sync(socketQueue(),^{POCDeferEventPoll(troll,body(cursor,0));});
    waitFor([]{__block BOOL done;dispatch_sync(socketQueue(),^{done=wireWrites.count==1;});return (bool)done;});
    dispatch_sync(socketQueue(),^{NSString *line=[[NSString alloc] initWithData:wireWrites[0] encoding:NSUTF8StringEncoding];assert([line isEqual:@"-1;;event_journal_invalid\r\n"]);[wireWrites removeAllObjects];});
    dispatch_semaphore_t remoteDone=dispatch_semaphore_create(0);
    NSData *remoteLine=[[@"95;;" stringByAppendingFormat:@"%@\r\n",body(cursor,0)] dataUsingEncoding:NSUTF8StringEncoding];
    TLinkBeginRemoteEventPoll(remoteLine,^(TLinkEventPollRequest *,NSData *response){
        NSString *line=[[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];assert([line isEqual:@"-1;;event_journal_invalid\r\n"]);dispatch_semaphore_signal(remoteDone);
    });
    assert(dispatch_semaphore_wait(remoteDone,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0&&[invalid isEqual:[NSData dataWithContentsOfFile:path]]);
    assert([healthy writeToFile:path atomically:YES]);error=nil;batch=TLinkEventChannelPollBody(body(cursor,0),&error);
    assert(!error&&[batch[@"state"] isEqual:@"ready"]&&[batch[@"next_cursor"] unsignedLongLongValue]==cursor&&[TLinkEventChannelStatus()[@"state"] isEqual:@"implemented"]);
    dispatch_sync(TLinkEventOwnerQueue(),^{assert(!sTLinkEventWaiters.count&&!sTLinkEventSnapshot);});fixtureOtherOwnerCanLock();
    assert(sTLinkEventActivePolls==0&&sTLinkEventAuthorizations==0);suppressNotify=savedNotify;
    puts("Event checked reads passed: status/poll malformed/read/NS/C++ errors, no reset or stale-cache delivery, cache invalidation with held authorization, transient contention/cancel/recovery, unchanged error wire adapters and balanced leases/locks. Missing-file epoch recovery pending.");
}
static void fixtureLockRejected(NSData *healthy,NSString *journalPath) {
    const unsigned reads=fixturePublishReads.load(),writes=fixtureWrites.load(),posts=fixturePosts.load(),permissions=fixtureLockPermissions.load();
    NSDictionary *reply=TLinkEventChannelPublish(@"fixture",@"script.run",@"updated",@{});
    assert([reply[@"state"] isEqual:@"error"]&&[reply[@"error"] isEqual:@"event_journal_lock_failed"]);
    NSDictionary *status=TLinkEventChannelStatus();assert([status[@"state"] isEqual:@"error"]&&[status[@"error"] isEqual:@"event_journal_unavailable"]);
    NSString *fingerprint=@"stale",*error=nil;
    assert(!TLinkEventLoadSnapshot(YES,&fingerprint,&error)&&!fingerprint&&[error isEqual:@"event_journal_unavailable"]);
    assert(fixturePublishReads==reads&&fixtureWrites==writes&&fixturePosts==posts&&fixtureLockPermissions==permissions);
    assert(!fixtureLiveEventFds&&fixtureEventLocks.empty()&&fixtureEventFds.empty()&&[healthy isEqual:[NSData dataWithContentsOfFile:journalPath]]);
}
static void fixtureValidatedLockCases() {
    const bool savedNotify=suppressNotify;suppressNotify=true;
    assert(TLinkEventEnsureDirectory()&&publish()==1);
    NSString *root=TLinkEventChannelRootPath(),*path=TLinkEventLockPath(),*journal=TLinkEventJournalPath();
    NSData *healthy=[NSData dataWithContentsOfFile:journal];NSFileManager *fm=[NSFileManager defaultManager];assert(healthy);
    struct stat original;assert(::lstat(path.fileSystemRepresentation,&original)==0&&S_ISREG(original.st_mode)&&original.st_nlink==1);
    for(bool reader:{false,true})for(bool nonblocking:{false,true}){
        const unsigned permissions=fixtureLockPermissions.load();const int fd=TLinkEventAcquireFileLock(reader,nonblocking);assert(fd>=0);
        struct stat info;assert(::fstat(fd,&info)==0&&info.st_ino==original.st_ino&&info.st_dev==original.st_dev&&fixtureLockPermissions==permissions+2);
        TLinkEventReleaseFileLock(fd);assert(!fixtureLiveEventFds&&fixtureEventFds.empty()&&fixtureEventLocks.empty());
    }
    fixtureLockStatFault=true;fixtureLockRejected(healthy,journal);fixtureLockStatFault=false;
    NSString *stash=[path stringByAppendingString:@".saved"],*alias=[path stringByAppendingString:@".alias"];
    assert(::link(path.fileSystemRepresentation,alias.fileSystemRepresentation)==0);fixtureLockRejected(healthy,journal);assert(::unlink(alias.fileSystemRepresentation)==0);
    assert(::rename(path.fileSystemRepresentation,stash.fileSystemRepresentation)==0);
    NSString *outside=[root stringByAppendingPathComponent:@"outside-lock"];
    NSData *outsideBytes=[@"outside ownership remains" dataUsingEncoding:NSUTF8StringEncoding];assert([outsideBytes writeToFile:outside atomically:YES]&&::chmod(outside.fileSystemRepresentation,0600)==0);
    assert(::symlink(outside.fileSystemRepresentation,path.fileSystemRepresentation)==0);fixtureLockRejected(healthy,journal);
    struct stat outsideInfo;assert(::stat(outside.fileSystemRepresentation,&outsideInfo)==0&&(outsideInfo.st_mode&0777)==0600&&[outsideBytes isEqual:[NSData dataWithContentsOfFile:outside]]);
    assert(::unlink(path.fileSystemRepresentation)==0&&::mkfifo(path.fileSystemRepresentation,0600)==0);fixtureLockRejected(healthy,journal);
    assert(::unlink(path.fileSystemRepresentation)==0&&[fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
    NSString *child=[path stringByAppendingPathComponent:@"keep.txt"];assert([outsideBytes writeToFile:child atomically:YES]);fixtureLockRejected(healthy,journal);
    assert([outsideBytes isEqual:[NSData dataWithContentsOfFile:child]]&&[fm removeItemAtPath:path error:nil]&&::rename(stash.fileSystemRepresentation,path.fileSystemRepresentation)==0);
    // Root refusal happens before create/chmod/lock open, without following a known leaf symlink or file.
    NSString *rootLink=[root stringByAppendingPathComponent:@"root-link"],*rootFile=[root stringByAppendingPathComponent:@"root-file"];
    assert(::symlink(root.fileSystemRepresentation,rootLink.fileSystemRepresentation)==0&&[outsideBytes writeToFile:rootFile atomically:YES]&&::chmod(rootFile.fileSystemRepresentation,0600)==0);
    for(NSString *badRoot in @[rootLink,rootFile]){fixtureEventRootOverride=badRoot;fixtureLockRejected(healthy,journal);fixtureEventRootOverride=nil;}
    assert(::stat(rootFile.fileSystemRepresentation,&outsideInfo)==0&&(outsideInfo.st_mode&0777)==0600&&[outsideBytes isEqual:[NSData dataWithContentsOfFile:rootFile]]);
    assert(::unlink(rootLink.fileSystemRepresentation)==0);
    // Real pathname changes after successful flock must release the old inode without touching replacement permissions.
    for(unsigned mode=0;mode<4;++mode){
        const unsigned permissions=fixtureLockPermissions.load(),reads=fixturePublishReads.load();
        NSString *moved=[root stringByAppendingString:@".moved"];
        fixtureAfterLock=[path,stash,alias,root,moved,mode]{
            if(mode<2){
                assert(::rename(path.fileSystemRepresentation,stash.fileSystemRepresentation)==0);
                if(mode==0){const int replacement=::open(path.fileSystemRepresentation,O_CREAT|O_RDWR,0600);assert(replacement>=0&&::close(replacement)==0);}
            }else if(mode==2)assert(::link(path.fileSystemRepresentation,alias.fileSystemRepresentation)==0);
            else assert(::rename(root.fileSystemRepresentation,moved.fileSystemRepresentation)==0&&::symlink(moved.fileSystemRepresentation,root.fileSystemRepresentation)==0);
        };
        assert(TLinkEventAcquireFileLock(NO,NO)<0);fixtureAfterLock={};
        assert(!fixtureLiveEventFds&&fixtureEventFds.empty()&&fixtureEventLocks.empty()&&fixtureLockPermissions==permissions&&fixturePublishReads==reads);
        if(mode<2){
            const int probe=::open(stash.fileSystemRepresentation,O_RDWR);assert(probe>=0&&::flock(probe,LOCK_EX|LOCK_NB)==0&&::flock(probe,LOCK_UN)==0&&::close(probe)==0);
            if(mode==0){struct stat replacement;assert(::stat(path.fileSystemRepresentation,&replacement)==0&&(replacement.st_mode&0777)==0600&&::unlink(path.fileSystemRepresentation)==0);}
            assert(::rename(stash.fileSystemRepresentation,path.fileSystemRepresentation)==0);
        }else if(mode==2)assert(::unlink(alias.fileSystemRepresentation)==0);
        else assert(::unlink(root.fileSystemRepresentation)==0&&::rename(moved.fileSystemRepresentation,root.fileSystemRepresentation)==0);
        assert([healthy isEqual:[NSData dataWithContentsOfFile:journal]]);fixtureOtherOwnerCanLock();
    }
    struct stat restored;assert(::lstat(path.fileSystemRepresentation,&restored)==0&&restored.st_ino==original.st_ino&&restored.st_dev==original.st_dev);
    assert(publish()==2&&[TLinkEventChannelStatus()[@"state"] isEqual:@"implemented"]&&!fixtureLiveEventFds);
    // A genuinely absent direct root is still created and supports an independent normal journal.
    fixtureEventRootOverride=[root stringByAppendingPathComponent:@"new-root"];assert(publish()==1&&[TLinkEventChannelStatus()[@"state"] isEqual:@"implemented"]);
    NSString *created=fixtureEventRootOverride;fixtureEventRootOverride=nil;assert([fm removeItemAtPath:created error:nil]);
    assert([fm removeItemAtPath:journal error:nil]);suppressNotify=savedNotify;
    assert(fixtureEventLocks.empty()&&fixtureEventFds.empty()&&!fixtureLiveEventFds);
    puts("Event lock passed: real regular/single-link inode admission, pre-stat failure, symlink/FIFO/directory/hardlink/root refusal, post-flock replacement/unlink/link/root swaps, descriptor permissions, stable inode and zero live descriptors. Cooperating-writer protocol required; arbitrary race/power-loss guarantees remain separate.");
}
static void fixtureBoundedReadRejected(NSString *code) {
    const unsigned writes=fixtureWrites.load(),posts=fixturePosts.load();
    NSDictionary *reply=TLinkEventChannelPublish(@"fixture",@"script.run",@"updated",@{});
    assert([reply[@"state"] isEqual:@"error"]&&[reply[@"error"] isEqual:code]);
    NSDictionary *status=TLinkEventChannelStatus();assert([status[@"state"] isEqual:@"error"]&&[status[@"error"] isEqual:code]);
    NSString *error=nil;NSDictionary *batch=TLinkEventChannelPollBody(body(8,0),&error);
    assert([error isEqual:code]&&!batch.count&&fixtureWrites==writes&&fixturePosts==posts&&sTLinkEventActivePolls==0);
    dispatch_sync(TLinkEventOwnerQueue(),^{assert(fixtureJournalFds.empty()&&fixtureEventFds.empty()&&!sTLinkEventWaiters.count);});
    assert(!fixtureLiveJournalFds&&!fixtureLiveEventFds&&fixtureEventFds.empty()&&fixtureJournalFds.empty());fixtureOtherOwnerCanLock();
}
static void fixtureBoundedJournalCases() {
    const bool savedNotify=suppressNotify;suppressNotify=true;
    NSString *path=TLinkEventJournalPath();NSFileManager *fm=[NSFileManager defaultManager];
    NSData *savedJournal=[NSData dataWithContentsOfFile:path];
    NSData *healthy=fixtureJournalData(fixtureJournal(9,@[fixtureStoredEvent(7),fixtureStoredEvent(8)]));assert([healthy writeToFile:path atomically:YES]);
    // Refuse a real sparse oversized file before a journal buffer or a single payload read.
    int fd=::open(path.fileSystemRepresentation,O_WRONLY|O_TRUNC);assert(fd>=0&&::ftruncate(fd,(off_t)kTLinkEventJournalMaxBytes+1)==0&&::close(fd)==0);
    fixtureJournalReads=0;fixtureJournalAllocations=0;fixtureBoundedReadRejected(@"event_journal_too_large");
    struct stat info;assert(::lstat(path.fileSystemRepresentation,&info)==0&&info.st_size==(off_t)kTLinkEventJournalMaxBytes+1&&!fixtureJournalReads&&!fixtureJournalAllocations);
    assert([healthy writeToFile:path atomically:YES]);
    for(unsigned fault=1;fault<=2;++fault){fixtureJournalOpenFault=fault;fixtureBoundedReadRejected(@"event_journal_read_failed");fixtureJournalOpenFault=0;}
    for(unsigned fault=1;fault<=3;++fault){
        fixtureJournalStatFault=fault;fixtureJournalReads=0;fixtureJournalAllocations=0;
        fixtureBoundedReadRejected(fault==2?@"event_journal_too_large":@"event_journal_read_failed");fixtureJournalStatFault=0;
        assert(!fixtureJournalReads&&!fixtureJournalAllocations);
    }
    for(unsigned fault:{2U,3U,4U,5U,7U}){
        fixtureJournalReadFault=fault;fixtureBoundedReadRejected(fault==4||fault==5?@"event_journal_exception":@"event_journal_read_failed");fixtureJournalReadFault=0;
        assert([healthy isEqual:[NSData dataWithContentsOfFile:path]]);
    }
    fixtureJournalReadFault=1;fixtureJournalReads=0;fixtureJournalBytes=0;
    NSDictionary *status=TLinkEventChannelStatus();fixtureJournalReadFault=0;
    assert([status[@"state"] isEqual:@"implemented"]&&[status[@"latest_cursor"] unsignedLongLongValue]==8&&fixtureJournalReads>2&&fixtureJournalBytes==healthy.length);
    // A valid journal padded to exactly the cap is accepted with at most the cap plus one-byte EOF probe.
    NSMutableData *padded=[NSMutableData dataWithLength:kTLinkEventJournalMaxBytes];memset(padded.mutableBytes,' ',padded.length);memcpy(padded.mutableBytes,healthy.bytes,healthy.length);
    assert([padded writeToFile:path atomically:YES]);fixtureJournalReads=0;fixtureJournalBytes=0;
    status=TLinkEventChannelStatus();assert([status[@"state"] isEqual:@"implemented"]&&fixtureJournalBytes==kTLinkEventJournalMaxBytes&&fixtureJournalReads>=65);
    assert([padded isEqual:[NSData dataWithContentsOfFile:path]]);padded=nil;
    assert([healthy writeToFile:path atomically:YES]);
    NSString *stash=[path stringByAppendingString:@".bounded-saved"],*outside=[TLinkEventChannelRootPath() stringByAppendingPathComponent:@"bounded-outside.json"];
    assert(::rename(path.fileSystemRepresentation,stash.fileSystemRepresentation)==0&&[healthy writeToFile:outside atomically:YES]&&::chmod(outside.fileSystemRepresentation,0600)==0);
    assert(::symlink(outside.fileSystemRepresentation,path.fileSystemRepresentation)==0);fixtureBoundedReadRejected(@"event_journal_read_failed");
    assert([healthy isEqual:[NSData dataWithContentsOfFile:outside]]&&::stat(outside.fileSystemRepresentation,&info)==0&&(info.st_mode&0777)==0600);
    assert(::unlink(path.fileSystemRepresentation)==0&&::symlink([outside stringByAppendingString:@".absent"].fileSystemRepresentation,path.fileSystemRepresentation)==0);
    fixtureBoundedReadRejected(@"event_journal_read_failed");assert(::lstat(path.fileSystemRepresentation,&info)==0&&S_ISLNK(info.st_mode));
    assert(::unlink(path.fileSystemRepresentation)==0&&::mkfifo(path.fileSystemRepresentation,0600)==0);fixtureBoundedReadRejected(@"event_journal_read_failed");
    assert(::unlink(path.fileSystemRepresentation)==0&&[fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
    NSString *child=[path stringByAppendingPathComponent:@"keep"];assert([healthy writeToFile:child atomically:YES]);fixtureBoundedReadRejected(@"event_journal_read_failed");
    assert([healthy isEqual:[NSData dataWithContentsOfFile:child]]&&[fm removeItemAtPath:path error:nil]&&::rename(stash.fileSystemRepresentation,path.fileSystemRepresentation)==0);
    // Maximum normal event count/payload/token fields leave ample room below the journal cap.
    NSDictionary *payload=@{@"x":[@"" stringByPaddingToLength:4088 withString:@"a" startingAtIndex:0]};assert(fixtureJournalData(payload).length==4096);
    NSMutableArray *events=[NSMutableArray array];NSString *token=[@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    for(unsigned n=1;n<=256;++n){NSMutableDictionary *event=[fixtureStoredEvent(n) mutableCopy];
        event[@"payload"]=payload;event[@"runtime"]=token;event[@"topic"]=token;event[@"type"]=token;event[@"event_id"]=@"ffffffff-ffff-ffff-ffff-ffffffffffff";event[@"timestamp_ms"]=@(UINT64_MAX);[events addObject:event];}
    NSDictionary *canonical=fixtureJournal(257,events);const int writer=TLinkEventAcquireFileLock(NO,NO);assert(writer>=0&&TLinkEventWriteJournal(canonical));TLinkEventReleaseFileLock(writer);
    assert([[NSData dataWithContentsOfFile:path] length]<kTLinkEventJournalMaxBytes&&publish()==257);
    // Valid extension data can fill the cap; an append that exceeds it must not commit an unreadable file.
    NSMutableDictionary *near=[fixtureJournal(9,@[fixtureStoredEvent(7),fixtureStoredEvent(8)]) mutableCopy];near[@"blob"]=@"";
    const NSUInteger base=fixtureJournalData(near).length;near[@"blob"]=[@"" stringByPaddingToLength:kTLinkEventJournalMaxBytes-base withString:@"a" startingAtIndex:0];
    NSData *full=fixtureJournalData(near);assert(full.length==kTLinkEventJournalMaxBytes&&[full writeToFile:path atomically:YES]);
    const unsigned writes=fixtureWrites.load(),posts=fixturePosts.load();NSDictionary *reply=TLinkEventChannelPublish(@"fixture",@"script.run",@"updated",@{});
    assert([reply[@"error"] isEqual:@"event_journal_write_failed"]&&fixtureWrites==writes&&fixturePosts==posts&&[full isEqual:[NSData dataWithContentsOfFile:path]]);
    assert([healthy writeToFile:path atomically:YES]&&publish()==9&&[TLinkEventChannelStatus()[@"state"] isEqual:@"implemented"]);
    dispatch_sync(TLinkEventOwnerQueue(),^{assert(!sTLinkEventWaiters.count&&!sTLinkEventSnapshot&&fixtureJournalFds.empty());});
    assert(!fixtureLiveJournalFds&&!fixtureLiveEventFds);
    if(savedJournal)assert([savedJournal writeToFile:path atomically:YES]);else assert([fm removeItemAtPath:path error:nil]);
    suppressNotify=savedNotify;
    puts("Event bounded journal passed: regular/no-follow/nonblocking reads, 4-MiB admission before buffer allocation/payload IO, 64-KiB chunks, EOF probe, EINTR/short/error/NS/C++ cleanup, real sparse/FIFO/directory/symlink cases, exact-cap/maximum-normal journals and write-cap preservation. This is not an overall JSON/RSS or IO-time bound.");
}
#include "event-envelope-runtime-fixture.inc"
#include "event-wire-runtime-fixture.inc"
int main(int argc, char **argv) { @autoreleasepool {
    (void)kZXLegacyMaxBufferSize;
    if (argc > 1) { suppressNotify = strcmp(argv[1],"quiet") == 0; assert(publish()); return 0; }
    fixtureEventEnvelopeCases();
    fixtureEventWireCases();
    fixtureValidatedLockCases();
    fixtureCheckedPublicationCases();
    uint64_t one = publish(), unrelated = publish(@"other"), three = publish(), tail = publish(@"other");
    assert(one && unrelated == one + 1 && three == one + 2 && tail == one + 3);
    NSDictionary *batch = poll(0,1); assert([batch[@"has_more"] boolValue] && [batch[@"next_cursor"] unsignedLongLongValue] == unrelated);
    batch = poll(unrelated,1); assert(![batch[@"has_more"] boolValue] && [batch[@"next_cursor"] unsignedLongLongValue] == tail && [batch[@"events"] count] == 1);
    NSString *error = nil; (void)TLinkEventChannelPollBody(@"0;;0;;8;;a*b",&error); assert([error isEqual:@"event_topic_invalid"]);
    error = nil; (void)TLinkEventChannelPollBody(@"18446744073709551616;;0;;8;;*",&error); assert([error isEqual:@"event_request_invalid"]);
    fixtureCheckedReadCases(tail);
    fixtureBoundedJournalCases();
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
        assert([object[@"data"] count]==1);
        NSData *decoded=[[NSData alloc] initWithBase64EncodedString:object[@"data"][0] options:0];
        NSDictionary *eventBatch=[NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil];
        assert([eventBatch[@"schema"] isEqual:TLinkEventChannelSchemaV1]&&[eventBatch[@"timed_out"] boolValue]);
        assert([eventBatch[@"next_cursor"] unsignedLongLongValue]==latest);
        [wireWrites removeAllObjects]; zx_deferLegacyEventPoll(root,body(latest));
        [root.eventPollRequest cancel]; root.eventPollRequest = nil; root.writeStream = NULL; root.eventPollPending = NO;
    });
    ZXClientContext *rootErrors=[ZXClientContext new];rootErrors.writeStream=(CFWriteStreamRef)(uintptr_t)3;
    dispatch_sync(socketQueue(), ^{
        zx_deferJSONEventPoll(rootErrors,body(latest),@76);
        zx_deferJSONEventPoll(rootErrors,body(latest),@77);
        assert(wireWrites.count==1);
        NSDictionary *object=fixtureEnvelopeFrameObject(wireWrites.lastObject);
        assert([object[@"id"] isEqual:@77]&&[object[@"error"] isEqual:@"event_poll_already_pending"]);
        [rootErrors.eventPollRequest cancel];rootErrors.eventPollRequest=nil;rootErrors.eventPollPending=NO;
        [wireWrites removeAllObjects];
    });
    allowed=false;dispatch_sync(socketQueue(), ^{zx_deferJSONEventPoll(rootErrors,body(latest,0),@88);});
    waitFor([] {__block BOOL done;dispatch_sync(socketQueue(), ^{done=wireWrites.count==1;});return (bool)done;});
    dispatch_sync(socketQueue(), ^{
        NSDictionary *object=fixtureEnvelopeFrameObject(wireWrites.lastObject);
        assert([object[@"id"] isEqual:@88]&&[object[@"error"] isEqual:@"license_required"]);
        [wireWrites removeAllObjects];rootErrors.writeStream=NULL;
    });allowed=true;
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
    assert(!fixtureLiveEventFds&&fixtureEventFds.empty()&&fixtureEventLocks.empty()&&!fixtureLiveJournalFds&&fixtureJournalFds.empty());
    puts("Event Foundation passed: real journal/locks, cross-process and missed notifications, quiet/idle I/O, eight cancellations, blocked authorization, deadlines, pagination/gap and root/TrollStore/remote wire adapters.");
} }
