#import <Foundation/Foundation.h>
#include "../shared/TLinkVPNBrokerBudget.h"
#include "../shared/TLinkVPNBrokerOperations.h"
#include <cassert>
#include <atomic>
#include <thread>
#include <vector>
#include <stdexcept>
#include <cstdio>
typedef void (^TLinkVPNResultCompletion)(NSDictionary *result);
static std::atomic<uint64_t> clockMs{100};
static unsigned waitCalls=0,waitMs=0,managerCalls=0,licenseCalls=0;
static int waitMode=0;static bool licensed=true;static uint64_t licenseCost=0;
static TLinkVPNResultCompletion pending=nil;
static NSDictionary *managerResult;
static std::unique_ptr<TLinkVPNBrokerOperations> operationOwner;
static uint64_t operationAcquireCost=0;
static TLinkVPNBrokerOperations &fixtureOperationOwner(){assert(operationOwner);clockMs+=operationAcquireCost;return *operationOwner;}
static uint64_t fixtureNow(){return clockMs.load();}
static bool fixtureWait(TLinkVPNBrokerCompletion &state,int milliseconds){
    assert(milliseconds>0&&milliseconds<=250);++waitCalls;waitMs+=static_cast<unsigned>(milliseconds);
    if(waitMode==1){clockMs+=static_cast<unsigned>(milliseconds);return false;}
    return state.wait(milliseconds);
}
static BOOL TLinkLicenseFeatureAllowed(NSString *feature,NSString **error){
    assert([feature isEqualToString:@"automation"]);++licenseCalls;clockMs+=licenseCost;
    if(!licensed&&error)*error=@"fixture_denied";return licensed;
}
static void TLinkVPNReadManagerStatus(TLinkVPNResultCompletion completion){++managerCalls;completion(managerResult);}
static void TLinkVPNSetConnected(BOOL connected,NSTimeInterval timeout,TLinkVPNResultCompletion completion){(void)connected;assert(timeout==20.0);++managerCalls;completion(managerResult);}
static NSDictionary *TLinkVPNDiagnosticsSnapshot(NSString *runtime,NSString *state,NSString *query,NSString *control,NSString *backend,NSString *broker,NSNumber *connected){
    return @{@"runtime":runtime,@"state":state,@"query":query,@"control":control,@"backend":backend,@"broker":broker,@"connected":connected?:[NSNull null]};
}
namespace Current {
#include "VPNBrokerWaitUnderTest.inc"
}
namespace Legacy {
#include "VPNBrokerWaitLegacy.inc"
}
using TLinkVPNBrokerIngress::Window;
static void reset(){clockMs=100;waitCalls=waitMs=managerCalls=licenseCalls=0;waitMode=0;licensed=true;licenseCost=operationAcquireCost=0;pending=nil;operationOwner=std::make_unique<TLinkVPNBrokerOperations>();managerResult=@{@"ok":@1,@"connected":@1,@"configured":@1,@"enabled":@1,@"connection_status":@"connected"};}
static void expired(NSDictionary *value){assert(![value[@"ok"] boolValue]&&[value[@"code"] isEqualToString:@"vpn_broker_operation_timeout"]);}
static NSDictionary *uniqueValue(){return @{@"token":[[NSUUID UUID] UUIDString]};}
static void synchronousCases(){
    reset();NSDictionary *first=uniqueValue(),*second=uniqueValue();
    NSDictionary *result=Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){pending=[completion copy];completion(first);completion(second);},8.0,Window(100));
    assert(result==first);pending(second);assert(result==first);pending=nil;
    reset();auto publisher=std::make_shared<std::thread>();
    NSDictionary *async=Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){
        TLinkVPNResultCompletion copied=[completion copy];
        *publisher=std::thread([copied,first]{@autoreleasepool{copied(first);}});
    },8.0,Window(100));
    publisher->join();assert(async==first);
    reset();expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){completion(nil);completion(first);},8.0,Window(100)));
    for(NSTimeInterval bad:std::vector<NSTimeInterval>{0.0,-1.0,31.0,std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()}){
        reset();__block bool called=false;expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){(void)completion;called=true;},bad,Window(100)));assert(!called&&waitCalls==0);
    }
}
static void timeoutCases(){
    for(uint64_t time:std::vector<uint64_t>{99,30100,UINT64_MAX}){
        reset();clockMs=time;__block bool called=false;
        expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){(void)completion;called=true;},8.0,Window(100)));assert(!called&&waitCalls==0);
    }
    reset();waitMode=1;
    expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){pending=[completion copy];clockMs+=7000;},8.0,Window(100)));
    assert(clockMs==8100&&waitMs==1000);
    __weak NSDictionary *released;
    @autoreleasepool{NSDictionary *late=uniqueValue();released=late;pending(late);pending(late);}
    assert(!released);pending=nil;
    reset();waitMode=1;clockMs=30090;
    expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){pending=[completion copy];},24.0,Window(100)));
    assert(clockMs==30100&&waitMs==10&&waitCalls==1);pending(nil);pending=nil;
    reset();NSDictionary *value=uniqueValue();
    expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){completion(value);clockMs+=8000;},8.0,Window(100)));assert(waitCalls==0);
}
static void unwindCases(){
    for(unsigned kind=0;kind<2;++kind){
        reset();bool caught=false;
        try{@try{
            (void)Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){pending=[completion copy];if(kind==0)[NSException raise:@"FixtureStart" format:@"start"];throw std::runtime_error("start");},8.0,Window(100));
        }@catch(NSException *exception){(void)exception;caught=true;}}catch(...){caught=true;}
        assert(caught&&pending&&operationOwner->stats().active==1);__weak NSDictionary *released;
        @autoreleasepool{NSDictionary *value=uniqueValue();released=value;pending(value);}assert(!released);pending=nil;
        assert(operationOwner->stats().active==0);
    }
}
static void latchCases(){
    auto state=std::make_shared<TLinkVPNBrokerCompletion>();assert(state->valid());
    NSDictionary *held=nil;__weak NSDictionary *weak;
    @autoreleasepool{NSDictionary *value=uniqueValue();weak=value;state->complete(value);assert(state->wait(1));held=state->finish(true);}
    assert(held&&[held[@"token"] length]);held=nil;assert(!weak);
    auto expiredState=std::make_shared<TLinkVPNBrokerCompletion>();expiredState->complete(uniqueValue());
    bool checked=false;assert(!expiredState->finishChecked([&checked]{checked=true;return false;}));assert(checked);
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        auto latch=std::make_shared<TLinkVPNBrokerCompletion>();NSDictionary *first=uniqueValue();
        std::thread publish([latch,first]{@autoreleasepool{latch->complete(first);}});
        std::thread abandon([latch]{@autoreleasepool{latch->abandon();}});publish.join();abandon.join();
        assert(!latch->finish(true));latch->complete(first);
    }}
    auto multiple=std::make_shared<TLinkVPNBrokerCompletion>();std::vector<std::thread> callbacks;
    for(unsigned n=0;n<8;++n)callbacks.emplace_back([multiple,n]{@autoreleasepool{multiple->complete(@{@"index":@(n)});}});
    for(std::thread &callback:callbacks)callback.join();assert(multiple->wait(1)&&!multiple->wait(1));
    NSDictionary *winner=multiple->finish(true);assert(winner&&[winner[@"index"] unsignedIntValue]<8&&!multiple->finish(true));
}
static id diagnostics(NSString *wire){assert([wire hasPrefix:@"0;;"]);NSString *encoded=[[wire substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];NSData *data=[[NSData alloc] initWithBase64EncodedString:encoded options:0];return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];}
static void responseCases(){
    for(NSString *command in @[@"query",@"connect",@"disconnect",@"diagnostics",@"unknown",@" query\r\n"]){
        for(unsigned failure=0;failure<3;++failure){reset();if(failure==1)licensed=false;if(failure==2)managerResult=@{@"ok":@0,@"code":@"fixture_manager_error"};
            NSString *old=Legacy::TLinkVPNBrokerResponse(command),*current=Current::TLinkVPNBrokerResponse(command,Window(100));
            if([command isEqualToString:@"diagnostics"])assert([diagnostics(old) isEqual:diagnostics(current)]);else assert([old isEqual:current]);
        }
    }
    reset();clockMs=30100;assert([Current::TLinkVPNBrokerResponse(@"connect",Window(100)) hasPrefix:@"-1;;vpn_broker_operation_timeout"]&&licenseCalls==0&&managerCalls==0);
    reset();licenseCost=30000;assert([Current::TLinkVPNBrokerResponse(@"connect",Window(100)) hasPrefix:@"-1;;vpn_broker_operation_timeout"]&&licenseCalls==1&&managerCalls==0);
    reset();(void)Current::TLinkVPNBrokerResponse(@"diagnostics",Window(100));assert(licenseCalls==0&&managerCalls==1);
}
static void operationCases(){
    reset();waitMode=1;NSMutableArray *callbacks=[NSMutableArray array];
    for(unsigned n=0;n<8;++n){clockMs=100;
        expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){[callbacks addObject:[completion copy]];},8.0,Window(100)));
        assert(operationOwner->stats().active==n+1);
    }
    clockMs=100;__block bool started=false;
    NSDictionary *busy=Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){(void)completion;started=true;},8.0,Window(100));
    assert(!started&&[busy[@"code"] isEqualToString:@"vpn_broker_busy"]&&operationOwner->stats().active==8);
    // Ordinary authorization still precedes operation overload; diagnostics stays exempt.
    licensed=false;assert([Current::TLinkVPNBrokerResponse(@"connect",Window(100)) hasPrefix:@"-1;;vpn_license_denied"]);
    const unsigned gates=licenseCalls;NSDictionary *diag=diagnostics(Current::TLinkVPNBrokerResponse(@"diagnostics",Window(100)));
    assert(licenseCalls==gates&&[diag[@"manager_status"][@"last_error"] isEqualToString:@"vpn_broker_busy"]);
    licensed=true;
    TLinkVPNResultCompletion first=(TLinkVPNResultCompletion)callbacks[0];first(uniqueValue());assert(operationOwner->stats().active==7);
    clockMs=100;waitMode=1;__block TLinkVPNResultCompletion replacement=nil;
    expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){replacement=[completion copy];},8.0,Window(100)));
    assert(operationOwner->stats().active==8);first(nil);assert(operationOwner->stats().active==8); // Retired token cannot free its replacement.
    replacement(nil);replacement=nil;
    for(NSUInteger n=1;n<callbacks.count;++n){TLinkVPNResultCompletion callback=(TLinkVPNResultCompletion)callbacks[n];callback(nil);}
    assert(operationOwner->stats().active==0&&operationOwner->stats().completed==9);
    reset();operationAcquireCost=30000;started=false;
    expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){(void)completion;started=true;},8.0,Window(100)));
    assert(!started&&operationOwner->stats().active==0&&operationOwner->stats().cancelled==1);
    reset();NSDictionary *value=uniqueValue();
    NSDictionary *result=Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){
        completion(value);assert(operationOwner->stats().active==1); // Starter still owns execution.
    },8.0,Window(100));
    assert(result==value&&operationOwner->stats().active==0);
    // A starter that discards its callback does not prove that submitted work ended.
    reset();waitMode=1;
    for(unsigned n=0;n<8;++n){clockMs=100;expired(Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){(void)completion;},8.0,Window(100)));}
    clockMs=100;busy=Current::TLinkVPNBrokerWait(^(TLinkVPNResultCompletion completion){(void)completion;assert(false);},8.0,Window(100));
    assert([busy[@"code"] isEqualToString:@"vpn_broker_busy"]&&operationOwner->stats().active==8);
}
int main(){@autoreleasepool{
    puts("VPN broker wait Foundation: actual mutex completion/wait/response with controlled manager/authority and clock");
    synchronousCases();timeoutCases();unwindCases();latchCases();responseCases();operationCases();
    puts("VPN broker wait/operation admission passed: completion/phase/pool/frozen authority parity, eight pending across timeout, immediate busy, late recovery, stale token fencing, prestart cancellation and conservative dropped/throwing starters. Underlying cancellation/device qualification pending.");
}return 0;}
