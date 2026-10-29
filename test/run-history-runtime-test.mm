#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <spawn.h>
#include <unistd.h>
#include <cassert>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstdint>
#include <functional>
#include <mutex>
#include <set>
#include <stdexcept>
#include <vector>
static NSString *historyTestRoot;
static NSMutableArray *historyEvents;
static std::mutex historyMutex;
static std::set<int> historyLocks;
static std::atomic<unsigned> historyRegexBuilds{0},historyUUIDs{0};
static std::atomic<uint64_t> historyClockMs{1000000};
static unsigned historyReadFault=0;
static unsigned historyMutationReadFault=0;
static bool historyLockDenied=false;
static size_t historyIndexReads=0;
static std::function<void()> historyStatusHook;
static NSString *historyWriteStage;
static unsigned historyWriteFault=0;
static unsigned historyCrashIndex=0;
static NSMutableArray *historyWriteAttempts;
static unsigned historyPruneFault=0;
static NSString *historyPruneTarget;
static NSMutableArray *historyPruneAttempts;
static unsigned historyRecoveryReadFault=0;
static bool historyRecoveryOpenFault=false,historyRecoveryStatFault=false;
static size_t historyRecoveryOpens=0,historyRecoveryReads=0,historyRecoveryBytes=0;
static std::set<int> historyRecoveryFds;
static unsigned historyMarkerFault=0;
static off_t historyMarkerFaultLength=-1;
static bool historyMarkerStatFault=false;
static size_t historyMarkerChanges=0;
extern char **environ;
static int historyMarkerStat(int fd,struct stat *info){
    assert(historyLocks.count(fd));if(historyMarkerStatFault){errno=EIO;return -1;}return ::fstat(fd,info);
}
static int historyMarkerTruncate(int fd,off_t length){
    assert(historyLocks.count(fd)&&(length==0||length==1));++historyMarkerChanges;
    const bool inject=historyMarkerFaultLength==length;
    if(inject&&historyMarkerFault==1){errno=EIO;return -1;}
    if(inject&&historyMarkerFault==2){historyMarkerFault=0;errno=EINTR;return -1;}
    const int result=::ftruncate(fd,length);
    if(inject&&historyMarkerFault==3){errno=EIO;return -1;}return result;
}
static int historyRecoveryOpen(const char *path,int flags){
    assert(flags==(O_RDONLY|O_NONBLOCK|O_NOFOLLOW));assert(historyLocks.size()==1);++historyRecoveryOpens;
    if(historyRecoveryOpenFault){errno=EACCES;return -1;}
    const int fd=::open(path,flags);if(fd>=0)assert(historyRecoveryFds.insert(fd).second);return fd;
}
static int historyRecoveryStat(int fd,struct stat *info){
    assert(historyRecoveryFds.count(fd));if(historyRecoveryStatFault){errno=EIO;return -1;}return ::fstat(fd,info);
}
static ssize_t historyRecoveryRead(int fd,void *bytes,size_t count){
    assert(historyRecoveryFds.count(fd)&&count<=65536);++historyRecoveryReads;
    if(historyRecoveryReadFault==1){historyRecoveryReadFault=6;errno=EINTR;return -1;}
    if(historyRecoveryReadFault==2){errno=EIO;return -1;}
    if(historyRecoveryReadFault==3)return 0;
    if(historyRecoveryReadFault==4)[NSException raise:@"HistoryFixture" format:@"recovery read failed"];
    if(historyRecoveryReadFault==5)throw std::runtime_error("recovery read failed");
    const ssize_t got=::read(fd,bytes,historyRecoveryReadFault==6?MIN(count,(size_t)17):count);
    if(got>0)historyRecoveryBytes+=(size_t)got;return got;
}
static BOOL historyRemoveArtifact(NSString *path){
    if(historyPruneFault==1)[NSException raise:@"HistoryFixture" format:@"cleanup failed"];
    if(historyPruneFault==2)throw std::runtime_error("cleanup failed");
    return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}
static int historyUnlinkArtifact(const char *name){
    assert(historyLocks.size()==1);NSString *path=[NSString stringWithUTF8String:name];[historyPruneAttempts addObject:path];
    const bool inject=!historyPruneTarget||[historyPruneTarget isEqualToString:path];
    if(inject&&historyPruneFault==1)[NSException raise:@"HistoryFixture" format:@"cleanup failed"];
    if(inject&&historyPruneFault==2)throw std::runtime_error("cleanup failed");
    if(inject&&historyPruneFault==3){errno=EACCES;return -1;}
    if(inject&&historyPruneFault==4){historyPruneFault=0;errno=EINTR;return -1;}
    const int result=::unlink(name);
    if(inject&&historyPruneFault==5){errno=EIO;return -1;}return result;
}
static BOOL historyWriteData(NSData *data,NSString *path){
    NSString *stage=[path.lastPathComponent isEqualToString:@"index.json"]?@"index":([path containsString:@"/evidence/"]?@"evidence":@"record");
    [historyWriteAttempts addObject:stage];
    if([stage isEqualToString:@"index"]&&historyCrashIndex==1)::_exit(81);
    if([stage isEqualToString:historyWriteStage]){
        if(historyWriteFault==1)return NO;
        if(historyWriteFault==2)[NSException raise:@"HistoryFixture" format:@"write failed"];
        if(historyWriteFault==3)throw std::runtime_error("write failed");
    }
    const BOOL written=[data writeToFile:path atomically:YES];
    if([stage isEqualToString:@"index"]&&historyCrashIndex==2)::_exit(82);
    if([stage isEqualToString:historyWriteStage]&&historyWriteFault==4)return NO;
    if([stage isEqualToString:historyWriteStage]&&historyWriteFault==5)[NSException raise:@"HistoryFixture" format:@"post-write fault"];
    if([stage isEqualToString:historyWriteStage]&&historyWriteFault==6)throw std::runtime_error("post-write fault");
    return written;
}
static void historyIndexReadProbe(){
    ++historyIndexReads;
    if(historyReadFault==1)[NSException raise:@"HistoryFixture" format:@"index read fault"];
    if(historyReadFault==2)throw std::runtime_error("index read fault");
}
static NSData *historyReadMutationData(NSString *path,NSError **error){
    historyIndexReadProbe();
    if(historyMutationReadFault){
        if(error)*error=historyMutationReadFault==1?[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoPermissionError userInfo:nil]:
            (historyMutationReadFault==2?[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil]:nil);
        return nil;
    }
    return [NSData dataWithContentsOfFile:path options:0 error:error];
}
static void historyStatusPreparationProbe(){if(historyStatusHook)historyStatusHook();}
static int historyChmod(const char *path,mode_t mode){assert([[NSString stringWithUTF8String:path] hasPrefix:historyTestRoot]);assert(mode==0750||mode==0640);return 0;}
static int historyChown(const char *path,uid_t uid,gid_t gid){assert([[NSString stringWithUTF8String:path] hasPrefix:historyTestRoot]);assert(uid==501&&gid==501);return 0;}
static int historyFlock(int fd,int operation){
    if(historyLockDenied&&operation==LOCK_EX){errno=EACCES;return -1;}
    const int result=::flock(fd,operation);
    if(!result){std::lock_guard<std::mutex> guard(historyMutex);if(operation==LOCK_EX)assert(historyLocks.insert(fd).second);else if(operation==LOCK_UN)assert(historyLocks.erase(fd)==1);}
    return result;
}
static int historyClose(int fd){{std::lock_guard<std::mutex> guard(historyMutex);assert(!historyLocks.count(fd));}historyRecoveryFds.erase(fd);return ::close(fd);}
static NSDictionary *historyPublish(NSString *runtime,NSString *topic,NSString *type,NSDictionary *payload){
    std::lock_guard<std::mutex> guard(historyMutex);assert(historyLocks.empty());
    NSDictionary *event=@{@"runtime":runtime,@"topic":topic,@"type":type,@"payload":payload};[historyEvents addObject:event];return event;
}
@interface HistoryClock : NSObject
+ (NSDate *)date;
@end
@implementation HistoryClock
+ (NSDate *)date {return [NSDate dateWithTimeIntervalSince1970:double(historyClockMs.load())/1000.0];}
@end
@interface HistoryUUID : NSObject
+ (NSUUID *)UUID;
@end
@implementation HistoryUUID
+ (NSUUID *)UUID {NSString *value=[NSString stringWithFormat:@"%08x-0000-0000-0000-000000000000",++historyUUIDs];return [[NSUUID alloc] initWithUUIDString:value];}
@end
@interface HistoryRegexFactory : NSObject
+ (NSRegularExpression *)regularExpressionWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error;
@end
@implementation HistoryRegexFactory
+ (NSRegularExpression *)regularExpressionWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error {++historyRegexBuilds;return [NSRegularExpression regularExpressionWithPattern:pattern options:options error:error];}
@end
#define NSDate HistoryClock
#define NSUUID HistoryUUID
#define chmod historyChmod
#define lchown historyChown
#define flock historyFlock
#define close historyClose
#define TLinkEventChannelPublish historyPublish
namespace Current {
static NSString *fixtureRoot;
#include "HistoryUnderTest.inc"
}
namespace Legacy {
static NSString *fixtureRoot;
#include "HistoryLegacy.inc"
}
#undef TLinkEventChannelPublish
#undef close
#undef flock
#undef lchown
#undef chmod
#undef NSUUID
#undef NSDate
@interface HistoryProbe : NSObject {
@public std::function<void()> callback;
}
@end
@implementation HistoryProbe
- (NSString *)description {if(callback)callback();return @"license_key=probe-secret";}
@end
static id historyNormalize(id value,NSString *root){
    if([value isKindOfClass:[NSString class]])return [value stringByReplacingOccurrencesOfString:root withString:@"$HISTORY"];
    if([value isKindOfClass:[NSArray class]]){NSMutableArray *result=[NSMutableArray array];for(id item in value)[result addObject:historyNormalize(item,root)];return result;}
    if([value isKindOfClass:[NSDictionary class]]){NSMutableDictionary *result=[NSMutableDictionary dictionary];for(NSString *key in value)if(![key isEqualToString:@"persistence_diagnostics"])result[key]=historyNormalize(value[key],root);return result;}
    return value;
}
static NSData *historyCanonical(id value,NSString *root){NSData *data=[NSJSONSerialization dataWithJSONObject:historyNormalize(value,root) options:NSJSONWritingSortedKeys error:nil];assert(data);return data;}
static id historyReadJSON(NSString *path){NSData *data=[NSData dataWithContentsOfFile:path];assert(data);id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];assert(value);return value;}
using HistoryBegin=NSDictionary *(*)(NSString *,NSString *,NSString *,NSDictionary *);
using HistoryFinish=NSDictionary *(*)(NSString *,NSString *,NSString *,NSArray<NSString *> *,NSString *,NSString *,NSString *,NSDictionary *);
using HistorySnapshot=NSDictionary *(*)(NSUInteger);
static NSData *historyTransactions(bool modern,NSString *console,NSString *screenshot){
    HistoryBegin begin=modern?Current::TLinkRunHistoryBegin:Legacy::TLinkRunHistoryBegin;
    HistoryFinish finish=modern?Current::TLinkRunHistoryFinish:Legacy::TLinkRunHistoryFinish;
    HistorySnapshot snapshot=modern?Current::TLinkRunHistorySnapshot:Legacy::TLinkRunHistorySnapshot;
    NSString *root=modern?Current::fixtureRoot:Legacy::fixtureRoot;
    historyUUIDs=0;[historyEvents removeAllObjects];NSMutableArray *results=[NSMutableArray array];
    NSMutableArray *tail=[NSMutableArray array];
    for(unsigned n=0;n<60;++n)[tail addObject:[NSString stringWithFormat:@"%u ảnh 测试 license_key=hidden Bearer abc-token %@",n,[@"x" stringByPaddingToLength:1100 withString:@"x" startingAtIndex:0]]];
    NSArray *states=@[@"finished",@"failed",@"cancelled",@"license_revoked",@""];
    for(unsigned n=0;n<75;++n){@autoreleasepool{
        historyClockMs=1000000+n*1000;
        NSString *runId;
        if(n%11){NSDictionary *started=begin(n%2?@"rootfull":@"trollstore",@"/bundle",@"main.js",@{@"repeat":@1});assert(started.count);[results addObject:started];runId=started[@"run_id"];}
        else runId=[NSString stringWithFormat:@"missing-%u",n];
        historyClockMs+=500;
        NSString *error=n%3?@"license_key=secret; VPN_PASSWORD='abc'; Bearer abc-token":[@"error" stringByPaddingToLength:5000 withString:@"x" startingAtIndex:0];
        NSDictionary *record=finish(runId,states[n%states.count],error,n%2?tail:@[],console,n%3?screenshot:@"",n%2?@"capture_failed":nil,@{@"case":@(n)});
        assert(record.count);[results addObject:record];
        assert([historyCanonical(record,root) isEqual:historyCanonical(historyReadJSON(record[@"record_path"]),root)]);
        NSDictionary *evidence=record[@"failure_evidence"];
        if(evidence.count)assert([historyCanonical(evidence,root) isEqual:historyCanonical(historyReadJSON(evidence[@"metadata_path"]),root)]);
    }}
    for(NSNumber *limit in @[@0,@1,@20,@50,@99]){NSDictionary *status=snapshot(limit.unsignedIntegerValue);assert([status[@"total_count"] intValue]==50);[results addObject:status];}
    [results addObject:historyReadJSON([root stringByAppendingPathComponent:@"index.json"])];[results addObject:[historyEvents copy]];
    assert([[NSFileManager defaultManager] contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:@"runs"] error:nil].count==50);
    return historyCanonical(results,root);
}
// Only POSIX calls in the child: no Foundation/Objective-C after fork.
static bool historyChildCanLock(NSString *path){
    const char *name=path.fileSystemRepresentation;std::vector<int> inherited;
    {std::lock_guard<std::mutex> guard(historyMutex);inherited.assign(historyLocks.begin(),historyLocks.end());}
    const pid_t child=::fork();assert(child>=0);
    if(!child){for(int fd:inherited)::close(fd);const int fd=::open(name,O_RDWR);if(fd<0)::_exit(2);const int result=::flock(fd,LOCK_EX|LOCK_NB);const int saved=errno;if(!result)::flock(fd,LOCK_UN);::close(fd);::_exit(!result?0:((saved==EWOULDBLOCK||saved==EAGAIN)?1:2));}
    int status=0;pid_t waited;do{waited=::waitpid(child,&status,0);}while(waited<0&&errno==EINTR);assert(waited==child&&WIFEXITED(status)&&WEXITSTATUS(status)!=2);return WEXITSTATUS(status)==0;
}
static NSDictionary *historyDiagnostics(){return Current::TLinkRunHistorySnapshot(0)[@"persistence_diagnostics"];}
static void historyCommitCases(NSString *console,NSString *screenshot){
    NSString *root=Current::fixtureRoot,*indexPath=[root stringByAppendingPathComponent:@"index.json"],*lockPath=[root stringByAppendingPathComponent:@"history.lock"];
    NSDictionary *initial=historyDiagnostics();assert([initial[@"scope"] isEqualToString:@"process"]&&[initial[@"failure_count"] unsignedLongLongValue]==0&&[initial[@"last_failure"] count]==0);
    for(bool beginning:{true,false}){
        NSArray *stages=beginning?@[@"record",@"index"]:@[@"evidence",@"record",@"index"];
        for(NSString *stage in stages)for(unsigned fault=1;fault<=3;++fault){
            NSString *runId=[NSString stringWithFormat:@"write-fault-%@-%u",stage,fault];NSData *indexBefore=[NSData dataWithContentsOfFile:indexPath];
            NSDictionary *oldest=[historyReadJSON(indexPath)[@"runs"] lastObject];NSMutableDictionary *victims=[NSMutableDictionary dictionary];
            NSDictionary *evidence=oldest[@"failure_evidence"];
            for(id raw in @[oldest[@"record_path"]?:@"",evidence[@"metadata_path"]?:@"",evidence[@"screenshot_path"]?:@""]){NSString *path=raw;
                if([path hasPrefix:[root stringByAppendingString:@"/"]]){NSData *bytes=[NSData dataWithContentsOfFile:path];if(bytes)victims[path]=bytes;}}
            assert(victims.count>0);const NSUInteger eventCount=historyEvents.count;const uint64_t failures=[historyDiagnostics()[@"failure_count"] unsignedLongLongValue];[historyWriteAttempts removeAllObjects];
            historyWriteStage=stage;historyWriteFault=fault;
            NSDictionary *failed=beginning?Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"write-fault.js",@{}):Current::TLinkRunHistoryFinish(runId,@"failed",@"original script error license_key=secret",@[],console,screenshot,nil,@{});
            historyWriteStage=nil;historyWriteFault=0;NSDictionary *diagnostics=historyDiagnostics();
            assert(failed.count==0&&historyEvents.count==eventCount&&historyLocks.empty()&&historyChildCanLock(lockPath)&&!Current::sTLinkRunHistoryRecovered);
            assert([indexBefore isEqual:[NSData dataWithContentsOfFile:indexPath]]&&[diagnostics[@"failure_count"] unsignedLongLongValue]==failures+1);
            assert([diagnostics[@"last_failure"][@"operation"] isEqualToString:beginning?@"begin":@"finish"]&&[diagnostics[@"last_failure"][@"stage"] isEqualToString:stage]);
            NSString *code=fault==1?@"write_failed":@"exception";assert([diagnostics[@"last_failure"][@"code"] isEqualToString:code]);
            const NSUInteger attempts=[stage isEqualToString:@"evidence"]?1:([stage isEqualToString:@"record"]?(beginning?1:2):(beginning?2:3));
            assert(historyWriteAttempts.count==attempts);
            for(NSString *path in victims)assert([victims[path] isEqual:[NSData dataWithContentsOfFile:path]]);
            NSData *encoded=[NSJSONSerialization dataWithJSONObject:diagnostics options:0 error:nil];assert(encoded.length<=512);
            NSString *diagnosticText=[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];assert(![diagnosticText containsString:@"secret"]&&![diagnosticText containsString:@"original script error"]);
            NSDictionary *recovered=beginning?Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"recovered.js",@{}):Current::TLinkRunHistoryFinish(runId,@"failed",@"original script error",@[],console,screenshot,nil,@{});
            assert(recovered.count&&historyEvents.count==eventCount+1&&historyLocks.empty()&&Current::sTLinkRunHistoryRecovered);
            assert([historyDiagnostics()[@"failure_count"] unsignedLongLongValue]==failures+1);
            for(NSString *path in victims)assert(![[NSFileManager defaultManager] fileExistsAtPath:path]);
            assert([Current::TLinkRunHistorySnapshot(50)[@"total_count"] intValue]==50);
        }
    }
    for(bool beginning:{true,false})for(unsigned fault=1;fault<=3;++fault){
        const uint64_t failures=[historyDiagnostics()[@"failure_count"] unsignedLongLongValue];const NSUInteger eventCount=historyEvents.count;NSData *indexBefore=[NSData dataWithContentsOfFile:indexPath];[historyWriteAttempts removeAllObjects];
        const BOOL recoveredBefore=Current::sTLinkRunHistoryRecovered;
        if(fault==3)historyLockDenied=true;else historyReadFault=fault;
        NSDictionary *result=beginning?Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"read-fault.js",@{}):Current::TLinkRunHistoryFinish(@"read-fault",@"finished",@"",@[],@"",@"",nil,@{});
        historyLockDenied=false;historyReadFault=0;NSDictionary *diagnostics=historyDiagnostics();
        assert(Current::sTLinkRunHistoryRecovered==recoveredBefore);
        assert(!result.count&&historyLocks.empty()&&historyEvents.count==eventCount&&historyWriteAttempts.count==0&&historyChildCanLock(lockPath));
        assert([indexBefore isEqual:[NSData dataWithContentsOfFile:indexPath]]&&[diagnostics[@"failure_count"] unsignedLongLongValue]==failures+1);
        assert([diagnostics[@"last_failure"][@"stage"] isEqualToString:fault==3?@"lock":@"read"]);
    }
    const NSUInteger serializationEvents=historyEvents.count;NSData *serializationIndex=[NSData dataWithContentsOfFile:indexPath];[historyWriteAttempts removeAllObjects];
    NSDictionary *unsupported=@{@"not_json":[NSObject new]};
    assert(!Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"invalid-settings.js",unsupported).count);
    assert(historyEvents.count==serializationEvents&&historyWriteAttempts.count==0&&[serializationIndex isEqual:[NSData dataWithContentsOfFile:indexPath]]&&historyLocks.empty());
    assert([historyDiagnostics()[@"last_failure"][@"stage"] isEqualToString:@"record"]);
    for(unsigned fault=1;fault<=2;++fault){
        const uint64_t failures=[historyDiagnostics()[@"failure_count"] unsignedLongLongValue];const NSUInteger eventCount=historyEvents.count;
        NSString *victim=[historyReadJSON(indexPath)[@"runs"] lastObject][@"record_path"];NSData *victimBytes=[NSData dataWithContentsOfFile:victim];
        historyPruneFault=fault;NSDictionary *committed=Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"cleanup-fault.js",@{});historyPruneFault=0;
        assert(committed.count&&historyEvents.count==eventCount+1&&historyLocks.empty()&&[victimBytes isEqual:[NSData dataWithContentsOfFile:victim]]&&Current::sTLinkRunHistoryRecovered);
        assert([historyDiagnostics()[@"failure_count"] unsignedLongLongValue]==failures+1&&[historyDiagnostics()[@"last_failure"][@"operation"] isEqualToString:@"prune"]);
        assert([Current::TLinkRunHistorySnapshot(1)[@"runs"][0][@"run_id"] isEqualToString:committed[@"run_id"]]);
    }
    // A reported failure can follow a committed atomic write. Suppress success
    // and leave artifacts alone; no rollback/replay of an uncertain outcome.
    NSDictionary *oldest=[historyReadJSON(indexPath)[@"runs"] lastObject];NSString *oldPath=oldest[@"record_path"];NSData *oldBytes=[NSData dataWithContentsOfFile:oldPath];
    NSData *indexBefore=[NSData dataWithContentsOfFile:indexPath];const NSUInteger eventsBefore=historyEvents.count;
    historyWriteStage=@"index";historyWriteFault=4;NSDictionary *unknown=Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"uncertain.js",@{});historyWriteStage=nil;historyWriteFault=0;
    assert(!unknown.count&&historyEvents.count==eventsBefore&&historyLocks.empty()&&!Current::sTLinkRunHistoryRecovered);
    assert(![indexBefore isEqual:[NSData dataWithContentsOfFile:indexPath]]&&[oldBytes isEqual:[NSData dataWithContentsOfFile:oldPath]]);
    assert([Current::TLinkRunHistorySnapshot(1)[@"runs"][0][@"entry_path"] isEqualToString:@"uncertain.js"]);
    const uint64_t saved=Current::sTLinkRunHistoryPersistenceFailures;Current::sTLinkRunHistoryPersistenceFailures=UINT64_MAX-1;historyLockDenied=true;
    assert(!Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"max.js",@{}).count&&!Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"max.js",@{}).count);historyLockDenied=false;
    assert([historyDiagnostics()[@"failure_count"] unsignedLongLongValue]==UINT64_MAX);Current::sTLinkRunHistoryPersistenceFailures=saved;
}
static NSDictionary *historyDiskBytes(NSString *root){
    NSMutableDictionary *files=[NSMutableDictionary dictionary];NSFileManager *fm=[NSFileManager defaultManager];
    for(NSString *relative in [fm enumeratorAtPath:root]){
        NSString *path=[root stringByAppendingPathComponent:relative];
        if([[[fm attributesOfItemAtPath:path error:nil] fileType] isEqualToString:NSFileTypeRegular]){
            NSData *data=[NSData dataWithContentsOfFile:path];assert(data);files[relative]=data;
        }
    }
    return files;
}
static off_t historyPendingSize(){
    struct stat info;assert(::stat([Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"].fileSystemRepresentation,&info)==0);return info.st_size;
}
static NSDictionary *historyPayloadBytes(NSString *root){
    NSMutableDictionary *files=[historyDiskBytes(root) mutableCopy];[files removeObjectForKey:@"history.lock"];return files;
}
static NSDictionary *historyMutation(bool beginning){
    return beginning?Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"read-validation.js",@{}):
        Current::TLinkRunHistoryFinish(@"validation-finish",@"failed",@"failure",@[@"line"],@"",@"",nil,@{});
}
static void historyMutationReadCases(){
    NSString *savedRoot=Current::fixtureRoot;Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"index-validation"];
    NSString *root=Current::fixtureRoot,*path=[root stringByAppendingPathComponent:@"index.json"],*lock=[root stringByAppendingPathComponent:@"history.lock"];
    NSFileManager *fm=[NSFileManager defaultManager];
    // A genuine missing index remains the only empty-start case, including finish.
    assert(historyMutation(true).count);assert([fm removeItemAtPath:path error:nil]);assert(historyMutation(false).count);
    NSArray<NSString *> *invalid=@[@"",@"not-json",@"null",@"[]",@"{}",@"{\"runs\":[]}",
        @"{\"schema\":\"future\",\"runs\":[]}",@"{\"schema\":1,\"runs\":[]}",
        @"{\"schema\":\"run_history_v1\",\"runs\":42}",@"{\"schema\":\"run_history_v1\",\"runs\":null}",
        @"{\"schema\":\"run_history_v1\",\"runs\":[42]}",@"{\"schema\":\"run_history_v1\",\"runs\":[null]}",
        @"{\"schema\":\"run_history_v1\",\"runs\":[{}]}",@"{\"schema\":\"run_history_v1\",\"runs\":[{\"run_id\":42}]}",
        @"{\"schema\":\"run_history_v1\",\"runs\":[{\"run_id\":\"\"}]}",
        @"{\"schema\":\"run_history_v1\",\"runs\":[{\"run_id\":\"same\"},{\"run_id\":\"same\"}]}"];
    for(bool beginning:{true,false})for(NSString *text in invalid){@autoreleasepool{
        NSData *healthy=[NSData dataWithContentsOfFile:path],*bad=[text dataUsingEncoding:NSUTF8StringEncoding];assert(healthy&&[bad writeToFile:path atomically:YES]);
        NSDictionary *files=historyDiskBytes(root);const NSUInteger events=historyEvents.count;const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
        [historyWriteAttempts removeAllObjects];NSDictionary *result=historyMutation(beginning);
        assert(!result.count&&historyEvents.count==events&&!historyWriteAttempts.count&&historyLocks.empty()&&historyChildCanLock(lock));
        assert([files isEqual:historyDiskBytes(root)]&&Current::sTLinkRunHistoryPersistenceFailures==failures+1);
        NSDictionary *last=Current::sTLinkRunHistoryLastPersistenceFailure;
        assert([last[@"operation"] isEqualToString:beginning?@"begin":@"finish"]&&[last[@"stage"] isEqualToString:@"read"]&&[last[@"code"] isEqualToString:@"invalid_index"]);
        // Explicit fixture repair, not automatic production reconstruction/replay.
        assert([healthy writeToFile:path atomically:YES]);assert(historyMutation(beginning).count&&historyEvents.count==events+1);
        assert([historyDiagnostics()[@"failure_count"] unsignedLongLongValue]==failures+1);
    }}
    // Permission/read failures, an unexpected error domain and missing NSError
    // all preserve the real index. Existing exception tests cover NS/C++ unwind.
    for(bool beginning:{true,false})for(unsigned fault=1;fault<=3;++fault){
        NSDictionary *files=historyDiskBytes(root);const NSUInteger events=historyEvents.count;const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
        [historyWriteAttempts removeAllObjects];historyMutationReadFault=fault;NSDictionary *result=historyMutation(beginning);historyMutationReadFault=0;
        assert(!result.count&&historyEvents.count==events&&!historyWriteAttempts.count&&[files isEqual:historyDiskBytes(root)]&&historyLocks.empty()&&historyChildCanLock(lock));
        assert(Current::sTLinkRunHistoryPersistenceFailures==failures+1&&[Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"read_failed"]);
        assert(historyMutation(beginning).count&&historyEvents.count==events+1);
    }
    // Real unreadable path (directory) must not be mistaken for a missing file.
    NSData *healthy=[NSData dataWithContentsOfFile:path];assert([fm removeItemAtPath:path error:nil]);
    assert([fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
    for(bool beginning:{true,false}){
        NSDictionary *files=historyDiskBytes(root);const NSUInteger events=historyEvents.count;[historyWriteAttempts removeAllObjects];
        assert(!historyMutation(beginning).count&&historyEvents.count==events&&!historyWriteAttempts.count&&[files isEqual:historyDiskBytes(root)]&&historyLocks.empty()&&historyChildCanLock(lock));
        BOOL directory=NO;assert([fm fileExistsAtPath:path isDirectory:&directory]&&directory);
        assert([Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"read_failed"]);
    }
    assert([fm removeItemAtPath:path error:nil]&&[healthy writeToFile:path atomically:YES]);assert(historyMutation(true).count);
    // Valid v1 empty history and extra envelope keys remain accepted.
    NSData *empty=[@"{\"schema\":\"run_history_v1\",\"runs\":[],\"extension\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    for(bool beginning:{true,false}){assert([empty writeToFile:path atomically:YES]);assert(historyMutation(beginning).count);}
    Current::fixtureRoot=savedRoot;
}
static void historyRecoveryReject(bool beginning,NSString *code){
    NSString *path=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
    NSData *index=[NSData dataWithContentsOfFile:path];const NSUInteger events=historyEvents.count;const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
    Current::sTLinkRunHistoryRecovered=NO;[historyWriteAttempts removeAllObjects];
    assert(!historyMutation(beginning).count&&!Current::sTLinkRunHistoryRecovered);
    assert(historyEvents.count==events&&[index isEqual:[NSData dataWithContentsOfFile:path]]&&historyLocks.empty()&&historyRecoveryFds.empty());
    assert(historyChildCanLock([Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"]));
    NSDictionary *last=Current::sTLinkRunHistoryLastPersistenceFailure;
    assert(Current::sTLinkRunHistoryPersistenceFailures==failures+1&&[last[@"operation"] isEqualToString:beginning?@"begin":@"finish"]);
    assert([last[@"stage"] isEqualToString:@"recovery"]&&[last[@"code"] isEqualToString:code]);
}
static void historyRecoveryCases(const char *executable){
    NSString *savedRoot=Current::fixtureRoot;Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"recovery"];
    Current::sTLinkRunHistoryRecovered=NO;NSFileManager *fm=[NSFileManager defaultManager];
    NSString *root=Current::fixtureRoot,*indexPath=[root stringByAppendingPathComponent:@"index.json"];
    NSDictionary *started=Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"interrupted.js",@{});
    assert(started.count);
    NSDictionary *failedStart=Current::TLinkRunHistoryBegin(@"trollstore",@"/bundle",@"committed-failure.js",@{});
    NSString *outside=[historyTestRoot stringByAppendingPathComponent:@"recovery-screen.bin"];NSData *outsideBytes=[@"unchanged screen" dataUsingEncoding:NSUTF8StringEncoding];
    assert([outsideBytes writeToFile:outside atomically:YES]);
    NSDictionary *failed=Current::TLinkRunHistoryFinish(failedStart[@"run_id"],@"failed",@"committed failure",@[@"kept line"],@"",outside,nil,@{});
    assert(failed.count);NSString *metadata=failed[@"failure_evidence"][@"metadata_path"];
    // A false return after index replacement must use the NEW committed index.
    historyWriteStage=@"index";historyWriteFault=4;assert(!Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"uncertain-recovery.js",@{}).count);historyWriteStage=nil;historyWriteFault=0;
    NSDictionary *uncertain=historyReadJSON(indexPath)[@"runs"][0];
    // Make the final mutation fail before index replacement. No later public
    // mutation in this process runs before the new executable's recovery pass.
    NSData *indexBefore=[NSData dataWithContentsOfFile:indexPath];const NSUInteger eventsBefore=historyEvents.count;
    historyWriteStage=@"index";historyWriteFault=1;
    assert(!Current::TLinkRunHistoryFinish(started[@"run_id"],@"failed",@"uncommitted error",@[@"line"],@"",@"",nil,@{}).count);
    historyWriteStage=nil;historyWriteFault=0;
    assert([indexBefore isEqual:[NSData dataWithContentsOfFile:indexPath]]&&historyEvents.count==eventsBefore);
    assert([historyReadJSON(started[@"record_path"])[@"state"] isEqualToString:@"failed"]);
    NSString *orphanEvidence=[Current::TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[started[@"run_id"] stringByAppendingString:@".json"]];
    NSData *orphanEvidenceBytes=[NSData dataWithContentsOfFile:orphanEvidence];assert(orphanEvidenceBytes);
    assert([fm removeItemAtPath:metadata error:nil]);assert([[@"truncated" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:failed[@"record_path"] atomically:YES]);
    assert([fm removeItemAtPath:uncertain[@"record_path"] error:nil]);
    NSString *orphan=[Current::TLinkRunHistoryRunsPath() stringByAppendingPathComponent:@"orphan.json"];NSData *orphanBytes=[@"orphan stays" dataUsingEncoding:NSUTF8StringEncoding];assert([orphanBytes writeToFile:orphan atomically:YES]);
    // A new executable process starts with a fresh gate and uses public begin.
    const char *base=historyTestRoot.fileSystemRepresentation;char mode[]="--recover";
    char *args[]={const_cast<char *>(executable),const_cast<char *>(base),mode,nullptr};pid_t child=0;
    assert(::posix_spawn(&child,executable,nullptr,nullptr,args,environ)==0);int status=0;pid_t waited;
    do{waited=::waitpid(child,&status,0);}while(waited<0&&errno==EINTR);assert(waited==child&&WIFEXITED(status)&&WEXITSTATUS(status)==0);
    assert([historyReadJSON(started[@"record_path"]) isEqual:started]);
    assert([historyReadJSON(failed[@"record_path"]) isEqual:failed]&&[historyReadJSON(metadata) isEqual:failed[@"failure_evidence"]]);
    assert([historyReadJSON(uncertain[@"record_path"]) isEqual:uncertain]);
    assert([orphanEvidenceBytes isEqual:[NSData dataWithContentsOfFile:orphanEvidence]]&&[orphanBytes isEqual:[NSData dataWithContentsOfFile:orphan]]&&[outsideBytes isEqual:[NSData dataWithContentsOfFile:outside]]);
    // Both public entries block on false/NS/C++/post-write failures, then retry.
    for(bool beginning:{true,false})for(NSString *stage in @[@"record",@"evidence"])for(unsigned fault=1;fault<=4;++fault){
        NSString *target=[stage isEqualToString:@"record"]?started[@"record_path"]:metadata;
        assert([fm removeItemAtPath:target error:nil]);historyWriteStage=stage;historyWriteFault=fault;
        historyRecoveryReject(beginning,(fault==1||fault==4)?@"recovery_write_failed":@"exception");
        assert(historyWriteAttempts.count==1);historyWriteStage=nil;historyWriteFault=0;
        assert(historyMutation(beginning).count&&Current::sTLinkRunHistoryRecovered&&historyRecoveryFds.empty());
        assert([historyReadJSON(target) isEqual:[stage isEqualToString:@"record"]?started:failed[@"failure_evidence"]]);
    }
    // Repeated READ faults and exceptional unwind never retain an artifact FD.
    for(unsigned fault=2;fault<=5;++fault){
        historyRecoveryReadFault=fault;historyRecoveryReject(true,fault<=3?@"recovery_read_failed":@"exception");historyRecoveryReadFault=0;
        assert(!historyWriteAttempts.count&&historyMutation(true).count);
    }
    historyRecoveryOpenFault=true;historyRecoveryReject(false,@"recovery_read_failed");historyRecoveryOpenFault=false;assert(historyMutation(false).count);
    historyRecoveryStatFault=true;historyRecoveryReject(true,@"recovery_read_failed");historyRecoveryStatFault=false;assert(historyMutation(true).count);
    // EINTR and short positive reads preserve logical JSON and make no repairs.
    Current::sTLinkRunHistoryRecovered=NO;historyRecoveryReadFault=1;const size_t reads=historyRecoveryReads;[historyWriteAttempts removeAllObjects];
    assert(historyMutation(true).count&&historyRecoveryReads>reads+1&&historyWriteAttempts.count==2&&historyRecoveryFds.empty());historyRecoveryReadFault=0;
    // Large mismatching files are replaced without reading their full length.
    NSMutableData *large=[NSMutableData dataWithLength:8*1024*1024];assert([large writeToFile:started[@"record_path"] atomically:YES]);
    Current::sTLinkRunHistoryRecovered=NO;historyRecoveryBytes=0;assert(historyMutation(true).count&&historyRecoveryBytes<1024*1024);
    assert([historyReadJSON(started[@"record_path"]) isEqual:started]);
    NSMutableData *invalidJSON=[NSMutableData dataWithLength:[NSData dataWithContentsOfFile:started[@"record_path"]].length];
    assert([invalidJSON writeToFile:started[@"record_path"] atomically:YES]);Current::sTLinkRunHistoryRecovered=NO;
    assert(historyMutation(true).count&&[historyReadJSON(started[@"record_path"]) isEqual:started]);
    // Leaf symlinks and directories are rejected without modifying the target.
    NSString *target=started[@"record_path"];NSData *targetBytes=[NSData dataWithContentsOfFile:target];assert([fm removeItemAtPath:target error:nil]);
    assert(::symlink(outside.fileSystemRepresentation,target.fileSystemRepresentation)==0);historyRecoveryReject(true,@"recovery_read_failed");
    assert([outsideBytes isEqual:[NSData dataWithContentsOfFile:outside]]&&::unlink(target.fileSystemRepresentation)==0);
    assert([fm createDirectoryAtPath:target withIntermediateDirectories:NO attributes:nil error:nil]);historyRecoveryReject(false,@"recovery_read_failed");
    assert([fm removeItemAtPath:target error:nil]);assert(::mkfifo(target.fileSystemRepresentation,0600)==0);historyRecoveryReject(true,@"recovery_read_failed");
    assert(::unlink(target.fileSystemRepresentation)==0&&[targetBytes writeToFile:target atomically:YES]);assert(historyMutation(true).count);
    // A bad LAST record must be rejected before repairing a damaged first file.
    NSData *healthy=[NSData dataWithContentsOfFile:indexPath];NSDictionary *index=historyReadJSON(indexPath);NSArray *runs=index[@"runs"];
    NSString *firstPath=runs[0][@"record_path"];NSDictionary *first=historyReadJSON(firstPath);
    assert([[@"damaged first file" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:firstPath atomically:YES]);
    for(unsigned invalid=0;invalid<8;++invalid){
        NSMutableArray *bad=[runs mutableCopy];NSMutableDictionary *last=[bad.lastObject mutableCopy];
        if(invalid==0)last[@"record_path"]=outside;
        if(invalid==1)last[@"schema"]=@"future";
        if(invalid==2)last[@"failure_evidence"]=[NSNull null];
        if(invalid>=3&&invalid<=5){
            NSMutableDictionary *evidence=[failed[@"failure_evidence"] mutableCopy];evidence[@"run_id"]=last[@"run_id"];
            evidence[@"metadata_path"]=[Current::TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[last[@"run_id"] stringByAppendingString:@".json"]];
            if(invalid==3)evidence[@"metadata_path"]=outside;
            if(invalid==4)evidence[@"run_id"]=@"different";
            if(invalid==5)evidence[@"schema"]=@"future";
            last[@"failure_evidence"]=evidence;
        }
        bad[bad.count-1]=last;
        if(invalid>=6){
            [bad removeAllObjects];
            for(unsigned n=0;n<(invalid==6?2U:51U);++n){
                NSMutableDictionary *item=[started mutableCopy];NSString *identity=invalid==6?(n?@"shared?a":@"shared/a"):[NSString stringWithFormat:@"limit-%u",n];
                item[@"run_id"]=identity;item[@"record_path"]=[Current::TLinkRunHistoryRunsPath() stringByAppendingPathComponent:[Current::TLinkRunHistorySanitize(identity) stringByAppendingString:@".json"]];[bad addObject:item];
            }
        }
        NSMutableDictionary *changed=[index mutableCopy];changed[@"runs"]=bad;
        NSData *bytes=[NSJSONSerialization dataWithJSONObject:changed options:0 error:nil];assert([bytes writeToFile:indexPath atomically:YES]);
        NSDictionary *files=historyPayloadBytes(root);const size_t opens=historyRecoveryOpens;historyRecoveryReject(true,@"recovery_invalid_index");
        assert(historyRecoveryOpens==opens&&!historyWriteAttempts.count&&[files isEqual:historyPayloadBytes(root)]&&historyPendingSize()==1);
    }
    assert([healthy writeToFile:indexPath atomically:YES]);assert(historyMutation(true).count&&[first isEqual:historyReadJSON(firstPath)]);
    // Directory symlinks must not redirect even an empty recovery set.
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"recovery-parent"];Current::TLinkRunHistoryEnsureDirectories();
    NSString *linked=Current::TLinkRunHistoryEvidencePath(),*destination=[historyTestRoot stringByAppendingPathComponent:@"outside-metadata"];
    assert([fm createDirectoryAtPath:destination withIntermediateDirectories:NO attributes:nil error:nil]);assert([fm removeItemAtPath:linked error:nil]);
    assert(::symlink(destination.fileSystemRepresentation,linked.fileSystemRepresentation)==0);
    NSData *empty=[@"{\"schema\":\"run_history_v1\",\"runs\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
    assert([empty writeToFile:[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"] atomically:YES]);
    historyRecoveryReject(true,@"recovery_read_failed");assert(![fm contentsOfDirectoryAtPath:destination error:nil].count);
    assert(::unlink(linked.fileSystemRepresentation)==0);assert(historyMutation(true).count);
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=YES;
}
static void historyInProcessRecoveryCases(){
    NSString *savedRoot=Current::fixtureRoot,*base=[historyTestRoot stringByAppendingPathComponent:@"in-process"];
    NSString *screen=[historyTestRoot stringByAppendingPathComponent:@"in-process-screen.bin"];NSData *screenBytes=[@"untouched screen" dataUsingEncoding:NSUTF8StringEncoding];
    assert([screenBytes writeToFile:screen atomically:YES]);
    for(bool beginning:{true,false})for(NSString *stage in (beginning?@[@"record",@"index"]:@[@"evidence",@"record",@"index"]))for(unsigned fault=1;fault<=6;++fault){@autoreleasepool{
        Current::fixtureRoot=[base stringByAppendingPathComponent:[NSString stringWithFormat:@"%d-%@-%u",beginning,stage,fault]];
        Current::sTLinkRunHistoryRecovered=NO;
        NSDictionary *anchor=Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"anchor.js",@{});
        NSDictionary *start=Current::TLinkRunHistoryBegin(@"trollstore",@"/bundle",@"target.js",@{});
        NSDictionary *target=Current::TLinkRunHistoryFinish(start[@"run_id"],@"failed",@"old error",@[@"old line"],@"",screen,nil,@{});
        assert(anchor.count&&target.count&&Current::sTLinkRunHistoryRecovered);
        NSString *indexPath=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
        NSData *before=[NSData dataWithContentsOfFile:indexPath];const NSUInteger events=historyEvents.count;const size_t opens=historyRecoveryOpens;
        const uint64_t savedFailures=Current::sTLinkRunHistoryPersistenceFailures;
        const bool saturated=!beginning&&[stage isEqualToString:@"index"]&&fault==6;
        if(saturated)Current::sTLinkRunHistoryPersistenceFailures=UINT64_MAX;
        const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
        [historyWriteAttempts removeAllObjects];historyWriteStage=stage;historyWriteFault=fault;
        NSDictionary *result=beginning?Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"failed-begin.js",@{}):
            Current::TLinkRunHistoryFinish(start[@"run_id"],@"failed",@"new error",@[@"new line"],@"",screen,nil,@{});
        historyWriteStage=nil;historyWriteFault=0;
        assert(!result.count&&!Current::sTLinkRunHistoryRecovered&&historyRecoveryOpens==opens&&historyEvents.count==events);
        assert(Current::sTLinkRunHistoryPersistenceFailures==(saturated?UINT64_MAX:failures+1));
        NSDictionary *diagnostic=Current::sTLinkRunHistoryLastPersistenceFailure;
        assert([diagnostic[@"operation"] isEqualToString:beginning?@"begin":@"finish"]&&[diagnostic[@"stage"] isEqualToString:stage]);
        assert([diagnostic[@"code"] isEqualToString:(fault==1||fault==4)?@"write_failed":@"exception"]);
        NSData *committed=[NSData dataWithContentsOfFile:indexPath];const bool replaced=[stage isEqualToString:@"index"]&&fault>=4;
        assert([before isEqual:committed]!=replaced);
        NSArray *authoritative=historyReadJSON(indexPath)[@"runs"];
        NSDictionary *expectedTarget=nil;NSMutableSet *referenced=[NSMutableSet set];
        for(NSDictionary *run in authoritative){
            [referenced addObject:run[@"record_path"]];NSDictionary *evidence=run[@"failure_evidence"];
            if(evidence.count)[referenced addObject:evidence[@"metadata_path"]];
            if([run[@"run_id"] isEqualToString:target[@"run_id"]])expectedTarget=run;
        }
        assert(expectedTarget&&[expectedTarget[@"error"] isEqualToString:(!beginning&&replaced)?@"new error":@"old error"]);
        // Status alone must neither clear the dirty gate nor access artifacts.
        assert(Current::TLinkRunHistorySnapshot(50).count&&!Current::sTLinkRunHistoryRecovered&&historyRecoveryOpens==opens);
        assert([committed isEqual:[NSData dataWithContentsOfFile:indexPath]]&&historyEvents.count==events);
        NSMutableDictionary *orphans=[NSMutableDictionary dictionary];NSDictionary *files=historyDiskBytes(Current::fixtureRoot);
        for(NSString *relative in files){
            NSString *path=[Current::fixtureRoot stringByAppendingPathComponent:relative];
            if(([relative hasPrefix:@"runs/"]||[relative hasPrefix:@"evidence/"])&&![referenced containsObject:path])orphans[path]=files[relative];
        }
        // Corrupt another retained record so every case requires a real repair,
        // while preserving the failed operation's own old/new artifact versions.
        assert([[@"damaged anchor" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:anchor[@"record_path"] atomically:YES]);
        if([stage isEqualToString:@"index"]&&fault==4){
            if(beginning)historyRecoveryReadFault=2;else{historyWriteStage=@"record";historyWriteFault=1;}
            historyRecoveryReject(!beginning,beginning?@"recovery_read_failed":@"recovery_write_failed");
            historyRecoveryReadFault=0;historyWriteStage=nil;historyWriteFault=0;
            assert(!Current::sTLinkRunHistoryRecovered);
        }
        const uint64_t beforeRetry=Current::sTLinkRunHistoryPersistenceFailures;
        NSDictionary *next=beginning?Current::TLinkRunHistoryFinish(@"different-call",@"finished",@"",@[],@"",@"",nil,@{}):
            Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"different-call.js",@{});
        assert(next.count&&Current::sTLinkRunHistoryRecovered&&historyRecoveryOpens>opens&&historyEvents.count==events+1);
        assert(Current::sTLinkRunHistoryPersistenceFailures==beforeRetry&&historyRecoveryFds.empty()&&historyLocks.empty());
        assert(historyChildCanLock([Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"]));
        for(NSDictionary *run in authoritative){
            assert([historyReadJSON(run[@"record_path"]) isEqual:run]);NSDictionary *evidence=run[@"failure_evidence"];
            if(evidence.count)assert([historyReadJSON(evidence[@"metadata_path"]) isEqual:evidence]);
        }
        for(NSString *path in orphans)assert([orphans[path] isEqual:[NSData dataWithContentsOfFile:path]]);
        assert([screenBytes isEqual:[NSData dataWithContentsOfFile:screen]]);
        assert([historyEvents.lastObject[@"payload"][@"run_id"] isEqual:next[@"run_id"]]);
        const size_t cleanOpens=historyRecoveryOpens;const NSUInteger cleanEvents=historyEvents.count;[historyWriteAttempts removeAllObjects];
        assert(Current::TLinkRunHistoryFinish(@"clean-followup",@"finished",@"",@[],@"",@"",nil,@{}).count);
        assert(historyRecoveryOpens==cleanOpens&&historyWriteAttempts.count==2&&historyEvents.count==cleanEvents+1&&Current::sTLinkRunHistoryRecovered);
        if(saturated)Current::sTLinkRunHistoryPersistenceFailures=savedFailures;
    }}
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=YES;
}
static void historyControlSend(int fd,char value){
    ssize_t count;do{count=::write(fd,&value,1);}while(count<0&&errno==EINTR);assert(count==1);
}
static char historyControlRead(int fd){
    char value=0;ssize_t count;do{count=::read(fd,&value,1);}while(count<0&&errno==EINTR);assert(count==1);return value;
}
static void historyWaitExit(pid_t pid,int expected){
    int status=0;pid_t waited;do{waited=::waitpid(pid,&status,0);}while(waited<0&&errno==EINTR);
    assert(waited==pid&&WIFEXITED(status)&&WEXITSTATUS(status)==expected);
}
static int historyMarkerWorker(int channel,NSString *root){
    Current::fixtureRoot=root;historyUUIDs=500000;
    assert(Current::TLinkRunHistoryBegin(@"trollstore",@"/bundle",@"worker-warm.js",@{}).count);
    assert(Current::sTLinkRunHistoryRecovered&&historyPendingSize()==0);historyControlSend(channel,'R');
    assert(historyControlRead(channel)=='N');const size_t before=historyRecoveryOpens;
    // No local failure or flag reset: the other owner left the held inode dirty.
    assert(Current::sTLinkRunHistoryRecovered&&historyPendingSize()==1);
    assert(Current::TLinkRunHistoryBegin(@"trollstore",@"/bundle",@"worker-after-peer.js",@{}).count);
    assert(historyRecoveryOpens>before&&Current::sTLinkRunHistoryRecovered&&historyPendingSize()==0&&historyEvents.count==2);
    historyControlSend(channel,'D');assert(historyControlRead(channel)=='C');const size_t clean=historyRecoveryOpens;
    assert(Current::TLinkRunHistoryBegin(@"trollstore",@"/bundle",@"worker-clean.js",@{}).count);
    assert(historyRecoveryOpens==clean&&historyEvents.count==3&&historyPendingSize()==0);historyControlSend(channel,'C');
    assert(historyControlRead(channel)=='Q');assert(historyLocks.empty()&&historyRecoveryFds.empty());::close(channel);return 0;
}
static void historyCrossProcessCases(const char *executable){
    NSString *savedRoot=Current::fixtureRoot;NSFileManager *fm=[NSFileManager defaultManager];
    for(unsigned scenario=0;scenario<6;++scenario){@autoreleasepool{
        Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"cross-owner-%u",scenario]];Current::sTLinkRunHistoryRecovered=NO;
        NSDictionary *start=Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"peer-target.js",@{});
        NSDictionary *old=Current::TLinkRunHistoryFinish(start[@"run_id"],@"failed",@"old peer error",@[@"old peer line"],@"",@"",nil,@{});
        assert(old.count&&Current::sTLinkRunHistoryRecovered&&historyPendingSize()==0);
        NSString *lockPath=[Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"],*indexPath=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
        struct stat original;assert(::stat(lockPath.fileSystemRepresentation,&original)==0);
        int channel[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,channel)==0);
        struct timeval timeout={20,0};for(int fd:channel){assert(::setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout))==0);assert(::setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout))==0);}
        NSString *descriptor=[NSString stringWithFormat:@"%d",channel[1]];char workerMode[]="--marker-worker";
        char *args[]={const_cast<char *>(executable),const_cast<char *>(historyTestRoot.fileSystemRepresentation),workerMode,const_cast<char *>(descriptor.UTF8String),const_cast<char *>(Current::fixtureRoot.fileSystemRepresentation),nullptr};
        posix_spawn_file_actions_t actions;assert(::posix_spawn_file_actions_init(&actions)==0);assert(::posix_spawn_file_actions_addclose(&actions,channel[0])==0);
        pid_t worker=0;assert(::posix_spawn(&worker,executable,&actions,nullptr,args,environ)==0);assert(::posix_spawn_file_actions_destroy(&actions)==0);::close(channel[1]);
        assert(historyControlRead(channel[0])=='R'&&Current::sTLinkRunHistoryRecovered);
        const NSUInteger events=historyEvents.count;NSData *before=[NSData dataWithContentsOfFile:indexPath];
        if(scenario<4){
            const unsigned faults[]={1,4,5,6};historyWriteStage=@"index";historyWriteFault=faults[scenario];
            assert(!Current::TLinkRunHistoryFinish(start[@"run_id"],@"failed",@"new peer error",@[@"new peer line"],@"",@"",nil,@{}).count);historyWriteStage=nil;historyWriteFault=0;
        }else{
            char crashMode[]="--marker-crash";NSString *phase=scenario==4?@"1":@"2";
            char *crashArgs[]={const_cast<char *>(executable),const_cast<char *>(historyTestRoot.fileSystemRepresentation),crashMode,const_cast<char *>(Current::fixtureRoot.fileSystemRepresentation),const_cast<char *>([start[@"run_id"] UTF8String]),const_cast<char *>(phase.UTF8String),nullptr};
            pid_t writer=0;assert(::posix_spawn(&writer,executable,nullptr,nullptr,crashArgs,environ)==0);historyWaitExit(writer,scenario==4?81:82);
            assert(Current::sTLinkRunHistoryRecovered); // warm parent also saw no local error
        }
        assert(historyPendingSize()==1&&historyEvents.count==events);
        const bool replaced=(scenario>0&&scenario!=4);assert([before isEqual:[NSData dataWithContentsOfFile:indexPath]]!=replaced);
        NSArray *committed=historyReadJSON(indexPath)[@"runs"];NSDictionary *expected=nil;
        for(NSDictionary *run in committed)if([run[@"run_id"] isEqual:start[@"run_id"]])expected=run;
        assert(expected&&[expected[@"error"] isEqualToString:replaced?@"new peer error":@"old peer error"]);
        assert([historyReadJSON(old[@"record_path"])[@"error"] isEqualToString:@"new peer error"]);
        // Damage a second retained record; the warm peer must perform repairs.
        NSDictionary *other=committed[0];assert(![other[@"run_id"] isEqual:start[@"run_id"]]);assert([fm removeItemAtPath:other[@"record_path"] error:nil]);
        historyControlSend(channel[0],'N');assert(historyControlRead(channel[0])=='D');
        for(NSDictionary *run in committed){
            assert([historyReadJSON(run[@"record_path"]) isEqual:run]);NSDictionary *evidence=run[@"failure_evidence"];
            if(evidence.count)assert([historyReadJSON(evidence[@"metadata_path"]) isEqual:evidence]);
        }
        struct stat after;assert(::stat(lockPath.fileSystemRepresentation,&after)==0&&after.st_ino==original.st_ino&&after.st_dev==original.st_dev&&after.st_size==0);
        assert(historyEvents.count==events&&historyLocks.empty()&&historyRecoveryFds.empty());
        historyControlSend(channel[0],'C');assert(historyControlRead(channel[0])=='C');historyControlSend(channel[0],'Q');::close(channel[0]);historyWaitExit(worker,0);
    }}
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=YES;
}
static void historyMarkerFaultCases(){
    NSString *savedRoot=Current::fixtureRoot;Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"marker-faults"];Current::sTLinkRunHistoryRecovered=NO;
    assert(historyMutation(true).count&&historyPendingSize()==0);
    for(bool beginning:{true,false})for(unsigned fault:{1U,3U}){
        NSDictionary *payload=historyPayloadBytes(Current::fixtureRoot);const NSUInteger events=historyEvents.count;
        [historyWriteAttempts removeAllObjects];historyMarkerFaultLength=1;historyMarkerFault=fault;
        assert(!historyMutation(beginning).count&&!Current::sTLinkRunHistoryRecovered&&historyEvents.count==events&&!historyWriteAttempts.count);
        assert([payload isEqual:historyPayloadBytes(Current::fixtureRoot)]&&historyPendingSize()==(fault==1?0:1));
        assert([Current::sTLinkRunHistoryLastPersistenceFailure[@"stage"] isEqualToString:@"intent"]);
        assert([Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"history_marker_write_failed"]);
        historyMarkerFault=0;historyMarkerFaultLength=-1;assert(historyMutation(beginning).count&&historyPendingSize()==0&&Current::sTLinkRunHistoryRecovered);
    }
    for(bool beginning:{true,false})for(unsigned fault:{1U,3U}){
        const NSUInteger events=historyEvents.count;const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
        historyMarkerFaultLength=0;historyMarkerFault=fault;NSDictionary *committed=historyMutation(beginning);
        assert(committed.count&&historyEvents.count==events+1&&!Current::sTLinkRunHistoryRecovered&&historyPendingSize()==(fault==1?1:0));
        assert(Current::sTLinkRunHistoryPersistenceFailures==failures+1&&[Current::sTLinkRunHistoryLastPersistenceFailure[@"stage"] isEqualToString:@"commit_marker"]);
        assert([historyReadJSON(committed[@"record_path"]) isEqual:committed]);
        historyMarkerFault=0;historyMarkerFaultLength=-1;const size_t opens=historyRecoveryOpens;
        assert(historyMutation(true).count&&historyRecoveryOpens>opens&&Current::sTLinkRunHistoryRecovered&&historyPendingSize()==0);
    }
    for(off_t length:{(off_t)1,(off_t)0}){
        const size_t calls=historyMarkerChanges;const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
        historyMarkerFaultLength=length;historyMarkerFault=2;assert(historyMutation(true).count);
        assert(historyMarkerChanges==calls+3&&historyPendingSize()==0&&Current::sTLinkRunHistoryPersistenceFailures==failures);historyMarkerFaultLength=-1;
    }
    NSDictionary *payload=historyPayloadBytes(Current::fixtureRoot);const NSUInteger events=historyEvents.count;[historyWriteAttempts removeAllObjects];
    historyMarkerStatFault=true;assert(!historyMutation(true).count&&!Current::sTLinkRunHistoryRecovered);historyMarkerStatFault=false;
    assert(!historyWriteAttempts.count&&historyEvents.count==events&&[payload isEqual:historyPayloadBytes(Current::fixtureRoot)]);
    assert([Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"history_marker_read_failed"]);
    assert(historyMutation(true).count&&historyPendingSize()==0);
    NSString *lockPath=[Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"];
    int fd=Current::TLinkRunHistoryAcquireFileLock();assert(fd>=0&&::ftruncate(fd,2)==0);Current::TLinkRunHistoryReleaseFileLock(fd);
    payload=historyPayloadBytes(Current::fixtureRoot);const size_t opens=historyRecoveryOpens;[historyWriteAttempts removeAllObjects];
    assert(!historyMutation(true).count&&historyPendingSize()==2&&!historyWriteAttempts.count&&historyRecoveryOpens==opens);
    assert([payload isEqual:historyPayloadBytes(Current::fixtureRoot)]&&[Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"history_marker_invalid"]);
    assert(Current::TLinkRunHistorySnapshot(50).count&&historyPendingSize()==2&&!Current::sTLinkRunHistoryRecovered);
    fd=Current::TLinkRunHistoryAcquireFileLock();assert(fd>=0&&::ftruncate(fd,0)==0);Current::TLinkRunHistoryReleaseFileLock(fd);assert(historyMutation(true).count);
    NSString *alias=[historyTestRoot stringByAppendingPathComponent:@"lock-hardlink"];assert(::link(lockPath.fileSystemRepresentation,alias.fileSystemRepresentation)==0);
    [historyWriteAttempts removeAllObjects];assert(!historyMutation(true).count&&!historyWriteAttempts.count&&historyPendingSize()==0);
    assert([Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"history_marker_invalid"]);
    assert(::unlink(alias.fileSystemRepresentation)==0);assert(historyMutation(true).count);
    NSString *backup=[lockPath stringByAppendingString:@".saved"],*outside=[historyTestRoot stringByAppendingPathComponent:@"marker-outside.bin"];
    NSData *outsideBytes=[@"do not truncate" dataUsingEncoding:NSUTF8StringEncoding];assert([outsideBytes writeToFile:outside atomically:YES]);
    assert(::rename(lockPath.fileSystemRepresentation,backup.fileSystemRepresentation)==0&&::symlink(outside.fileSystemRepresentation,lockPath.fileSystemRepresentation)==0);
    [historyWriteAttempts removeAllObjects];assert(!historyMutation(true).count&&!historyWriteAttempts.count&&[outsideBytes isEqual:[NSData dataWithContentsOfFile:outside]]);
    assert(::unlink(lockPath.fileSystemRepresentation)==0&&::mkfifo(lockPath.fileSystemRepresentation,0600)==0);
    assert(!historyMutation(true).count&&!historyWriteAttempts.count);
    assert(::unlink(lockPath.fileSystemRepresentation)==0&&::rename(backup.fileSystemRepresentation,lockPath.fileSystemRepresentation)==0);
    assert(historyMutation(true).count&&historyPendingSize()==0&&historyLocks.empty()&&historyRecoveryFds.empty());
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=YES;
}
// Seed authoritative, canonical retained records without replaying lifecycle events.
static NSMutableArray *historyRetirementSeed(NSString *label){
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:label];Current::TLinkRunHistoryEnsureDirectories();
    NSMutableArray *runs=[NSMutableArray array];
    for(unsigned n=0;n<50;++n){
        NSString *runId=[NSString stringWithFormat:@"retire-%u",n];
        NSString *record=[Current::TLinkRunHistoryRunsPath() stringByAppendingPathComponent:[runId stringByAppendingString:@".json"]];
        NSString *metadata=[Current::TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[runId stringByAppendingString:@".json"]];
        NSString *shot=[Current::TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[runId stringByAppendingString:@".png"]];
        NSDictionary *evidence=@{@"schema":Current::TLinkFailureEvidenceSchemaV1,@"run_id":runId,@"metadata_path":metadata,@"screenshot_path":shot};
        NSDictionary *item=@{@"schema":Current::TLinkRunHistorySchemaV1,@"run_id":runId,@"record_path":record,@"state":@"failed",@"failure_evidence":evidence};
        assert(Current::TLinkRunHistoryWriteJSON(item,record)&&Current::TLinkRunHistoryWriteJSON(evidence,metadata));
        assert([[@"owned screenshot" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:shot atomically:YES]);[runs addObject:item];
    }
    assert(Current::TLinkRunHistoryWriteIndex(runs));Current::sTLinkRunHistoryRecovered=YES;return runs;
}
static void historyPruneOwned(NSArray *retired,NSArray *retained){
    const int fd=Current::TLinkRunHistoryAcquireFileLock();assert(fd>=0);
    @try{Current::TLinkRunHistoryPrune(retired,retained);}@finally{Current::TLinkRunHistoryReleaseFileLock(fd);}
    assert(historyLocks.empty());
}
static void historyRetirementCases(){
    NSString *savedRoot=Current::fixtureRoot;const BOOL savedReady=Current::sTLinkRunHistoryRecovered;NSFileManager *fm=[NSFileManager defaultManager];
    for(bool beginning:{true,false})for(unsigned fault=0;fault<=6;++fault){@autoreleasepool{
        NSMutableArray *runs=historyRetirementSeed([NSString stringWithFormat:@"retirement-%u-%u",(unsigned)beginning,fault]);
        NSDictionary *victim=runs.lastObject,*evidence=victim[@"failure_evidence"];
        NSArray *paths=@[victim[@"record_path"],evidence[@"metadata_path"],evidence[@"screenshot_path"]];
        if(fault==6)for(NSString *path in paths)assert(::unlink(path.fileSystemRepresentation)==0);
        const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;const NSUInteger events=historyEvents.count;
        NSString *lock=[Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"];struct stat before,after;
        const int seedLock=Current::TLinkRunHistoryAcquireFileLock();assert(seedLock>=0);Current::TLinkRunHistoryReleaseFileLock(seedLock);
        assert(::stat(lock.fileSystemRepresentation,&before)==0);
        [historyPruneAttempts removeAllObjects];historyPruneTarget=paths[0];historyPruneFault=fault==6?0:fault;
        NSDictionary *committed=beginning?Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"retire.js",@{}):
            Current::TLinkRunHistoryFinish(@"retirement-new",@"finished",@"",@[],@"",@"",nil,@{});
        historyPruneFault=0;historyPruneTarget=nil;
        assert(committed.count&&historyEvents.count==events+1&&historyLocks.empty()&&Current::sTLinkRunHistoryRecovered&&historyPendingSize()==0);
        assert(historyChildCanLock(lock)&&::stat(lock.fileSystemRepresentation,&after)==0&&after.st_nlink==1&&before.st_ino==after.st_ino&&before.st_dev==after.st_dev);
        NSArray *indexed=historyReadJSON([Current::fixtureRoot stringByAppendingPathComponent:@"index.json"])[@"runs"];
        assert(indexed.count==50&&[indexed[0] isEqual:committed]);
        for(NSDictionary *item in indexed)assert(![item[@"run_id"] isEqualToString:victim[@"run_id"]]);
        const bool exceptional=fault==1||fault==2,failed=exceptional||fault==3||fault==5;
        assert(Current::sTLinkRunHistoryPersistenceFailures==failures+(failed?1:0));
        if(failed){NSDictionary *last=Current::sTLinkRunHistoryLastPersistenceFailure;
            assert([last[@"operation"] isEqualToString:@"prune"]&&[last[@"stage"] isEqualToString:@"artifacts"]);
            assert([last[@"code"] isEqualToString:exceptional?@"exception":@"remove_failed"]);
        }
        assert(historyPruneAttempts.count==(exceptional?1:(fault==4?4:3)));
        for(NSUInteger n=0;n<paths.count;++n)assert([fm fileExistsAtPath:paths[n]]==(exceptional||(fault==3&&n==0)));
        // A cleanup failure is reported once; a later mutation does not rediscover retired orphans.
        const size_t opens=historyRecoveryOpens;[historyPruneAttempts removeAllObjects];
        assert(Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"next-retire.js",@{}).count&&historyRecoveryOpens==opens);
        assert(Current::sTLinkRunHistoryPersistenceFailures==failures+(failed?1:0));
        if(fault==3)assert([fm fileExistsAtPath:paths[0]]);
    }}
    // Old/corrupted path claims must never retire control files, directories, arbitrary leaves or outside files.
    NSMutableArray *runs=historyRetirementSeed(@"retirement-ownership");NSDictionary *victim=runs.lastObject;
    NSString *record=victim[@"record_path"],*metadata=victim[@"failure_evidence"][@"metadata_path"],*shot=victim[@"failure_evidence"][@"screenshot_path"];
    NSString *index=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"],*lock=[Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"];
    int fd=Current::TLinkRunHistoryAcquireFileLock();assert(fd>=0);Current::TLinkRunHistoryReleaseFileLock(fd);
    NSString *outside=[historyTestRoot stringByAppendingPathComponent:@"outside-history.log"];
    NSData *outsideBytes=[@"outside remains" dataUsingEncoding:NSUTF8StringEncoding];assert([outsideBytes writeToFile:outside atomically:YES]);
    NSString *orphan=[Current::TLinkRunHistoryRunsPath() stringByAppendingPathComponent:@"unrelated.json"];
    assert([outsideBytes writeToFile:orphan atomically:YES]);
    for(NSString *path in @[index,lock,Current::TLinkRunHistoryRunsPath(),Current::TLinkRunHistoryEvidencePath(),orphan]){
        const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;NSDictionary *before=historyDiskBytes(Current::fixtureRoot);
        [historyPruneAttempts removeAllObjects];historyPruneOwned(@[@{@"run_id":victim[@"run_id"],@"record_path":path}],@[]);
        assert(!historyPruneAttempts.count&&[before isEqual:historyDiskBytes(Current::fixtureRoot)]&&Current::sTLinkRunHistoryPersistenceFailures==failures+1);
        assert([Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"path_not_owned"]);
    }
    const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
    [historyPruneAttempts removeAllObjects];
    historyPruneOwned(@[@{@"run_id":@"external",@"record_path":outside,@"failure_evidence":@{@"metadata_path":[NSNull null],@"screenshot_path":@""}}],@[]);
    assert(!historyPruneAttempts.count&&Current::sTLinkRunHistoryPersistenceFailures==failures&&[outsideBytes isEqual:[NSData dataWithContentsOfFile:outside]]);
    // A reference in ANY retained field protects a leaf, even across run-ID sanitization collisions.
    NSDictionary *bytes=historyDiskBytes(Current::fixtureRoot);[historyPruneAttempts removeAllObjects];
    historyPruneOwned(@[victim],@[@{@"record_path":shot,@"failure_evidence":@{@"metadata_path":record,@"screenshot_path":metadata}}]);
    assert(!historyPruneAttempts.count&&[bytes isEqual:historyDiskBytes(Current::fixtureRoot)]);
    NSString *collision=[Current::TLinkRunHistoryRunsPath() stringByAppendingPathComponent:@"a_b.json"];
    assert([outsideBytes writeToFile:collision atomically:YES]);
    historyPruneOwned(@[@{@"run_id":@"a/b",@"record_path":collision}],@[@{@"run_id":@"a?b",@"record_path":collision}]);
    assert(!historyPruneAttempts.count&&[outsideBytes isEqual:[NSData dataWithContentsOfFile:collision]]);
    // Leaf unlink is nonrecursive and never follows the screenshot symlink's target.
    assert(::unlink(record.fileSystemRepresentation)==0&&[fm createDirectoryAtPath:record withIntermediateDirectories:NO attributes:nil error:nil]);
    NSString *child=[record stringByAppendingPathComponent:@"keep.txt"];assert([outsideBytes writeToFile:child atomically:YES]);
    assert(::unlink(shot.fileSystemRepresentation)==0&&::symlink(outside.fileSystemRepresentation,shot.fileSystemRepresentation)==0);
    historyPruneOwned(@[victim],@[]);struct stat linkInfo;
    assert([outsideBytes isEqual:[NSData dataWithContentsOfFile:child]]&&[outsideBytes isEqual:[NSData dataWithContentsOfFile:outside]]);
    assert(::lstat(shot.fileSystemRepresentation,&linkInfo)!=0&&errno==ENOENT&&![fm fileExistsAtPath:metadata]);
    assert(Current::sTLinkRunHistoryPersistenceFailures==failures+1&&[Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"remove_failed"]);
    // Refuse an evidence-parent symlink even when its target contains the canonical names.
    NSString *evidenceDir=Current::TLinkRunHistoryEvidencePath(),*backup=[evidenceDir stringByAppendingString:@"-backup"];
    NSString *otherDir=[historyTestRoot stringByAppendingPathComponent:@"outside-evidence"];
    assert([fm createDirectoryAtPath:otherDir withIntermediateDirectories:NO attributes:nil error:nil]);
    for(NSString *path in @[metadata,shot])assert([outsideBytes writeToFile:[otherDir stringByAppendingPathComponent:path.lastPathComponent] atomically:YES]);
    assert(::rename(evidenceDir.fileSystemRepresentation,backup.fileSystemRepresentation)==0&&::symlink(otherDir.fileSystemRepresentation,evidenceDir.fileSystemRepresentation)==0);
    const uint64_t parentFailures=Current::sTLinkRunHistoryPersistenceFailures;[historyPruneAttempts removeAllObjects];
    historyPruneOwned(@[@{@"run_id":victim[@"run_id"],@"failure_evidence":victim[@"failure_evidence"]}],@[]);
    assert(!historyPruneAttempts.count&&Current::sTLinkRunHistoryPersistenceFailures==parentFailures+2);
    for(NSString *path in @[metadata,shot])assert([outsideBytes isEqual:[NSData dataWithContentsOfFile:[otherDir stringByAppendingPathComponent:path.lastPathComponent]]]);
    assert(::unlink(evidenceDir.fileSystemRepresentation)==0&&::rename(backup.fileSystemRepresentation,evidenceDir.fileSystemRepresentation)==0);
    assert(historyLocks.empty()&&historyRecoveryFds.empty()&&historyChildCanLock(lock));
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=savedReady;
}
static bool historyContainsLF(NSData *data){
    const uint8_t *bytes=(const uint8_t *)data.bytes;for(NSUInteger n=0;n<data.length;++n)if(bytes[n]=='\n')return true;return false;
}
static void historyCompactIndexCases(){
    NSString *savedRoot=Current::fixtureRoot,*savedLegacy=Legacy::fixtureRoot;const BOOL savedReady=Current::sTLinkRunHistoryRecovered;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"compact-index"];Legacy::fixtureRoot=Current::fixtureRoot;
    Current::TLinkRunHistoryEnsureDirectories();NSString *path=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
    const NSUInteger events=historyEvents.count;uint64_t compactBytes=0,prettyBytes=0;NSMutableArray *lastRuns=nil;
    for(unsigned count:{0U,1U,20U,50U}){@autoreleasepool{
        NSMutableArray *runs=[NSMutableArray array];
        for(unsigned n=0;n<count;++n){
            NSString *runId=[NSString stringWithFormat:@"compact-%u",n];
            NSString *recordPath=[Current::TLinkRunHistoryRunsPath() stringByAppendingPathComponent:[runId stringByAppendingString:@".json"]];
            NSString *metadataPath=[Current::TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[runId stringByAppendingString:@".json"]];
            NSString *shot=[Current::TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[runId stringByAppendingString:@".png"]];
            NSString *line=[[@"ảnh 测试 😀 / quote \" backslash \\ \t\n" stringByPaddingToLength:1000 withString:@"x" startingAtIndex:0] stringByAppendingString:@"\0"];
            NSDictionary *evidence=@{@"schema":Current::TLinkFailureEvidenceSchemaV1,@"run_id":runId,@"metadata_path":metadataPath,
                @"screenshot_path":shot,@"log_tail":@[line,@"\r\n",@"[REDACTED]"],@"error":[@"error" stringByPaddingToLength:4000 withString:@"e" startingAtIndex:0]};
            [runs addObject:@{@"schema":Current::TLinkRunHistorySchemaV1,@"run_id":runId,@"record_path":recordPath,@"state":n%2?@"failed":@"finished",
                @"started_at_ms":@(1000+n),@"ended_at_ms":@(2000+n),@"failure_evidence":evidence,
                @"extra":@{@"null":[NSNull null],@"bool":@(YES),@"integer":@(UINT64_MAX),@"fraction":@1.25,@"empty":@[],@"nested":@{@"value":line}}}];
        }
        assert(Current::TLinkRunHistoryWriteIndex(runs));NSData *compact=[NSData dataWithContentsOfFile:path];NSDictionary *modern=historyReadJSON(path);
        assert(compact.length&&!historyContainsLF(compact)&&[modern[@"runs"] count]==count);
        assert(Legacy::TLinkRunHistoryWriteIndex(runs));NSData *pretty=[NSData dataWithContentsOfFile:path];NSDictionary *old=historyReadJSON(path);
        assert(pretty.length>compact.length&&historyContainsLF(pretty)&&[modern isEqual:old]);
        compactBytes+=compact.length;prettyBytes+=pretty.length;
        // The current status reader consumes a legacy pretty file without rewriting it.
        NSDictionary *modernStatus=Current::TLinkRunHistorySnapshot(50);
        assert([pretty isEqual:[NSData dataWithContentsOfFile:path]]&&Current::TLinkRunHistoryWriteIndex(runs));
        // The frozen reader also consumes compact JSON with identical public fields.
        NSDictionary *oldStatus=Legacy::TLinkRunHistorySnapshot(50);
        assert([historyCanonical(modernStatus,Current::fixtureRoot) isEqual:historyCanonical(oldStatus,Legacy::fixtureRoot)]);
        if(runs.count){
            NSDictionary *item=runs[0],*evidence=item[@"failure_evidence"];
            assert(Current::TLinkRunHistoryWriteJSON(item,item[@"record_path"])&&Current::TLinkRunHistoryWriteJSON(evidence,evidence[@"metadata_path"]));
            assert(historyContainsLF([NSData dataWithContentsOfFile:item[@"record_path"]])&&historyContainsLF([NSData dataWithContentsOfFile:evidence[@"metadata_path"]]));
        }
        lastRuns=runs;
    }}
    assert(historyEvents.count==events&&compactBytes<prettyBytes);
    // A pretty pre-upgrade index is valid input to a cold public mutation/recovery.
    assert(Legacy::TLinkRunHistoryWriteIndex(lastRuns));Current::sTLinkRunHistoryRecovered=NO;
    NSDictionary *started=Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"compact-migration.js",@{});
    assert(started.count&&Current::sTLinkRunHistoryRecovered&&historyPendingSize()==0&&historyEvents.count==events+1);
    NSDictionary *index=historyReadJSON(path);assert([index[@"runs"] count]==50&&[index[@"runs"][0] isEqual:started]&&!historyContainsLF([NSData dataWithContentsOfFile:path]));
    const size_t opens=historyRecoveryOpens;
    assert(Current::TLinkRunHistoryFinish(started[@"run_id"],@"finished",@"",@[],@"",@"",nil,@{}).count);
    assert(historyRecoveryOpens==opens&&historyEvents.count==events+2&&!historyContainsLF([NSData dataWithContentsOfFile:path])&&historyLocks.empty()&&historyRecoveryFds.empty());
    printf("History compact index fixture bytes: %llu compact vs %llu pretty (same decoded graphs, not device IO measurements).\n",(unsigned long long)compactBytes,(unsigned long long)prettyBytes);
    Current::fixtureRoot=savedRoot;Legacy::fixtureRoot=savedLegacy;Current::sTLinkRunHistoryRecovered=savedReady;
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2||argc==3||argc==5||argc==6);historyTestRoot=[NSString stringWithUTF8String:argv[1]];historyEvents=[NSMutableArray array];historyWriteAttempts=[NSMutableArray array];historyPruneAttempts=[NSMutableArray array];
    if(argc==5){assert([[NSString stringWithUTF8String:argv[2]] isEqualToString:@"--marker-worker"]);return historyMarkerWorker([[NSString stringWithUTF8String:argv[3]] intValue],[NSString stringWithUTF8String:argv[4]]);}
    if(argc==6){
        assert([[NSString stringWithUTF8String:argv[2]] isEqualToString:@"--marker-crash"]);Current::fixtureRoot=[NSString stringWithUTF8String:argv[3]];
        historyCrashIndex=(unsigned)[[NSString stringWithUTF8String:argv[5]] intValue];assert(historyCrashIndex==1||historyCrashIndex==2);
        Current::TLinkRunHistoryFinish([NSString stringWithUTF8String:argv[4]],@"failed",@"new peer error",@[@"new peer line"],@"",@"",nil,@{});assert(false);
    }
    if(argc==3){
        assert([[NSString stringWithUTF8String:argv[2]] isEqualToString:@"--recover"]&&!Current::sTLinkRunHistoryRecovered);
        Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"recovery"];historyUUIDs=100000;
        assert(Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"after-restart.js",@{}).count&&Current::sTLinkRunHistoryRecovered);
        assert(historyEvents.count==1&&historyWriteAttempts.count==6&&historyRecoveryFds.empty()&&historyLocks.empty());
        const size_t opens=historyRecoveryOpens;[historyWriteAttempts removeAllObjects];
        assert(Current::TLinkRunHistoryFinish(@"restart-probe",@"finished",@"",@[],@"",@"",nil,@{}).count);
        assert(historyRecoveryOpens==opens&&historyWriteAttempts.count==2&&historyEvents.count==2);return 0;
    }
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"current"];
    Legacy::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"legacy"];
    puts("History Foundation: actual/frozen redaction, persistence/evidence and pre-flock preparation");fflush(stdout);
    dispatch_group_t group=dispatch_group_create();
    for(unsigned t=0;t<8;++t)dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{@autoreleasepool{for(unsigned n=0;n<100;++n)assert([Current::TLinkRunHistoryRedactText(@"license_key=abc Bearer xyz") isEqualToString:@"license_key=[REDACTED] Bearer [REDACTED]"]);}});
    assert(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0&&historyRegexBuilds==2);
    NSArray *inputs=@[@"",@"plain ảnh 测试 😀",@"LICENSE-KEY: 'top-secret'; bearer abc.def_-/+=",@"private_key=one\nadmin-token=two",@"license_key=first license_key=second",@42,[NSNull null]];
    const unsigned before=historyRegexBuilds;
    for(unsigned n=0;n<1000;++n){NSString *value=(NSString *)inputs[n%inputs.count];assert([Current::TLinkRunHistoryRedactText(value) isEqual:Legacy::TLinkRunHistoryRedactText(value)]);}
    assert(historyRegexBuilds==before+2000);
    NSString *console=[historyTestRoot stringByAppendingPathComponent:@"console.log"],*screenshot=[historyTestRoot stringByAppendingPathComponent:@"capture.bin"];
    NSString *log=[[@"x" stringByPaddingToLength:270000 withString:@"x" startingAtIndex:0] stringByAppendingString:@"\nlicense_key=from-console\nBearer token\nlast\n"];
    assert([log writeToFile:console atomically:YES encoding:NSUTF8StringEncoding error:nil]);assert([[@"capture" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:screenshot atomically:YES]);
    NSData *expected=historyTransactions(false,console,screenshot),*actual=historyTransactions(true,console,screenshot);assert([expected isEqual:actual]);
    for(bool modern:{false,true}){
        HistoryBegin begin=modern?Current::TLinkRunHistoryBegin:Legacy::TLinkRunHistoryBegin;HistoryFinish finish=modern?Current::TLinkRunHistoryFinish:Legacy::TLinkRunHistoryFinish;
        NSString *root=modern?Current::fixtureRoot:Legacy::fixtureRoot;NSDictionary *started=begin(@"rootfull",@"/bundle",@"probe.js",@{});
        HistoryProbe *probe=[HistoryProbe new];probe->callback=[modern,root]{assert(historyChildCanLock([root stringByAppendingPathComponent:@"history.lock"])==modern);};
        NSArray *probeTail=@[probe];NSDictionary *done=finish(started[@"run_id"],@"failed",@"failure",probeTail,console,@"",nil,@{});assert([done[@"failure_evidence"] count]>0);
    }
    for(bool cpp:{false,true}){
        NSDictionary *started=Current::TLinkRunHistoryBegin(@"rootfull",@"/bundle",@"fault.js",@{});const NSUInteger eventCount=historyEvents.count;
        HistoryProbe *probe=[HistoryProbe new];probe->callback=[cpp]{if(cpp)throw std::runtime_error("description fault");[NSException raise:@"HistoryFixture" format:@"description fault"];};NSArray *probeTail=@[probe];bool threw=false;
        @try{try{Current::TLinkRunHistoryFinish(started[@"run_id"],@"failed",@"failure",probeTail,console,@"",nil,@{});}catch(const std::runtime_error &){threw=true;}}@catch(__unused NSException *exception){threw=true;}
        assert(threw&&historyEvents.count==eventCount&&historyLocks.empty()&&historyChildCanLock([Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"]));
        assert([historyReadJSON(started[@"record_path"])[@"state"] isEqualToString:@"running"]);
        assert(Current::TLinkRunHistoryFinish(started[@"run_id"],@"failed",@"failure",@[],console,@"",nil,@{}).count>0);
    }
    // Snapshot field preparation now permits a real child to acquire flock;
    // the frozen implementation still holds it during that same preparation.
    for(bool modern:{false,true}){
        HistorySnapshot snapshot=modern?Current::TLinkRunHistorySnapshot:Legacy::TLinkRunHistorySnapshot;
        NSString *root=modern?Current::fixtureRoot:Legacy::fixtureRoot;
        historyStatusHook=[modern,root]{assert(historyChildCanLock([root stringByAppendingPathComponent:@"history.lock"])==modern);};
        assert(snapshot(20).count>0);historyStatusHook={};
    }
    // A cooperating writer changes the private index after decode, while
    // status construction is paused. The response must remain the old graph.
    NSString *indexPath=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
    NSString *lockPath=[Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"];
    NSData *beforeStatus=historyCanonical(Current::TLinkRunHistorySnapshot(50),Current::fixtureRoot);
    historyStatusHook=[indexPath,lockPath]{
        assert(historyLocks.empty());const int fd=::open(lockPath.fileSystemRepresentation,O_RDWR);assert(fd>=0&&::flock(fd,LOCK_EX|LOCK_NB)==0);
        NSMutableDictionary *index=[historyReadJSON(indexPath) mutableCopy];NSMutableArray *runs=[index[@"runs"] mutableCopy];NSMutableDictionary *run=[runs[0] mutableCopy];
        run[@"state"]=@"cancelled";run[@"error"]=@"changed-after-read";runs[0]=run;index[@"runs"]=runs;
        NSData *data=[NSJSONSerialization dataWithJSONObject:index options:0 error:nil];assert(data&&[data writeToFile:indexPath atomically:YES]);assert(::flock(fd,LOCK_UN)==0&&::close(fd)==0);
    };
    const size_t readsBefore=historyIndexReads;
    NSDictionary *captured=Current::TLinkRunHistorySnapshot(50);historyStatusHook={};
    assert(historyIndexReads==readsBefore+1&&[beforeStatus isEqual:historyCanonical(captured,Current::fixtureRoot)]);
    NSDictionary *next=Current::TLinkRunHistorySnapshot(50);NSData *nextBytes=historyCanonical(next,Current::fixtureRoot);
    assert([next[@"runs"][0][@"error"] isEqualToString:@"changed-after-read"]&&![beforeStatus isEqual:nextBytes]);
    NSMutableDictionary *returned=next[@"runs"][0];returned[@"error"]=@"caller-edited";
    assert([nextBytes isEqual:historyCanonical(Current::TLinkRunHistorySnapshot(50),Current::fixtureRoot)]);
    // Index-read and formatting faults each unwind through the local monitor;
    // no file lock or partial status escapes, and the next call recovers.
    for(unsigned fault=1;fault<=4;++fault){
        const NSUInteger eventCount=historyEvents.count;NSData *indexBefore=[NSData dataWithContentsOfFile:indexPath];bool threw=false;
        if(fault<=2)historyReadFault=fault;
        else historyStatusHook=[fault]{assert(historyLocks.empty());if(fault==3)[NSException raise:@"HistoryFixture" format:@"status fault"];throw std::runtime_error("status fault");};
        @try{try{Current::TLinkRunHistorySnapshot(50);}catch(const std::runtime_error &){threw=true;}}@catch(__unused NSException *exception){threw=true;}
        historyReadFault=0;historyStatusHook={};
        assert(threw&&historyLocks.empty()&&historyEvents.count==eventCount&&historyChildCanLock(lockPath));
        assert([indexBefore isEqual:[NSData dataWithContentsOfFile:indexPath]]&&[nextBytes isEqual:historyCanonical(Current::TLinkRunHistorySnapshot(50),Current::fixtureRoot)]);
    }
    // Preserve the existing lock-failure/read-fallback policy; this slice
    // changes the successful read lock window, not status error semantics.
    for(bool modern:{false,true}){
        HistorySnapshot snapshot=modern?Current::TLinkRunHistorySnapshot:Legacy::TLinkRunHistorySnapshot;NSString *root=modern?Current::fixtureRoot:Legacy::fixtureRoot;
        NSData *normal=historyCanonical(snapshot(20),root);historyLockDenied=true;NSDictionary *denied=snapshot(20);historyLockDenied=false;
        assert(historyLocks.empty()&&[normal isEqual:historyCanonical(denied,root)]);
    }
    NSData *currentIndex=[NSData dataWithContentsOfFile:indexPath];NSString *oldIndexPath=[Legacy::fixtureRoot stringByAppendingPathComponent:@"index.json"];NSData *oldIndex=[NSData dataWithContentsOfFile:oldIndexPath];
    for(NSString *invalid in @[@"",@"not-json",@"{\"runs\":42}",@"{\"runs\":[]}"]){
        NSData *data=[invalid dataUsingEncoding:NSUTF8StringEncoding];assert([data writeToFile:indexPath atomically:YES]&&[data writeToFile:oldIndexPath atomically:YES]);
        NSDictionary *fresh=Current::TLinkRunHistorySnapshot(0),*frozen=Legacy::TLinkRunHistorySnapshot(0);
        assert([fresh[@"total_count"] intValue]==0&&[historyCanonical(fresh,Current::fixtureRoot) isEqual:historyCanonical(frozen,Legacy::fixtureRoot)]);
    }
    assert([currentIndex writeToFile:indexPath atomically:YES]&&[oldIndex writeToFile:oldIndexPath atomically:YES]);
    historyCommitCases(console,screenshot);
    historyMutationReadCases();
    historyRecoveryCases(argv[0]);
    historyInProcessRecoveryCases();
    historyCrossProcessCases(argv[0]);
    historyMarkerFaultCases();
    historyRetirementCases();
    historyCompactIndexCases();
    assert(historyLocks.empty());historyEvents=nil;historyWriteAttempts=nil;historyPruneAttempts=nil;
    puts("History Foundation passed: two cold regex builds across 8 callers, 1000 frozen redaction cases, 75 full transactions/runtime with exact records/evidence/index/events/status/retention, real child flock probe before versus during preparation, NS/C++ preparation unwind and recovery. Only private temporary files; chmod/chown and event publication controlled. Device qualification pending.");
    puts("History snapshot Foundation passed: flock released before status construction, one private decoded index across a cooperating write, next-call freshness and caller isolation, NS/C++ read/format unwind/recovery, unchanged lock-denial/malformed-index policy and exact frozen status fields. Local serialization retained; device qualification pending.");
    puts("History commit Foundation passed: record/evidence/index false and NS/C++ failures suppress success/events, retain old-index artifacts until commit, release locks, report bounded process diagnostics and recover; read/lock failures, counter saturation and uncertain post-write outcome without rollback/replay. Multi-file crash recovery remains pending.");
    puts("History mutation reads passed: missing-index bootstrap, 32 invalid schema/shape/identity cases, read permission/domain/nil-error faults, real directory rejection, unchanged files/events, lock release and explicit repair followed by successful mutation. Status fallback unchanged; multi-file recovery pending.");
    puts("History startup recovery passed: new-process public entry repairs retained metadata from old/new authoritative index, leaves orphans/screenshots/events alone, gates once, retries false/NS/C++/uncertain writes, releases FDs/flock, handles read/EINTR/short/size bounds and rejects invalid paths/symlinks/directories. Orphan/event recovery and device qualification pending.");
    puts("History in-process recovery passed: 30 warm begin/finish writer faults including post-replacement NS/C++ exceptions, old/new index authority, next DIFFERENT mutation repairs without restart/replay, status remains read-only, failed recovery retries, clean fast path, saturated diagnostics and balanced descriptors/flock. Device qualification pending.");
    puts("History cross-process recovery passed: already-warm peer handles NO/NS/C++/post-index failures and actual writer exit before/after index replacement, stable lock inode, old/new authority, no event replay and subsequent clean fast path. Power-loss/device qualification remains separate.");
    puts("History retirement passed: committed begin/finish ACK/events across unlink/ENOENT/EINTR/EACCES/post-effect/NS/C++ faults, retained-reference and alias protection, control/outside/directory/parent-symlink refusal, nonrecursive leaf ownership and stable fast path. Orphan retries/log retention and device qualification remain pending.");
    puts("History compact index passed: 0/1/20/50 runs, frozen decoded fields/status, Unicode/escaping/NUL/nested extensions, bidirectional reader compatibility, pretty artifact files, cold public migration/recovery and warm finish. Device IO/latency qualification pending.");
    puts("History marker passed: pre/post dirty and clean errors, committed ACK on clear failure, EINTR retry, read/invalid-size/hardlink/symlink/FIFO rejection, unchanged payload on admission failure and balanced resources. No power-loss guarantee.");
}}
