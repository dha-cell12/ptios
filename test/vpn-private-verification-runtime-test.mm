#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#include "../shared/TLinkVPNPrivatePolling.h"
#include <cassert>
#include <cerrno>
#include <cstdio>
#include <stdexcept>
static NSString *const kTLinkVPNPrivateNamePrefix=@"TLinkauto Private VPN (tlinkauto-private-v1) ";
static uint64_t tick=100,readCost=0,createCost=0,visibleAt=100;
static unsigned postReads=0,mainPauses=0,sleeps=0,creates=0,selects=0,markers=0,deletes=0,fault=0,mainSlice=100,interruptSlice=100;
static bool onMain=true,storeOK=true,canCreate=true,canList=true,createOK=true,selectedOK=true,markerOK=true,oldMarker=false,created=false,regress=false,sleepFails=false;
enum class Pattern {Exact,Single,Ambiguous,Duplicate,Existing,Empty,ExactAmbiguous,None};
static Pattern pattern=Pattern::Exact;
static NSDictionary *createOptions,*selectedRecord,*markerRecord;
static __weak NSDictionary *candidate;
static double requestedPause=0;
static NSString *fixtureUUID(){return @"fixture-uuid";}
static uint64_t fixtureNow(){return tick;}
static NSDictionary *oldRecord(){return @{@"name":[kTLinkVPNPrivateNamePrefix stringByAppendingString:@"old"],@"identifier":@"old-id"};}
static void advance(unsigned milliseconds){if(regress)tick=1;else tick+=milliseconds;}
static int fixtureSleep(unsigned microseconds){
    assert(microseconds>0&&microseconds<=100000);++sleeps;
    if(sleepFails){errno=EINVAL;return -1;}
    const unsigned requested=(microseconds+999)/1000,elapsed=std::min(requested,interruptSlice);advance(elapsed);
    if(elapsed<requested){errno=EINTR;return -1;}return 0;
}
@interface VerificationThread:NSObject
+ (BOOL)isMainThread;
@end
@implementation VerificationThread
+ (BOOL)isMainThread{return onMain;}
@end
@interface VerificationDate:NSObject
+ (NSDate *)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds;
@end
@implementation VerificationDate
+ (NSDate *)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds {requestedPause=seconds;return [NSDate dateWithTimeIntervalSinceReferenceDate:seconds];}
@end
@interface VerificationRunLoop:NSObject
+ (instancetype)currentRunLoop;
- (void)runUntilDate:(NSDate *)date;
@end
@implementation VerificationRunLoop
+ (instancetype)currentRunLoop{static VerificationRunLoop *loop;static dispatch_once_t once;dispatch_once(&once, ^{loop=[VerificationRunLoop new];});return loop;}
- (void)runUntilDate:(NSDate *)date {
    assert(date&&requestedPause>0&&requestedPause<=0.1);++mainPauses;
    if(fault==5)[NSException raise:@"VerificationFixture" format:@"run loop"];
    if(fault==6)throw std::runtime_error("run loop");
    advance(std::min(static_cast<unsigned>(std::lround(requestedPause*1000.0)),mainSlice));
}
@end
@interface VerificationStore:NSObject
- (uintptr_t)createVPNWithOptions:(NSDictionary *)options;
- (id)configurations;
@end
@implementation VerificationStore
- (BOOL)respondsToSelector:(SEL)selector {
    if(selector==@selector(createVPNWithOptions:)&&!canCreate)return NO;
    if(selector==@selector(configurations)&&!canList)return NO;
    return [super respondsToSelector:selector];
}
- (id)configurations{return @[];}
- (uintptr_t)createVPNWithOptions:(NSDictionary *)options {
    ++creates;createOptions=[options copy];tick+=createCost;
    if(fault==1)[NSException raise:@"VerificationFixture" format:@"create"];
    if(fault==2)throw std::runtime_error("create");
    created=createOK;return createOK?1:0;
}
@end
@interface ModernVerificationStore:VerificationStore
+ (id)createAllVPNByUserDefinedNamesDictionary;
@end
@implementation ModernVerificationStore
+ (id)createAllVPNByUserDefinedNamesDictionary{return @{};}
@end
static VerificationStore *fixtureStore;
static NSDictionary *TLinkVPNResult(BOOL ok,NSString *code,NSDictionary *extra){
    NSMutableDictionary *result=extra?[extra mutableCopy]:[NSMutableDictionary dictionary];result[@"ok"]=@(ok);result[@"code"]=code;return result;
}
static id TLinkVPNPrivateStore(NSString **failure){if(!storeOK){if(failure)*failure=@"fixture_store_failed";return nil;}return fixtureStore;}
static NSDictionary *TLinkVPNPrivateLoadMarker(){return oldMarker?oldRecord():nil;}
static NSArray<NSDictionary *> *TLinkVPNPrivateConfigurationRecords(id store){
    assert(store);if(!created)return @[oldRecord()];++postReads;tick+=readCost;
    if(fault==3)[NSException raise:@"VerificationFixture" format:@"records"];
    if(fault==4)throw std::runtime_error("records");
    if(tick<visibleAt)return @[oldRecord()];
    @autoreleasepool {
        NSDictionary *match=@{@"name":createOptions[@"dispName"],@"identifier":@"new-id"};candidate=match;
        NSDictionary *renamed=@{@"name":@"normalized name",@"identifier":@"new-id"};
        switch(pattern){
            case Pattern::Exact:return @[oldRecord(),match];
            case Pattern::Single:candidate=renamed;return @[oldRecord(),renamed];
            case Pattern::Ambiguous:return @[oldRecord(),renamed,@{@"name":@"other",@"identifier":@"other-id"}];
            case Pattern::Duplicate:return @[oldRecord(),renamed,renamed];
            case Pattern::Existing:return @[oldRecord()];
            case Pattern::Empty:return @[@{@"name":@"empty id",@"identifier":@""}];
            case Pattern::ExactAmbiguous:return @[renamed,match,@{@"name":@"other",@"identifier":@"other-id"}];
            case Pattern::None:return nil;
        }
    }
    return nil;
}
static BOOL TLinkVPNPrivateSelectConfiguration(id store,NSDictionary *record){assert(store&&record);++selects;selectedRecord=record;return selectedOK;}
static BOOL TLinkVPNPrivateWriteMarker(NSDictionary *record,NSString *type,NSString **failure){assert(record&&type);++markers;markerRecord=record;if(!markerOK&&failure)*failure=@"fixture_marker_failed";return markerOK;}
static NSDictionary *TLinkVPNPrivateFindConfiguration(id store,NSString *name,NSString *identifier){assert(store&&name&&identifier);return [identifier isEqualToString:@"old-id"]?oldRecord():nil;}
static BOOL TLinkVPNPrivateDeleteConfiguration(id store,NSDictionary *record){assert(store&&record);++deletes;return YES;}
#include "PrivateVPNStatusFields.inc"
#define NSThread VerificationThread
#define NSDate VerificationDate
#define NSRunLoop VerificationRunLoop
#include "PrivateVPNVerificationUnderTest.inc"
#include "PrivateVPNVerificationLegacy.inc"
#undef NSRunLoop
#undef NSDate
#undef NSThread
static void reset(bool modern){
    tick=100;readCost=createCost=0;visibleAt=100;postReads=mainPauses=sleeps=creates=selects=markers=deletes=fault=0;mainSlice=interruptSlice=100;
    onMain=storeOK=canCreate=canList=createOK=selectedOK=markerOK=true;oldMarker=created=regress=sleepFails=false;
    createOptions=selectedRecord=markerRecord=nil;candidate=nil;pattern=Pattern::Exact;
    fixtureStore=modern?[ModernVerificationStore new]:[VerificationStore new];
}
static NSDictionary *invoke(bool current,NSString *type=@"L2TP",NSString *name=@"profile"){
    return current?TLinkVPNPrivateConfigureLegacySync(type,@"server",@"user",@"password",@"secret",@"group",name,4,YES)
        :LegacyPrivateConfigureSync(type,@"server",@"user",@"password",@"secret",@"group",name,4,YES);
}
static void expect(NSDictionary *result,NSString *code,BOOL ok){
    if(![result[@"code"] isEqualToString:code]||[result[@"ok"] boolValue]!=ok)NSLog(@"Verification expected %@/%d, got %@",code,ok,result);
    assert([result[@"code"] isEqualToString:code]&&[result[@"ok"] boolValue]==ok);
}
static void parityCases(){
    for(bool modern:{false,true}){
        for(Pattern shape:{Pattern::Exact,Pattern::Single,Pattern::Ambiguous,Pattern::Duplicate,Pattern::Existing,Pattern::Empty,Pattern::ExactAmbiguous,Pattern::None}){
            for(unsigned delay:{0U,100U,4900U}){
                NSDictionary *expected=nil,*options=nil;unsigned expectedSelects=0,expectedMarkers=0,expectedDeletes=0,expectedReads=0;
                for(bool current:{false,true}){
                    reset(modern);pattern=shape;visibleAt=tick+delay;oldMarker=true;
                    NSDictionary *result=invoke(current);
                    if(!current){expected=result;options=createOptions;expectedSelects=selects;expectedMarkers=markers;expectedDeletes=deletes;expectedReads=postReads;}
                    else{assert([result isEqual:expected]&&[options isEqual:createOptions]);assert(selects==expectedSelects&&markers==expectedMarkers&&deletes==expectedDeletes&&postReads==expectedReads);}
                }
            }
        }
        for(unsigned scenario=0;scenario<7;++scenario){
            NSDictionary *expected=nil;
            for(bool current:{false,true}){
                reset(modern);NSString *type=@"IPSec";
                switch(scenario){case 0:storeOK=false;break;case 1:canCreate=false;break;case 2:createOK=false;break;
                    case 3:selectedOK=false;break;case 4:markerOK=false;break;case 5:type=@"unsupported";break;case 6:if(!modern)canList=false;break;}
                NSDictionary *result=invoke(current,type,@"  Ứng dụng 测试  ");
                if(current)assert([result isEqual:expected]);else expected=result;
            }
        }
    }
}
static void budgetCases(){
    for(bool main:{false,true}){
        reset(true);onMain=main;pattern=Pattern::Ambiguous;readCost=300;
        NSDictionary *result=invoke(true);expect(result,@"vpn_private_create_verification_failed",NO);
        assert(tick==5200&&postReads==13&&selects==0&&markers==0&&deletes==0);assert([result[@"verification_attempts"] unsignedIntValue]==13);
        reset(true);onMain=main;readCost=5000;
        expect(invoke(true),@"vpn_private_create_verification_failed",NO);assert(postReads==1&&selects==0&&markers==0&&deletes==0);
        reset(true);onMain=main;visibleAt=5100;
        expect(invoke(true),@"vpn_private_create_verification_failed",NO);assert(postReads==50&&tick==5000&&selects==0);
        reset(true);onMain=main;mainSlice=interruptSlice=1;visibleAt=200;
        expect(invoke(true),@"vpn_private_profile_saved",YES);assert(postReads==2&&tick==200&&mainPauses+sleeps==100);
        reset(true);onMain=main;regress=true;pattern=Pattern::Ambiguous;
        expect(invoke(true),@"vpn_private_create_verification_failed",NO);assert(postReads==1&&selects==0);
    }
    reset(true);onMain=false;sleepFails=true;pattern=Pattern::Ambiguous;
    expect(invoke(true),@"vpn_private_create_verification_failed",NO);assert(postReads==1&&sleeps==1);
    reset(true);tick=UINT64_MAX;
    expect(invoke(true),@"vpn_private_create_verification_failed",NO);assert(creates==1&&postReads==0&&selects==0);
    reset(true);createCost=6000;visibleAt=6200;
    expect(invoke(true),@"vpn_private_profile_saved",YES);assert(postReads==2&&tick==6200); // Verification starts after create returns.
}
static void faultsAndLifetime(){
    for(unsigned kind=1;kind<=6;++kind){
        reset(true);fault=kind;if(kind>=5)pattern=Pattern::Ambiguous;bool caught=false;
        @try{try{(void)invoke(true);}catch(const std::runtime_error &){caught=kind%2==0;}}
        @catch(NSException *exception){(void)exception;caught=kind%2==1;}
        assert(caught&&markers==0);reset(true);expect(invoke(true),@"vpn_private_profile_saved",YES);
    }
    NSDictionary *held=nil;@autoreleasepool{reset(true);held=invoke(true);fixtureStore=nil;createOptions=nil;selectedRecord=nil;markerRecord=nil;}
    assert([held[@"profile_identifier"] isEqualToString:@"new-id"]&&[held[@"verification_mode"] isEqualToString:@"exact_name"]);held=nil;
    @autoreleasepool{reset(true);pattern=Pattern::Single;held=invoke(true);assert(candidate&&[markerRecord[@"identifier"] isEqualToString:@"new-id"]);fixtureStore=nil;createOptions=nil;selectedRecord=nil;markerRecord=nil;}
    assert([held[@"profile_name"] isEqualToString:@"normalized name"]);held=nil;
}
int main(){@autoreleasepool{parityCases();budgetCases();faultsAndLifetime();fixtureStore=nil;createOptions=selectedRecord=markerRecord=nil;
    puts("Private VPN verification Foundation passed: actual/frozen exact-name/single-delta/ambiguity/options/replies, 50-attempt/continuous budget, main publication/EINTR/faults, late refusal and pool lifetime. Private store/device qualification pending.");}}
