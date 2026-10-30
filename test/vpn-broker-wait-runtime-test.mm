#import <Foundation/Foundation.h>
#include "../shared/TLinkVPNBrokerBudget.h"
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
static void reset(){clockMs=100;waitCalls=waitMs=managerCalls=licenseCalls=0;waitMode=0;licensed=true;licenseCost=0;pending=nil;managerResult=@{@"ok":@1,@"connected":@1,@"configured":@1,@"enabled":@1,@"connection_status":@"connected"};}
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
        assert(caught&&pending);__weak NSDictionary *released;
        @autoreleasepool{NSDictionary *value=uniqueValue();released=value;pending(value);}assert(!released);pending=nil;
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
int main(){@autoreleasepool{
    puts("VPN broker wait Foundation: actual mutex completion/wait/response with controlled manager/authority and clock");
    synchronousCases();timeoutCases();unwindCases();latchCases();responseCases();
    puts("VPN broker wait passed: first/nil/duplicate/late callbacks, phase/start/outer expiry, exception abandonment, ARC pool ownership, 1000 callback/abandon races, eight competing publishers and frozen response/authority parity. Underlying operation/device qualification pending.");
}return 0;}
