#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <os/lock.h>
#include "../shared/TLinkConsoleLogBudget.h"
#include "../shared/TLinkHelperConsoleLog.inc"
#include "../shared/TLinkJSConsolePrelude.h"
#include <cassert>
#include <vector>
#include <cstdio>
static const unsigned long long kTLinkJSHelperMaxConsoleLogBytes=512*1024;
static std::atomic<unsigned> systemCalls{0};
static void ProducerSystem(NSString *format,NSString *run,NSString *level,NSString *message){(void)format;(void)run;(void)level;(void)message;++systemCalls;}
#include "ConsoleProducerOwner.inc"
@interface TLinkJSRuntimeCore:NSObject {
    os_unfair_lock _logStateLock;
    BOOL _acceptingLogs;
    std::shared_ptr<TLinkConsoleLogBudget> _logBudget;
    std::vector<std::shared_ptr<TLinkConsoleLogPermit>> _held;
}
- (BOOL)canAcceptConsoleLog;
- (void)hold;
- (void)releaseAll;
- (void)stop;
- (TLinkConsoleLogStats)stats;
@end
@implementation TLinkJSRuntimeCore
- (instancetype)init{self=[super init];if(self){_logStateLock=OS_UNFAIR_LOCK_INIT;_acceptingLogs=YES;_logBudget=std::make_shared<TLinkConsoleLogBudget>();}return self;}
#include "ConsoleProducerGate.inc"
- (void)hold{for(unsigned n=0;n<64;++n){auto permit=TLinkConsoleLogPermit::acquire(_logBudget);assert(permit);_held.push_back(permit);}}
- (void)releaseAll{_held.clear();}
- (void)stop{os_unfair_lock_lock(&_logStateLock);_acceptingLogs=NO;os_unfair_lock_unlock(&_logStateLock);}
- (TLinkConsoleLogStats)stats{return _logBudget->snapshot();}
@end
static void installCore(JSContext *context,TLinkJSRuntimeCore *instance){__weak TLinkJSRuntimeCore *weakSelf=instance;
#include "ConsoleProducerCoreHook.inc"
}
static void installHelper(JSContext *ctx,std::shared_ptr<TLinkHelperConsoleAsync::Owner> consoleOwner){
#include "ConsoleProducerHelperHook.inc"
}
static void evaluate(JSContext *context,NSString *source){[context evaluateScript:source];if(context.exception)fprintf(stderr,"Producer JSCore exception: %s\n",context.exception.toString.UTF8String);assert(!context.exception);}
static void installPrelude(JSContext *context){evaluate(context,TLinkJSConsolePrelude());evaluate(context,@"var converted=0;var value={toJSON:function(){++converted;return 'ảnh 😀';}};");}
static void rootCases(){
    TLinkJSRuntimeCore *owner=[TLinkJSRuntimeCore new];JSContext *context=[JSContext new];__block unsigned calls=0;__block NSString *held=nil;
    context[@"_tlinkautoLog"]=^(NSString *level,NSString *message){(void)level;++calls;held=[message copy];};installCore(context,owner);installPrelude(context);
    [owner hold];evaluate(context,@"for(var i=0;i<1000;++i)console.log(value);");
    assert(calls==0&&[owner stats].dropped==1000&&[context[@"converted"] toUInt32]==0);[owner releaseAll];
    evaluate(context,@"console.info(value);");assert(calls==1&&[context[@"converted"] toUInt32]==1&&[held isEqual:@"\"ảnh 😀\""]);
    evaluate(context,@"console.log('x'.repeat(4095)+'😀','tail');");assert(held.length==4097);
    NSString *snapshot=held;assert(TLinkConsoleLogPrefix(snapshot.length,4096,[snapshot](size_t n){return [snapshot characterAtIndex:n];})==4095);
    [owner stop];evaluate(context,@"console.log(value);");assert(calls==2&&[context[@"converted"] toUInt32]==1&&[owner stats].pending==0);
    __weak TLinkJSRuntimeCore *weak=nil;@autoreleasepool{TLinkJSRuntimeCore *temporary=[TLinkJSRuntimeCore new];weak=temporary;installCore(context,temporary);}
    assert(!weak);evaluate(context,@"console.log(value);");assert(calls==2);
}
static void helperCases(NSString *root){
    NSString *path=[root stringByAppendingPathComponent:@"run.log"],*latest=[root stringByAppendingPathComponent:@"latest.log"];
    assert([[NSData data] writeToFile:path atomically:YES]&&[[NSData data] writeToFile:latest atomically:YES]);
    auto owner=TLinkHelperConsoleAsync::Create(path,latest);assert(owner);JSContext *context=[JSContext new];
    context[@"_tlinkautoLog"]=^(NSString *level,NSString *message){owner->submit(@"run",level,message);};installHelper(context,owner);installPrelude(context);
    dispatch_semaphore_t entered=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0);
    dispatch_async(TLinkHelperConsoleAsync::Queue(),^{dispatch_semaphore_signal(entered);assert(dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);});
    assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    for(unsigned n=0;n<64;++n){owner->submit(@"run",@"log",@"held");}
    auto other=TLinkHelperConsoleAsync::Create(path,latest);assert(other&&!other->maySubmit()&&other->stats().dropped==1&&other->stats().pending==0);
    evaluate(context,@"for(var i=0;i<1000;++i)console.log(value);");assert([context[@"converted"] toUInt32]==0&&owner->stats().dropped==1000&&owner->stats().pending==64);
    dispatch_semaphore_signal(release);assert(owner->close()&&other->close());
    evaluate(context,@"console.log(value);");assert(owner->stats().dropped==1001&&owner->stats().pending==0&&systemCalls==64&&[context[@"converted"] toUInt32]==0);
    auto next=TLinkHelperConsoleAsync::Create(path,latest);installHelper(context,next);
    context[@"_tlinkautoLog"]=^(NSString *level,NSString *message){next->submit(@"run",level,message);};
    evaluate(context,@"console.log(value);");assert(next->close()&&next->stats().accepted==1&&next->stats().pending==0&&[context[@"converted"] toUInt32]==1);
    std::shared_ptr<TLinkHelperConsoleAsync::Owner> fallback;installHelper(context,fallback);__block unsigned fallbackCalls=0;
    context[@"_tlinkautoLog"]=^(NSString *level,NSString *message){(void)level;(void)message;++fallbackCalls;};evaluate(context,@"console.log(value);");assert(fallbackCalls==1&&[context[@"converted"] toUInt32]==2);
    assert(TLinkHelperConsoleAsync::GlobalBudget()->snapshot().pending==0);
}
int main(int argc,char **argv){@autoreleasepool{
    (void)&TLinkHelperConsoleEmit;(void)&TLinkHelperConsoleAsync::Diagnostics;
    assert(argc==2);rootCases();helperCases([NSString stringWithUTF8String:argv[1]]);
    puts("Console producer Foundation passed: actual root/helper preflight hooks and shared JSCore prelude, 1000 refusals each with no conversions, recovery, Unicode lookahead, closed/weak owners, helper global admission, real queued files and zero final permits. Device performance pending.");
}return 0;}
