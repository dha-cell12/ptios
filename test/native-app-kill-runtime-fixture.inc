// Actual termination selector dispatch, Process core/RAW parser and typed entry; fake applications only.
static int appKillMode=0;
static unsigned appKillFault=0;
static std::vector<int> appKillQueries,appKillEvents;
static std::function<void()> appKillOnCommit;
static void appKillCommit(int selector){
    if(appKillFault==1)[NSException raise:@"AppKillFixture" format:@"before selector effect"];
    if(appKillFault==2)throw std::runtime_error("before selector effect");
    appKillEvents.push_back(selector);if(appKillOnCommit)appKillOnCommit();
    if(appKillFault==3)[NSException raise:@"AppKillFixture" format:@"after selector effect"];
    if(appKillFault==4)throw std::runtime_error("after selector effect");
}
@interface NativeKillApplicationFixture : NativeStateApplicationFixture
- (void)kill;
- (void)terminate;
@end
@implementation NativeKillApplicationFixture
- (BOOL)respondsToSelector:(SEL)selector {
    if(sel_isEqual(selector,@selector(kill))){appKillQueries.push_back(1);return appKillMode==0||appKillMode==1;}
    if(sel_isEqual(selector,@selector(terminate))){appKillQueries.push_back(2);return appKillMode==0||appKillMode==2;}
    return [super respondsToSelector:selector];
}
- (void)kill {appKillCommit(1);}
- (void)terminate {appKillCommit(2);}
@end
#define SBApplication NativeStateApplicationFixture
#include "AppTerminationUnderTest.inc"
#include "AppKillCoreUnderTest.inc"
#define sendTerminationToApp legacySendTerminationToApp
#include "fixtures/app-termination-legacy-v1.inc"
#define killAppFromRawData legacyKillAppFromRawData
#include "fixtures/app-kill-core-legacy-v1.inc"
#undef killAppFromRawData
#undef sendTerminationToApp
#undef SBApplication
static void appKillLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_APP_KILL;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=31\r\n",writeStreamRef);return;}
    if(false){}
#define killAppFromRawData legacyKillAppFromRawData
#include "fixtures/app-kill-handler-legacy-v1.inc"
#undef killAppFromRawData
}
static void typedAppKillCases(TLinkInProcessNativeBridge *bridge){
    mode=@"appKillRuntime";
    // Modes: both selectors, kill only, terminate only, neither selector, missing app.
    const auto reset=[](TLinkTaskExecutionContext *context,int selection=0){
        appKillMode=selection;appKillFault=0;appKillOnCommit={};appKillQueries.clear();appKillEvents.clear();
        stateApplication=selection==4?nil:[NativeKillApplicationFixture new];appStateFault=0;appStateOnLookup={};appStateOnSelector={};appStateBundle=nil;
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodKillApp arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,int selection,NSUInteger cap){
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context,selection);const unsigned oldReads=appStateReads;const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyAppQuery:request(args) context:context];NSString *bundle=appStateBundle;const auto events=appKillEvents,queries=appKillQueries;
        const unsigned delta=appStateReads-oldReads;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(context,selection);const unsigned reads=appStateReads;const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(appStateReads==reads+delta&&appKillEvents==events&&appKillQueries==queries&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        assert((appStateBundle==bundle)||[appStateBundle isEqual:bundle]);
        if(delta)assert(lastLicenseTask==TASK_APP_KILL&&!appStateBudget->cleanup()&&!appStateBudget->capturesResponse()&&appStateBudget->response().capacity()==0);
    };
    for(int n=0;n<160;++n)parity(@[[NSString stringWithFormat:@"com.example.kill%d",n]],n%5,1024);
    for(int selection:{0,1,2,3,4}){parity(@[@"com.app"],selection,3);parity(@[@"com.app"],selection,2);}
    NSString *nul=[NSString stringWithFormat:@"app%Ctail",(unichar)0];const unichar invalidUTF16=0xd800;
    NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *inputs=[@[@[],@[@0],@[[NSNull null]],@[@""],@[@"a;;b"],@[@"a\r"],@[@"a\n"],@[nul],@[@"ứng.dụng.测试"],@[@"app😀"],@[@" space|app "],@[@"com.app",@"ignored"]] mutableCopy];if(invalid)[inputs addObject:@[invalid]];
    for(NSArray *args in inputs)parity(args,0,1024);
    for(NSString *unit in @[@"x",@"界",@"😀"]){
        NSString *exact=[@"" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];
        parity(@[exact],0,1024);parity(@[[exact stringByAppendingString:@"x"]],0,1024);
    }
    auto context=parent();reset(context);unsigned reads=appStateReads;int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@"com.app"],context).value,@"license_required task=31");assert(appStateReads==reads&&appKillEvents.empty()&&licenseCalls==gates+1);
    context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appStateReads==reads&&appKillEvents.empty()&&licenseCalls==gates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appStateReads==reads&&appKillEvents.empty()&&licenseCalls==gates);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appStateReads==reads&&appKillEvents.empty());
    context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appStateReads==reads&&appKillEvents.empty());
    // Accepted opaque lookup/dispatch work is not preempted or retried after stop/output failure.
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;
    appStateOnLookup=[token]{[token cancel];};failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appKillEvents==std::vector<int>({1}));
    context=parent(0.01);reset(context);appStateOnLookup=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appKillEvents==std::vector<int>({1}));
    context=parent();reset(context);token=context.cancellationToken;appKillOnCommit=[token]{[token cancel];};
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appKillEvents==std::vector<int>({1}));
    context=parent(1,2);reset(context);failure(invoke(@[@"com.app"],context).value,@"response_too_large");assert(appKillEvents==std::vector<int>({1}));
    for(unsigned fault:{1U,2U}){context=parent();reset(context);appStateFault=fault;failure(invoke(@[@"com.app"],context).value,@"native_exception");assert(appKillEvents.empty());}
    for(unsigned fault:{1U,2U,3U,4U}){
        context=parent();reset(context);appKillFault=fault;failure(invoke(@[@"com.app"],context).value,@"native_exception");
        assert(appKillEvents.size()==(fault>=3?1U:0U)&&appKillQueries==std::vector<int>({1}));
    }
    for(NSString *raw in @[@"",@"com.app",@"ứng.dụng.测试",@"a;;b",@"a\r\n",nul]){
        context=parent();reset(context);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);
        NSError *oldError=nil;NSString *expected=legacyKillAppFromRawData((UInt8 *)raw.UTF8String,&oldError);NSString *bundle=appStateBundle;const auto events=appKillEvents,queries=appKillQueries;
        reset(context);NSError *error=nil;NSString *actual=killAppFromRawData((UInt8 *)raw.UTF8String,&error);
        assert((actual==expected)||[actual isEqual:expected]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
        assert(appKillEvents==events&&appKillQueries==queries&&((appStateBundle==bundle)||[appStateBundle isEqual:bundle]));
    }
    context=parent();reset(context);NSMutableString *input=[NSMutableString stringWithString:@"com.original"];appStateOnLookup=[input]{[input appendString:@".changed"];};NSDictionary *held=nil;
    @autoreleasepool{held=invoke(@[input],context).value;context=nil;stateApplication=nil;}
    assert([appStateBundle isEqualToString:@"com.original"]&&[held[@"ok"] boolValue]&&[held[@"raw"] isEqualToString:@"0\r\n"]&&[held[@"parts"] isEqual:@[@"0"]]);
    NSError *heldError=nil;@autoreleasepool{assert(!killAppForBundleIdentifier(@"",&heldError));}assert([heldError.localizedDescription isEqualToString:@"-1;;Missing bundle identifier.\r\n"]);
    reads=appStateReads;gates=licenseCalls;failure(TLinkExecuteNativeKillApp(nil,parent()),@"invalid_payload");assert(appStateReads==reads&&licenseCalls==gates);
    stateApplication=nil;appStateBundle=nil;appStateOnLookup={};appStateOnSelector={};appStateBudget.reset();appKillEvents.clear();appKillQueries.clear();appKillOnCommit={};licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed app kill passed: actual selector/core/RAW and frozen bridge/task/helper parity, kill/terminate precedence, missing/unsupported apps, exact Unicode ingress/output, task-31 gate, committed-effect stop/fault semantics and pool lifetime. No real apps terminated.");
}
