#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <objc/message.h>
#include <dlfcn.h>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <unordered_set>
#include "../shared/TLinkAXSymbolCache.h"
#include "../shared/TLinkNativeBudget.h"
#include "../shared/TLinkAXAdmission.h"
#include "../shared/TLinkAXSnapshotOutput.h"
#include "../shared/TLinkAXWireOutput.h"
#include "../shared/TLinkAXJSONQuota.h"
#include "AXCapabilityConstants.inc"
static NSString *const TLinkAXBackendName=@"axruntime_numeric_v1",*const TLinkAXSnapshotSchema=@"ui_snapshot_v1";
#include "AXProbeError.inc"
static int marker;
static void *sTLinkAXCreateApp=&marker,*sTLinkAXCopyAttribute=&marker,*sTLinkAXSetTimeout=&marker,*sTLinkAXValueGetValue=&marker,*sTLinkAXHitTest=&marker;
static BOOL sTLinkAXFrameworkLoaded=YES,sTLinkAccessibilityLibraryLoaded=YES,sTLinkAXEnableSymbol=YES,sTLinkAXAutomationSymbol=YES,sTLinkAXRequestingClientSymbol=YES,sTLinkAXOverrideClientSymbol=YES;
static const char *const sbsPath="/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices";
static const char *const securityPath="/System/Library/Frameworks/Security.framework/Security";
static unsigned counts[26],stopAt,stopNth=1,faultAt,faultKind,afterStop,tokenDrops,cfCreates,cfDrops,valueDrops;
static bool overflow,registrationFailure,taskFailure,malformedLegacy,missingClass,missingServer,escapeTLS,systemFrontmost=true;
static unsigned contextMode;
static std::shared_ptr<TLinkNativeCancellation> cancellation;
static std::shared_ptr<TLinkNativeBudget> captured;
static std::unordered_set<CFTypeRef> tasks,errors;
static std::unique_ptr<TLinkAXSymbols::Cache> sbsCache,securityCache,copyCache;
static std::unique_ptr<TLinkAXSymbols::Symbol> serverSymbol,legacySymbol;
static NSArray *frontValues;
#undef assert
#define assert(condition) do { if (!(condition)) { \
    std::fprintf(stderr,"AX probe check line %d: %s; stop=%u nth=%u output=%d fault=%u/%u after=%u token=%u/%u CF=%u/%u tasks=%zu errors=%zu\n", \
        __LINE__,#condition,stopAt,stopNth,(int)overflow,faultAt,faultKind,afterStop,tokenDrops,counts[1],cfDrops,cfCreates,tasks.size(),errors.size()); \
    std::abort(); \
} } while (0)
static void effect(unsigned stage){
    assert(stage<26);if(captured&&captured->stopped())++afterStop;
    const unsigned call=++counts[stage];
    if(stage==stopAt&&call==stopNth){assert(captured&&cancellation);if(overflow)assert(!captured->outputAllowed(1025));else cancellation->cancel();
        if(escapeTLS)TLinkNativeBudgetSlot()=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1024);}
    if(stage==faultAt){if(faultKind==1)[NSException raise:@"AXProbeFixture" format:@"fault"];if(faultKind==2)throw std::runtime_error("probe");}
}
static void reset(){
    assert(tasks.empty()&&errors.empty());
    std::memset(counts,0,sizeof(counts));stopAt=faultAt=faultKind=afterStop=tokenDrops=cfCreates=cfDrops=valueDrops=0;stopNth=1;
    overflow=registrationFailure=taskFailure=malformedLegacy=missingClass=missingServer=escapeTLS=false;systemFrontmost=true;contextMode=0;
    captured.reset();cancellation.reset();frontValues=@[@"first.测试",@"second.Ảnh"];
    sbsCache.reset(new TLinkAXSymbols::Cache(sbsPath,"SBSSpringBoardServerPort","SBGetScreenLockStatus"));
    securityCache.reset(new TLinkAXSymbols::Cache(securityPath,"SecTaskCreateFromSelf","SecTaskCopyValueForEntitlement"));
    copyCache.reset(new TLinkAXSymbols::Cache(sbsPath,"SBSCopyFrontmostApplicationDisplayIdentifier","SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay"));
    serverSymbol.reset(new TLinkAXSymbols::Symbol("SBSSpringBoardServerPort"));legacySymbol.reset(new TLinkAXSymbols::Symbol("SBFrontmostApplicationDisplayIdentifier"));
}
static TLinkAXSymbols::Cache &fixtureCache(const char *path){return !std::strcmp(path,sbsPath)?*sbsCache:*securityCache;}
static int fixtureRegister(const char *name,int *token){assert(name&&token);effect(1);if(registrationFailure)return 1;*token=42;return 0;}
static int fixtureState(int token,uint64_t *state){assert(token==42&&state);effect(2);*state=1;return 0;}
static int fixtureCancel(int token){assert(token==42);++tokenDrops;return 0;}
static mach_port_t fixtureServer(){effect(6);return 123;}
static void fixtureLock(mach_port_t port,BOOL *locked,BOOL *passcode){assert(port==123);effect(7);*locked=YES;*passcode=YES;}
static CFTypeRef fixtureCreateTask(CFAllocatorRef allocator){
    assert(allocator==kCFAllocatorDefault);effect(10);if(taskFailure)return NULL;
    const uint8_t bytes[]={1,2,3};CFDataRef task=CFDataCreate(allocator,bytes,3);assert(task&&tasks.insert(task).second);return task;
}
static CFTypeRef fixtureEntitlement(CFTypeRef task,CFStringRef name,CFErrorRef *error){
    assert(tasks.count(task)&&name&&error&&!*error);
    *error=CFErrorCreate(kCFAllocatorDefault,CFSTR("AXProbeFixture"),1,NULL);assert(*error&&errors.insert(*error).second);
    effect(11);return CFRetain(kCFBooleanTrue);
}
static CFStringRef fixtureCopy(unsigned index){effect(14+index);id value=frontValues[index];if(value==[NSNull null])return NULL;++cfCreates;return (CFStringRef)CFRetain((__bridge CFTypeRef)value);}
static CFStringRef fixtureFirst(){return fixtureCopy(0);}
static CFStringRef fixtureSecond(){return fixtureCopy(1);}
static NSString *fixtureSnapshotCopy(CFStringRef value){effect(16);return [(__bridge NSString *)value copy];}
static void fixtureLegacy(mach_port_t port,char *buffer){assert(port==123&&buffer);effect(17);if(malformedLegacy)std::memset(buffer,'x',512);else std::memcpy(buffer,"legacy.fixture",15);}
static void fixtureRelease(CFTypeRef value){
    assert(value);if(tasks.erase(value)){}else if(errors.erase(value)){}else if(value==kCFBooleanTrue)++valueDrops;else ++cfDrops;CFRelease(value);
}
static void *fixtureOpen(const char *path,int flags){assert(flags==(RTLD_LAZY|RTLD_LOCAL));const bool security=!std::strcmp(path,securityPath);assert(security||!std::strcmp(path,sbsPath));effect(security?8:4);return security?(void *)&securityPath:(void *)&sbsPath;}
static void *fixtureLookup(void *handle,const char *name){
    const bool security=handle==(void *)&securityPath;assert(security||handle==(void *)&sbsPath);effect(security?9:5);
    if(!std::strcmp(name,"SecTaskCreateFromSelf"))return (void *)&fixtureCreateTask;
    if(!std::strcmp(name,"SecTaskCopyValueForEntitlement"))return (void *)&fixtureEntitlement;
    if(!std::strcmp(name,"SBSSpringBoardServerPort"))return (void *)&fixtureServer;
    if(!std::strcmp(name,"SBGetScreenLockStatus"))return (void *)&fixtureLock;
    if(!std::strcmp(name,"SBSCopyFrontmostApplicationDisplayIdentifier"))return (void *)&fixtureFirst;
    if(!std::strcmp(name,"SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay"))return (void *)&fixtureSecond;
    assert(!std::strcmp(name,"SBFrontmostApplicationDisplayIdentifier"));return (void *)&fixtureLegacy;
}
static int fixtureClose(void *handle){assert(handle);return 0;}
static BOOL TLinkAXPrepare(){effect(12);return YES;}
static NSDictionary *TLinkAXCopyFrontmostContext(){effect(13);return @{@"ok":@YES,@"bundle_id":@"fixture",@"pid":@123};}
static void fixtureDirectLoad(){effect(18);}
@interface FixtureAXServer:NSObject
+(id)server;
-(BOOL)isSystemAppFrontmost;
@end
@implementation FixtureAXServer
+(id)server{effect(20);static id value;static dispatch_once_t once;dispatch_once(&once,^{value=[FixtureAXServer new];});return missingServer?nil:value;}
-(BOOL)isSystemAppFrontmost{effect(23);return systemFrontmost;}
@end
static Class fixtureClass(NSString *name){assert([name isEqual:@"AXSpringBoardServer"]);effect(19);return missingClass?(Class)nullptr:[FixtureAXServer class];}
static pid_t fixturePID(id server,SEL selector){assert(server);if(selector==NSSelectorFromString(@"focusedAppPID")){effect(21);return 123;}assert(selector==NSSelectorFromString(@"topEventPidOverride"));effect(22);return 456;}
static NSDictionary *fixtureContext(pid_t pid){effect(24);if((contextMode==0&&pid==123)||(contextMode==1&&pid==456)||(contextMode==2&&pid==789))return @{@"bundle_id":@"fixture",@"pid":@(pid)};return nil;}
static pid_t fixtureScan(NSString *bundle){assert([bundle isEqual:@"com.apple.springboard"]);effect(25);return 789;}
namespace Current {
#include "CurrentAXProbenotify.inc"
#include "CurrentAXProbelock.inc"
#include "CurrentAXProbeentitlement.inc"
#include "CurrentAXProbecapability.inc"
#include "CurrentAXProbefrontmost.inc"
#include "CurrentAXProbedirect.inc"
}
namespace Before {
#include "BeforeAXProbenotify.inc"
#include "BeforeAXProbelock.inc"
#include "BeforeAXProbeentitlement.inc"
#include "BeforeAXProbecapability.inc"
#include "BeforeAXProbefrontmost.inc"
#include "BeforeAXProbedirect.inc"
}
static void balanced(){assert(tasks.empty()&&errors.empty()&&tokenDrops==counts[1]-(registrationFailure?counts[1]:0)&&cfCreates==cfDrops);}
static NSDictionary *capability(bool current){return current?Current::TLinkAXCapabilitySnapshot():Before::TLinkAXCapabilitySnapshot();}
static NSDictionary *direct(bool current){return current?Current::TLinkAXDirectFrontmostContext():Before::TLinkAXDirectFrontmostContext();}
static NSString *frontmost(bool current){return current?Current::TLinkAXFrontmostBundleID():Before::TLinkAXFrontmostBundleID();}
static void parityCases(){
    for(unsigned n=0;n<128;++n){NSDictionary *cap=nil,*context=nil;NSString *front=nil;
        for(bool current:{false,true}){@autoreleasepool{
            reset();contextMode=n%4;systemFrontmost=n%5!=0;missingClass=n%7==0;missingServer=n%11==0;taskFailure=n%13==0;registrationFailure=n%17==0;
            if(n%3==0)frontValues=@[[NSNull null],@"second.测试"];if(n%4==0)frontValues=@[@"",[NSNull null]];
            NSDictionary *c=capability(current),*d=direct(current);NSString *f=frontmost(current);
            if(current){assert([c isEqual:cap]&&[d isEqual:context]);assert(f==front||[f isEqual:front]);}else{cap=c;context=d;front=f;}
            balanced();
        }}
    }
}
static void bind(bool cleanup=false,bool parent=false){
    cancellation=std::make_shared<TLinkNativeCancellation>();captured=std::make_shared<TLinkNativeBudget>(cancellation,0,1024,cleanup);
    if(parent)captured=std::make_shared<TLinkNativeBudget>(0,captured);
}
static void checkError(NSDictionary *value){assert([value[@"error"] isEqual:(overflow?@"ui_response_too_large":@"ui_cancelled_or_timed_out")]);}
static void stoppedCases(){
    for(bool out:{false,true})for(unsigned stage:{0U,1U,2U,4U,5U,6U,7U,8U,9U,10U,11U,12U,13U}){@autoreleasepool{
        reset();bind();overflow=out;stopAt=stage;TLinkNativeBudgetScope scope(captured);
        if(!stage){if(out)assert(!captured->outputAllowed(1025));else cancellation->cancel();}
        checkError(capability(true));assert(afterStop==(stage==4||stage==8?2U:(stage==5||stage==9?1U:0U)));balanced();
        if(stage==10)assert(counts[11]==0&&valueDrops==0);
        if(stage==11)assert(counts[11]==1&&valueDrops==1);
    }}
    for(unsigned nth=1;nth<=3;++nth){reset();bind();stopAt=11;stopNth=nth;TLinkNativeBudgetScope scope(captured);checkError(capability(true));assert(counts[11]==nth&&counts[10]==1&&valueDrops==1&&afterStop==0);balanced();}
    for(bool out:{false,true})for(unsigned stage:{0U,4U,5U,14U,15U,16U,6U,17U}){@autoreleasepool{
        reset();bind();overflow=out;stopAt=stage;if(stage==15)frontValues=@[[NSNull null],@"second"];if(stage==6||stage==17)frontValues=@[[NSNull null],[NSNull null]];
        TLinkNativeBudgetScope scope(captured);if(!stage){if(out)assert(!captured->outputAllowed(1025));else cancellation->cancel();}
        assert(!frontmost(true)&&afterStop==(stage==4?1U:0U));balanced();
    }}
    for(bool out:{false,true})for(unsigned stage:{0U,18U,19U,20U,21U,22U,23U,24U,25U}){@autoreleasepool{
        reset();bind();overflow=out;stopAt=stage;contextMode=stage==25?2:0;TLinkNativeBudgetScope scope(captured);
        if(!stage){if(out)assert(!captured->outputAllowed(1025));else cancellation->cancel();}
        checkError(direct(true));assert(afterStop==0);balanced();if(stage==25)assert(counts[24]==2);
    }}
    for(bool cleanup:{false,true}){reset();bind(cleanup,true);cancellation->cancel();TLinkNativeBudgetScope scope(captured);checkError(capability(true));assert(counts[12]==0);balanced();}
    reset();bind(true);cancellation->cancel();{TLinkNativeBudgetScope scope(captured);assert([capability(true)[@"ok"] boolValue]);}balanced();
    reset();cancellation=std::make_shared<TLinkNativeCancellation>();captured=std::make_shared<TLinkNativeBudget>(cancellation,1,1024);{TLinkNativeBudgetScope scope(captured);checkError(capability(true));assert(counts[12]==0);}balanced();
    for(bool out:{false,true})for(unsigned stage:{2U,13U,14U,21U}){reset();bind();overflow=out;escapeTLS=true;stopAt=stage;
        {TLinkNativeBudgetScope scope(captured);if(stage==14)assert(!frontmost(true));else if(stage==21)checkError(direct(true));else checkError(capability(true));assert(TLinkCurrentNativeBudget()!=captured);}
        assert(!TLinkCurrentNativeBudget());balanced();}
}
static void faultCases(){
    // Old code lacks cleanup after string-copy or notify-state exceptions: do
    // not deliberately leak its retained objects just to compare failures.
    for(unsigned stage:{2U,11U,16U})for(unsigned kind:{1U,2U}){@autoreleasepool{
        reset();faultAt=stage;faultKind=kind;bool caught=false;
        @try{try{if(stage==2)Current::TLinkNotifyFlag("fixture");else if(stage==11)capability(true);else frontmost(true);}
            catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"AXProbeFixture"];}
        assert(caught);balanced();
    }}
    for(unsigned stage:{20U,21U,22U,23U})for(unsigned kind:{1U,2U})for(bool current:{false,true}){@autoreleasepool{
        reset();faultAt=stage;faultKind=kind;bool caught=false;NSDictionary *value=nil;
        @try{try{value=direct(current);}catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){(void)exception;assert(false);}
        if(kind==1)assert([value[@"error"] isEqual:@"ui_ax_springboard_query_failed"]&&!caught);else assert(caught);
        balanced();
    }}
    for(unsigned stage:{10U,11U}){reset();bind();stopAt=stage;{TLinkNativeBudgetScope scope(captured);assert(!Current::TLinkAXEntitlementValue(@"inspection"));}balanced();}
    for(unsigned n=0;n<128;++n){@autoreleasepool{reset();bind();stopAt=11;{TLinkNativeBudgetScope scope(captured);checkError(capability(true));}balanced();reset();assert([capability(true)[@"ok"] boolValue]);balanced();}}
    reset();frontValues=@[[NSNull null],[NSNull null]];malformedLegacy=true;assert(!frontmost(true));balanced();
}
int main(){@autoreleasepool{
    std::puts("AX probes: actual/frozen notify/lock/Security/capability/SBS/direct helpers, real Foundation/CF and controlled private providers");
    parityCases();stoppedCases();faultCases();reset();assert(!TLinkCurrentNativeBudget());
    std::puts("AX probes passed: 128 frozen graph/provider cases, captured cancel/limit/parent/cleanup/deadline/TLS stages, skipped subsequent probe groups, notify/CF exception cleanup, bounded legacy string and 128 stop/recovery cycles. Loader groups/private/device qualification pending.");
}return 0;}
