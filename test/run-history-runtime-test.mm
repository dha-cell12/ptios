#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <cassert>
#include <atomic>
#include <cerrno>
#include <cstdio>
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
static int historyChmod(const char *path,mode_t mode){assert([[NSString stringWithUTF8String:path] hasPrefix:historyTestRoot]);assert(mode==0750||mode==0640);return 0;}
static int historyChown(const char *path,uid_t uid,gid_t gid){assert([[NSString stringWithUTF8String:path] hasPrefix:historyTestRoot]);assert(uid==501&&gid==501);return 0;}
static int historyFlock(int fd,int operation){
    const int result=::flock(fd,operation);
    if(!result){std::lock_guard<std::mutex> guard(historyMutex);if(operation==LOCK_EX)assert(historyLocks.insert(fd).second);else if(operation==LOCK_UN)assert(historyLocks.erase(fd)==1);}
    return result;
}
static int historyClose(int fd){{std::lock_guard<std::mutex> guard(historyMutex);assert(!historyLocks.count(fd));}return ::close(fd);}
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
    if([value isKindOfClass:[NSDictionary class]]){NSMutableDictionary *result=[NSMutableDictionary dictionary];for(NSString *key in value)result[key]=historyNormalize(value[key],root);return result;}
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
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2);historyTestRoot=[NSString stringWithUTF8String:argv[1]];historyEvents=[NSMutableArray array];
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
    assert(historyLocks.empty());historyEvents=nil;
    puts("History Foundation passed: two cold regex builds across 8 callers, 1000 frozen redaction cases, 75 full transactions/runtime with exact records/evidence/index/events/status/retention, real child flock probe before versus during preparation, NS/C++ preparation unwind and recovery. Only private temporary files; chmod/chown and event publication controlled. Device qualification pending.");
}}
