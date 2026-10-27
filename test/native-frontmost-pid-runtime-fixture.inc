// Actual Process core/RAW wrapper and native entry; controlled foreground/PID lookup boundaries.
#include <sys/types.h>
static pid_t frontPidValue=0;
static unsigned frontPidReads=0,frontPidFault=0;
static NSString *frontPidBundle=nil;
static TLinkNativeBudgetPtr frontPidBudget;
static std::function<void()> frontPidOnRead;
static pid_t zx_pidForBundleId(NSString *bundleId){
    ++frontPidReads;frontPidBudget=TLinkCurrentNativeBudget();assert(frontPidBudget&&!frontPidBudget->cleanup());
    frontPidBundle=[bundleId copy];
    if(frontPidFault==1)[NSException raise:@"FrontPidFixture" format:@"PID read throws"];
    if(frontPidFault==2)throw std::runtime_error("PID read throws");
    if(frontPidOnRead)frontPidOnRead();return frontPidValue;
}
NSString *frontMostPidValue(void);
#include "FrontmostPidCoreUnderTest.inc"
#define frontMostPidFromRawData legacyFrontMostPidFromRawData
#include "FrontmostPidLegacyCoreUnderTest.inc"
#undef frontMostPidFromRawData
static void frontmostPidLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_FRONTMOST_PID;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=51\r\n",writeStreamRef);return;}
    if(false){}
#define frontMostPidFromRawData legacyFrontMostPidFromRawData
#include "fixtures/frontmost-pid-handler-legacy-v1.inc"
#undef frontMostPidFromRawData
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeFrontmostPidEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedFrontmostPidCases(TLinkInProcessNativeBridge *bridge){
    mode=@"frontmostPidRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        frontmostValue=@"com.example.foreground";frontmostFault=0;frontmostOnRead={};frontPidFault=0;frontPidOnRead={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFrontMostPid arguments:args];};
    const auto invoke=[bridge,request](TLinkTaskExecutionContext *context)->NSDictionary *{
        NSDictionary *result=[bridge executeRequest:request(@[@"ignored",@1]) context:context error:nil].value;
        assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](pid_t pid,NSUInteger cap){
        frontPidValue=pid;TLinkTaskExecutionContext *context=parent(1,cap);reset(context);
        NSDictionary *expected=[bridge legacyFrontmostPid:request(@[]) context:context].value;
        context=parent(1,cap);reset(context);const unsigned pidReads=frontPidReads,appReads=frontmostReads;const int gates=licenseCalls,rawCalls=calls;
        NSDictionary *actual=invoke(context);assert([actual isEqual:expected]);
        assert(frontPidReads==pidReads+1&&frontmostReads==appReads+1&&frontmostReadTask==TASK_FRONTMOST_APP_ID);
        assert(licenseCalls==gates+1&&lastLicenseTask==TASK_FRONTMOST_PID&&calls==rawCalls);
        assert([frontPidBundle isEqualToString:frontmostValue]&&frontPidBudget==frontmostBudget);
        assert(!frontPidBudget->capturesResponse()&&frontPidBudget->response().capacity()==0&&!frontPidBudget->cleanup());
    };
    for(int n=0;n<160;++n)parity(pid_t(n*7919),1024*1024);
    for(int pid:{0,1,-1,INT_MIN,INT_MAX,12345}){
        NSString *raw=[NSString stringWithFormat:@"0;;%d\r\n",pid];const NSUInteger bytes=[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        parity(pid_t(pid),bytes);parity(pid_t(pid),bytes-1);
    }
    // RAW's ignored input/error contract is retained by the actual wrapper.
    auto context=parent();reset(context);frontPidValue=77;
    NSError *sentinel=[NSError errorWithDomain:@"fixture" code:77 userInfo:nil];NSError *error=sentinel;
    {
        TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);
        NSString *expected=legacyFrontMostPidFromRawData(nullptr,&error);assert(error==sentinel);
        NSString *actual=frontMostPidFromRawData((UInt8 *)"ignored;;input",&error);assert(error==sentinel&&[actual isEqual:expected]);
    }
    const auto noReads=[](unsigned appReads,unsigned pidReads){assert(frontmostReads==appReads&&frontPidReads==pidReads);};
    context=parent();reset(context);unsigned appReads=frontmostReads,pidReads=frontPidReads;licenseAllowed=false;
    context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(context),@"license_required task=51");noReads(appReads,pidReads);
    context=parent();reset(context);[context.cancellationToken cancel];int gates=licenseCalls;
    failure(invoke(context),@"AbortError");noReads(appReads,pidReads);assert(licenseCalls==gates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(context),@"TimeoutError");noReads(appReads,pidReads);assert(licenseCalls==gates);
    context=parent();reset(context);stopInLicense=true;failure(invoke(context),@"AbortError");noReads(appReads,pidReads);
    context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(context),@"TimeoutError");noReads(appReads,pidReads);
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;
    frontPidOnRead=[token]{[token cancel];};failure(invoke(context),@"AbortError");assert(frontPidReads==pidReads+1);
    context=parent(0.01);reset(context);frontPidOnRead=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(context),@"TimeoutError");assert(frontPidReads==pidReads+2);
    for(unsigned fault:{1U,2U}){
        context=parent();reset(context);frontPidFault=fault;failure(invoke(context),@"native_exception");
        context=parent();reset(context);frontmostFault=fault;pidReads=frontPidReads;
        failure(invoke(context),@"native_exception");assert(frontPidReads==pidReads);
    }
    // Foreground identity is passed through unchanged, including a missing provider result.
    for(id bundle in @[@"com.apple.springboard",@"ứng.dụng.测试",@"",[NSNull null]]){
        context=parent();reset(context);frontmostValue=bundle==[NSNull null]?nil:bundle;
        frontPidValue=456;NSDictionary *result=invoke(context);
        assert([result[@"pid"] intValue]==456&&((frontPidBundle==frontmostValue)||[frontPidBundle isEqual:frontmostValue]));
    }
    NSDictionary *held=nil;
    @autoreleasepool{context=parent();reset(context);frontPidValue=123;held=invoke(context);context=nil;frontmostValue=nil;}
    assert([held[@"pid"] intValue]==123&&[held[@"parts"][1] isEqualToString:@"123"]&&[held[@"raw"] isEqualToString:@"0;;123\r\n"]);
    frontPidBundle=nil;frontPidOnRead={};frontPidBudget.reset();frontmostValue=nil;frontmostOnRead={};frontmostBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed frontmost PID passed: actual Process core/RAW wrapper and frozen bridge/task/core parity, ignored arguments/error, signed PID/output boundaries, one task-51 gate, foreground/PID stop/deadline/faults, pool lifetime and no typed RAW dispatch/response vector.");
}
