#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <dispatch/dispatch.h>
#include <cassert>
#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <set>
#include <thread>
#include <vector>
#include <stdexcept>
#include <atomic>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include "ProductionLogAPI.h"
static NSString *logPath;
static NSMutableArray *queued,*messages;
static unsigned enqueueMode=0,sinkFault=0,ioFault=0,writeInterrupts=0;
static size_t maxWrite=SIZE_MAX;
static off_t failAfter=-1;
static std::set<int> descriptors;
static dispatch_semaphore_t sinkEntered,sinkRelease;
static std::atomic<bool> holdSink{false};
static NSString *POCLogFilePath(){return logPath;}
static NSString *FixtureLogStamp(){return @"stamp";}
static dispatch_queue_t FixtureLogQueue(dispatch_queue_t queue){if(enqueueMode==5)return nil;return queue;}
static void FixtureLogEnqueue(dispatch_queue_t queue,dispatch_block_t block){
    if(enqueueMode==1)[NSException raise:@"LogFixture" format:@"enqueue"];
    if(enqueueMode==2)throw std::runtime_error("enqueue");
    if(enqueueMode==3)return;
    if(enqueueMode==4){dispatch_async(queue,block);return;}
    @synchronized(queued){[queued addObject:[block copy]];}
}
static void FixtureSystemLog(NSString *format,...){
    if(holdSink){dispatch_semaphore_signal(sinkEntered);assert(dispatch_semaphore_wait(sinkRelease,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    if(sinkFault==1)[NSException raise:@"LogFixture" format:@"system"];
    if(sinkFault==2)throw std::runtime_error("system");
    va_list args;va_start(args,format);NSString *text=[[NSString alloc] initWithFormat:format arguments:args];va_end(args);
    @synchronized(messages){[messages addObject:text?:@""];}
}
static int FixtureLogOpen(const char *path,int flags,mode_t mode){if(ioFault==1){errno=EACCES;return -1;}int fd=::open(path,flags,mode);if(fd>=0)assert(descriptors.insert(fd).second);return fd;}
static int FixtureLogFlock(int fd,int op){if(ioFault==2){errno=EWOULDBLOCK;return -1;}return ::flock(fd,op);}
static int FixtureLogStat(int fd,struct stat *info){if(ioFault==3){errno=EIO;return -1;}return ::fstat(fd,info);}
static int FixtureLogTruncate(int fd,off_t length){if(ioFault==4){errno=EIO;return -1;}return ::ftruncate(fd,length);}
static int64_t FixtureLogWrite(int fd,const uint8_t *bytes,size_t count){
    if(writeInterrupts){--writeInterrupts;errno=EINTR;return -1;}
    if(ioFault==5){errno=EIO;return -1;}if(ioFault==6)return 0;
    count=std::min(count,maxWrite);
    if(failAfter>=0){const off_t size=::lseek(fd,0,SEEK_END);if(size>=failAfter){errno=EIO;return -1;}count=std::min(count,size_t(failAfter-size));}
    return ::write(fd,bytes,count);
}
static int FixtureLogClose(int fd){assert(descriptors.erase(fd)==1);const int result=::close(fd);if(ioFault==7){errno=EIO;return -1;}return result;}
#include "ProductionLogUnderTest.inc"
#include "ProductionLogLegacy.inc"
#include "../stream-app/streamd/TLinkScriptLogBuffer.inc"
@class TLinkJSFileHandle;
#include "ScriptLogSession.inc"
#include "ScriptLogLegacySession.inc"
static TLinkScriptSession *sTLinkScriptSession;
static LegacyScriptSession *sLegacyScriptSession;
static NSString *const kTLinkScriptsRootPath=@"fixture-root";
static NSString *sTLinkLastScriptError=@"fixture";
static uint64_t sTLinkLastScriptErrorTs=9;
static unsigned long long TLinkNowMs(){return 42;}
static BOOL TLinkScriptIsActive(id session){return [[(TLinkScriptSession *)session state] isEqual:@"running"];}
static NSData *TLinkSuccess(NSString *value){return [[NSString stringWithFormat:@"0;;%@\r\n",value] dataUsingEncoding:NSUTF8StringEncoding];}
#include "ScriptLogAppend.inc"
#include "ScriptLogAppendLegacy.inc"
#include "ScriptLogStatus.inc"
#include "ScriptLogStatusLegacy.inc"
#include "ScriptLogClear.inc"
#include "ScriptLogClearLegacy.inc"
#include "ScriptLogHooks.inc"
#include "ScriptLogHooksLegacy.inc"
static void drain(){@autoreleasepool {
    for(;;){
        dispatch_block_t work=nil;
        @synchronized(queued){if(queued.count){work=(dispatch_block_t)queued.firstObject;[queued removeObjectAtIndex:0];}}
        if(!work)break;
        work();work=nil;
    }
}}
static void resetFile(){assert(descriptors.empty());[[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];[messages removeAllObjects];}
static void healthyCases(NSString *root){
    NSString *current=[root stringByAppendingPathComponent:@"current.log"],*before=[root stringByAppendingPathComponent:@"before.log"];
    for(NSString *text in @[@"",@"ASCII %s",@"ảnh 测试 😀",@"a\0b",[@"x" stringByPaddingToLength:3000 withString:@"x" startingAtIndex:0]]){
        logPath=before;resetFile();FixtureLegacyLogf("script[%s]: %s","id",text.UTF8String);
        NSData *expected=[NSData dataWithContentsOfFile:before];NSArray *expectedSystem=[messages copy];
        logPath=current;resetFile();POCLogf("script[%s]: %s","id",text.UTF8String);assert(![NSFileManager.defaultManager fileExistsAtPath:current]);
        drain();assert([expected isEqual:[NSData dataWithContentsOfFile:current]]&&[expectedSystem isEqual:messages]);
        assert(POCLogGetStatistics().pending==0&&descriptors.empty());
    }
}
static void writerCases(){
    NSData *line=[@"abcdef" dataUsingEncoding:NSUTF8StringEncoding];
    resetFile();maxWrite=2;writeInterrupts=2;assert(POCLogWriteData(line,logPath));maxWrite=SIZE_MAX;
    assert([[NSData dataWithContentsOfFile:logPath] isEqual:line]);
    resetFile();failAfter=3;assert(!POCLogWriteData(line,logPath));failAfter=-1;
    assert([[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:logPath] encoding:NSUTF8StringEncoding] isEqual:@"abc"]);
    for(unsigned fault=1;fault<=7;++fault){
        resetFile();if(fault==4){NSMutableData *large=[NSMutableData dataWithLength:1048576];assert([large writeToFile:logPath atomically:YES]);}
        ioFault=fault;assert(!POCLogWriteData(line,logPath));ioFault=0;assert(descriptors.empty());assert(POCLogWriteData(line,logPath));
    }
    resetFile();NSMutableData *full=[NSMutableData dataWithLength:1048576];assert([full writeToFile:logPath atomically:YES]);
    assert(POCLogWriteData(line,logPath)&&[[NSData dataWithContentsOfFile:logPath] isEqual:line]);
    resetFile();NSString *target=[logPath stringByAppendingString:@".foreign"];assert([line writeToFile:target atomically:YES]);
    assert(::symlink(target.fileSystemRepresentation,logPath.fileSystemRepresentation)==0);assert(!POCLogWriteData(line,logPath));
    assert([[NSData dataWithContentsOfFile:target] isEqual:line]);[[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    assert(::link(target.fileSystemRepresentation,logPath.fileSystemRepresentation)==0);assert(!POCLogWriteData(line,logPath));
    [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];[[NSFileManager defaultManager] removeItemAtPath:target error:nil];
    assert(::mkfifo(logPath.fileSystemRepresentation,0600)==0);assert(!POCLogWriteData(line,logPath));resetFile();assert(descriptors.empty());
}
static void queueCases(){
    resetFile();auto before=POCLogGetStatistics();
    @autoreleasepool {for(unsigned n=0;n<1000;++n)POCLogf("held %u",n);}
    auto held=POCLogGetStatistics();assert(held.pending==64&&held.dropped==before.dropped+936);drain();assert(POCLogGetStatistics().pending==0);
    before=POCLogGetStatistics();std::vector<std::thread> producers;
    for(unsigned t=0;t<8;++t){producers.emplace_back([t]{@autoreleasepool {for(unsigned n=0;n<100;++n)POCLogf("producer %u:%u",t,n);}});}
    for(auto &producer:producers){producer.join();}
    held=POCLogGetStatistics();assert(held.pending==64&&held.dropped==before.dropped+736);drain();
    for(unsigned mode:{1U,2U,3U,5U}){
        @autoreleasepool {enqueueMode=mode;POCLogf("enqueue fault");enqueueMode=0;}
        assert(POCLogGetStatistics().pending==0);
    }
    for(unsigned fault=1;fault<=2;++fault){
        resetFile();before=POCLogGetStatistics();sinkFault=fault;POCLogf("system failure");drain();sinkFault=0;
        assert(POCLogGetStatistics().systemFailures==before.systemFailures+1&&[NSData dataWithContentsOfFile:logPath].length>0);
    }
    // Real owner queue: a held system backend cannot block the producer/session.
    resetFile();enqueueMode=4;holdSink=true;POCLogf("held real backend");
    assert(dispatch_semaphore_wait(sinkEntered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    assert(POCLogGetStatistics().pending==1);
    TLinkScriptSession *session=[TLinkScriptSession new];session.sessionId=@"held";session.state=@"running";
    sTLinkScriptSession=session;TLinkScriptAppendLog(session,@"while sink held");
    assert([TLinkScriptStatusDictionary()[@"log_tail"] count]==1&&POCLogGetStatistics().pending==2);sTLinkScriptSession=nil;
    holdSink=false;dispatch_semaphore_signal(sinkRelease);
    dispatch_sync(POCLogQueue(),^{});enqueueMode=0;
    assert(POCLogGetStatistics().pending==0&&descriptors.empty());
}
static void scriptCases(){
    __weak TLinkScriptSession *weak=nil;
    @autoreleasepool {
    TLinkScriptSession *session=[TLinkScriptSession new];LegacyScriptSession *old=[LegacyScriptSession new];
    session.sessionId=old.sessionId=@"session";session.state=old.state=@"running";session.logs=[TLinkScriptLogBuffer new];old.logs=[NSMutableArray array];
    sTLinkScriptSession=session;sLegacyScriptSession=old;
    for(unsigned n=0;n<450;++n){@autoreleasepool {
        NSString *line=[NSString stringWithFormat:@"row %u ảnh\0测试",n];TLinkScriptAppendLog(session,line);LegacyScriptAppendLog(old,line);
        assert([[session.logs tail:20] isEqual:[old.logs subarrayWithRange:NSMakeRange(old.logs.count-MIN(old.logs.count,NSUInteger(20)),MIN(old.logs.count,NSUInteger(20)))]]);
    }}
    NSArray *tail=[session.logs tail:50];assert([tail isEqual:[old.logs subarrayWithRange:NSMakeRange(150,50)]]);
    NSMutableDictionary *status=[TLinkScriptStatusDictionary() mutableCopy];assert(status[@"log_diagnostics"]);[status removeObjectForKey:@"log_diagnostics"];
    assert([status isEqual:LegacyScriptStatusDictionary()]);assert([TLinkHandleClearScriptLog(@"") isEqual:LegacyClearScriptLog(@"")]);
    assert(session.logs.count==0&&tail.count==50);drain();
    NSString *huge=[@"x" stringByPaddingToLength:20000 withString:@"x" startingAtIndex:0];TLinkScriptAppendLog(session,huge);
    assert(session.logs.truncated==1&&[[session.logs tail:1][0] hasSuffix:@" [truncated]"]&&[[session.logs tail:1][0] length]<4200);drain();
    JSContext *context=[JSContext new];FixtureLogHooks(context,session);[context evaluateScript:@"console.log('log');console.error('error');device.log('device')"];assert(!context.exception);drain();
    JSContext *legacyContext=[JSContext new];LegacyLogHooks(legacyContext,old);[legacyContext evaluateScript:@"console.log('log');console.error('error');device.log('device')"];assert(!legacyContext.exception);
    assert([[session.logs tail:3] isEqual:[old.logs subarrayWithRange:NSMakeRange(0,3)]]);
    TLinkScriptAppendLog(session,@"late owned backend");weak=session;sTLinkScriptSession=nil;sLegacyScriptSession=nil;
    session=nil;context=nil;old=nil;legacyContext=nil;
    }
    assert(!weak&&POCLogGetStatistics().pending==1);drain();
}
int main(int argc,char **argv){@autoreleasepool {
    assert(argc==2);NSString *root=[NSString stringWithUTF8String:argv[1]];queued=[NSMutableArray array];messages=[NSMutableArray array];
    sinkEntered=dispatch_semaphore_create(0);sinkRelease=dispatch_semaphore_create(0);
    puts("Production logs Foundation: actual/frozen raw formatter, real queue/file guards and session retention");
    healthyCases(root);writerCases();queueCases();scriptCases();
    assert(POCLogGetStatistics().pending==0&&descriptors.empty());
    puts("Production logs passed: frozen formatted system/file bytes, partial/EINTR/fault/close cleanup, exact file rotation, symlink/hardlink/FIFO refusal, 64/65 held admission, enqueue/system faults, real blocked-backend independence, 450 FIFO/tail/status/clear comparisons, large-text cap, actual JS hooks and owner retirement. Device latency/IO durability remain unqualified.");
}}
