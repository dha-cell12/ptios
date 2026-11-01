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
static NSString *const kTLinkVPNPrivateMarkerPath=@"fixture-marker-only";
static uint64_t cleanupActionCost=0,cleanupProbeCost=0,cleanupDelay=200,cleanupActionAt=0;
static unsigned cleanupActions=0,cleanupReads=0,markerRemoves=0;
static bool cleanupActive=false,cleanupRecordPresent=true,cleanupConnectionPresent=true,cleanupActionPresent=true,cleanupDeleteOK=true,markerExists=true,markerRemoveOK=true;
static NSString *cleanupInitialStatus=@"connected";
static double wallShift=0,wallJump=0;
static NSString *fixtureUUID(){return @"fixture-uuid";}
static uint64_t fixtureNow(){return tick;}
static NSDictionary *oldRecord(){return @{@"name":[kTLinkVPNPrivateNamePrefix stringByAppendingString:@"old"],@"identifier":@"old-id"};}
static void advance(unsigned milliseconds){if(regress)tick=1;else tick+=milliseconds;wallShift+=wallJump;}
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
+ (NSTimeInterval)timeIntervalSinceReferenceDate;
@end
@implementation VerificationDate
+ (NSDate *)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds {requestedPause=seconds;return [NSDate dateWithTimeIntervalSinceReferenceDate:seconds];}
+ (NSTimeInterval)timeIntervalSinceReferenceDate{return double(tick)/1000.0+wallShift;}
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
static NSDictionary *TLinkVPNPrivateFindConfiguration(id store,NSString *name,NSString *identifier){assert(store&&name&&identifier);return cleanupRecordPresent&&[identifier isEqualToString:@"old-id"]?oldRecord():nil;}
static BOOL TLinkVPNPrivateDeleteConfiguration(id store,NSDictionary *record){assert(store&&record);++deletes;return cleanupDeleteOK;}
@interface CleanupConnection:NSObject
- (void)disconnect;
@end
@implementation CleanupConnection
- (BOOL)respondsToSelector:(SEL)selector{if(selector==@selector(disconnect)&&!cleanupActionPresent)return NO;return [super respondsToSelector:selector];}
- (void)disconnect{
    ++cleanupActions;cleanupActive=true;cleanupActionAt=tick;tick+=cleanupActionCost;
    if(fault==1)[NSException raise:@"CleanupFixture" format:@"disconnect"];
    if(fault==2)throw std::runtime_error("disconnect");
}
@end
static CleanupConnection *cleanupConnection;
static id TLinkVPNPrivateCurrentConnection(id store){
    assert(store);++cleanupReads;
    if(cleanupActive){tick+=cleanupProbeCost;if(fault==3)[NSException raise:@"CleanupFixture" format:@"probe"];if(fault==4)throw std::runtime_error("probe");}
    return cleanupConnectionPresent?cleanupConnection:nil;
}
static NSString *TLinkVPNPrivateConnectionStatus(id connection){
    if(!connection)return @"invalid";
    return [(cleanupActive&&tick>=cleanupActionAt&&tick-cleanupActionAt>=cleanupDelay?@"disconnected":cleanupInitialStatus) mutableCopy];
}
@interface CleanupFiles:NSObject
+ (instancetype)defaultManager;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
@end
@implementation CleanupFiles
+ (instancetype)defaultManager{static CleanupFiles *files;static dispatch_once_t once;dispatch_once(&once, ^{files=[CleanupFiles new];});return files;}
- (BOOL)fileExistsAtPath:(NSString *)path{assert([path isEqualToString:kTLinkVPNPrivateMarkerPath]);return markerExists;}
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error{
    assert([path isEqualToString:kTLinkVPNPrivateMarkerPath]);++markerRemoves;
    if(!markerRemoveOK){if(error)*error=[NSError errorWithDomain:@"CleanupFixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"marker removal failed"}];return NO;}
    markerExists=false;return YES;
}
@end
#include "PrivateVPNStatusFields.inc"
#define NSThread VerificationThread
#define NSDate VerificationDate
#define NSRunLoop VerificationRunLoop
#include "PrivateVPNVerificationUnderTest.inc"
#include "PrivateVPNVerificationLegacy.inc"
#define NSFileManager CleanupFiles
#include "PrivateVPNCleanupUnderTest.inc"
#include "PrivateVPNCleanupLegacy.inc"
#undef NSFileManager
#undef NSRunLoop
#undef NSDate
#undef NSThread
static void reset(bool modern){
    tick=100;readCost=createCost=0;visibleAt=100;postReads=mainPauses=sleeps=creates=selects=markers=deletes=fault=0;mainSlice=interruptSlice=100;
    onMain=storeOK=canCreate=canList=createOK=selectedOK=markerOK=true;oldMarker=created=regress=sleepFails=false;
    createOptions=selectedRecord=markerRecord=nil;candidate=nil;pattern=Pattern::Exact;
    cleanupActionCost=cleanupProbeCost=cleanupActionAt=0;cleanupDelay=200;cleanupActions=cleanupReads=markerRemoves=0;
    cleanupActive=false;cleanupRecordPresent=cleanupConnectionPresent=cleanupActionPresent=cleanupDeleteOK=markerExists=markerRemoveOK=true;
    cleanupInitialStatus=@"connected";wallShift=wallJump=0;cleanupConnection=[CleanupConnection new];
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
static void cleanupCases(){
    for(bool main:{false,true}){
        for(unsigned scenario=0;scenario<11;++scenario){
            NSDictionary *expected=nil;unsigned expectedDeletes=0,expectedRemoves=0,expectedActions=0;
            for(bool current:{false,true}){
                reset(true);onMain=main;oldMarker=true;
                switch(scenario){case 0:break;case 1:oldMarker=false;break;case 2:storeOK=false;break;case 3:cleanupRecordPresent=false;break;
                    case 4:cleanupInitialStatus=@"disconnected";break;case 5:cleanupConnectionPresent=false;break;case 6:cleanupActionPresent=false;break;
                    case 7:cleanupDeleteOK=false;break;case 8:markerRemoveOK=false;break;case 9:cleanupDelay=UINT64_MAX;break;case 10:markerExists=false;break;}
                NSDictionary *result=current?TLinkVPNPrivateRemoveOwnedProfileSync():LegacyPrivateRemoveOwnedProfileSync();
                if(!current){expected=result;expectedDeletes=deletes;expectedRemoves=markerRemoves;expectedActions=cleanupActions;}
                else{assert([result isEqual:expected]&&deletes==expectedDeletes&&markerRemoves==expectedRemoves&&cleanupActions==expectedActions);}
            }
        }
        for(unsigned scenario=0;scenario<8;++scenario){
            reset(true);onMain=main;oldMarker=true;
            switch(scenario){case 0:cleanupActionCost=5000;cleanupDelay=0;break;case 1:cleanupProbeCost=5000;cleanupDelay=0;break;
                case 2:cleanupDelay=5000;break;case 3:regress=true;break;case 4:tick=UINT64_MAX;break;
                case 5:wallJump=-100000;cleanupDelay=UINT64_MAX;break;case 6:wallJump=100000;cleanupDelay=UINT64_MAX;break;
                case 7:cleanupDelay=UINT64_MAX;cleanupProbeCost=300;break;}
            NSDictionary *result=TLinkVPNPrivateRemoveOwnedProfileSync();expect(result,@"vpn_private_cleanup_disconnect_timeout",NO);
            assert(deletes==0&&markerRemoves==0&&markerExists);
            if(scenario==0||scenario==4)assert(cleanupReads==1);
            if(scenario==1)assert([result[@"connection_status"] isEqualToString:@"disconnected"]); // Late observed target must not authorize deletion.
        }
        reset(true);onMain=main;oldMarker=true;mainSlice=interruptSlice=1;cleanupDelay=100;
        expect(TLinkVPNPrivateRemoveOwnedProfileSync(),@"vpn_private_profile_removed",YES);
        assert(cleanupReads==2&&deletes==1&&markerRemoves==1&&mainPauses+sleeps==101); // Includes unchanged post-delete publication pause.
    }
    reset(true);onMain=false;oldMarker=true;sleepFails=true;
    expect(TLinkVPNPrivateRemoveOwnedProfileSync(),@"vpn_private_cleanup_disconnect_timeout",NO);assert(deletes==0&&markerRemoves==0);
    for(unsigned kind=1;kind<=6;++kind){
        reset(true);oldMarker=true;fault=kind;bool caught=false;
        @try{try{(void)TLinkVPNPrivateRemoveOwnedProfileSync();}catch(const std::runtime_error &){caught=kind%2==0;}}
        @catch(NSException *exception){(void)exception;caught=kind%2==1;}
        assert(caught&&deletes==0&&markerRemoves==0);
    }
    NSDictionary *held=nil;@autoreleasepool{reset(true);oldMarker=true;cleanupProbeCost=5000;cleanupDelay=0;held=TLinkVPNPrivateRemoveOwnedProfileSync();cleanupConnection=nil;}
    assert([held[@"connection_status"] isEqualToString:@"disconnected"]);held=nil;
    puts("Private VPN cleanup passed: frozen preflight/delete/marker/reply parity, continuous disconnect window, main/EINTR waits, late-target refusal, clock/wall/fault gates and pool lifetime; no real profile or marker removed.");
}
int main(){@autoreleasepool{parityCases();budgetCases();faultsAndLifetime();cleanupCases();fixtureStore=nil;cleanupConnection=nil;createOptions=selectedRecord=markerRecord=nil;
    puts("Private VPN verification Foundation passed: actual/frozen exact-name/single-delta/ambiguity/options/replies, 50-attempt/continuous budget, main publication/EINTR/faults, late refusal and pool lifetime. Private store/device qualification pending.");}}
