#import <Foundation/Foundation.h>
#import <objc/message.h>
#include "../shared/TLinkVPNPrivatePolling.h"
#include "../shared/TLinkHelperSocketIO.h"
#include <cassert>
#include <cerrno>
#include <cstdio>
#include <stdexcept>

// Execute the actual private transition, not a replacement state machine.
// The private store, clock and sleeping are controlled; no real VPN is touched.
static uint64_t tick=100,actionCost=0,probeCost=0,completeAfter=200,actionAt=0;
static unsigned actions=0,reads=0,pauses=0,earlySleep=100000,oversleep=0,fault=0;
static bool markerPresent=true,storePresent=true,recordPresent=true,selectOK=true,connectionPresent=true,actionPresent=true;
static bool active=false,wantConnected=true,initialTarget=false,regress=false,fatalSleep=false;
static double wallShift=0,wallJump=0;
static __weak NSString *publishedStatus;
@interface PrivateConnectionFixture:NSObject
- (void)connect;
- (void)disconnect;
@end
@implementation PrivateConnectionFixture
- (BOOL)respondsToSelector:(SEL)selector {
    if((selector==@selector(connect)||selector==@selector(disconnect))&&!actionPresent)return NO;
    return [super respondsToSelector:selector];
}
- (void)performAction:(BOOL)connected {
    ++actions;active=true;wantConnected=connected;actionAt=tick;tick+=actionCost;
    if(fault==1)[NSException raise:@"PrivateVPNFixture" format:@"action"];
    if(fault==2)throw std::runtime_error("action");
}
- (void)connect {[self performAction:YES];}
- (void)disconnect {[self performAction:NO];}
@end
static PrivateConnectionFixture *fixtureConnection;
static uint64_t fixtureNow(){return tick;}
static double fixtureWallNow(){return double(tick)/1000.0+wallShift;}
static int fixtureSleep(unsigned microseconds){
    ++pauses;assert(microseconds>0&&microseconds<=100000);
    if(fatalSleep){errno=EINVAL;return -1;}
    if(regress){tick=1;return 0;}
    wallShift+=wallJump;
    const unsigned elapsed=std::min(microseconds,earlySleep);
    tick+=(elapsed+999)/1000+oversleep;
    if(elapsed<microseconds){errno=EINTR;return -1;}return 0;
}
static NSDictionary *TLinkVPNResult(BOOL ok,NSString *code,NSDictionary *extra){
    NSMutableDictionary *result=extra?[extra mutableCopy]:[NSMutableDictionary dictionary];
    result[@"ok"]=@(ok);result[@"code"]=code;return result;
}
static NSDictionary *TLinkVPNPrivateLoadMarker(){return markerPresent?@{@"name":@"owned",@"identifier":@"id"}:nil;}
static id TLinkVPNPrivateStore(NSString **failure){if(!storePresent){if(failure)*failure=@"fixture_store_failed";return nil;}return @"store";}
static NSDictionary *TLinkVPNPrivateFindConfiguration(id store,NSString *name,NSString *identifier){assert(store&&name&&identifier);return recordPresent?@{@"identifier":identifier}:nil;}
static BOOL TLinkVPNPrivateSelectConfiguration(id store,NSDictionary *record){assert(store&&record);return selectOK;}
static id TLinkVPNPrivateCurrentConnection(id store){
    assert(store);++reads;
    if(active){tick+=probeCost;if(fault==3)[NSException raise:@"PrivateVPNFixture" format:@"probe"];if(fault==4)throw std::runtime_error("probe");}
    return connectionPresent?fixtureConnection:nil;
}
static NSString *TLinkVPNPrivateConnectionStatus(id connection){
    @autoreleasepool {
        const bool target=initialTarget||(active&&tick>=actionAt&&tick-actionAt>=completeAfter);
        NSString *text=!connection?@"invalid":target?(wantConnected?@"connected":@"disconnected"):(wantConnected?@"disconnected":@"connected");
        NSMutableString *value=[text mutableCopy];publishedStatus=value;return value;
    }
}
static NSDictionary *TLinkVPNPrivateStatusFields(NSDictionary *marker,NSString *status){return @{@"profile_identifier":marker[@"identifier"],@"connection_status":status};}
#include "PrivateVPNTransitionUnderTest.inc"
#include "PrivateVPNTransitionLegacy.inc"
static void reset(BOOL connected){
    tick=100;actionCost=probeCost=actionAt=0;completeAfter=200;actions=reads=pauses=oversleep=fault=0;earlySleep=100000;
    markerPresent=storePresent=recordPresent=selectOK=connectionPresent=actionPresent=true;
    active=initialTarget=regress=fatalSleep=false;wantConnected=connected;wallShift=wallJump=0;
    publishedStatus=nil;fixtureConnection=[PrivateConnectionFixture new];
}
static void expectCode(NSDictionary *result,NSString *code,BOOL ok){
    if(![result[@"code"] isEqualToString:code]||[result[@"ok"] boolValue]!=ok)NSLog(@"Private VPN expected %@/%d, got %@",code,ok,result);
    assert([result[@"code"] isEqualToString:code]&&[result[@"ok"] boolValue]==ok);
}
static void parityCases(){
    for(unsigned connected=0;connected<2;++connected){
        for(unsigned scenario=0;scenario<9;++scenario){
            NSDictionary *expected=nil;unsigned expectedActions=0;
            for(bool current:{false,true}){
                reset(connected);
                switch(scenario){case 0:break;case 1:initialTarget=true;break;case 2:markerPresent=false;break;
                    case 3:storePresent=false;break;case 4:recordPresent=false;break;case 5:selectOK=false;break;
                    case 6:connectionPresent=false;break;case 7:actionPresent=false;break;case 8:completeAfter=UINT64_MAX;break;}
                NSDictionary *result=current?TLinkVPNPrivateSetConnectedSync(connected,5):LegacyPrivateSetConnectedSync(connected,5);
                if(current){assert([result isEqual:expected]&&actions==expectedActions);}else{expected=result;expectedActions=actions;}
            }
        }
        for(uint64_t delay:{0ULL,1ULL,99ULL,100ULL,101ULL,499ULL,4800ULL,4900ULL}){
            reset(connected);completeAfter=delay;NSDictionary *expected=LegacyPrivateSetConnectedSync(connected,5);const unsigned expectedReads=reads;
            reset(connected);completeAfter=delay;NSDictionary *actual=TLinkVPNPrivateSetConnectedSync(connected,5);
            assert([actual isEqual:expected]&&reads==expectedReads&&actions==1);
        }
    }
}
static void deadlineCases(){
    for(unsigned connected=0;connected<2;++connected){
        NSString *success=connected?@"vpn_connected":@"vpn_disconnected";
        for(double jump:{-100000.0,100000.0}){
            reset(connected);wallJump=jump;completeAfter=UINT64_MAX;
            expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),@"vpn_private_transition_timeout",NO);
            assert(tick==5100&&actions==1&&reads==50&&pauses==50);
        }
        reset(connected);actionCost=5000;completeAfter=0;
        expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),@"vpn_private_transition_timeout",NO);assert(reads==1&&pauses==0&&actions==1);
        reset(connected);actionCost=4800;completeAfter=4900;
        expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),success,YES);assert(tick==5000&&reads==2);
        reset(connected);probeCost=5000;completeAfter=0;
        expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),@"vpn_private_transition_timeout",NO);assert(reads==2&&actions==1);
        reset(connected);oversleep=5000;completeAfter=0;
        expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),@"vpn_private_transition_timeout",NO);assert(reads==1&&pauses==1);
        reset(connected);earlySleep=1000;completeAfter=100;
        expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),success,YES);assert(reads==2&&pauses==100&&tick==200);
        reset(connected);regress=true;expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),@"vpn_private_transition_timeout",NO);assert(reads==1);
        reset(connected);fatalSleep=true;expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),@"vpn_private_transition_timeout",NO);assert(reads==1);
        reset(connected);tick=UINT64_MAX;expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),@"vpn_private_transition_timeout",NO);assert(actions==0&&reads==1);
        reset(connected);completeAfter=5000;expectCode(TLinkVPNPrivateSetConnectedSync(connected,5),@"vpn_private_transition_timeout",NO);assert(tick==5100&&reads==50);
    }
}
static void lifetimeAndFaultCases(){
    for(unsigned kind=1;kind<=4;++kind){
        reset(YES);fault=kind;bool caught=false;
        @try{try{(void)TLinkVPNPrivateSetConnectedSync(YES,5);}catch(const std::runtime_error &){caught=kind==2||kind==4;}}
        @catch(NSException *exception){(void)exception;caught=kind==1||kind==3;}
        assert(caught&&actions==1);reset(YES);expectCode(TLinkVPNPrivateSetConnectedSync(YES,5),@"vpn_connected",YES);
    }
    NSDictionary *held=nil;@autoreleasepool{reset(YES);held=TLinkVPNPrivateSetConnectedSync(YES,5);fixtureConnection=nil;}
    assert([held[@"connection_status"] isEqualToString:@"connected"]&&publishedStatus!=nil);
    held=nil;@autoreleasepool{reset(YES);completeAfter=UINT64_MAX;held=TLinkVPNPrivateSetConnectedSync(YES,5);fixtureConnection=nil;}
    assert([held[@"connection_status"] isEqualToString:@"disconnected"]&&publishedStatus!=nil);held=nil;
}
int main(){@autoreleasepool{
    const uint64_t realNow=TLinkHelperIO::nowMs();assert(realNow!=UINT64_MAX&&TLinkHelperIO::nowMs()>=realNow);
    parityCases();deadlineCases();lifetimeAndFaultCases();fixtureConnection=nil;
    puts("Private VPN transition Foundation passed: actual/frozen preflight/reply parity, continuous action/probe deadlines, wall jumps, late success refusal, interrupted/failing waits, NS/C++ unwind and result pool lifetime. Private backend/device qualification pending.");
}}
