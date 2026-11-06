#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dispatch/dispatch.h>
#include <cassert>
#include <cmath>
#include <math.h>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include <vector>
#include <atomic>
#include <thread>
#include "../shared/TLinkAXSnapshotWindow.h"
#include "../shared/TLinkAXAdmission.h"
#include "../shared/TLinkAXSnapshotOutput.h"
#include "AXAdmissionUnderTest.inc"
using TLinkAXElementRef=CFTypeRef;
// Distinct fixture trait bits. UIKit/private AX providers are controlled.
static const uint64_t UIAccessibilityTraitButton=1ULL<<0,UIAccessibilityTraitLink=1ULL<<1,UIAccessibilityTraitImage=1ULL<<2,
    UIAccessibilityTraitHeader=1ULL<<3,UIAccessibilityTraitAdjustable=1ULL<<4,UIAccessibilityTraitSearchField=1ULL<<5,
    UIAccessibilityTraitKeyboardKey=1ULL<<6,UIAccessibilityTraitStaticText=1ULL<<7,UIAccessibilityTraitNotEnabled=1ULL<<8;
static NSString *const TLinkAXSnapshotSchema=@"ui_snapshot_v1",*const TLinkAXBackendName=@"axruntime_numeric_v1";
static uint64_t tick=1000000000ULL,attributeCost=0,setupCost=0,rootSetupCost=0,decodeCost=0;
static unsigned rootRetains=0,rootDrops=0,rootQueries=0,valueDrops=0,boxes=0,boxCreates=0,cancelAt=0,errorKey=0,nilKey=0,throwKey=0,throwKind=0;
static uint64_t hitCreateCost=0,hitCallCost=0,hitQueueCost=0,hitPostQueueCost=0,hitLockCost=0,hitPrepareCost=0,hitScreenCost=0,hitRootDropCost=0,hitDropCost=0;
static unsigned hitRetains=0,hitDrops=0,hitCalls=0,hitCreates=0,hitDispatches=0,hitSetters=0,hitCancelPhase=0,hitFaultPhase=0,hitFaultKind=0;
static double hitRootTimeout=0;
static bool hitRootMissing=false,hitMissing=false,hitError=false,hitLocked=false,hitScreenOff=false,hitPrepared=true,hitSkipDispatch=false;
static bool cancelled=false,cancelSetup=false,badFrame=false,badPoint=false;
static size_t hitOutputCap=1024*1024;
static bool observeHitOutput=false,stopDuringHitOutput=false,latchHitOutputOverflow=false,hitOutputOverflowed=false;
static unsigned hitOutputCalls=0,hitOutputFaultKind=0;
static uint64_t hitOutputCost=0;
static bool honorAttributeTimeout=false;
static double lastAttributeTimeout=0;
static std::vector<uint32_t> keys;
static std::vector<double> timeouts;
static std::vector<uint64_t> queryStarts;
static NSDictionary *rootObject;
static __weak NSArray *queryArray;
static __weak NSObject *lastBox;
struct ParentBudget {
    uint64_t end;
    double remainingSeconds(double maximum){return tick>=end?0:std::min(maximum,static_cast<double>(end-tick)/1e9);}
};
static std::shared_ptr<ParentBudget> parent;
static dispatch_queue_t admissionQueue;
static dispatch_semaphore_t admissionEnqueued,admissionRootEntered,admissionRootRelease;
static std::atomic<unsigned> admissionDispatches{0};
static bool admissionHoldRoot=false;
@interface AXValueBox:NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) CGPoint point;
@property(nonatomic) int kind;
@end
@implementation AXValueBox
-(instancetype)init{self=[super init];if(self){++boxes;++boxCreates;}return self;}
-(void)dealloc{assert(boxes>0);--boxes;}
@end
@interface AXNode:NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) CGPoint point;
@property(nonatomic,strong) id label;
@property(nonatomic,strong) id value;
@property(nonatomic,strong) id identifier;
@property(nonatomic,strong) id traits;
@end
@implementation AXNode
@end
static AXNode *node;
static uint64_t fixtureNow(){return tick;}
static double fixtureEpoch(){return 1700000000.0;}
static bool TLinkNativeStopped(){return cancelled||hitOutputOverflowed||(parent&&tick>=parent->end);}
static bool TLinkNativeOutputAllowed(size_t bytes){
    if(observeHitOutput){
        assert(rootRetains==rootDrops&&hitRetains==hitDrops);++hitOutputCalls;tick+=hitOutputCost;
        if(stopDuringHitOutput)cancelled=true;
        if(hitOutputFaultKind==1)[NSException raise:@"AXHitOutputFixture" format:@"output"];
        if(hitOutputFaultKind==2)throw std::runtime_error("hit output");
    }
    const bool allowed=!hitOutputOverflowed&&(!hitOutputCap||bytes<=hitOutputCap);
    if(!allowed&&latchHitOutputOverflow)hitOutputOverflowed=true;
    return allowed;
}
static std::shared_ptr<ParentBudget> TLinkCurrentNativeBudget(){return parent;}
static void fixtureHitFault(unsigned phase){
    if(hitFaultPhase!=phase)return;
    if(hitFaultKind==1)[NSException raise:@"AXHitFixture" format:@"provider"];
    if(hitFaultKind==2)throw std::runtime_error("hit provider");
}
static void fixtureRelease(CFTypeRef value){
    assert(value);
    if(value==(__bridge CFTypeRef)rootObject){++rootDrops;tick+=hitRootDropCost;}
    else if(value==(__bridge CFTypeRef)node){++hitDrops;tick+=hitDropCost;}
    else ++valueDrops;
    CFRelease(value);
}
static int fixtureSetTimeout(TLinkAXElementRef element,float timeout){
    assert(timeout>0);
    if(element==(__bridge CFTypeRef)rootObject){
        ++hitSetters;hitRootTimeout=timeout;tick+=rootSetupCost;if(hitCancelPhase==4)cancelled=true;fixtureHitFault(4);
        if(admissionHoldRoot){
            dispatch_semaphore_signal(admissionRootEntered);
            assert(dispatch_semaphore_wait(admissionRootRelease,dispatch_time(DISPATCH_TIME_NOW,30LL*NSEC_PER_SEC))==0);
            admissionHoldRoot=false;
        }
    }
    else{assert(element==(__bridge CFTypeRef)node);timeouts.push_back(timeout);lastAttributeTimeout=timeout;tick+=setupCost;if(cancelSetup)cancelled=true;}
    return 0;
}
static TLinkAXElementRef fixtureCreateApp(pid_t pid){
    assert(pid==123);++hitCreates;tick+=hitCreateCost;if(hitCancelPhase==3)cancelled=true;fixtureHitFault(3);
    if(hitRootMissing)return NULL;
    ++rootRetains;return CFRetain((__bridge CFTypeRef)rootObject);
}
static int fixtureHitTest(TLinkAXElementRef root,TLinkAXElementRef *out,float x,float y){
    assert(root==(__bridge CFTypeRef)rootObject&&out&&std::isfinite(x)&&std::isfinite(y));++hitCalls;tick+=hitCallCost;
    if(hitCancelPhase==5)cancelled=true;
    if(!hitMissing){++hitRetains;*out=CFRetain((__bridge CFTypeRef)node);}
    fixtureHitFault(5);return hitError?9:0;
}
static int fixtureCopyAttribute(TLinkAXElementRef element,CFStringRef rawKey,CFTypeRef *out){
    assert(out);const uint32_t key=static_cast<uint32_t>((uintptr_t)rawKey);
    if(element==(__bridge CFTypeRef)rootObject){
        assert(key==3015);++rootQueries;
        @autoreleasepool{NSArray *values=@[node];queryArray=values;*out=CFRetain((__bridge CFTypeRef)values);return 0;}
    }
    assert(element==(__bridge CFTypeRef)node);keys.push_back(key);queryStarts.push_back(tick);
    tick+=honorAttributeTimeout&&lastAttributeTimeout>0?std::min(attributeCost,(uint64_t)std::ceil(lastAttributeTimeout*1e9)):attributeCost;
    if(cancelAt==keys.size())cancelled=true;
    @autoreleasepool{
        id value=nil;
        if(key!=nilKey){
            if(key==2003||key==2007){
                AXValueBox *box=[AXValueBox new];box.kind=key==2003?3:1;box.frame=node.frame;box.point=node.point;value=box;lastBox=box;
            }else if(key==2001)value=node.label;
            else if(key==2006)value=node.value;
            else if(key==5019)value=node.identifier;
            else{assert(key==2004);value=node.traits;}
        }
        *out=value?CFRetain((__bridge CFTypeRef)value):NULL;
        if(key==throwKey){
            if(throwKind==1)[NSException raise:@"AXAttributeFixture" format:@"query"];
            if(throwKind==2)throw std::runtime_error("query");
        }
        return key==errorKey?7:0;
    }
}
static Boolean fixtureValueGet(CFTypeRef value,int kind,void *out){
    AXValueBox *box=(__bridge AXValueBox *)value;assert(box.kind==kind);tick+=decodeCost;
    if(kind==3){if(badFrame)return false;*static_cast<CGRect *>(out)=box.frame;}
    else{assert(kind==1);if(badPoint)return false;*static_cast<CGPoint *>(out)=box.point;}
    return true;
}
static TLinkAXElementRef (*sTLinkAXCreateApp)(pid_t)=fixtureCreateApp;
static int (*sTLinkAXSetTimeout)(TLinkAXElementRef,float)=fixtureSetTimeout;
static int (*sTLinkAXCopyAttribute)(TLinkAXElementRef,CFStringRef,CFTypeRef *)=fixtureCopyAttribute;
static Boolean (*sTLinkAXValueGetValue)(CFTypeRef,int,void *)=fixtureValueGet;
static int (*sTLinkAXHitTest)(TLinkAXElementRef,TLinkAXElementRef *,float,float)=fixtureHitTest;
namespace Current {
#include "AXAttributesUnderTest.inc"
}
namespace Legacy {
#include "AXAttributesLegacy.inc"
}
namespace BeforeParent {
#include "AXAttributesBeforeParent.inc"
}
static NSDictionary *TLinkAXSerializeElement(TLinkAXElementRef value,CGRect screen,NSUInteger index,TLinkAXSnapshotWindow *window=nullptr){
    return Current::TLinkAXSerializeElement(value,screen,index,window);
}
static NSDictionary *TLinkAXLockState(){tick+=hitLockCost;if(hitCancelPhase==1)cancelled=true;fixtureHitFault(1);return @{@"locked":@(hitLocked),@"screen_off":@(hitScreenOff)};}
static BOOL TLinkAXPrepare(){tick+=hitPrepareCost;if(hitCancelPhase==2)cancelled=true;return hitPrepared;}
@interface FixtureScreen:NSObject
+(instancetype)mainScreen;
@property(nonatomic,readonly) CGRect bounds;
@property(nonatomic,readonly) CGFloat scale;
@end
@implementation FixtureScreen
+(instancetype)mainScreen{static FixtureScreen *value;static dispatch_once_t once;dispatch_once(&once,^{value=[FixtureScreen new];});return value;}
-(CGRect)bounds{tick+=hitScreenCost;if(hitCancelPhase==8)cancelled=true;return CGRectMake(0,0,320,640);}
-(CGFloat)scale{return 2;}
@end
#include "AXErrorUnderTest.inc"
#include "AXBoundedIntegerUnderTest.inc"
#include "AXScanLimitsUnderTest.inc"
#include "AXSnapshotUnderTest.inc"
#define TLinkAXSerializeElement Legacy::TLinkAXSerializeElement
#include "AXSnapshotBeforeAttributes.inc"
#undef TLinkAXSerializeElement
#include "AXCompletenessUnderTest.inc"
static dispatch_queue_t TLinkAXQueue(){return dispatch_get_main_queue();}
static void TLinkNativeDispatchSync(dispatch_queue_t queue,dispatch_block_t work){
    if(admissionQueue){
        assert(queue==dispatch_get_main_queue());++admissionDispatches;
        if(admissionEnqueued)dispatch_semaphore_signal(admissionEnqueued);
        dispatch_sync(admissionQueue,^{@autoreleasepool{if(!TLinkNativeStopped())work();}});
        return;
    }
    assert(queue==dispatch_get_main_queue());++hitDispatches;tick+=hitQueueCost;
    if(!hitSkipDispatch&&!TLinkNativeStopped())work();
    tick+=hitPostQueueCost;
}
#include "AXSnapshotWrapperUnderTest.inc"
#include "AXFindUnderTest.inc"
#include "AXHitTestUnderTest.inc"
#include "AXHitTestLegacy.inc"
#include "AXHitTestBeforeOutput.inc"
static void reset(){
    assert(TLinkAXAdmissionState().pending()==0&&!admissionQueue);
    assert(boxes==0);tick=1000000000ULL;attributeCost=setupCost=rootSetupCost=decodeCost=0;
    rootRetains=rootDrops=rootQueries=valueDrops=boxCreates=cancelAt=errorKey=nilKey=throwKey=throwKind=0;
    hitCreateCost=hitCallCost=hitQueueCost=hitPostQueueCost=hitLockCost=hitPrepareCost=hitScreenCost=hitRootDropCost=hitDropCost=0;
    hitRetains=hitDrops=hitCalls=hitCreates=hitDispatches=hitSetters=hitCancelPhase=hitFaultPhase=hitFaultKind=0;hitRootTimeout=0;
    hitRootMissing=hitMissing=hitError=hitLocked=hitScreenOff=hitSkipDispatch=false;hitPrepared=true;
    cancelled=cancelSetup=badFrame=badPoint=false;keys.clear();timeouts.clear();queryStarts.clear();parent.reset();queryArray=nil;lastBox=nil;
    hitOutputCap=1024*1024;observeHitOutput=stopDuringHitOutput=latchHitOutputOverflow=hitOutputOverflowed=false;hitOutputCalls=hitOutputFaultKind=0;hitOutputCost=0;
    honorAttributeTimeout=false;lastAttributeTimeout=0;
    rootObject=@{@"fixture-root":@YES};node=[AXNode new];node.frame=CGRectMake(10,20,40,20);node.point=CGPointMake(30,30);
    node.label=@"Ứng dụng 测试";node.value=@42;node.identifier=@"identifier";node.traits=@(UIAccessibilityTraitButton);
    sTLinkAXSetTimeout=fixtureSetTimeout;sTLinkAXCopyAttribute=fixtureCopyAttribute;sTLinkAXValueGetValue=fixtureValueGet;
    sTLinkAXHitTest=fixtureHitTest;
}
static bool equal(id left,id right){return left==right||[left isEqual:right];}
static NSDictionary *serialize(unsigned mode){
    TLinkAXSnapshotWindow window(tick,1000);
    if(mode==0)return Legacy::TLinkAXSerializeElement((__bridge CFTypeRef)node,CGRectMake(0,0,320,640),7);
    return Current::TLinkAXSerializeElement((__bridge CFTypeRef)node,CGRectMake(0,0,320,640),7,mode==1?nullptr:&window);
}
static NSDictionary *snapshot(bool current,unsigned timeout=100){
    NSDictionary *options=@{@"timeout_ms":@(timeout),@"visible_only":@NO};
    return current?TLinkAXCopySnapshotUnlocked(123,@"fixture.bundle",options):PrecedingAXCopySnapshotUnlocked(123,@"fixture.bundle",options);
}
static void parityCases(){
    for(unsigned n=0;n<240;++n){
        NSDictionary *expected=nil;std::vector<uint32_t> expectedKeys;
        for(unsigned mode=0;mode<3;++mode){
            @autoreleasepool{
                reset();attributeCost=1000000ULL;
                node.traits=@(n%512);node.frame=CGRectMake(n%5==0?500:10,20,n%7==0?0:40,20);
                node.point=CGPointMake(n%3==0?-10:30,n%4==0?900:30);
                node.label=n%2?(id)@123:(id)@"label";node.value=n%3?(id)@"value":(id)[NSNull null];node.identifier=n%2?(id)@"id":(id)@42;
                if(n%11==0)errorKey=2001;if(n%13==0)nilKey=2007;if(n%17==0)badFrame=true;if(n%19==0)badPoint=true;
                NSDictionary *value=serialize(mode);
                if(mode==0){expected=value;expectedKeys=keys;}else assert(equal(value,expected)&&keys==expectedKeys);
                assert(timeouts.size()==(mode==2?keys.size():1));
                for(double timeout:timeouts)assert(std::fabs(timeout-.1)<1e-6);
            }
            assert(boxes==0&&!lastBox);
        }
    }
    for(bool current:{false,true}){
        @autoreleasepool{reset();attributeCost=1000000ULL;NSDictionary *value=snapshot(current,1000);assert(TLinkAXResultCompleteForAction(value));assert(keys.size()==6&&rootRetains==rootDrops);}
        assert(boxes==0&&!queryArray);
    }
}
static void deadlineCases(){
    for(bool current:{false,true}){
        @autoreleasepool{
            reset();attributeCost=30000000ULL;const uint64_t end=tick+100000000ULL;
            NSDictionary *value=snapshot(current);assert([value[@"partial"] boolValue]&&!TLinkAXResultCompleteForAction(value));
            assert(keys.size()==(current?4U:6U));assert([value[@"duration_ms"] intValue]==(current?120:180));
            if(current){
                assert(timeouts.size()==4);for(size_t n=0;n<keys.size();++n){assert(queryStarts[n]<end);assert(timeouts[n]<=.100001);assert(timeouts[n]<=static_cast<double>(end-queryStarts[n])/1e9+1e-6);}
            }
            assert(rootRetains==rootDrops);
        }
        assert(boxes==0&&!queryArray);
    }
    for(unsigned scenario=0;scenario<5;++scenario){
        @autoreleasepool{
            reset();
            if(scenario==0)attributeCost=100000000ULL;
            if(scenario==1)setupCost=100000000ULL;
            if(scenario==2){attributeCost=100000000ULL;sTLinkAXSetTimeout=nullptr;}
            if(scenario==3)decodeCost=100000000ULL;
            if(scenario==4)rootSetupCost=100000000ULL;
            NSDictionary *value=snapshot(true);
            if(scenario==4){assert(![value[@"ok"] boolValue]&&rootQueries==0&&keys.empty());}
            else{assert([value[@"partial"] boolValue]&&!TLinkAXResultCompleteForAction(value));assert(keys.size()==(scenario==1?0U:1U));}
            assert(rootRetains==rootDrops);
            if(scenario==0||scenario==2)assert(valueDrops==1&&boxes==0&&!lastBox);
        }
        assert(boxes==0&&!queryArray);
    }
    @autoreleasepool{
        reset();attributeCost=15000000ULL;parent.reset(new ParentBudget{tick+20000000ULL});const uint64_t end=parent->end;
        NSDictionary *value=snapshot(true,1000);assert(![value[@"ok"] boolValue]&&[value[@"error"] isEqualToString:@"ui_cancelled_or_timed_out"]);
        assert(keys.size()==2&&std::fabs(timeouts[0]-.02)<1e-6&&std::fabs(timeouts[1]-.005)<1e-6&&parent->end==end&&rootRetains==rootDrops);
    }
    assert(boxes==0&&!queryArray);
}
static void cleanupCases(){
    for(unsigned at=1;at<=6;++at){
        @autoreleasepool{reset();cancelAt=at;NSDictionary *value=snapshot(true);assert(![value[@"ok"] boolValue]&&keys.size()==at&&rootRetains==rootDrops);}
        assert(boxes==0&&!queryArray);
    }
    @autoreleasepool{reset();cancelSetup=true;NSDictionary *value=snapshot(true);assert(![value[@"ok"] boolValue]&&keys.empty()&&rootRetains==rootDrops);}
    for(unsigned kind:{1U,2U}){
        for(unsigned key:{2003U,2007U}){
            for(bool local:{false,true}){
                @autoreleasepool{
                    reset();throwKind=kind;throwKey=key;bool caught=false;
                    try{NSDictionary *value=serialize(local?2:1);assert(kind==1&&!value);caught=kind==1;}
                    catch(const std::runtime_error &){caught=kind==2;}
                    assert(caught&&valueDrops==1);
                }
                assert(boxes==0&&!lastBox);
            }
        }
    }
    @autoreleasepool{
        reset();errorKey=2003;int error=0;TLinkAXSnapshotWindow window(tick,100);
        assert(!Current::TLinkAXAttribute((__bridge CFTypeRef)node,2003,&error,&window));assert(error==7&&valueDrops==1&&boxes==0);
        keys.clear();cancelled=true;assert(!Current::TLinkAXAttribute((__bridge CFTypeRef)node,2003,&error,&window)&&keys.empty());
    }
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{reset();attributeCost=100000000ULL;NSDictionary *value=snapshot(true);assert([value[@"partial"] boolValue]&&rootRetains==rootDrops);}
        assert(boxes==0&&!queryArray);
    }
    parent.reset();node=nil;rootObject=nil;
}
#include "ax-hit-test-runtime-fixture.inc"
#include "ax-parent-attribute-runtime-fixture.inc"
#include "ax-admission-runtime-fixture.inc"
#include "ax-hit-output-runtime-fixture.inc"
int main(){@autoreleasepool{
    std::puts("AX attributes Foundation: actual/frozen attribute/serializer plus complete snapshot/action gate, real CF ownership/CG geometry and controlled AX providers");
    parityCases();deadlineCases();cleanupCases();hitTestCases();parentAttributeCases();admissionCases();hitOutputCases();
    std::puts("AX attributes passed: 240 frozen/default/local row and key-order cases, per-RPC local/parent timeout, setup/decode/late/cancel gates, missing setter, NS/C++ after-write CF cleanup and 128 pool lifecycles. Private AX/device qualification pending.");
}return 0;}
