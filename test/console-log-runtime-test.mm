#import <Foundation/Foundation.h>
#import <os/lock.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include "../shared/TLinkConsoleLogBudget.h"
#include "../shared/TLinkConsoleLogBatch.h"
#include <cassert>
#include <atomic>
#include <cstdio>
#include <functional>
#include <stdexcept>
#include <cstdarg>
#include "ConsoleLogConstants.h"
#include "ConsoleLogHelpers.inc"
#include "ConsoleLogEntry.inc"
static std::atomic<unsigned> consoleFault{0},consoleLive{0},consoleOpens{0},consoleWrites{0},consoleCloses{0},consoleStats{0};
static std::atomic<unsigned> consoleSystemFault{0};
static char consoleQueueKey;
static std::mutex consoleSystemMutex;
static NSMutableArray *consoleSystemRecords;
static dispatch_semaphore_t consoleSystemEntered,consoleSystemRelease;
static void consoleWait(dispatch_semaphore_t semaphore);
static void ConsoleCaptureLog(NSString *format,...) NS_FORMAT_FUNCTION(1,2);
static void ConsoleCaptureLog(NSString *format,...){
    va_list arguments;va_start(arguments,format);NSString *text;
    @try {text=[[NSString alloc] initWithFormat:format arguments:arguments];} @finally {va_end(arguments);}
    {
        std::lock_guard<std::mutex> guard(consoleSystemMutex);
        [consoleSystemRecords addObject:@{@"text":text?:@"",@"queued":@(dispatch_get_specific(&consoleQueueKey)!=nullptr)}];
    }
    if(consoleSystemEntered&&[text hasSuffix:@": slow-system"]){dispatch_semaphore_signal(consoleSystemEntered);consoleWait(consoleSystemRelease);}
    if(consoleSystemFault==1)throw std::runtime_error("system log failed after capture");
    if(consoleSystemFault==2)[NSException raise:@"LogFixture" format:@"system log failed after capture"];
}
static NSArray *consoleTakeSystemRecords(){std::lock_guard<std::mutex> guard(consoleSystemMutex);NSArray *records=[consoleSystemRecords copy];[consoleSystemRecords removeAllObjects];return records;}
@interface ConsoleLogFileManager : NSObject
+ (instancetype)defaultManager;
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)parents attributes:(NSDictionary *)attributes error:(NSError **)error;
@end
@implementation ConsoleLogFileManager
+ (instancetype)defaultManager {static ConsoleLogFileManager *manager;static dispatch_once_t once;dispatch_once(&once,^{manager=[self new];});return manager;}
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {++consoleStats;return [[NSFileManager defaultManager] attributesOfItemAtPath:path error:error];}
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {if(consoleFault==6)return NO;return [[NSFileManager defaultManager] removeItemAtPath:path error:error];}
- (BOOL)fileExistsAtPath:(NSString *)path {return [[NSFileManager defaultManager] fileExistsAtPath:path];}
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)parents attributes:(NSDictionary *)attributes error:(NSError **)error {return [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:parents attributes:attributes error:error];}
@end
@interface ConsoleLogClock : NSObject
+ (NSDate *)date;
@end
@implementation ConsoleLogClock
+ (NSDate *)date {return [NSDate dateWithTimeIntervalSince1970:1234567890];}
@end
@interface ConsoleLogFileHandle : NSObject {
    NSFileHandle *_handle;BOOL _closed,_latest;
}
+ (instancetype)fileHandleForWritingAtPath:(NSString *)path;
- (unsigned long long)seekToEndOfFile;
- (void)writeData:(NSData *)data;
- (void)closeFile;
@end
@implementation ConsoleLogFileHandle
+ (instancetype)fileHandleForWritingAtPath:(NSString *)path {
    NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];if(!handle)return nil;
    ConsoleLogFileHandle *result=[self new];result->_handle=handle;result->_latest=[path hasSuffix:@"/latest.log"];++consoleLive;++consoleOpens;return result;
}
- (unsigned long long)seekToEndOfFile {if(consoleFault==1)[NSException raise:@"LogFixture" format:@"seek failed"];return [_handle seekToEndOfFile];}
- (void)writeData:(NSData *)data {++consoleWrites;if(consoleFault==2)throw std::runtime_error("write failed");if(consoleFault==5&&_latest)[NSException raise:@"LogFixture" format:@"latest write failed"];[_handle writeData:data];}
- (void)closeFile {
    if(_closed)return;_closed=YES;[_handle closeFile];assert(consoleLive.fetch_sub(1)>0);++consoleCloses;
    if(consoleFault==3)[NSException raise:@"LogFixture" format:@"close failed"];
    if(consoleFault==4)throw std::runtime_error("close failed");
}
- (void)dealloc {if(!_closed&&_handle){[_handle closeFile];assert(consoleLive.fetch_sub(1)>0);}}
@end
@interface ConsoleMessageProbe : NSObject {
@public std::function<void()> callback;
}
@property(nonatomic) unsigned calls;
@end
@implementation ConsoleMessageProbe
- (NSString *)description {++self.calls;if(callback)callback();return @"late-log";}
@end
@interface TLinkJSRuntimeCore : NSObject {
    NSString *_bundlePath,*_runId,*_consoleLogPath,*_consoleLatestLogPath;
    dispatch_queue_t _logQueue;os_unfair_lock _logStateLock;BOOL _acceptingLogs;
    uint64_t _logGeneration;std::shared_ptr<TLinkConsoleLogBudget> _logBudget;
    std::vector<std::shared_ptr<TLinkConsoleLogEntry>> _logPending;BOOL _logDrainScheduled;
}
- (void)prepareConsoleLogFiles;
- (BOOL)appendConsoleData:(NSData *)data toConsolePath:(NSString *)path;
- (BOOL)writeConsoleData:(NSData *)data runPath:(NSString *)runPath latestPath:(NSString *)latestPath;
- (uint64_t)writeConsoleBatch:(const std::vector<std::shared_ptr<TLinkConsoleLogEntry>> &)batch toConsolePath:(NSString *)path;
- (BOOL)emitConsoleSystemLog:(const TLinkConsoleLogEntry &)entry;
- (void)drainConsoleLogs;
- (void)beginConsoleLogging;
- (void)finishConsoleLogging;
- (NSDictionary *)currentConsoleLogStats;
- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message;
- (void)legacyPrepareConsoleLogFiles;
- (void)legacyAppendLine:(NSString *)line toConsolePath:(NSString *)path;
- (void)legacyAppendConsoleLogWithLevel:(NSString *)level message:(NSString *)message;
- (void)configure:(NSString *)root run:(NSString *)run;
- (NSString *)runPath;
- (NSString *)latestPath;
- (void)holdWriter;
- (void)resumeWriter;
- (NSString *)runId;
- (void)installConsole:(JSContext *)context;
- (void)legacyInstallConsole:(JSContext *)context;
@end
@implementation TLinkJSRuntimeCore
- (instancetype)init {self=[super init];if(self){_logQueue=dispatch_queue_create("fixture.log",DISPATCH_QUEUE_SERIAL);dispatch_queue_set_specific(_logQueue,&consoleQueueKey,&consoleQueueKey,nullptr);_logStateLock=OS_UNFAIR_LOCK_INIT;_logBudget=std::make_shared<TLinkConsoleLogBudget>();}return self;}
- (void)configure:(NSString *)root run:(NSString *)run {_bundlePath=[root copy];_runId=[run copy];}
- (NSString *)runPath {return _consoleLogPath;}
- (NSString *)latestPath {return _consoleLatestLogPath;}
- (void)holdWriter {dispatch_suspend(_logQueue);}
- (void)resumeWriter {dispatch_resume(_logQueue);}
- (NSString *)runId {return _runId?:@"";}
#define NSDate ConsoleLogClock
#define NSFileHandle ConsoleLogFileHandle
#define NSFileManager ConsoleLogFileManager
#define NSLog ConsoleCaptureLog
#include "ConsoleLogMethods.inc"
- (void)installConsole:(JSContext *)context {
    __weak TLinkJSRuntimeCore *weakSelf=self;
#include "ConsoleLogCallback.inc"
}
#define prepareConsoleLogFiles legacyPrepareConsoleLogFiles
#define appendLine legacyAppendLine
#define appendConsoleLogWithLevel legacyAppendConsoleLogWithLevel
#include "fixtures/console-log-legacy-v1.inc"
- (void)legacyInstallConsole:(JSContext *)context {
    __weak TLinkJSRuntimeCore *weakSelf=self;
#include "fixtures/console-callback-legacy-v1.inc"
}
#undef appendConsoleLogWithLevel
#undef appendLine
#undef prepareConsoleLogFiles
#undef NSFileHandle
#undef NSFileManager
#undef NSDate
#undef NSLog
@end
static void consoleWait(dispatch_semaphore_t semaphore){assert(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0);}
static NSString *consoleText(NSString *path){return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]?:@"";}
static TLinkJSRuntimeCore *consoleStart(NSString *root,NSString *run){TLinkJSRuntimeCore *logger=[TLinkJSRuntimeCore new];[logger configure:root run:run];[logger prepareConsoleLogFiles];[logger beginConsoleLogging];return logger;}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2);NSString *root=[NSString stringWithUTF8String:argv[1]];
    consoleSystemRecords=[NSMutableArray array];
    puts("Console logger Foundation: actual formatter/admission/GCD/files versus frozen ordinary logs");fflush(stdout);
    TLinkJSRuntimeCore *old=[TLinkJSRuntimeCore new],*now=[TLinkJSRuntimeCore new];
    [old configure:[root stringByAppendingPathComponent:@"old"] run:@"ordinary"];
    [now configure:[root stringByAppendingPathComponent:@"new"] run:@"ordinary"];
    [old legacyPrepareConsoleLogFiles];[now prepareConsoleLogFiles];
    for(unsigned batch=0;batch<20;++batch){[old beginConsoleLogging];[now beginConsoleLogging];
        for(unsigned n=0;n<8;++n){NSString *message=[NSString stringWithFormat:@"%u:%u ảnh 测试 😀\r\nnext",batch,n];
            [old legacyAppendConsoleLogWithLevel:@"warn:detail" message:message];[now appendConsoleLogWithLevel:@"warn:detail" message:message];}
        [old finishConsoleLogging];[now finishConsoleLogging];
    }
    [old beginConsoleLogging];[now beginConsoleLogging];
    for(id level in @[@"",@42,[NSNull null]]){[old legacyAppendConsoleLogWithLevel:(NSString *)level message:@"level"];[now appendConsoleLogWithLevel:(NSString *)level message:@"level"];}
    [old legacyAppendConsoleLogWithLevel:nil message:nil];[now appendConsoleLogWithLevel:nil message:nil];
    [old finishConsoleLogging];[now finishConsoleLogging];
    assert([[NSData dataWithContentsOfFile:old.runPath] isEqual:[NSData dataWithContentsOfFile:now.runPath]]);
    assert([[NSData dataWithContentsOfFile:now.runPath] isEqual:[NSData dataWithContentsOfFile:now.latestPath]]);
    assert([[now currentConsoleLogStats][@"accepted"] unsignedLongLongValue]==164&&[[now currentConsoleLogStats][@"pendingLines"] intValue]==0&&consoleLive==0);
    // Existing rotation threshold and ordinary line bytes remain unchanged.
    NSData *large=[[@"x" stringByPaddingToLength:512*1024+1 withString:@"x" startingAtIndex:0] dataUsingEncoding:NSUTF8StringEncoding];
    for(TLinkJSRuntimeCore *logger in @[old,now]){assert([large writeToFile:logger.runPath atomically:YES]);assert([large writeToFile:logger.latestPath atomically:YES]);[logger beginConsoleLogging];}
    [old legacyAppendConsoleLogWithLevel:@"log" message:@"rotated"];[now appendConsoleLogWithLevel:@"log" message:@"rotated"];
    [old finishConsoleLogging];[now finishConsoleLogging];assert([consoleText(old.runPath) isEqual:consoleText(now.runPath)]);
    // Hold both actual queues so a full burst is deterministic, with no timer.
    TLinkJSRuntimeCore *batched=consoleStart([root stringByAppendingPathComponent:@"batched"],@"burst");
    TLinkJSRuntimeCore *legacyBurst=[TLinkJSRuntimeCore new];[legacyBurst configure:[root stringByAppendingPathComponent:@"legacy-burst"] run:@"burst"];[legacyBurst legacyPrepareConsoleLogFiles];[legacyBurst beginConsoleLogging];
    [batched holdWriter];[legacyBurst holdWriter];
    for(unsigned n=0;n<64;++n){NSString *entry=[NSString stringWithFormat:@"burst-%u ảnh 测试\r\n",n];[batched appendConsoleLogWithLevel:@"log" message:entry];[legacyBurst legacyAppendConsoleLogWithLevel:@"log" message:entry];}
    consoleOpens=0;consoleWrites=0;consoleCloses=0;consoleStats=0;[legacyBurst resumeWriter];[legacyBurst finishConsoleLogging];
    assert(consoleOpens==128&&consoleWrites==128&&consoleCloses==128&&consoleStats==128);
    consoleOpens=0;consoleWrites=0;consoleCloses=0;consoleStats=0;[batched resumeWriter];[batched finishConsoleLogging];
    assert(consoleOpens==2&&consoleWrites==2&&consoleCloses==2&&consoleStats==4&&consoleLive==0);
    assert([consoleText(legacyBurst.runPath) isEqual:consoleText(batched.runPath)]&&[consoleText(legacyBurst.latestPath) isEqual:consoleText(batched.latestPath)]);
    assert([[batched currentConsoleLogStats][@"accepted"] intValue]==64&&[[batched currentConsoleLogStats][@"pendingLines"] intValue]==0);
    // Both files plan their own rotations; threshold equality must keep the
    // next whole line. A large burst crosses more than one threshold.
    NSString *wide=[@"测" stringByPaddingToLength:4000 withString:@"测" startingAtIndex:0];
    for(NSNumber *initial in @[@(512*1024-1),@(512*1024),@(512*1024+1),@(512*1024-32768)]){
        NSString *run=[NSString stringWithFormat:@"boundary-%@",initial];
        TLinkJSRuntimeCore *expected=[TLinkJSRuntimeCore new],*actual=consoleStart([root stringByAppendingPathComponent:[run stringByAppendingString:@"-new"]],run);
        [expected configure:[root stringByAppendingPathComponent:[run stringByAppendingString:@"-old"]] run:run];[expected legacyPrepareConsoleLogFiles];[expected beginConsoleLogging];
        NSData *runSeed=[[@"s" stringByPaddingToLength:initial.unsignedIntegerValue withString:@"s" startingAtIndex:0] dataUsingEncoding:NSUTF8StringEncoding];
        NSData *latestSeed=[[@"s" stringByPaddingToLength:512*1024-20000 withString:@"s" startingAtIndex:0] dataUsingEncoding:NSUTF8StringEncoding];
        for(TLinkJSRuntimeCore *logger in @[expected,actual]){assert([runSeed writeToFile:logger.runPath atomically:YES]);assert([latestSeed writeToFile:logger.latestPath atomically:YES]);[logger holdWriter];}
        for(unsigned n=0;n<64;++n){NSString *entry=[NSString stringWithFormat:@"%u %@",n,wide];[expected legacyAppendConsoleLogWithLevel:@"log" message:entry];[actual appendConsoleLogWithLevel:@"log" message:entry];}
        [expected resumeWriter];[expected finishConsoleLogging];[actual resumeWriter];[actual finishConsoleLogging];
        assert([consoleText(expected.runPath) isEqual:consoleText(actual.runPath)]&&[consoleText(expected.latestPath) isEqual:consoleText(actual.latestPath)]&&consoleLive==0);
        assert([[actual currentConsoleLogStats][@"writeFailures"] intValue]==0&&[[actual currentConsoleLogStats][@"pendingLines"] intValue]==0);
    }
    for(unsigned missing=1;missing<=3;++missing){
        NSString *run=[NSString stringWithFormat:@"missing-%u",missing];
        TLinkJSRuntimeCore *expected=[TLinkJSRuntimeCore new],*actual=consoleStart([root stringByAppendingPathComponent:[run stringByAppendingString:@"-new"]],run);
        [expected configure:[root stringByAppendingPathComponent:[run stringByAppendingString:@"-old"]] run:run];[expected legacyPrepareConsoleLogFiles];[expected beginConsoleLogging];
        for(TLinkJSRuntimeCore *logger in @[expected,actual]){
            if(missing&1)assert([[NSFileManager defaultManager] removeItemAtPath:logger.runPath error:nil]);
            if(missing&2)assert([[NSFileManager defaultManager] removeItemAtPath:logger.latestPath error:nil]);
            [logger holdWriter];
        }
        for(unsigned n=0;n<16;++n){[expected legacyAppendConsoleLogWithLevel:@"log" message:@"created"];[actual appendConsoleLogWithLevel:@"log" message:@"created"];}
        [expected resumeWriter];[expected finishConsoleLogging];[actual resumeWriter];[actual finishConsoleLogging];
        assert([consoleText(expected.runPath) isEqual:consoleText(actual.runPath)]&&[consoleText(expected.latestPath) isEqual:consoleText(actual.latestPath)]&&consoleLive==0);
    }
    TLinkJSRuntimeCore *removeOld=[TLinkJSRuntimeCore new],*removeNew=consoleStart([root stringByAppendingPathComponent:@"remove-new"],@"remove-fails");
    [removeOld configure:[root stringByAppendingPathComponent:@"remove-old"] run:@"remove-fails"];[removeOld legacyPrepareConsoleLogFiles];[removeOld beginConsoleLogging];
    for(TLinkJSRuntimeCore *logger in @[removeOld,removeNew]){assert([large writeToFile:logger.runPath atomically:YES]);assert([large writeToFile:logger.latestPath atomically:YES]);[logger holdWriter];}
    for(unsigned n=0;n<8;++n){[removeOld legacyAppendConsoleLogWithLevel:@"log" message:@"remove failed"];[removeNew appendConsoleLogWithLevel:@"log" message:@"remove failed"];}
    consoleFault=6;[removeOld resumeWriter];[removeOld finishConsoleLogging];[removeNew resumeWriter];[removeNew finishConsoleLogging];consoleFault=0;
    assert([consoleText(removeOld.runPath) isEqual:consoleText(removeNew.runPath)]&&[consoleText(removeOld.latestPath) isEqual:consoleText(removeNew.latestPath)]&&consoleLive==0);
    // Post-write close failure marks all affected entries once and never
    // replays their bytes. A latest-only failure must still write the run log.
    for(unsigned fault:{2U,4U,5U}){
        TLinkJSRuntimeCore *logger=consoleStart([root stringByAppendingPathComponent:[NSString stringWithFormat:@"batch-fault%u",fault]],@"group-fault");[logger holdWriter];
        for(unsigned n=0;n<8;++n)[logger appendConsoleLogWithLevel:@"log" message:@"group-entry"];
        consoleFault=fault;[logger resumeWriter];[logger finishConsoleLogging];consoleFault=0;
        assert([[logger currentConsoleLogStats][@"writeFailures"] intValue]==8&&[[logger currentConsoleLogStats][@"pendingLines"] intValue]==0&&consoleLive==0);
        const NSUInteger runEntries=[consoleText(logger.runPath) componentsSeparatedByString:@" group-entry\n"].count-1;
        const NSUInteger latestEntries=[consoleText(logger.latestPath) componentsSeparatedByString:@" group-entry\n"].count-1;
        assert(runEntries==(fault==2?0U:8U)&&latestEntries==(fault==4?8U:0U));
        [logger beginConsoleLogging];[logger appendConsoleLogWithLevel:@"log" message:@"batch-recovered"];[logger finishConsoleLogging];
        assert([consoleText(logger.runPath) containsString:@"batch-recovered"]&&[consoleText(logger.latestPath) containsString:@"batch-recovered"]&&consoleLive==0);
    }
    TLinkJSRuntimeCore *full=consoleStart([root stringByAppendingPathComponent:@"full"],@"full");[full holdWriter];
    consoleTakeSystemRecords();
    for(unsigned n=0;n<100;++n)[full appendConsoleLogWithLevel:@"log" message:@"bounded"];
    ConsoleMessageProbe *probe=[ConsoleMessageProbe new];[full appendConsoleLogWithLevel:@"log" message:(NSString *)probe];
    NSDictionary *stats=[full currentConsoleLogStats];assert([stats[@"pendingLines"] intValue]==64&&[stats[@"pendingBytesReserved"] intValue]==1024*1024&&[stats[@"dropped"] intValue]==37&&probe.calls==0);
    assert([stats[@"pendingSystemBytesReserved"] intValue]==1024*1024&&[stats[@"pendingTotalBytesReserved"] intValue]==2*1024*1024&&consoleTakeSystemRecords().count==0);
    [full resumeWriter];[full finishConsoleLogging];assert([[full currentConsoleLogStats][@"pendingLines"] intValue]==0&&[consoleText(full.runPath) containsString:@"dropped=37"]&&consoleLive==0);
    NSArray *systemRecords=consoleTakeSystemRecords();assert(systemRecords.count==65);
    for(NSUInteger n=0;n<64;++n)assert([systemRecords[n][@"text"] hasSuffix:@": bounded"]&&[systemRecords[n][@"queued"] boolValue]);
    TLinkJSRuntimeCore *cut=consoleStart([root stringByAppendingPathComponent:@"cut"],@"cut");[cut holdWriter];
    NSMutableString *message=[[@"x" stringByPaddingToLength:4095 withString:@"x" startingAtIndex:0] mutableCopy];[message appendString:@"😀tail"];
    NSMutableString *level=[[@"l" stringByPaddingToLength:1000 withString:@"l" startingAtIndex:0] mutableCopy];[cut appendConsoleLogWithLevel:level message:message];[message setString:@"changed"];[level setString:@"changed-level"];
    [cut resumeWriter];[cut finishConsoleLogging];NSString *text=consoleText(cut.runPath);
    assert([text containsString:@" [truncated]"]&&![text containsString:@"😀"]&&![text containsString:@"changed"]&&[[cut currentConsoleLogStats][@"truncated"] intValue]==1);
    systemRecords=consoleTakeSystemRecords();NSString *systemText=systemRecords[0][@"text"];
    assert([systemText hasSuffix:@" [truncated]"]&&![systemText containsString:@"changed"]&&![systemText containsString:@"😀"]&&[systemRecords[0][@"queued"] boolValue]);
    for(unsigned fault=1;fault<=4;++fault){TLinkJSRuntimeCore *logger=consoleStart([root stringByAppendingPathComponent:[NSString stringWithFormat:@"fault%u",fault]],@"fault");consoleFault=fault;
        [logger appendConsoleLogWithLevel:@"log" message:@"fault"];[logger finishConsoleLogging];consoleFault=0;
        assert([[logger currentConsoleLogStats][@"writeFailures"] intValue]==1&&[[logger currentConsoleLogStats][@"pendingLines"] intValue]==0&&consoleLive==0);
        [logger beginConsoleLogging];[logger appendConsoleLogWithLevel:@"log" message:@"recovered"];[logger finishConsoleLogging];assert([consoleText(logger.runPath) containsString:@"recovered"]);
    }
    // A formatter that began in one run cannot publish after finish/reopen.
    TLinkJSRuntimeCore *race=consoleStart([root stringByAppendingPathComponent:@"race"],@"race");
    consoleTakeSystemRecords();
    dispatch_semaphore_t entered=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0),done=dispatch_semaphore_create(0);
    probe=[ConsoleMessageProbe new];probe->callback=[entered,release]{dispatch_semaphore_signal(entered);consoleWait(release);};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{[race appendConsoleLogWithLevel:@"log" message:(NSString *)probe];dispatch_semaphore_signal(done);});
    consoleWait(entered);assert([[race currentConsoleLogStats][@"pendingLines"] intValue]==1);NSString *oldPath=race.runPath;
    [race finishConsoleLogging];[race configure:[root stringByAppendingPathComponent:@"race"] run:@"next"];[race prepareConsoleLogFiles];[race beginConsoleLogging];
    [race appendConsoleLogWithLevel:@"log" message:@"fresh"];dispatch_semaphore_signal(release);consoleWait(done);[race finishConsoleLogging];
    assert(![consoleText(oldPath) containsString:@"late-log"]&&![consoleText(race.runPath) containsString:@"late-log"]&&[consoleText(race.runPath) containsString:@"fresh"]&&[[race currentConsoleLogStats][@"pendingLines"] intValue]==0);
    systemRecords=consoleTakeSystemRecords();for(NSDictionary *record in systemRecords)assert(![record[@"text"] containsString:@"late-log"]);
    // Formatter faults release provisional reservations as well.
    TLinkJSRuntimeCore *format=consoleStart([root stringByAppendingPathComponent:@"format"],@"format");
    for(bool cpp:{false,true}){probe=[ConsoleMessageProbe new];probe->callback=[cpp]{if(cpp)throw std::runtime_error("format fault");[NSException raise:@"LogFixture" format:@"format fault"];};[format appendConsoleLogWithLevel:@"log" message:(NSString *)probe];}
    [format finishConsoleLogging];assert([[format currentConsoleLogStats][@"dropped"] intValue]==2&&[[format currentConsoleLogStats][@"pendingLines"] intValue]==0);
    consoleTakeSystemRecords();
    probe=[ConsoleMessageProbe new];[format appendConsoleLogWithLevel:@"log" message:(NSString *)probe];assert(probe.calls==0&&[[format currentConsoleLogStats][@"dropped"] intValue]==2);
    assert(consoleTakeSystemRecords().count==0);
    TLinkJSRuntimeCore *concurrent=consoleStart([root stringByAppendingPathComponent:@"concurrent"],@"concurrent");dispatch_group_t group=dispatch_group_create();
    for(unsigned t=0;t<8;++t)dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{for(unsigned n=0;n<100;++n)[concurrent appendConsoleLogWithLevel:@"log" message:[NSString stringWithFormat:@"concurrent-%u-%u",t,n]];});
    assert(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0);[concurrent finishConsoleLogging];stats=[concurrent currentConsoleLogStats];
    assert([stats[@"accepted"] intValue]+[stats[@"dropped"] intValue]==800&&[stats[@"pendingLines"] intValue]==0&&[stats[@"peakPendingLines"] intValue]<=64);
    assert([consoleText(concurrent.runPath) componentsSeparatedByString:@" concurrent-"].count-1==[stats[@"accepted"] unsignedIntegerValue]);
    NSString *previous=now.runPath,*before=consoleText(previous),*invalid=[root stringByAppendingPathComponent:@"not-directory"];
    assert([[@"file" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:invalid atomically:YES]);[now configure:invalid run:@"invalid"];[now prepareConsoleLogFiles];[now beginConsoleLogging];[now appendConsoleLogWithLevel:@"log" message:@"must not use old path"];[now finishConsoleLogging];
    assert(now.runPath==nil&&now.latestPath==nil&&[consoleText(previous) isEqual:before]&&consoleLive==0);
    // Compare the actual JSCore hook with the frozen synchronous hook, while
    // both disk queues are held. Only the new hook must return without NSLog.
    TLinkJSRuntimeCore *hookOld=[TLinkJSRuntimeCore new],*hookNew=consoleStart([root stringByAppendingPathComponent:@"hook-new"],@"hook");
    [hookOld configure:[root stringByAppendingPathComponent:@"hook-old"] run:@"hook"];[hookOld legacyPrepareConsoleLogFiles];[hookOld beginConsoleLogging];
    JSContext *oldContext=[JSContext new],*newContext=[JSContext new];[hookOld legacyInstallConsole:oldContext];[hookNew installConsole:newContext];
    [hookOld holdWriter];[hookNew holdWriter];consoleTakeSystemRecords();
    const unichar nulUnits[]={'a',0,'b'};NSString *nul=[NSString stringWithCharacters:nulUnits length:3];
    NSArray *messages=@[@"ordinary",@"",@"ảnh 测试 😀\r\nnext",@"one;;two",@"tab\tnewline\n",nul];
    NSArray *levels=@[@"log",@"info",@"warn",@"error",@"warn:detail",@""];
    for(unsigned n=0;n<32;++n)[oldContext[@"_tlinkautoLog"] callWithArguments:@[levels[n%levels.count],messages[n%messages.count]]];
    NSArray *expectedSystem=consoleTakeSystemRecords();assert(expectedSystem.count==32);
    for(NSDictionary *record in expectedSystem)assert(![record[@"queued"] boolValue]);
    [hookOld resumeWriter];[hookOld finishConsoleLogging];
    for(unsigned n=0;n<32;++n)[newContext[@"_tlinkautoLog"] callWithArguments:@[levels[n%levels.count],messages[n%messages.count]]];
    assert(!oldContext.exception&&!newContext.exception&&consoleTakeSystemRecords().count==0&&[[hookNew currentConsoleLogStats][@"pendingLines"] intValue]==32);
    [hookNew resumeWriter];[hookNew finishConsoleLogging];systemRecords=consoleTakeSystemRecords();
    assert([[expectedSystem valueForKey:@"text"] isEqual:[systemRecords valueForKey:@"text"]]);
    for(NSDictionary *record in systemRecords)assert([record[@"queued"] boolValue]);
    assert([consoleText(hookOld.runPath) isEqual:consoleText(hookNew.runPath)]&&[consoleText(hookOld.latestPath) isEqual:consoleText(hookNew.latestPath)]);
    // A blocked system sink holds an admission slot, never the JS caller.
    TLinkJSRuntimeCore *slow=consoleStart([root stringByAppendingPathComponent:@"slow-system"],@"slow-system");JSContext *slowContext=[JSContext new];[slow installConsole:slowContext];
    consoleSystemEntered=dispatch_semaphore_create(0);consoleSystemRelease=dispatch_semaphore_create(0);
    assert([[slowContext evaluateScript:@"_tlinkautoLog('log','slow-system'); 42"] toInt32]==42);consoleWait(consoleSystemEntered);
    assert([[slowContext evaluateScript:@"_tlinkautoLog('info','after-slow'); _tlinkautoLog('warn','third'); 43"] toInt32]==43&&[[slow currentConsoleLogStats][@"pendingLines"] intValue]==3);
    dispatch_semaphore_signal(consoleSystemRelease);[slow finishConsoleLogging];consoleSystemEntered=nil;consoleSystemRelease=nil;
    systemRecords=consoleTakeSystemRecords();assert(systemRecords.count==3&&[[slow currentConsoleLogStats][@"pendingTotalBytesReserved"] intValue]==0);
    assert([systemRecords[0][@"text"] hasSuffix:@": slow-system"]&&[systemRecords[1][@"text"] hasSuffix:@": after-slow"]&&[systemRecords[2][@"text"] hasSuffix:@": third"]);
    // System faults (including after capture) never replay or skip disk output.
    for(unsigned fault:{1U,2U}){
        TLinkJSRuntimeCore *logger=consoleStart([root stringByAppendingPathComponent:[NSString stringWithFormat:@"system-fault%u",fault]],@"system-fault");JSContext *context=[JSContext new];[logger installConsole:context];
        consoleSystemFault=fault;assert([[context evaluateScript:@"_tlinkautoLog('error','system-fault'); 44"] toInt32]==44);[logger finishConsoleLogging];consoleSystemFault=0;
        systemRecords=consoleTakeSystemRecords();stats=[logger currentConsoleLogStats];
        assert(systemRecords.count==2&&[systemRecords[0][@"text"] hasSuffix:@": system-fault"]&&[systemRecords[1][@"text"] containsString:@"systemFailures=1"]);
        assert([stats[@"systemFailures"] intValue]==1&&[stats[@"writeFailures"] intValue]==0&&[stats[@"pendingLines"] intValue]==0&&[consoleText(logger.runPath) containsString:@" system-fault\n"]&&[consoleText(logger.latestPath) containsString:@" system-fault\n"]);
        [logger beginConsoleLogging];[context evaluateScript:@"_tlinkautoLog('log','recovered-system')"];[logger finishConsoleLogging];
        assert([[logger currentConsoleLogStats][@"systemFailures"] intValue]==1&&[consoleText(logger.runPath) containsString:@"recovered-system"]&&consoleLive==0);consoleTakeSystemRecords();
    }
    consoleSystemRecords=nil;
    puts("Console logger Foundation passed: frozen bytes/independent rotations/missing files, 64-entry burst uses 4 metadata checks and 2 writes/opens/closes versus 128 each, no batch retry after NS/C++/post-write/one-path faults, held caps, early rejection, Unicode snapshots, late-run isolation, concurrent producers and zero live handles/charges. No real script or device syslog workload qualified.");
    puts("Console system logging passed: actual/frozen JSCore hook/output parity, asynchronous held/blocked sink, shared 64-entry disk/system admission, immutable bounded Unicode snapshots, NS/C++ failure accounting/recovery and finish drain without replay. Device syslog qualification pending.");
}}
