#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <vector>
#include "../shared/TLinkNativeBudget.h"
#include "../shared/TLinkAXProcessPolicy.h"
#include "ax-node-pool-owner.h"
static NSString *const TLinkAXSnapshotSchema=@"ui_snapshot_v1",*const TLinkAXBackendName=@"axruntime_numeric_v1";
#include "AXErrorUnderTest.inc"
static unsigned probes,reads,allocations,lookups,pathReads,infoReads,dispatches,appReads,stopAt,faultAt,faultKind;
static size_t reportedOverride,returnedOverride;
static bool overrideProbe,overrideRead,failProbe,failRead,failAllocation,shortAllocation,missingSymbol,trackOwners,readFiles;
static unsigned pathMode;
static bool outputStop=false;
static bool escapeCallerTLS=false;
static std::vector<struct kinfo_proc> rows;
static NSDictionary *pathMap,*infoMap;
static __weak NSMutableData *tableOwner;
static std::shared_ptr<TLinkNativeCancellation> cancellation;
static std::weak_ptr<TLinkNativeBudget> caller;
extern "C" void TLinkAXFixtureOwnerDidDrain(void){}
static void effect(unsigned stage){
    if(stage==stopAt){assert(cancellation);if(outputStop){auto budget=caller.lock();assert(budget&&!budget->outputAllowed(budget->outputLimit()+1));}else cancellation->cancel();
        if(escapeCallerTLS)TLinkNativeBudgetSlot()=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1024);}
    if(stage==faultAt){if(faultKind==1)[NSException raise:@"ForegroundFixture" format:@"fault"];if(faultKind==2)throw std::runtime_error("foreground");}
}
static pid_t fixtureSelfPID(){return 999999;}
static int fixtureSysctl(int *mib,unsigned count,void *output,size_t *length,void *input,size_t inputLength){
    assert(mib&&count==3&&mib[0]==CTL_KERN&&mib[1]==KERN_PROC&&mib[2]==KERN_PROC_ALL&&!input&&!inputLength&&length);
    if(!output){++probes;effect(1);*length=overrideProbe?reportedOverride:rows.size()*sizeof(struct kinfo_proc);return failProbe?-1:0;}
    ++reads;effect(3);const size_t capacity=*length,bytes=rows.size()*sizeof(struct kinfo_proc);
    if(bytes)std::memcpy(output,rows.data(),std::min(capacity,bytes));
    *length=overrideRead?returnedOverride:bytes;return failRead?-1:0;
}
static NSMutableData *fixtureTableData(NSUInteger capacity){
    ++allocations;effect(2);assert(capacity<=TLinkAXProcessPolicy::MaxTableBytes);
    if(failAllocation)return nil;
    NSMutableData *data=[NSMutableData dataWithLength:shortAllocation?capacity-1:capacity];tableOwner=data;return data;
}
static int fixturePIDPath(int pid,void *output,uint32_t capacity){
    ++pathReads;effect(5);assert(output&&capacity==4096);
    if(pathMode==1)return 0;
    if(pathMode==2){std::memset(output,'x',capacity);return (int)capacity;}
    if(pathMode==3){std::memcpy(output,"a\0",2);return 9;}
    if(pathMode==4)return std::numeric_limits<int>::max();
    NSString *path=pathMap[@(pid)];if(!path)return 0;
    const char *utf8=path.UTF8String;const size_t length=std::strlen(utf8);assert(length<capacity);
    std::memcpy(output,utf8,length+1);return (int)length;
}
static void *fixtureLookup(void *handle,const char *name){
    ++lookups;effect(4);assert(handle==RTLD_DEFAULT&&!std::strcmp(name,"proc_pidpath"));return missingSymbol?nullptr:(void *)&fixturePIDPath;
}
static NSDictionary *fixtureInfo(NSString *path){
    ++infoReads;if(trackOwners)TLinkAXFixtureAutoreleaseOwner();effect(6);
    if(!readFiles)return infoMap[path];
    NSData *data=[NSData dataWithContentsOfFile:path];
    id value=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL]:nil;
    return [value isKindOfClass:[NSDictionary class]]?value:nil;
}
#include "CurrentAXProcess.inc"
#include "BeforeAXProcess.inc"
static void reset(unsigned count=4){
    probes=reads=allocations=lookups=pathReads=infoReads=dispatches=appReads=stopAt=faultAt=faultKind=0;
    reportedOverride=returnedOverride=0;overrideProbe=overrideRead=failProbe=failRead=failAllocation=shortAllocation=missingSymbol=trackOwners=readFiles=false;pathMode=0;
    rows.assign(count,{});NSMutableDictionary *paths=[NSMutableDictionary dictionary];
    for(unsigned n=0;n<count;++n){rows[n].kp_proc.p_pid=100+(int)n;paths[@(100+n)]=@"/fixture/Ứng.app/Run";}
    pathMap=paths;infoMap=@{@"/fixture/Ứng.app/Info.plist":@{@"CFBundleIdentifier":@"target",@"CFBundleExecutable":@"Run",@"CFBundlePackageType":@"APPL"}};
    tableOwner=nil;cancellation.reset();caller.reset();outputStop=escapeCallerTLS=false;
}
static pid_t scan(bool current,NSString *bundle=@"target"){return current?CurrentTLinkAXPIDForBundleID(bundle):BeforeTLinkAXPIDForBundleID(bundle);}
static NSDictionary *context(bool current,pid_t pid=100){return current?CurrentTLinkAXContextForPID(pid):BeforeTLinkAXContextForPID(pid);}
static void processCases(){
    for(unsigned n=0;n<128;++n){
        pid_t oldPID=0;NSDictionary *oldContext=nil;
        for(bool current:{false,true}){@autoreleasepool{
            reset(1+n%8);if(n%3==0)rows[0].kp_proc.p_pid=-1;if(n%5==0)missingSymbol=true;if(n%7==0)failRead=true;
            pid_t pid=scan(current);NSDictionary *value=context(current);
            if(current){assert(pid==oldPID);assert(value==oldContext||[value isEqual:oldContext]);}else{oldPID=pid;oldContext=value;}
        }}
    }
    for(unsigned fault=0;fault<9;++fault){@autoreleasepool{
        reset();
        if(fault==0){overrideProbe=true;reportedOverride=std::numeric_limits<size_t>::max();}
        if(fault==1){overrideProbe=true;reportedOverride=TLinkAXProcessPolicy::MaxTableBytes;}
        if(fault==2)failAllocation=true;
        if(fault==3)shortAllocation=true;
        if(fault==4){overrideRead=true;returnedOverride=TLinkAXProcessPolicy::MaxTableBytes+1;}
        if(fault>=5)pathMode=fault-4;
        assert(scan(true)==0);assert(infoReads==0);
        if(fault<=1)assert(allocations==0&&reads==0);
        if(fault==2||fault==3)assert(reads==0);
        if(fault==4)assert(lookups==0);
    }}
    for(unsigned stage=1;stage<=6;++stage){@autoreleasepool{
        reset();stopAt=stage;cancellation=std::make_shared<TLinkNativeCancellation>();
        auto budget=std::make_shared<TLinkNativeBudget>(cancellation,0,1024);caller=budget;TLinkNativeBudgetScope scope(budget);
        assert(scan(true)==0&&budget->stopped());
        assert((stage<=2?reads==0:true)&&(stage<=3?lookups==0:true)&&(stage<=4?pathReads==0:true)&&(stage<=5?infoReads==0:true));
        cancellation.reset();
    }}
    for(bool current:{false,true}){
        TLinkAXFixtureResetOwners();
        @autoreleasepool{
            reset(256);trackOwners=true;assert(scan(current,@"missing")==0&&infoReads==256);
            assert(TLinkAXFixtureLiveOwners()==(current?0U:256U));assert(TLinkAXFixturePeakOwners()==(current?1U:256U));
            if(current)assert(!tableOwner);
        }
        assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==256&&!tableOwner);
    }
    for(bool current:{false,true})for(unsigned stage:{5U,6U})for(unsigned kind:{1U,2U}){
        TLinkAXFixtureResetOwners();
        @autoreleasepool{
            reset();trackOwners=true;faultAt=stage;faultKind=kind;bool caught=false;
            @try{try{scan(current);}catch(const std::runtime_error &){caught=kind==2;}}
            @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"ForegroundFixture"];}
            assert(caught);
        }
        assert(!tableOwner&&TLinkAXFixtureLiveOwners()==0);
    }
}
static void metadataCases(){
    for(bool current:{false,true}){reset();assert(!context(current,0)&&!context(current,fixtureSelfPID())&&lookups==0);}
    for(unsigned n=0;n<8;++n){
        NSDictionary *before=nil;
        for(bool current:{false,true}){@autoreleasepool{
            reset();NSMutableDictionary *info=[infoMap.allValues[0] mutableCopy];
            if(n==1)info[@"CFBundleExecutable"]=@"other";
            if(n==2)info[@"CFBundlePackageType"]=@"BNDL";
            if(n==3)info[@"LSBackgroundOnly"]=@YES;
            if(n==4)info[@"LSUIElement"]=@YES;
            if(n==5)info[@"SBAppTags"]=@[@"hidden"];
            if(n==6)info[@"CFBundleIdentifier"]=@"com.apple.AccessibilityUIServer";
            if(n==7)info[@"CFBundleIdentifier"]=@"com.apple.springboard";
            infoMap=@{@"/fixture/Ứng.app/Info.plist":info};NSDictionary *value=context(current);
            if(current)assert(value==before||[value isEqual:before]);else before=value;
            assert((value!=nil)==(n==0||n==7));
        }}
    }
    for(unsigned mode=1;mode<=4;++mode){reset();pathMode=mode;assert(!context(true)&&infoReads==0);}
    NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *app=[folder stringByAppendingPathComponent:@"Ảnh.app"],*file=[app stringByAppendingPathComponent:@"Info.plist"];
    @try{
        assert([[NSFileManager defaultManager] createDirectoryAtPath:app withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSDictionary *info=@{@"CFBundleIdentifier":@"real.fixture",@"CFBundleExecutable":@"Run",@"CFBundlePackageType":@"APPL"};
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];assert([data writeToFile:file atomically:YES]);
        for(bool current:{false,true}){reset();readFiles=true;pathMap=@{@100:[app stringByAppendingPathComponent:@"Run"]};assert(scan(current,@"real.fixture")==100&&[context(current)[@"bundle_id"] isEqual:@"real.fixture"]);}
    }@finally{assert([[NSFileManager defaultManager] removeItemAtPath:folder error:NULL]);}
}
static bool mainThread=true,inSpringBoard=true,missingClass=false,nilApp=false,callbackBound=false;
static unsigned queueStop=0;
static id app;
static void fixtureDispatchSync(dispatch_queue_t queue,dispatch_block_t operation){
    assert(queue==dispatch_get_main_queue());++dispatches;
    if(queueStop==1){assert(cancellation);cancellation->cancel();}
    if(queueStop==2){auto budget=caller.lock();assert(budget&&budget->deadline());std::this_thread::sleep_until(TLinkNativeClock::time_point(std::chrono::nanoseconds(budget->deadline())));}
    if(queueStop==3){auto budget=caller.lock();assert(budget&&!budget->outputAllowed(budget->outputLimit()+1));}
    auto ambient=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1024);
    TLinkNativeBudgetScope external(ambient);operation();
}
#define dispatch_sync fixtureDispatchSync
#include "../shared/TLinkNativeDispatch.h"
#undef dispatch_sync
@interface FixtureBundle:NSObject
+(instancetype)mainBundle;
-(NSString *)bundleIdentifier;
@end
@implementation FixtureBundle
+(instancetype)mainBundle{static FixtureBundle *value;static dispatch_once_t once;dispatch_once(&once,^{value=[FixtureBundle new];});return value;}
-(NSString *)bundleIdentifier{return inSpringBoard?@"com.apple.springboard":@"fixture.other";}
@end
@interface FixtureApp:NSObject
@property(nonatomic,strong) id pidNumber;
-(NSString *)bundleIdentifier;
-(id)pid;
-(id)processIdentifier;
@end
@implementation FixtureApp
-(NSString *)bundleIdentifier{effect(9);return @"target";}
-(id)pid{effect(10);return self.pidNumber;}
-(id)processIdentifier{return self.pidNumber;}
@end
@interface FixtureSpringBoard:NSObject
+(instancetype)sharedApplication;
-(id)_accessibilityFrontMostApplication;
@end
@implementation FixtureSpringBoard
+(instancetype)sharedApplication{static FixtureSpringBoard *value;static dispatch_once_t once;dispatch_once(&once,^{value=[FixtureSpringBoard new];});return value;}
-(id)_accessibilityFrontMostApplication{++appReads;callbackBound=TLinkCurrentNativeBudget()==caller.lock();effect(8);return nilApp?nil:app;}
@end
static BOOL fixtureMainThread(){return mainThread;}
static Class fixtureClass(NSString *name){return !missingClass&&[name isEqual:@"SpringBoard"]?[FixtureSpringBoard class]:(Class)nullptr;}
#include "CurrentAXSpringBoard.inc"
#include "BeforeAXSpringBoard.inc"
static void bridgeReset(){reset();mainThread=true;queueStop=0;missingClass=nilApp=false;inSpringBoard=true;callbackBound=false;FixtureApp *value=[FixtureApp new];value.pidNumber=@123;app=value;}
static NSDictionary *bridge(bool current){return current?CurrentTLinkAXSpringBoardProcessContext():BeforeTLinkAXSpringBoardProcessContext();}
static void bridgeCases(){
    for(unsigned n=0;n<8;++n){NSDictionary *before=nil;
        for(bool current:{false,true}){@autoreleasepool{
            bridgeReset();mainThread=n%2==0;if(n==2)inSpringBoard=false;if(n==3)missingClass=true;if(n==4)nilApp=true;
            if(n>=5)((FixtureApp *)app).pidNumber=nil;
            if(n==6)infoMap=@{};
            NSDictionary *value=bridge(current);if(current)assert(value==before||[value isEqual:before]);else before=value;
        }}
    }
    for(bool current:{false,true})for(unsigned stop=0;stop<4;++stop){@autoreleasepool{
        bridgeReset();mainThread=false;queueStop=stop;cancellation=std::make_shared<TLinkNativeCancellation>();
        auto budget=std::make_shared<TLinkNativeBudget>(cancellation,stop==2?TLinkNativeDeadline(.025):0,1024);caller=budget;TLinkNativeBudgetScope scope(budget);
        NSDictionary *value=bridge(current);
        if(current&&stop){assert([value[@"error"] isEqual:(stop==3?@"ui_response_too_large":@"ui_cancelled_or_timed_out")]&&appReads==0);assert(dispatches==1||(stop==2&&dispatches==0));}
        else{assert([value[@"ok"] boolValue]&&appReads==1);assert(callbackBound==current);}
        cancellation.reset();
    }}
    for(unsigned stage:{8U,9U,10U}){@autoreleasepool{
        bridgeReset();stopAt=stage;cancellation=std::make_shared<TLinkNativeCancellation>();
        auto budget=std::make_shared<TLinkNativeBudget>(cancellation,0,1024);caller=budget;TLinkNativeBudgetScope scope(budget);
        assert([bridge(true)[@"error"] isEqual:@"ui_cancelled_or_timed_out"]);cancellation.reset();
    }}
    for(bool current:{false,true})for(unsigned kind:{1U,2U}){@autoreleasepool{
        bridgeReset();faultAt=8;faultKind=kind;bool caught=false;NSDictionary *value=nil;
        @try{try{value=bridge(current);}catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){(void)exception;assert(false);}
        if(kind==1)assert([value[@"error"] isEqual:@"ui_springboard_frontmost_query_failed"]&&!caught);else assert(caught);
    }}
}
static unsigned inCalls,directCalls,bundleCalls,pidCalls,inMode,directMode;
static NSDictionary *goodContext(){return @{@"ok":@YES,@"bundle_id":@"target",@"pid":@123};}
static NSDictionary *fixtureInProcess(){++inCalls;effect(11);return inMode==0?nil:(inMode==1?goodContext():TLinkAXError(@"in_error",nil));}
static NSDictionary *fixtureDirect(){++directCalls;effect(12);return directMode==1?goodContext():TLinkAXError(@"direct_error",nil);}
static NSString *fixtureBundleID(){++bundleCalls;effect(13);return @"target";}
static pid_t fixturePID(NSString *bundle){assert([bundle isEqual:@"target"]);++pidCalls;effect(14);return 123;}
#include "CurrentAXPublicForeground.inc"
#include "BeforeAXPublicForeground.inc"
static void publicReset(){reset();inCalls=directCalls=bundleCalls=pidCalls=inMode=directMode=0;}
static void publicCases(){
    for(unsigned n=0;n<128;++n){NSDictionary *before=nil;
        for(bool current:{false,true}){@autoreleasepool{
            publicReset();inMode=n%3;directMode=n%2;
            NSDictionary *value=current?CurrentTLinkAXCopyFrontmostContext():BeforeTLinkAXCopyFrontmostContext();
            if(current)assert([value isEqual:before]);else before=value;
        }}
    }
    for(bool overflow:{false,true})for(unsigned stage:{0U,11U,12U,13U,14U}){@autoreleasepool{
        publicReset();stopAt=stage;outputStop=overflow;cancellation=std::make_shared<TLinkNativeCancellation>();
        auto budget=std::make_shared<TLinkNativeBudget>(cancellation,0,1024);caller=budget;TLinkNativeBudgetScope scope(budget);
        if(stage==0){if(overflow)assert(!budget->outputAllowed(1025));else cancellation->cancel();}
        NSDictionary *value=CurrentTLinkAXCopyFrontmostContext();assert([value[@"error"] isEqual:(overflow?@"ui_response_too_large":@"ui_cancelled_or_timed_out")]);
        assert(inCalls==(stage==0?0U:1U)&&directCalls==(stage<=11?0U:1U)&&bundleCalls==(stage<=12?0U:1U)&&pidCalls==(stage<=13?0U:1U));
        cancellation.reset();
    }}
}
int main(){@autoreleasepool{
    std::puts("AX foreground work: actual/frozen process/metadata/main/public helpers, real Foundation/CF/plist and controlled sysctl/path/private/queue providers");
    processCases();metadataCases();bridgeCases();publicCases();
    for(bool overflow:{false,true})for(unsigned stage:{8U,9U,10U,11U,12U,13U,14U}){@autoreleasepool{
        if(stage<=10)bridgeReset();else publicReset();stopAt=stage;escapeCallerTLS=true;outputStop=overflow;
        cancellation=std::make_shared<TLinkNativeCancellation>();auto budget=std::make_shared<TLinkNativeBudget>(cancellation,0,1024);caller=budget;
        {TLinkNativeBudgetScope scope(budget);NSDictionary *value=stage<=10?bridge(true):CurrentTLinkAXCopyFrontmostContext();
            assert([value[@"error"] isEqual:(overflow?@"ui_response_too_large":@"ui_cancelled_or_timed_out")]);assert(TLinkCurrentNativeBudget()!=budget);}
        assert(!TLinkCurrentNativeBudget());
    }}reset();
    assert(!TLinkCurrentNativeBudget()&&TLinkAXFixtureLiveOwners()==0);
    std::puts("AX foreground work passed: 128 process/public frozen comparisons, bounded allocation/path faults, scan cancellation, peak one vs256 temporary owners, real plist guards, actual native budget bridge under controlled main scheduling and fallback stop isolation. Real process/main-thread/device performance pending.");
}return 0;}
