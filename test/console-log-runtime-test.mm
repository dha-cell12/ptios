#import <Foundation/Foundation.h>
#import <os/lock.h>
#include "../shared/TLinkConsoleLogBudget.h"
#include <cassert>
#include <atomic>
#include <cstdio>
#include <functional>
#include <stdexcept>
#include "ConsoleLogConstants.h"
#include "ConsoleLogHelpers.inc"
static std::atomic<unsigned> consoleFault{0},consoleLive{0};
@interface ConsoleLogClock : NSObject
+ (NSDate *)date;
@end
@implementation ConsoleLogClock
+ (NSDate *)date {return [NSDate dateWithTimeIntervalSince1970:1234567890];}
@end
@interface ConsoleLogFileHandle : NSObject {
    NSFileHandle *_handle;BOOL _closed;
}
+ (instancetype)fileHandleForWritingAtPath:(NSString *)path;
- (unsigned long long)seekToEndOfFile;
- (void)writeData:(NSData *)data;
- (void)closeFile;
@end
@implementation ConsoleLogFileHandle
+ (instancetype)fileHandleForWritingAtPath:(NSString *)path {
    NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];if(!handle)return nil;
    ConsoleLogFileHandle *result=[self new];result->_handle=handle;++consoleLive;return result;
}
- (unsigned long long)seekToEndOfFile {if(consoleFault==1)[NSException raise:@"LogFixture" format:@"seek failed"];return [_handle seekToEndOfFile];}
- (void)writeData:(NSData *)data {if(consoleFault==2)throw std::runtime_error("write failed");[_handle writeData:data];}
- (void)closeFile {
    if(_closed)return;_closed=YES;[_handle closeFile];assert(consoleLive.fetch_sub(1)>0);
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
}
- (void)prepareConsoleLogFiles;
- (BOOL)appendConsoleData:(NSData *)data toConsolePath:(NSString *)path;
- (BOOL)writeConsoleData:(NSData *)data runPath:(NSString *)runPath latestPath:(NSString *)latestPath;
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
@end
@implementation TLinkJSRuntimeCore
- (instancetype)init {self=[super init];if(self){_logQueue=dispatch_queue_create("fixture.log",DISPATCH_QUEUE_SERIAL);_logStateLock=OS_UNFAIR_LOCK_INIT;_logBudget=std::make_shared<TLinkConsoleLogBudget>();}return self;}
- (void)configure:(NSString *)root run:(NSString *)run {_bundlePath=[root copy];_runId=[run copy];}
- (NSString *)runPath {return _consoleLogPath;}
- (NSString *)latestPath {return _consoleLatestLogPath;}
- (void)holdWriter {dispatch_suspend(_logQueue);}
- (void)resumeWriter {dispatch_resume(_logQueue);}
#define NSDate ConsoleLogClock
#define NSFileHandle ConsoleLogFileHandle
#include "ConsoleLogMethods.inc"
#define prepareConsoleLogFiles legacyPrepareConsoleLogFiles
#define appendLine legacyAppendLine
#define appendConsoleLogWithLevel legacyAppendConsoleLogWithLevel
#include "fixtures/console-log-legacy-v1.inc"
#undef appendConsoleLogWithLevel
#undef appendLine
#undef prepareConsoleLogFiles
#undef NSFileHandle
#undef NSDate
@end
static void consoleWait(dispatch_semaphore_t semaphore){assert(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0);}
static NSString *consoleText(NSString *path){return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]?:@"";}
static TLinkJSRuntimeCore *consoleStart(NSString *root,NSString *run){TLinkJSRuntimeCore *logger=[TLinkJSRuntimeCore new];[logger configure:root run:run];[logger prepareConsoleLogFiles];[logger beginConsoleLogging];return logger;}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2);NSString *root=[NSString stringWithUTF8String:argv[1]];
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
    TLinkJSRuntimeCore *full=consoleStart([root stringByAppendingPathComponent:@"full"],@"full");[full holdWriter];
    for(unsigned n=0;n<100;++n)[full appendConsoleLogWithLevel:@"log" message:@"bounded"];
    ConsoleMessageProbe *probe=[ConsoleMessageProbe new];[full appendConsoleLogWithLevel:@"log" message:(NSString *)probe];
    NSDictionary *stats=[full currentConsoleLogStats];assert([stats[@"pendingLines"] intValue]==64&&[stats[@"pendingBytesReserved"] intValue]==1024*1024&&[stats[@"dropped"] intValue]==37&&probe.calls==0);
    [full resumeWriter];[full finishConsoleLogging];assert([[full currentConsoleLogStats][@"pendingLines"] intValue]==0&&[consoleText(full.runPath) containsString:@"dropped=37"]&&consoleLive==0);
    TLinkJSRuntimeCore *cut=consoleStart([root stringByAppendingPathComponent:@"cut"],@"cut");[cut holdWriter];
    NSMutableString *message=[[@"x" stringByPaddingToLength:4095 withString:@"x" startingAtIndex:0] mutableCopy];[message appendString:@"😀tail"];
    NSString *level=[@"l" stringByPaddingToLength:1000 withString:@"l" startingAtIndex:0];[cut appendConsoleLogWithLevel:level message:message];[message setString:@"changed"];
    [cut resumeWriter];[cut finishConsoleLogging];NSString *text=consoleText(cut.runPath);
    assert([text containsString:@" [truncated]"]&&![text containsString:@"😀"]&&![text containsString:@"changed"]&&[[cut currentConsoleLogStats][@"truncated"] intValue]==1);
    for(unsigned fault=1;fault<=4;++fault){TLinkJSRuntimeCore *logger=consoleStart([root stringByAppendingPathComponent:[NSString stringWithFormat:@"fault%u",fault]],@"fault");consoleFault=fault;
        [logger appendConsoleLogWithLevel:@"log" message:@"fault"];[logger finishConsoleLogging];consoleFault=0;
        assert([[logger currentConsoleLogStats][@"writeFailures"] intValue]==1&&[[logger currentConsoleLogStats][@"pendingLines"] intValue]==0&&consoleLive==0);
        [logger beginConsoleLogging];[logger appendConsoleLogWithLevel:@"log" message:@"recovered"];[logger finishConsoleLogging];assert([consoleText(logger.runPath) containsString:@"recovered"]);
    }
    // A formatter that began in one run cannot publish after finish/reopen.
    TLinkJSRuntimeCore *race=consoleStart([root stringByAppendingPathComponent:@"race"],@"race");
    dispatch_semaphore_t entered=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0),done=dispatch_semaphore_create(0);
    probe=[ConsoleMessageProbe new];probe->callback=[entered,release]{dispatch_semaphore_signal(entered);consoleWait(release);};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{[race appendConsoleLogWithLevel:@"log" message:(NSString *)probe];dispatch_semaphore_signal(done);});
    consoleWait(entered);assert([[race currentConsoleLogStats][@"pendingLines"] intValue]==1);NSString *oldPath=race.runPath;
    [race finishConsoleLogging];[race configure:[root stringByAppendingPathComponent:@"race"] run:@"next"];[race prepareConsoleLogFiles];[race beginConsoleLogging];
    [race appendConsoleLogWithLevel:@"log" message:@"fresh"];dispatch_semaphore_signal(release);consoleWait(done);[race finishConsoleLogging];
    assert(![consoleText(oldPath) containsString:@"late-log"]&&![consoleText(race.runPath) containsString:@"late-log"]&&[consoleText(race.runPath) containsString:@"fresh"]&&[[race currentConsoleLogStats][@"pendingLines"] intValue]==0);
    // Formatter faults release provisional reservations as well.
    TLinkJSRuntimeCore *format=consoleStart([root stringByAppendingPathComponent:@"format"],@"format");
    for(bool cpp:{false,true}){probe=[ConsoleMessageProbe new];probe->callback=[cpp]{if(cpp)throw std::runtime_error("format fault");[NSException raise:@"LogFixture" format:@"format fault"];};[format appendConsoleLogWithLevel:@"log" message:(NSString *)probe];}
    [format finishConsoleLogging];assert([[format currentConsoleLogStats][@"dropped"] intValue]==2&&[[format currentConsoleLogStats][@"pendingLines"] intValue]==0);
    probe=[ConsoleMessageProbe new];[format appendConsoleLogWithLevel:@"log" message:(NSString *)probe];assert(probe.calls==0&&[[format currentConsoleLogStats][@"dropped"] intValue]==2);
    TLinkJSRuntimeCore *concurrent=consoleStart([root stringByAppendingPathComponent:@"concurrent"],@"concurrent");dispatch_group_t group=dispatch_group_create();
    for(unsigned t=0;t<8;++t)dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{for(unsigned n=0;n<100;++n)[concurrent appendConsoleLogWithLevel:@"log" message:[NSString stringWithFormat:@"concurrent-%u-%u",t,n]];});
    assert(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0);[concurrent finishConsoleLogging];stats=[concurrent currentConsoleLogStats];
    assert([stats[@"accepted"] intValue]+[stats[@"dropped"] intValue]==800&&[stats[@"pendingLines"] intValue]==0&&[stats[@"peakPendingLines"] intValue]<=64);
    assert([consoleText(concurrent.runPath) componentsSeparatedByString:@" concurrent-"].count-1==[stats[@"accepted"] unsignedIntegerValue]);
    NSString *previous=now.runPath,*before=consoleText(previous),*invalid=[root stringByAppendingPathComponent:@"not-directory"];
    assert([[@"file" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:invalid atomically:YES]);[now configure:invalid run:@"invalid"];[now prepareConsoleLogFiles];[now beginConsoleLogging];[now appendConsoleLogWithLevel:@"log" message:@"must not use old path"];[now finishConsoleLogging];
    assert(now.runPath==nil&&now.latestPath==nil&&[consoleText(previous) isEqual:before]&&consoleLive==0);
    puts("Console logger Foundation passed: frozen ordinary bytes/rotation, held queue caps, early rejection, Unicode truncation/snapshots, NS/C++ I/O and formatter faults, late-run isolation, concurrent producers and zero live handles/charges. No real script or device syslog workload qualified.");
}}
