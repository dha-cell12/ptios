#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dispatch/dispatch.h>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include "../shared/TLinkAXSnapshotWindow.h"
#include "../shared/TLinkAXAdmission.h"
#include "AXAdmissionUnderTest.inc"
#include "ax-node-pool-owner.h"
using TLinkAXElementRef=CFTypeRef;
static NSString *const TLinkAXSnapshotSchema=@"ui_snapshot_v1";
static NSString *const TLinkAXBackendName=@"axruntime_numeric_v1";
static uint64_t tick=1000000000ULL,createCost=0,queryCost=0,nodeCost=0;
static double wallShift=0,nodeWallJump=0,lastQueryTimeout=0,parentSeconds=1;
static unsigned sourceCount=4,serialized=0,creates=0,queries=0,rootRetains=0,rootDrops=0,arrayDrops=0,prepareCalls=0,lockCalls=0;
static unsigned failEvery=0,cancelAt=0;
static unsigned ownerFaultSite=0,ownerFaultKind=0,rawOutRetains=0;
static bool queryMissing=false;
static unsigned boundaryDispatches=0;
static bool boundaryQueueStop=false,boundaryReturnStop=false;
static bool locked=false,screenOff=false,prepared=true,rootMissing=false,queryError=false,wrongArray=false,throwQuery=false,throwNode=false,cancelled=false;
static bool regressCreate=false,regressNode=false,failClockNode=false;
static bool forceHidden=false,forceNotClickable=false;
static bool trackNodeOwners=false,throwNodeCPP=false;
static uint64_t ownerDropCost=0;
extern "C" void TLinkAXFixtureOwnerDidDrain(void){tick+=ownerDropCost;}
static size_t outputCap=1024*1024;
static NSDictionary *rootObject;
static __weak NSArray *returnedArray;
struct ParentBudget {double remainingSeconds(double maximum){return std::min(maximum,parentSeconds);}};
static std::shared_ptr<ParentBudget> parent;
static uint64_t fixtureNow(){return tick;}
static CFAbsoluteTime fixtureWall(){return static_cast<double>(tick)/1e9+wallShift;}
static double fixtureEpoch(){return 1700000000.0+wallShift;}
static bool TLinkNativeStopped(){return cancelled;}
static bool TLinkNativeOutputAllowed(size_t bytes){return bytes<=outputCap;}
static std::shared_ptr<ParentBudget> TLinkCurrentNativeBudget(){return parent;}
static void fixtureOwnerFault(unsigned site){
    if(ownerFaultSite!=site)return;
    if(ownerFaultKind==1)[NSException raise:@"AXSnapshotOwnerFixture" format:@"acquisition"];
    if(ownerFaultKind==2)throw std::runtime_error("acquisition");
}
static void fixtureRelease(CFTypeRef value){
    assert(value);if(value==(__bridge CFTypeRef)rootObject)++rootDrops;else ++arrayDrops;CFRelease(value);
}
static TLinkAXElementRef fixtureCreate(pid_t pid){
    assert(pid==123);++creates;tick=regressCreate?1:tick+createCost;
    fixtureOwnerFault(1);
    if(rootMissing)return NULL;
    ++rootRetains;return CFRetain((__bridge CFTypeRef)rootObject);
}
static int fixtureSetTimeout(TLinkAXElementRef root,float timeout){
    assert(root==(__bridge CFTypeRef)rootObject&&timeout>0);lastQueryTimeout=timeout;fixtureOwnerFault(2);return 0;
}
static int fixtureCopyAttribute(TLinkAXElementRef root,CFStringRef key,CFTypeRef *out){
    assert(root==(__bridge CFTypeRef)rootObject&&(uintptr_t)key==3015&&out);++queries;tick+=queryCost;fixtureOwnerFault(3);
    @autoreleasepool{
        NSMutableArray *values=[NSMutableArray array];for(unsigned n=0;n<sourceCount;++n)[values addObject:@(n)];
        returnedArray=values;
        if(!queryMissing){++rawOutRetains;*out=CFRetain((__bridge CFTypeRef)(wrongArray?(id)@42:values));}
        fixtureOwnerFault(4);
        if(throwQuery)[NSException raise:@"AXSnapshotFixture" format:@"query"];
        return queryError?9:0;
    }
}
static auto sTLinkAXCreateApp=&fixtureCreate;
static auto sTLinkAXSetTimeout=&fixtureSetTimeout;
static auto sTLinkAXCopyAttribute=&fixtureCopyAttribute;
static NSDictionary *TLinkAXLockState(){++lockCalls;return @{@"locked":@(locked),@"screen_off":@(screenOff)};}
static BOOL TLinkAXPrepare(){++prepareCalls;return prepared;}
static NSDictionary *TLinkAXSerializeElement(TLinkAXElementRef object,CGRect screen,NSUInteger index,TLinkAXSnapshotWindow *window=nullptr){
    (void)window;
    assert(object&&screen.size.width==320);++serialized;tick+=nodeCost;wallShift+=nodeWallJump;
    if(regressNode)tick=1;
    if(failClockNode)tick=UINT64_MAX;
    if(cancelAt==serialized)cancelled=true;
    NSMutableDictionary *trackingRow=nil;
    if(trackNodeOwners){trackingRow=[NSMutableDictionary dictionary];TLinkAXFixtureAttachOwner(trackingRow);}
    if(throwNode)[NSException raise:@"AXSnapshotFixture" format:@"node"];
    if(throwNodeCPP)throw std::runtime_error("node");
    if(failEvery&&serialized%failEvery==0)return nil;
    NSDictionary *row=@{@"index":@(index),@"label":@"Ứng dụng 测试",@"value":@"value",@"identifier":@"id",@"role":@"element",
        @"intersects_screen":@(!forceHidden&&index%2==0),@"clickable":@(!forceNotClickable&&index%3!=0)};
    if(trackingRow){
        [trackingRow addEntriesFromDictionary:row];
        trackingRow[@"label"]=[NSMutableString stringWithFormat:@"node-%lu",(unsigned long)index];
        return trackingRow;
    }
    return row;
}
@interface FixtureScreen:NSObject
+(instancetype)mainScreen;
@property(nonatomic,readonly) CGRect bounds;
@property(nonatomic,readonly) CGFloat scale;
@end
@implementation FixtureScreen
+(instancetype)mainScreen{static FixtureScreen *value;static dispatch_once_t once;dispatch_once(&once,^{value=[FixtureScreen new];});return value;}
-(CGRect)bounds{return CGRectMake(0,0,320,640);}
-(CGFloat)scale{return 2;}
@end
#include "AXErrorUnderTest.inc"
#include "AXBoundedIntegerUnderTest.inc"
#include "AXScanLimitsUnderTest.inc"
#include "AXSnapshotUnderTest.inc"
#include "AXSnapshotLegacy.inc"
#include "AXSnapshotBeforeScan.inc"
#include "AXSnapshotBeforeNodePool.inc"
#include "AXSnapshotBeforeOwner.inc"
static dispatch_queue_t TLinkAXQueue(){return dispatch_get_main_queue();}
static void TLinkNativeDispatchSync(dispatch_queue_t queue,dispatch_block_t work){
    assert(queue==dispatch_get_main_queue());++boundaryDispatches;
    if(boundaryQueueStop)cancelled=true;
    if(!TLinkNativeStopped())work();
    if(boundaryReturnStop)cancelled=true;
}
#include "AXSnapshotWrapperUnderTest.inc"
#include "AXSnapshotWrapperBeforeStop.inc"
static NSUInteger matchedArrayAppends=0;
static void fixtureAppendMatch(NSMutableArray *matches,NSDictionary *element){++matchedArrayAppends;[matches addObject:element];}
#include "AXFindUnderTest.inc"
#include "AXFindLegacy.inc"
#include "AXFindBeforeStop.inc"
#include "AXCompletenessUnderTest.inc"
static void reset(){
    assert(TLinkAXAdmissionState().pending()==0);
    tick=1000000000ULL;createCost=queryCost=nodeCost=0;wallShift=nodeWallJump=lastQueryTimeout=0;parentSeconds=1;
    sourceCount=4;serialized=creates=queries=rootRetains=rootDrops=arrayDrops=prepareCalls=lockCalls=failEvery=cancelAt=0;
    locked=screenOff=rootMissing=queryError=wrongArray=throwQuery=throwNode=cancelled=regressCreate=regressNode=failClockNode=false;prepared=true;
    forceHidden=forceNotClickable=false;
    ownerFaultSite=ownerFaultKind=rawOutRetains=0;queryMissing=false;
    boundaryDispatches=0;boundaryQueueStop=boundaryReturnStop=false;
    trackNodeOwners=throwNodeCPP=false;ownerDropCost=0;
    outputCap=1024*1024;parent.reset();rootObject=@{@"fixture-root":@YES};returnedArray=nil;
}
static NSDictionary *call(bool current,NSDictionary *options=@{},pid_t pid=123){
    return current?TLinkAXCopySnapshotUnlocked(pid,@"fixture.bundle",options):LegacyAXCopySnapshotUnlocked(pid,@"fixture.bundle",options);
}
static void expectError(NSDictionary *value,NSString *code){assert(![value[@"ok"] boolValue]&&[value[@"error"] isEqualToString:code]);}
static void parityCases(){
    for(unsigned n=0;n<96;++n){
        NSDictionary *expected=nil;unsigned oldSerialized=0,oldQueries=0,oldDrops=0;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();sourceCount=n%9;nodeCost=(n%3)*1000000ULL;createCost=1000000ULL;queryCost=2000000ULL;failEvery=n%5==0?3:0;
                NSDictionary *options=@{@"visible_only":@((n&1)!=0),@"clickable_only":@((n&2)!=0),@"max_elements":@(1+n%6),@"timeout_ms":@100};
                NSDictionary *value=call(current,options);
                if(current){assert([value isEqual:expected]);assert(serialized==oldSerialized&&queries==oldQueries&&rootDrops==oldDrops);}
                else{expected=value;oldSerialized=serialized;oldQueries=queries;oldDrops=rootDrops;}
                assert(rootRetains==rootDrops&&lockCalls==1&&prepareCalls==1);
            }
            assert(!returnedArray);
        }
    }
    for(unsigned n=0;n<8;++n){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){
            reset();pid_t pid=123;NSDictionary *options=@{};
            switch(n){case 0:pid=0;break;case 1:locked=true;break;case 2:screenOff=true;break;case 3:prepared=false;break;
                case 4:rootMissing=true;break;case 5:queryError=true;break;case 6:wrongArray=true;break;case 7:throwQuery=true;break;}
            NSDictionary *value=call(current,options,pid);if(current)assert([value isEqual:expected]);else expected=value;
            assert(rootRetains==rootDrops);if(n>=5)assert(arrayDrops==1);
        }
    }
}
static void deadlineCases(){
    reset();sourceCount=0;createCost=40000000ULL;
    NSDictionary *value=call(true,@{@"timeout_ms":@100});assert([value[@"ok"] boolValue]&&std::fabs(lastQueryTimeout-.06)<1e-6);
    reset();sourceCount=0;createCost=40000000ULL;parent.reset(new ParentBudget);parentSeconds=.02;
    call(true,@{@"timeoutMs":@100});assert(std::fabs(lastQueryTimeout-.02)<1e-6&&parentSeconds==.02);
    reset();createCost=100000000ULL;expectError(call(true,@{@"timeout_ms":@100}),@"ui_cancelled_or_timed_out");assert(queries==0&&rootDrops==1);
    for(unsigned n=0;n<3;++n){
        reset();if(n==0)regressCreate=true;if(n==1)tick=UINT64_MAX;if(n==2)tick=UINT64_MAX-10;
        expectError(call(true),@"ui_cancelled_or_timed_out");assert(queries==0&&rootRetains==rootDrops);
    }
    for(bool empty:{false,true}){
        for(bool current:{false,true}){
            reset();sourceCount=empty?0:1;if(empty)queryCost=120000000ULL;else nodeCost=120000000ULL;
            value=call(current,@{@"timeout_ms":@100,@"visible_only":@NO});
            assert([value[@"ok"] boolValue]);assert([value[@"partial"] boolValue]==current&&[value[@"truncated"] boolValue]==current);
            assert(TLinkAXResultCompleteForAction(value)==!current);
            if(current)assert([value[@"count"] unsignedIntValue]==0&&[value[@"duration_ms"] intValue]==120);
            assert(rootRetains==rootDrops);
        }
    }
    for(int direction:{-1,1}){
        for(bool current:{false,true}){
            reset();sourceCount=32;nodeCost=20000000ULL;nodeWallJump=direction*100.0;
            value=call(current,@{@"timeout_ms":@100,@"visible_only":@NO,@"max_elements":@1000});
            if(current){
                assert(serialized==5&&[value[@"count"] unsignedIntValue]==4&&[value[@"partial"] boolValue]);
                assert([value[@"duration_ms"] intValue]==100&&!TLinkAXResultCompleteForAction(value));
            }else if(direction<0){assert(serialized==32&&[value[@"duration_ms"] longLongValue]<0&&TLinkAXResultCompleteForAction(value));}
            else assert(serialized==1);
        }
    }
    for(bool failedClock:{false,true}){
        reset();sourceCount=1;regressNode=!failedClock;failClockNode=failedClock;
        value=call(true,@{@"visible_only":@NO});assert([value[@"partial"] boolValue]&&[value[@"duration_ms"] longLongValue]>=0&&!TLinkAXResultCompleteForAction(value));
    }
}
static void cancellationAndLifetimeCases(){
    reset();cancelled=true;expectError(call(true),@"ui_cancelled_or_timed_out");assert(rootRetains==rootDrops&&queries==0);
    for(bool filtered:{false,true}){
        reset();sourceCount=1;cancelAt=1;
        expectError(call(true,@{@"clickable_only":@(filtered)}),@"ui_cancelled_or_timed_out");assert(rootRetains==rootDrops);
    }
    reset();sourceCount=0;outputCap=1;NSDictionary *empty=call(true);assert(TLinkAXResultCompleteForAction(empty)); // Existing empty-output policy retained.
    reset();outputCap=1;expectError(call(true),@"ui_response_too_large");
    reset();throwNode=true;bool caught=false;
    @try{call(true);}@catch(NSException *exception){caught=[exception.name isEqualToString:@"AXSnapshotFixture"];}
    assert(caught&&rootRetains==rootDrops); // Serializer fault behavior is unchanged.
    NSDictionary *held;
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{reset();sourceCount=1;nodeCost=120000000ULL;held=call(true,@{@"timeout_ms":@100});assert(rootRetains==rootDrops);}
        assert(!returnedArray&&[held[@"partial"] boolValue]&&!TLinkAXResultCompleteForAction(held));
    }
    held=nil;rootObject=nil;
}
static void scanBudgetCases(){
    NSArray *plans=@[
        @[@{},@4096],@[@{@"max_scanned_elements":@3},@3],@[@{@"maxScannedElements":@4},@4],
        @[@{@"max_scanned_elements":@2,@"maxScannedElements":@7},@2],
        @[@{@"max_scanned_elements":@0},@1],@[@{@"max_scanned_elements":@(-5)},@1],
        @[@{@"max_scanned_elements":@20000},@16384],@[@{@"max_scanned_elements":[NSNull null]},@4096],
        @[@{@"maxScannedElements":@"5"},@5],@[@{@"max_scanned_elements":@2.9},@2]
    ];
    for(NSArray *plan in plans){
        @autoreleasepool{
            reset();sourceCount=20000;forceHidden=true;
            NSDictionary *value=call(true,plan[0]);unsigned limit=[plan[1] unsignedIntValue];
            assert([value[@"ok"] boolValue]&&[value[@"partial"] boolValue]&&[value[@"truncated"] boolValue]);
            assert(serialized==limit&&[value[@"scanned_count"] unsignedIntValue]==limit&&[value[@"source_count"] unsignedIntValue]==20000);
            assert([value[@"count"] unsignedIntValue]==0&&!TLinkAXResultCompleteForAction(value)&&rootRetains==rootDrops);
        }
        assert(!returnedArray);
    }
    for(unsigned kind=0;kind<3;++kind){
        @autoreleasepool{
            reset();sourceCount=8;
            NSDictionary *options=@{@"max_scanned_elements":@3,@"clickable_only":@YES};
            if(kind==0)forceHidden=true;
            if(kind==1)forceNotClickable=true;
            if(kind==2)failEvery=1;
            NSDictionary *value=call(true,options);
            assert(serialized==3&&[value[@"count"] unsignedIntValue]==0&&[value[@"partial"] boolValue]);
            assert([value[@"serialization_failure_count"] unsignedIntValue]==(kind==2?3U:0U));
        }
        assert(!returnedArray);
    }
    @autoreleasepool{
        reset();sourceCount=3;NSDictionary *value=call(true,@{@"max_scanned_elements":@3,@"visible_only":@NO});
        assert(serialized==3&&[value[@"count"] unsignedIntValue]==3&&TLinkAXResultCompleteForAction(value));
    }
    NSDictionary *expected=nil;
    for(bool current:{false,true}){
        @autoreleasepool{
            reset();sourceCount=8;NSDictionary *options=@{@"max_elements":@1,@"max_scanned_elements":@3,@"visible_only":@NO};
            NSDictionary *value=current?call(true,options):PreScanAXCopySnapshotUnlocked(123,@"fixture.bundle",options);
            if(current)assert([value isEqual:expected]);else expected=value;
            assert(serialized==1&&rootRetains==rootDrops);
        }
    }
    for(bool current:{false,true}){
        @autoreleasepool{
            reset();sourceCount=20000;forceHidden=true;
            NSDictionary *value=current?call(true):PreScanAXCopySnapshotUnlocked(123,@"fixture.bundle",@{});
            assert(serialized==(current?4096U:20000U));assert([value[@"partial"] boolValue]==current);
            assert(TLinkAXResultCompleteForAction(value)==!current&&rootRetains==rootDrops);
        }
        assert(!returnedArray);
    }
    @autoreleasepool{
        reset();sourceCount=8;
        NSDictionary *value=TLinkAXFindElement(123,@"fixture.bundle",@{@"identifier":@"id",@"maxScannedElements":@3});
        assert(serialized==3&&[value[@"found"] boolValue]&&[value[@"match_count"] unsignedIntValue]==2&&!TLinkAXResultCompleteForAction(value));
        reset();sourceCount=8;
        value=TLinkAXFindElement(123,@"fixture.bundle",@{@"identifier":@"id",@"max_scanned_elements":@8,@"maxScannedElements":@1});
        assert(serialized==8&&[value[@"match_count"] unsignedIntValue]==4&&TLinkAXResultCompleteForAction(value));
        reset();sourceCount=8;
        value=TLinkAXFindElement(123,@"fixture.bundle",@{@"identifier":@"id",@"index":@7,@"max_scanned_elements":@3});
        assert(![value[@"found"] boolValue]&&[value[@"partial"] boolValue]&&!TLinkAXResultCompleteForAction(value));
    }
    @autoreleasepool{
        reset();sourceCount=8;forceHidden=true;cancelAt=3;
        expectError(call(true,@{@"max_scanned_elements":@3}),@"ui_cancelled_or_timed_out");assert(serialized==3&&rootRetains==rootDrops);
    }
    std::puts("AX scan budget passed: 4096 default/16384 hard cap, aliases/clamps, filtered/invalid nodes, exact exhaustion/row independence, 20k frozen versus 4096 scans, actual selector forwarding/partial absence and cancellation. Root materialization/device qualification pending.");
}
#include "ax-find-runtime-fixture.inc"
#include "ax-node-pool-runtime-fixture.inc"
#include "ax-snapshot-owner-runtime-fixture.inc"
#include "ax-query-stop-runtime-fixture.inc"
int main(){@autoreleasepool{
    std::puts("AX snapshot Foundation: actual/frozen snapshot loop, real CF arrays/references and controlled AX/serializer/clock/screen/parent providers");
    parityCases();deadlineCases();cancellationAndLifetimeCases();scanBudgetCases();findCases();nodePoolCases();snapshotOwnerCases();queryStopCases();
    std::puts("AX snapshot passed: 96 frozen rows/filters/output/count/metric cases, preflight/error/CF parity, root/parent remainder, clock/wall jumps, late final/empty partial action refusal, cancel/fault/output and 128 pool lifecycles. Attribute-group/device qualification pending.");
}return 0;}
