#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include "../shared/TLinkVPNBrokerBudget.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <stdexcept>
#include <thread>
#include <vector>

// Compile the complete current/frozen wrappers. Only identity, clock, run-loop
// driving and the asynchronous configuration provider are controlled.
enum class Mode {Inline,Nil,Never,OnLoop,Duplicate,Slow,ThrowNS,ThrowCPP,Race,Async};
static Mode mode=Mode::Inline;
static uint64_t tick=100,completeAt=300;
static double wallShift=0,wallJump=0;
static bool onMain=true,sources=true,setupOK=true,realClock=false;
static unsigned uidValue=0,gidValue=20,starts=0;
static std::atomic<unsigned> loops{0},waits{0};
static NSDictionary *providerResult;
static void (^heldReply)(NSDictionary *);
static dispatch_group_t workers=dispatch_group_create();
static uint64_t fixtureNow(){return realClock?TLinkHelperIO::nowMs():tick;}
static unsigned fixtureUID(){return uidValue;}
static unsigned fixtureGID(){return gidValue;}
static void deliver(){if(mode==Mode::OnLoop&&tick>=completeAt&&heldReply)heldReply(providerResult);}
class FixtureCompletion:public TLinkVPNBrokerCompletion {
public:
    bool valid()const{return setupOK&&TLinkVPNBrokerCompletion::valid();}
    bool wait(int milliseconds){
        ++waits;
        if(realClock)return TLinkVPNBrokerCompletion::wait(milliseconds);
        tick+=static_cast<unsigned>(milliseconds);deliver();return ready();
    }
};
@interface FixtureDate:NSObject
@property double target;
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds;
- (NSTimeInterval)timeIntervalSinceNow;
@end
@implementation FixtureDate
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds {
    FixtureDate *date=[FixtureDate new];date.target=tick/1000.0+wallShift+seconds;return date;
}
- (NSTimeInterval)timeIntervalSinceNow{return self.target-(tick/1000.0+wallShift);}
@end
@interface FixtureThread:NSObject
+ (BOOL)isMainThread;
@end
@implementation FixtureThread
+ (BOOL)isMainThread{return onMain;}
@end
@interface FixtureRunLoop:NSObject
+ (instancetype)mainRunLoop;
- (BOOL)runMode:(NSRunLoopMode)name beforeDate:(FixtureDate *)date;
@end
@implementation FixtureRunLoop
+ (instancetype)mainRunLoop {
    static FixtureRunLoop *loop;static dispatch_once_t once;
    dispatch_once(&once,^{loop=[FixtureRunLoop new];});return loop;
}
- (BOOL)runMode:(NSRunLoopMode)name beforeDate:(FixtureDate *)date {
    (void)name;(void)date;++loops;assert(!realClock&&onMain);
    wallShift+=wallJump;
    if(!sources)return NO;
    tick+=100;deliver();return YES;
}
@end
static NSDictionary *TLinkVPNResult(bool ok,NSString *code,NSDictionary *extra){
    NSMutableDictionary *value=extra?[extra mutableCopy]:[NSMutableDictionary dictionary];
    value[@"ok"]=@(ok);value[@"code"]=code;return value;
}
static void TLinkVPNConfigureIKEv2(NSString *server,NSString *remote,NSString *user,NSString *password,
                                  void (^completion)(NSDictionary *)){
    assert(([server isEqualToString:@"server"]&&[remote isEqualToString:@"remote"]&&
            [user isEqualToString:@"user"]&&[password isEqualToString:@"password"]));
    ++starts;heldReply=[completion copy];
    switch(mode){
        case Mode::Inline:completion(providerResult);break;
        case Mode::Nil:completion(nil);break;
        case Mode::Duplicate:completion(providerResult);completion(@{@"ok":@0,@"code":@"second"});break;
        case Mode::Slow:tick+=30000;completion(providerResult);break;
        case Mode::ThrowNS:completion(providerResult);[NSException raise:@"IKEv2Fixture" format:@"starter"];break;
        case Mode::ThrowCPP:completion(providerResult);throw std::runtime_error("starter");
        case Mode::Race:{
            std::vector<std::thread> threads;
            for(unsigned n=0;n<8;++n)threads.emplace_back([completion,n]{@autoreleasepool{
                completion(@{@"ok":@1,@"winner":@(n)});
            }});
            for(auto &thread:threads){thread.join();}
            break;
        }
        case Mode::Async:{
            NSDictionary *snapshot=providerResult;
            dispatch_group_async(workers,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
                @autoreleasepool{completion(snapshot);}
            });break;
        }
        case Mode::Never:case Mode::OnLoop:break;
    }
}
#define NSThread FixtureThread
#define NSRunLoop FixtureRunLoop
#define NSDate FixtureDate
#include "IKEv2SyncUnderTest.inc"
#include "IKEv2SyncLegacy.inc"
#undef NSDate
#undef NSRunLoop
#undef NSThread

static void reset(){
    assert(dispatch_group_wait(workers,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    heldReply=nil;providerResult=@{@"ok":@1,@"code":@"healthy",@"executor_uid":@999};
    mode=Mode::Inline;tick=100;completeAt=300;wallShift=0;wallJump=0;
    onMain=true;sources=true;setupOK=true;realClock=false;uidValue=0;gidValue=20;starts=0;loops=0;waits=0;
}
static NSDictionary *call(bool legacy=false){
    return legacy?LegacySyncIKEv2(@"server",@"remote",@"user",@"password"):
                  CurrentSyncIKEv2(@"server",@"remote",@"user",@"password");
}
static void timeout(NSDictionary *value){
    assert((![value[@"ok"] boolValue]&&[value[@"code"] isEqualToString:@"vpn_ikev2_helper_timeout"]));
    assert(value.count==3&&[value[@"executor_uid"] unsignedIntValue]==0);
}
static void lateResultReleased(){
    __weak NSDictionary *weakValue;
    @autoreleasepool{
        NSDictionary *value=[@{@"ok":@1,@"late":[NSUUID UUID].UUIDString} mutableCopy];
        weakValue=value;heldReply(value);
    }
    assert(!weakValue);
}
static void parityCases(){
    for(unsigned scenario=0;scenario<4;++scenario){@autoreleasepool{
        reset();
        if(scenario==1)providerResult=@{@"ok":@0,@"code":@"provider_failure",@"details":@[@1,@2]};
        if(scenario==2)uidValue=501;
        if(scenario==3)mode=Mode::OnLoop;
        NSDictionary *expected=call(true);unsigned previousStarts=starts;
        tick=100;NSDictionary *actual=call();assert([expected isEqual:actual]);
        assert(starts==previousStarts+(scenario==2?0:1));
    }}
    reset();NSDictionary *value=call();
    assert(([value[@"approval_path"] isEqualToString:@"privhelper_root_nevpnmanager_super_configuration"]));
    assert([value[@"executor_gid"] unsignedIntValue]==20);
    assert(([value[@"execution_process"] isEqualToString:@"privhelper_tsrootbinary"]));
}
static void deadlineCases(){
    for(unsigned scenario=0;scenario<6;++scenario){@autoreleasepool{
        reset();mode=Mode::Never;
        if(scenario==0)sources=false;
        if(scenario==1)onMain=false;
        if(scenario==2)wallJump=100000;
        if(scenario==3)wallJump=-100000;
        if(scenario==4){mode=Mode::OnLoop;completeAt=30100;}
        if(scenario==5)mode=Mode::Slow;
        timeout(call());assert(tick==30100&&starts==1);
        if(scenario==0)assert(loops==300&&waits==300);
        if(scenario==1)assert(loops==0&&waits==300);
        if(scenario==5)assert(loops==0&&waits==0);
        lateResultReleased();
    }}
    reset();setupOK=false;timeout(call());assert(starts==0);
    reset();tick=UINT64_MAX;timeout(call());assert(starts==0);
    reset();mode=Mode::Nil;timeout(call());assert(tick==100&&loops==0&&waits==0);lateResultReleased();
}
static void ownershipCases(){
    reset();mode=Mode::Duplicate;NSDictionary *first=call();
    assert(([first[@"code"] isEqualToString:@"healthy"]));lateResultReleased();
    for(unsigned kind=0;kind<2;++kind){
        reset();mode=kind?Mode::ThrowCPP:Mode::ThrowNS;
        __weak NSDictionary *weakValue;
        @autoreleasepool{
            providerResult=[@{@"ok":@1,@"unique":[NSUUID UUID].UUIDString} mutableCopy];weakValue=providerResult;
            bool caught=false;
            if(kind){try{(void)call();}catch(const std::runtime_error &){caught=true;}}
            else {@try{(void)call();}@catch(NSException *exception){(void)exception;caught=true;}}
            assert(caught&&starts==1);providerResult=nil;
        }
        // The retained callback survives unwind, but its accepted result does not.
        assert(!weakValue);lateResultReleased();
    }
    reset();NSDictionary *saved;
    @autoreleasepool{providerResult=[@{@"ok":@1,@"code":[NSUUID UUID].UUIDString} mutableCopy];saved=call();providerResult=nil;}
    assert([saved[@"ok"] boolValue]&&[saved[@"code"] length]>0);
    for(unsigned n=0;n<64;++n){@autoreleasepool{
        reset();mode=Mode::Race;NSDictionary *winner=call();
        assert([winner[@"ok"] boolValue]&&[winner[@"winner"] unsignedIntValue]<8);lateResultReleased();
    }}
    reset();mode=Mode::Async;onMain=false;realClock=true;
    // Real off-main caller and real semaphore/callback delivery. Join before
    // resetting fixture configuration; no shared fixture values are mutated.
    std::thread caller([]{@autoreleasepool{NSDictionary *result=call();assert([result[@"ok"] boolValue]);}});
    caller.join();assert(starts==1&&loops==0);
    assert(dispatch_group_wait(workers,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    lateResultReleased();reset();
}
int main(){@autoreleasepool{
    puts("IKEv2 helper Foundation: complete actual/frozen wrapper, synchronized callback and continuous wait");
    parityCases();deadlineCases();ownershipCases();reset();
    puts("IKEv2 helper passed: frozen healthy/root/error metadata, first-result/nil/late callback, pre-starter deadline, empty-mode/off-main wait, wall jumps, setup failure, NS/C++ unwind, pool lifetime and concurrent publishers. Configuration/identity/run loop controlled; NetworkExtension/device qualification pending.");
}return 0;}
