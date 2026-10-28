// Actual scheduler owner/registry/core; real GCD sources held at FOREVER for deterministic bridge parity.
#include <dispatch/dispatch.h>
#include "../shared/TLinkSchedulerState.h"
static bool nativeTimerCreateFails=false,nativeTimerGenerationFails=false;
static unsigned nativeTimerAttempts=0,nativeTimerCreated=0,nativeTimerCancelled=0,nativeTimerResumed=0,nativeTimerSyncs=0,nativeTimerFault=0;
static int64_t nativeTimerDelay=0;
static uint64_t nativeTimerPeriod=0,nativeTimerLeeway=0;
static NSString *nativeTimerFaultStage=nil;
static std::function<void(NSString *)> nativeTimerOnSync;
static TLinkNativeBudgetPtr nativeTimerBudget;
template<typename Timer> class NativeTimerRecordingRegistry {
    TLinkSchedulerRegistry<Timer> core_;
public:
    std::map<std::string,std::pair<NSString *,bool>> records;
    uint64_t set(const std::string &name,const Timer &timer,bool repeat){
        if(nativeTimerGenerationFails)return 0;
        const uint64_t generation=core_.set(name,timer,repeat);if(generation)records[name]={timer.script,repeat};return generation;
    }
    void remove(const std::string &name){core_.remove(name);records.erase(name);}
    size_t size()const{return core_.size();}
    template<typename Launch> TLinkSchedulerFireResult fire(const std::string &name,uint64_t generation,bool busy,Launch launch){return core_.fire(name,generation,busy,launch);}
};
static void nativeTimerCancel(dispatch_source_t source);
#define TLinkSchedulerRegistry NativeTimerRecordingRegistry
#define dispatch_source_cancel nativeTimerCancel
#include "TimerOwnerUnderTest.inc"
#undef dispatch_source_cancel
#undef TLinkSchedulerRegistry
static void nativeTimerCancel(dispatch_source_t source){assert(dispatch_get_specific(&schedulerQueueKey));++nativeTimerCancelled;dispatch_source_cancel(source);}
static dispatch_source_t nativeTimerCreate(dispatch_source_type_t type,uintptr_t handle,unsigned long mask,dispatch_queue_t queue){
    assert(dispatch_get_specific(&schedulerQueueKey)&&type==DISPATCH_SOURCE_TYPE_TIMER&&!handle&&!mask&&queue==schedulerQueue());++nativeTimerAttempts;
    if(nativeTimerCreateFails)return nullptr;
    dispatch_source_t source=dispatch_source_create(type,handle,mask,queue);assert(source);++nativeTimerCreated;return source;
}
static dispatch_time_t nativeTimerTime(dispatch_time_t base,int64_t delta){assert(dispatch_get_specific(&schedulerQueueKey)&&base==DISPATCH_TIME_NOW&&delta>0);nativeTimerDelay=delta;return dispatch_time(base,delta);}
static void nativeTimerConfigure(dispatch_source_t source,dispatch_time_t start,uint64_t period,uint64_t leeway){
    assert(dispatch_get_specific(&schedulerQueueKey)&&source&&start!=DISPATCH_TIME_FOREVER);nativeTimerPeriod=period;nativeTimerLeeway=leeway;
    dispatch_source_set_timer(source,DISPATCH_TIME_FOREVER,DISPATCH_TIME_FOREVER,0);
}
static void nativeTimerResume(dispatch_source_t source){assert(dispatch_get_specific(&schedulerQueueKey));++nativeTimerResumed;dispatch_resume(source);}
static void nativeTimerObserve(NSString *stage){
    nativeTimerBudget=TLinkCurrentNativeBudget();assert(nativeTimerBudget&&!nativeTimerBudget->cleanup());
    if([stage isEqual:nativeTimerFaultStage]&&nativeTimerFault==1)[NSException raise:@"TimerFixture" format:@"owner boundary throws"];
    if([stage isEqual:nativeTimerFaultStage]&&nativeTimerFault==2)throw std::runtime_error("timer owner boundary throws");
    if(nativeTimerOnSync)nativeTimerOnSync(stage);
}
static void nativeTimerSync(dispatch_block_t operation){++nativeTimerSyncs;nativeTimerObserve(@"before");schedulerPerformSync(operation);nativeTimerObserve(@"after");}
static BOOL nativeTimerCanStart(){assert(false&&"fixture sources must remain held; real delivery is covered by scheduler-runtime-test");return false;}
static BOOL nativeTimerLaunchAllowed(NSString *source){(void)source;assert(false);return false;}
static int nativeTimerPlay(UInt8 *path,NSError **error){(void)path;(void)error;assert(false);return 0;}
static void nativeTimerLastError(NSString *message){(void)message;assert(false);}
NSString* TLinkSetTimer(NSString *name, NSString *intervalText, BOOL repeat, NSString *script, NSError **error);
NSString* TLinkRemoveTimer(NSString *name, NSError **error);
#define canStartScriptPlaying nativeTimerCanStart
#define TLinkSchedulerScriptLaunchAllowed nativeTimerLaunchAllowed
#define playScript nativeTimerPlay
#define setLastScriptError nativeTimerLastError
#define schedulerPerformSync nativeTimerSync
#define dispatch_source_create nativeTimerCreate
#define dispatch_source_cancel nativeTimerCancel
#define dispatch_source_set_timer nativeTimerConfigure
#define dispatch_time nativeTimerTime
#define dispatch_resume nativeTimerResume
#include "TimerCoreUnderTest.inc"
#define setTimerFromRawData legacySetTimerFromRawData
#define removeTimerFromRawData legacyRemoveTimerFromRawData
#include "fixtures/timer-core-legacy-v1.inc"
#undef removeTimerFromRawData
#undef setTimerFromRawData
#undef dispatch_resume
#undef dispatch_time
#undef dispatch_source_set_timer
#undef dispatch_source_cancel
#undef dispatch_source_create
#undef schedulerPerformSync
#undef setLastScriptError
#undef playScript
#undef TLinkSchedulerScriptLaunchAllowed
#undef canStartScriptPlaying
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeTimerEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void timerLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=(bytes[0]-'0')*10+bytes[1]-'0';UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){NSString *denial=[NSString stringWithFormat:@"-1;;license_required task=%d\r\n",taskType];notifyClient((UInt8 *)denial.UTF8String,writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#define setTimerFromRawData legacySetTimerFromRawData
#define removeTimerFromRawData legacyRemoveTimerFromRawData
#include "fixtures/timer-handler-legacy-v1.inc"
#undef removeTimerFromRawData
#undef setTimerFromRawData
}
static NSDictionary *nativeTimerSnapshot(){
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    schedulerPerformSync(^{for(const auto &row:timerRegistry.records)result[[NSString stringWithUTF8String:row.first.c_str()]]=@{@"script":row.second.first,@"repeat":@(row.second.second)};assert(timerRegistry.size()==timerRegistry.records.size());});return [result copy];
}
static void nativeTimerDrain(){
    schedulerPerformSync(^{std::vector<std::string> names;for(const auto &row:timerRegistry.records)names.push_back(row.first);for(const auto &name:names)timerRegistry.remove(name);});
    schedulerPerformSync(^{assert(timerRegistry.size()==0&&timerRegistry.records.empty());});
    assert(nativeTimerCreated==nativeTimerCancelled&&nativeTimerCreated==nativeTimerResumed);
}
static void typedTimerCases(TLinkInProcessNativeBridge *bridge){
    @try {try{
    mode=@"timerRuntime";puts("Timer Foundation: actual parser/owner/source parity and interval rounding");fflush(stdout);
    const auto reset=[](TLinkTaskExecutionContext *context,bool seed=false){
        nativeTimerDrain();nativeTimerCreateFails=nativeTimerGenerationFails=false;nativeTimerFault=0;nativeTimerFaultStage=nil;nativeTimerOnSync={};
        nativeTimerAttempts=nativeTimerCreated=nativeTimerCancelled=nativeTimerResumed=nativeTimerSyncs=0;nativeTimerDelay=0;nativeTimerPeriod=nativeTimerLeeway=0;nativeTimerBudget.reset();
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
        if(seed){TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *error=nil;assert(TLinkSetTimer(@"present",@"3600",true,@"old-script",&error)&&!error);}
        nativeTimerSyncs=0;nativeTimerBudget.reset();
    };
    const auto request=[](bool remove,NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:remove?TLinkJSNativeMethodRemoveTimer:TLinkJSNativeMethodSetTimer arguments:args];};
    const auto invoke=[bridge,request](bool remove,NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(remove,args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](bool remove,NSArray *args,NSUInteger cap,unsigned fault=0){
        auto context=parent(30,cap);reset(context,remove);nativeTimerCreateFails=fault==1;nativeTimerGenerationFails=fault==2;int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyTimer:request(remove,args) context:context];NSDictionary *state=nativeTimerSnapshot();
        const unsigned attempts=nativeTimerAttempts,created=nativeTimerCreated,cancelled=nativeTimerCancelled,resumed=nativeTimerResumed,syncs=nativeTimerSyncs;const int gateDelta=licenseCalls-gates;
        const int64_t delay=nativeTimerDelay;const uint64_t period=nativeTimerPeriod,leeway=nativeTimerLeeway;
        context=parent(30,cap);reset(context,remove);nativeTimerCreateFails=fault==1;nativeTimerGenerationFails=fault==2;gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(remove,args,context);const bool matches=actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]);
        if(!matches){fprintf(stdout,"Timer parity failure: %s\n",[NSString stringWithFormat:@"remove=%d args=%@ expected=%@ actual=%@",remove,args,expected.value,actual.value].UTF8String);fflush(stdout);}assert(matches);
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert([nativeTimerSnapshot() isEqual:state]&&calls==rawCalls&&licenseCalls==gates+gateDelta);
        assert(nativeTimerAttempts==attempts&&nativeTimerCreated==created&&nativeTimerCancelled==cancelled&&nativeTimerResumed==resumed&&nativeTimerSyncs==syncs&&nativeTimerDelay==delay&&nativeTimerPeriod==period&&nativeTimerLeeway==leeway);
        if(gateDelta)assert(lastLicenseTask==(remove?39:38));if(syncs)assert(nativeTimerBudget&&!nativeTimerBudget->capturesResponse()&&nativeTimerBudget->response().capacity()==0);
    };
    for(unsigned n=0;n<160;++n)parity(false,@[[NSString stringWithFormat:@"timer-%u",n],@(1.125+n),@(n%2),[NSString stringWithFormat:@"/script/测试-%u",n]],4096);
    for(double interval:{0.0001,0.0004,0.0005,0.0006,0.9994,0.9995,0.9996,1.0004,1.0005,1.234567,1e9,1e10,1e300})for(bool repeat:{false,true})parity(false,@[@"round",@(interval),@(repeat),@"script"],4096);
    for(id value in @[@(-1),@0,@(NAN),@(INFINITY),@"0.125",@"invalid"])parity(false,@[@"interval",value,@0,@"script"],4096);
    for(NSString *name in @[@"present",@"absent",@"Ứng dụng 😀",@"a;",@";",@" space "]){parity(true,@[name],4096);for(NSString *script in @[@"script",@";path",@"path;",@"路径"])parity(false,@[name,@1,@1,script],4096);}
    for(id value in @[@0,@1,@(-1),@"YES",@"false"])parity(false,@[@"repeat",@1,value,@"script"],4096);
    for(id invalid in @[@"",@"a;;b",@"a\r",@"a\n",[NSNull null],@17]){parity(true,@[invalid],4096);parity(false,@[invalid,@1,@0,@"script"],4096);parity(false,@[@"name",@1,@0,invalid],4096);}
    parity(false,@[],4096);parity(false,@[@"name"],4096);parity(true,@[],4096);parity(true,@[@"present",@"ignored"],4096);
    for(bool remove:{false,true})for(NSUInteger cap:{NSUInteger(3),NSUInteger(2)})parity(remove,remove?@[@"present"]:@[@"name",@1,@1,@"script"],cap);
    for(unsigned fault:{1U,2U}){parity(false,@[@"name",@1,@1,@"script"],4096,fault);parity(false,@[@"name",@1,@1,@"script"],2,fault);}
    puts("Timer Foundation: exact ingress, cancellation, owner commit and cleanup");fflush(stdout);
    for(NSString *unit in @[@"x",@"界"]){
        NSString *exact=[@"" stringByPaddingToLength:8177 withString:unit startingAtIndex:0];parity(false,@[exact,@1,@1,@"s"],4096);parity(false,@[@"n",@1,@1,exact],4096);
        parity(false,@[[exact stringByAppendingString:@"x"],@1,@1,@"s"],4096);parity(false,@[@"n",@1,@1,[exact stringByAppendingString:@"x"]],4096);
        exact=[@"" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];parity(true,@[exact],4096);parity(true,@[[exact stringByAppendingString:@"x"]],4096);
    }
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];
    parity(true,@[nul],4096);parity(false,@[nul,@1,@1,@"script"],4096);parity(false,@[@"name",@1,@1,nul],4096);if(invalid){parity(true,@[invalid],4096);parity(false,@[@"name",@1,@1,invalid],4096);}
    for(bool remove:{false,true}){
        NSArray *args=remove?@[@"present"]:@[@"new",@1,@1,@"script"];auto context=parent();reset(context,true);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(remove,args,context).value,remove?@"license_required task=39":@"license_required task=38");assert(nativeTimerSyncs==0&&[nativeTimerSnapshot() count]==1);
        context=parent();reset(context,true);const int gates=licenseCalls;[context.cancellationToken cancel];failure(invoke(remove,args,context).value,@"AbortError");assert(licenseCalls==gates&&nativeTimerSyncs==0);
        context=parent();reset(context,true);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(remove,args,context).value,@"TimeoutError");assert(licenseCalls==gates&&nativeTimerSyncs==0);
        context=parent();reset(context,true);stopInLicense=true;failure(invoke(remove,args,context).value,@"AbortError");assert(nativeTimerSyncs==0);
        context=parent(0.1);reset(context,true);licenseDelayMs=150;failure(invoke(remove,args,context).value,@"TimeoutError");assert(nativeTimerSyncs==0);
        for(NSString *stage in @[@"before",@"after"]){context=parent();reset(context,true);TLinkCancellationToken *token=context.cancellationToken;nativeTimerOnSync=[token,stage](NSString *point){if([point isEqual:stage])[token cancel];};
            failure(invoke(remove,args,context).value,@"AbortError");assert(nativeTimerSyncs==1&&[nativeTimerSnapshot() count]==(remove?0U:2U));}
        context=parent(0.1);reset(context,true);nativeTimerOnSync=[](NSString *stage){if([stage isEqualToString:@"before"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};
        failure(invoke(remove,args,context).value,@"TimeoutError");assert([nativeTimerSnapshot() count]==(remove?0U:2U));
        for(NSString *stage in @[@"before",@"after"])for(unsigned fault:{1U,2U}){context=parent();reset(context,true);nativeTimerFault=fault;nativeTimerFaultStage=stage;
            failure(invoke(remove,args,context).value,@"native_exception");assert([nativeTimerSnapshot() count]==([stage isEqualToString:@"before"]?1U:(remove?0U:2U)));}
        context=parent(1,2);reset(context,true);failure(invoke(remove,args,context).value,@"response_too_large");assert([nativeTimerSnapshot() count]==(remove?0U:2U));
    }
    auto context=parent();reset(context);NSMutableString *name=[@"snapshot" mutableCopy],*script=[@"original" mutableCopy];nativeTimerOnSync=[name,script](NSString *stage){if([stage isEqualToString:@"before"]){[name setString:@"changed"];[script setString:@"changed"];}};
    NSDictionary *held=nil;@autoreleasepool{held=invoke(false,@[name,@1,@1,script],context).value;context=nil;}assert([held[@"ok"] boolValue]&&[nativeTimerSnapshot()[@"snapshot"][@"script"] isEqualToString:@"original"]);
    for(bool legacy:{false,true})for(NSUInteger column:{NSUInteger(1),NSUInteger(2)}){context=parent();reset(context);NSMutableArray *args=[@[@"name",@1,@1,@"script"] mutableCopy];args[column]=[NSNull null];unsigned exceptions=0;
        @try{if(legacy)[bridge legacyTimer:request(false,args) context:context];else invoke(false,args,context);}@catch(NSException *exception){(void)exception;++exceptions;}assert(exceptions==1&&!nativeTimerSyncs&&!TLinkCurrentNativeBudget());}
    for(NSString *raw in @[@"",@"a;;1",@"a;;0.001;;1;;script",@"a;;1oops;;1;;script",@"a;; 1 ;;1;;script",@"a;;1e0;;1;;script",@"a;;1;;-2;;script;;ignored",@";;1;;1;;script",@"name;;1;;1;;"]){
        context=parent();reset(context);NSError *oldError=nil,*error=nil;NSString *expected=nil,*actual=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);expected=legacySetTimerFromRawData((UInt8 *)raw.UTF8String,&oldError);}NSDictionary *state=nativeTimerSnapshot();reset(context);
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);actual=setTimerFromRawData((UInt8 *)raw.UTF8String,&error);}assert((actual==expected)||[actual isEqual:expected]);assert((error==oldError)||[error.localizedDescription isEqual:oldError.localizedDescription]);assert([nativeTimerSnapshot() isEqual:state]);
    }
    for(unsigned n=0;n<1000;++n){context=parent();reset(context);assert([invoke(false,@[@"cycle",@1,@1,@"script"],context).value[@"ok"] boolValue]);assert([invoke(true,@[@"cycle"],context).value[@"ok"] boolValue]&&[nativeTimerSnapshot() count]==0);}
    nativeTimerDrain();nativeTimerBudget.reset();nativeTimerFaultStage=nil;nativeTimerOnSync={};licenseBudget.reset();touchToken=nil;mode=@"echo";assert(!TLinkCurrentNativeBudget());
    puts("Typed timers passed: actual serial owner/registry and real held GCD source lifecycle, frozen JS/RAW rounding/reply/state parity, ingress/task-38/39 gates, provider failures, accepted stop/fault/output effects and 1000 balanced cycles. Real delivery remains covered by scheduler-runtime-test; no scripts launched.");
    }catch(const std::exception &exception){fprintf(stdout,"Timer fixture: uncaught C++ exception: %s\n",exception.what());fflush(stdout);throw;}catch(...){puts("Timer fixture: uncaught non-standard C++ exception");fflush(stdout);throw;}}
    @catch(NSException *exception){fprintf(stdout,"Timer fixture: uncaught Objective-C exception: %s\n",exception.description.UTF8String?:"(no description)");fflush(stdout);@throw;}
}
