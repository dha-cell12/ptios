// Actual Process launcher/RAW parser and app entry; controlled resolver/backend, real owned CF strings.
#include <algorithm>
#include <cstdarg>
static unsigned appOpenCreates=0,appOpenReleases=0,appOpenResolves=0,appOpenCalls=0,appOpenEffects=0,appOpenFault=0;
static bool appOpenCreateFails=false,appOpenSymbolAvailable=true;
static int appOpenResult=0;
static NSString *appOpenBundle=nil;
static TLinkNativeBudgetPtr appOpenBudget;
static std::vector<CFStringRef> appOpenOwned;
static std::function<void()> appOpenOnResolve,appOpenOnCall;
static int appOpenBackend(CFStringRef bundle,Boolean suspended){
    ++appOpenCalls;assert(!suspended);appOpenBundle=[(__bridge NSString *)bundle copy];
    appOpenBudget=TLinkCurrentNativeBudget();assert(appOpenBudget&&!appOpenBudget->cleanup());
    if(appOpenFault==1)[NSException raise:@"AppOpenFixture" format:@"before effect"];
    if(appOpenFault==2)throw std::runtime_error("before effect");
    ++appOpenEffects;
    if(appOpenOnCall)appOpenOnCall();
    if(appOpenFault==3)[NSException raise:@"AppOpenFixture" format:@"after effect"];
    if(appOpenFault==4)throw std::runtime_error("after effect");
    return appOpenResult;
}
static int (*appOpenFunction)(CFStringRef,Boolean)=nullptr;
static void *appOpenServices=nullptr;
static void *appOpenResolve(void *handle,const char *symbol){
    assert(handle==appOpenServices&&strcmp(symbol,"SBSLaunchApplicationWithIdentifier")==0);++appOpenResolves;
    if(appOpenFault==5)[NSException raise:@"AppOpenFixture" format:@"resolve throws"];
    if(appOpenFault==6)throw std::runtime_error("resolve throws");
    if(appOpenOnResolve)appOpenOnResolve();
    return appOpenSymbolAvailable?reinterpret_cast<void *>(appOpenBackend):nullptr;
}
static CFStringRef appOpenCreate(CFAllocatorRef allocator,CFDictionaryRef options,CFStringRef format,...){
    ++appOpenCreates;if(appOpenCreateFails)return nullptr;
    va_list args;va_start(args,format);CFStringRef value=CFStringCreateWithFormatAndArguments(allocator,options,format,args);va_end(args);
    assert(value);appOpenOwned.push_back(value);return value;
}
static void appOpenRelease(CFTypeRef value){
    auto it=std::find(appOpenOwned.begin(),appOpenOwned.end(),value);assert(it!=appOpenOwned.end());
    appOpenOwned.erase(it);++appOpenReleases;CFRelease(value);
}
#define openApp appOpenFunction
#define sbServices appOpenServices
#define dlsym appOpenResolve
#define CFStringCreateWithFormat appOpenCreate
#define CFRelease appOpenRelease
#define NSLog(...) ((void)0)
#include "AppOpenCoreUnderTest.inc"
#define bringAppForeground legacyBringAppForeground
#define switchProcessForegroundFromRawData legacySwitchProcessForegroundFromRawData
#include "fixtures/app-open-core-legacy-v1.inc"
#undef switchProcessForegroundFromRawData
#undef bringAppForeground
#undef NSLog
#undef CFRelease
#undef CFStringCreateWithFormat
#undef dlsym
#undef sbServices
#undef openApp
static void appOpenLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_PROCESS_BRING_FOREGROUND;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=11\r\n",writeStreamRef);return;}
    if(false){}
#define switchProcessForegroundFromRawData legacySwitchProcessForegroundFromRawData
#include "fixtures/app-open-handler-legacy-v1.inc"
#undef switchProcessForegroundFromRawData
}
static void typedAppOpenCases(TLinkInProcessNativeBridge *bridge){
    mode=@"appOpenRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,bool cached=false){
        // Only the frozen oracle intentionally leaves its created CF string outstanding.
        for(CFStringRef value:appOpenOwned)CFRelease(value);appOpenOwned.clear();
        appOpenCreates=appOpenReleases=appOpenResolves=appOpenCalls=appOpenEffects=appOpenFault=0;
        appOpenCreateFails=false;appOpenSymbolAvailable=true;appOpenFunction=cached?appOpenBackend:nullptr;
        appOpenBundle=nil;appOpenBudget.reset();appOpenOnResolve={};appOpenOnCall={};appOpenResult=0;
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodOpenApp arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,int status,bool cached,NSUInteger cap){
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context,cached);appOpenResult=status;const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyAppQuery:request(args) context:context];NSString *bundle=appOpenBundle;
        const unsigned creates=appOpenCreates,resolves=appOpenResolves,launches=appOpenCalls;const int gateDelta=licenseCalls-oldGates;
        assert(appOpenOwned.size()==launches&&appOpenReleases==0);
        context=parent(1,cap);reset(context,cached);appOpenResult=status;const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(appOpenCreates==creates&&appOpenResolves==resolves&&appOpenCalls==launches&&appOpenEffects==launches&&appOpenReleases==creates&&appOpenOwned.empty());
        assert(licenseCalls==gates+gateDelta&&calls==rawCalls&&((appOpenBundle==bundle)||[appOpenBundle isEqual:bundle]));
        if(launches)assert(lastLicenseTask==TASK_PROCESS_BRING_FOREGROUND&&!appOpenBudget->capturesResponse()&&appOpenBudget->response().capacity()==0&&!appOpenBudget->cleanup());
    };
    for(int n=0;n<160;++n)parity(@[[NSString stringWithFormat:@"com.example.open%d",n]],n%7-3,bool(n%2),1024);
    for(int status:{0,-1,INT_MIN,INT_MAX})for(bool cached:{false,true}){parity(@[@"com.app"],status,cached,3);parity(@[@"com.app"],status,cached,2);}
    NSString *nul=[NSString stringWithFormat:@"app%Ctail",(unichar)0];const unichar invalidUTF16=0xd800;
    NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *inputs=[@[@[],@[@0],@[[NSNull null]],@[@""],@[@"a;;b"],@[@"a\r"],@[@"a\n"],@[nul],@[@"ứng.dụng.测试"],@[@"app😀"],@[@" space|app "],@[@"com.app",@"ignored"]] mutableCopy];if(invalid)[inputs addObject:@[invalid]];
    for(NSArray *args in inputs)parity(args,0,false,1024);
    for(NSString *unit in @[@"x",@"界",@"😀"]){
        NSString *exact=[@"" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];
        parity(@[exact],0,false,1024);parity(@[[exact stringByAppendingString:@"x"]],0,false,1024);
    }
    auto context=parent();reset(context);int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@"com.app"],context).value,@"license_required task=11");assert(appOpenCreates==0&&licenseCalls==gates+1);
    context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appOpenCreates==0&&licenseCalls==gates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appOpenCreates==0&&licenseCalls==gates);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appOpenCreates==0);
    context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appOpenCreates==0);
    // No stop check is inserted between accepted resolver/backend work. Never retry after an uncertain effect.
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;appOpenOnResolve=[token]{[token cancel];};
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appOpenCalls==1&&appOpenOwned.empty()&&appOpenReleases==1);
    context=parent();reset(context);token=context.cancellationToken;appOpenOnCall=[token]{[token cancel];};
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appOpenCalls==1&&appOpenOwned.empty()&&appOpenReleases==1);
    context=parent(0.01);reset(context);appOpenOnCall=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appOpenCalls==1&&appOpenOwned.empty()&&appOpenReleases==1);
    context=parent(1,2);reset(context);failure(invoke(@[@"com.app"],context).value,@"response_too_large");assert(appOpenCalls==1&&appOpenOwned.empty()&&appOpenReleases==1);
    for(unsigned fault:{1U,2U,3U,4U,5U,6U}){
        context=parent();reset(context);appOpenFault=fault;failure(invoke(@[@"com.app"],context).value,@"native_exception");
        assert(appOpenCreates==1&&appOpenReleases==1&&appOpenOwned.empty()&&appOpenCalls==(fault<=4?1U:0U)&&appOpenEffects==((fault==3||fault==4)?1U:0U));
    }
    // New safety cases have no callable legacy oracle: unavailable symbol/allocation used to crash/leak.
    context=parent();reset(context);appOpenSymbolAvailable=false;NSDictionary *reply=invoke(@[@"com.app"],context).value;
    assert([reply[@"ok"] boolValue]&&appOpenCalls==0&&appOpenResolves==1&&appOpenReleases==1&&appOpenOwned.empty());
    appOpenSymbolAvailable=true;reply=invoke(@[@"com.app"],parent()).value;
    assert([reply[@"ok"] boolValue]&&appOpenCalls==1&&appOpenResolves==2&&appOpenReleases==2&&appOpenOwned.empty());
    context=parent();reset(context);appOpenCreateFails=true;reply=invoke(@[@"com.app"],context).value;
    assert([reply[@"ok"] boolValue]&&appOpenCreates==1&&appOpenCalls==0&&appOpenResolves==0&&appOpenReleases==0&&appOpenOwned.empty());
    for(NSString *raw in @[@"",@"com.app",@"ứng.dụng.测试",@"a;;b",@"a\r\n",nul]){
        context=parent();reset(context);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);
        appOpenResult=-77;const int expected=legacySwitchProcessForegroundFromRawData((UInt8 *)raw.UTF8String);NSString *bundle=appOpenBundle;
        reset(context);appOpenResult=-77;const int actual=switchProcessForegroundFromRawData((UInt8 *)raw.UTF8String);
        assert(actual==expected&&appOpenCalls==1&&appOpenResolves==1&&appOpenReleases==1&&appOpenOwned.empty()&&[appOpenBundle isEqual:bundle]);
    }
    // Public core still returns backend status; both task adapters intentionally ignore that status.
    context=parent();reset(context);{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);appOpenSymbolAvailable=false;assert(bringAppForeground(@"com.app")==-1);}
    assert(appOpenOwned.empty()&&appOpenReleases==1&&appOpenCalls==0);
    context=parent();reset(context);NSMutableString *input=[NSMutableString stringWithString:@"com.original"];appOpenOnResolve=[input]{[input appendString:@".changed"];};NSDictionary *held=nil;
    @autoreleasepool{held=invoke(@[input],context).value;context=nil;}
    assert([appOpenBundle isEqualToString:@"com.original"]&&[held[@"ok"] boolValue]&&[held[@"raw"] isEqualToString:@"0\r\n"]&&[held[@"parts"] isEqual:@[@"0"]]&&appOpenOwned.empty());
    for(unsigned n=0;n<1000;++n){context=parent();reset(context,bool(n%2));reply=invoke(@[@"com.app"],context).value;assert([reply[@"ok"] boolValue]&&appOpenCalls==1&&appOpenReleases==1&&appOpenOwned.empty());}
    gates=licenseCalls;failure(TLinkExecuteNativeOpenApp(nil,parent()),@"invalid_payload");assert(licenseCalls==gates);
    reset(parent());appOpenBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget()&&appOpenOwned.empty());
    puts("Typed app open passed: actual launcher/RAW and frozen bridge/task/core parity, cached/lazy resolver, ignored launch status/ACK, exact Unicode ingress/output, task-11 authority, committed-effect stop/faults, missing symbol/allocation and 1000 balanced real CF lifecycles. No real applications launched.");
}
