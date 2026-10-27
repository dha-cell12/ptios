// Actual state selector dispatch/formatting, RAW parser and shared typed entry; controlled application lookup.
#import <objc/message.h>
#import <objc/runtime.h>
static unsigned appStateReads=0,appStateProcessCalls=0,appStateRunningCalls=0,appStateFault=0;
static int appStateSelectors=0;
static NSInteger appStateValue=0;
static BOOL appStateRunning=false;
static NSString *appStateBundle=nil;
static std::vector<int> appStateQueries;
static TLinkNativeBudgetPtr appStateBudget;
static std::function<void()> appStateOnLookup,appStateOnSelector;
@interface NativeStateApplicationFixture : NSObject
- (NSInteger)processState;
- (BOOL)isRunning;
@end
@implementation NativeStateApplicationFixture
- (BOOL)respondsToSelector:(SEL)selector {
    if(sel_isEqual(selector,@selector(processState))){appStateQueries.push_back(1);return appStateSelectors==0||appStateSelectors==1;}
    if(sel_isEqual(selector,@selector(isRunning))){appStateQueries.push_back(2);return appStateSelectors==0||appStateSelectors==2;}
    return [super respondsToSelector:selector];
}
- (NSInteger)processState {
    ++appStateProcessCalls;
    if(appStateFault==3)[NSException raise:@"AppStateFixture" format:@"selector throws"];
    if(appStateFault==4)throw std::runtime_error("selector throws");
    if(appStateOnSelector)appStateOnSelector();return appStateValue;
}
- (BOOL)isRunning {
    ++appStateRunningCalls;if(appStateOnSelector)appStateOnSelector();return appStateRunning;
}
@end
static NativeStateApplicationFixture *stateApplication=nil;
static NativeStateApplicationFixture *getApplicationForBundleId(NSString *bundleId){
    ++appStateReads;appStateBundle=[bundleId copy];appStateBudget=TLinkCurrentNativeBudget();assert(appStateBudget&&!appStateBudget->cleanup());
    if(appStateFault==1)[NSException raise:@"AppStateFixture" format:@"lookup throws"];
    if(appStateFault==2)throw std::runtime_error("lookup throws");
    if(appStateOnLookup)appStateOnLookup();return stateApplication;
}
#define SBApplication NativeStateApplicationFixture
#include "AppStateCoreUnderTest.inc"
#define appStateFromRawData legacyAppStateFromRawData
#include "fixtures/app-state-core-legacy-v1.inc"
#undef appStateFromRawData
#undef SBApplication
static void appStateLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_APP_STATE;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=32\r\n",writeStreamRef);return;}
    if(false){}
#define appStateFromRawData legacyAppStateFromRawData
#include "fixtures/app-state-handler-legacy-v1.inc"
#undef appStateFromRawData
}
static void typedAppStateCases(TLinkInProcessNativeBridge *bridge){
    mode=@"appStateRuntime";
    // Modes: both selectors, only processState, only isRunning, neither, no app.
    const auto reset=[](TLinkTaskExecutionContext *context,int selectors=0){
        appStateFault=0;appStateOnLookup={};appStateOnSelector={};appStateBundle=nil;appStateQueries.clear();
        appStateSelectors=selectors;stateApplication=selectors==4?nil:[NativeStateApplicationFixture new];
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodAppState arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,int selectors,NSInteger state,BOOL running,NSUInteger cap){
        appStateValue=state;appStateRunning=running;TLinkTaskExecutionContext *context=parent(1,cap);reset(context,selectors);
        const unsigned oldReads=appStateReads,oldProcess=appStateProcessCalls,oldRunning=appStateRunningCalls;const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyAppQuery:request(args) context:context];NSString *bundle=appStateBundle;const auto queries=appStateQueries;
        const unsigned readDelta=appStateReads-oldReads,processDelta=appStateProcessCalls-oldProcess,runningDelta=appStateRunningCalls-oldRunning;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(context,selectors);const unsigned reads=appStateReads,processCalls=appStateProcessCalls,runningCalls=appStateRunningCalls;const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(appStateReads==reads+readDelta&&appStateProcessCalls==processCalls+processDelta&&appStateRunningCalls==runningCalls+runningDelta&&appStateQueries==queries);
        assert(licenseCalls==gates+gateDelta&&calls==rawCalls&&((appStateBundle==bundle)||[appStateBundle isEqual:bundle]));
        if(readDelta)assert(lastLicenseTask==TASK_APP_STATE&&!appStateBudget->capturesResponse()&&appStateBudget->response().capacity()==0&&!appStateBudget->cleanup());
    };
    for(int n=0;n<160;++n)parity(@[[NSString stringWithFormat:@"com.example.state%d",n]],n%5,NSInteger(n-80),bool(n%2),1024*1024);
    for(NSInteger state:{NSInteger(0),NSInteger(-1),NSInteger(1),NSInteger(4),NSInteger(INT_MIN),NSInteger(INT_MAX),NSInteger(INT_MAX)+1,NSInteger(LONG_MIN),NSInteger(LONG_MAX)}){
        for(int selectors:{0,1,2,3,4})for(BOOL running:{BOOL(false),BOOL(true)}){
            parity(@[@"com.app"],selectors,state,running,1024);
            const NSInteger wire=selectors==4?0:selectors==3?-1:selectors==2?(running?1:0):state;
            NSString *raw=[NSString stringWithFormat:@"0;;%ld\r\n",(long)wire];const NSUInteger bytes=[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            parity(@[@"com.app"],selectors,state,running,bytes);parity(@[@"com.app"],selectors,state,running,bytes-1);
        }
    }
    NSString *nul=[NSString stringWithFormat:@"app%Cignored",(unichar)0];
    const unichar invalidUTF16=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *inputs=[@[@[],@[@0],@[[NSNull null]],@[@""],@[@"a;;b"],@[@"a\r"],@[@"a\n"],@[nul],@[@"ứng.dụng.测试"],@[@"app😀"],@[@" space\t|app "],@[@"com.app",@"ignored"]] mutableCopy];
    if(invalid)[inputs addObject:@[invalid]];
    for(NSArray *input in inputs)parity(input,0,4,false,1024);
    for(NSString *unit in @[@"x",@"界",@"😀"]){
        NSString *exact=[@"" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];
        parity(@[exact],0,4,false,1024);parity(@[[exact stringByAppendingString:@"x"]],0,4,false,1024);
    }
    auto context=parent();reset(context);const unsigned reads=appStateReads;int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@"com.app"],context).value,@"license_required task=32");assert(appStateReads==reads&&licenseCalls==gates+1);
    context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appStateReads==reads&&licenseCalls==gates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appStateReads==reads&&licenseCalls==gates);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appStateReads==reads);
    context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appStateReads==reads);
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;
    appStateOnLookup=[token]{[token cancel];};failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appStateReads==reads+1);
    context=parent(0.01);reset(context);appStateOnSelector=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appStateReads==reads+2);
    for(unsigned fault:{1U,2U,3U,4U}){context=parent();reset(context);appStateFault=fault;failure(invoke(@[@"com.app"],context).value,@"native_exception");}
    // Actual RAW parser and empty-input error remain compatible independently of JS validation.
    for(NSString *raw in @[@"",@"com.app",@"ứng.dụng.测试",@"a;;b",@"a\r\n",nul]){
        context=parent();reset(context);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);
        NSError *oldError=nil;NSString *expected=legacyAppStateFromRawData((UInt8 *)raw.UTF8String,&oldError);NSString *bundle=appStateBundle;
        appStateBundle=nil;NSError *error=nil;NSString *actual=appStateFromRawData((UInt8 *)raw.UTF8String,&error);
        assert((actual==expected)||[actual isEqual:expected]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
        assert((appStateBundle==bundle)||[appStateBundle isEqual:bundle]);
    }
    context=parent();reset(context);appStateValue=4;NSMutableString *input=[NSMutableString stringWithString:@"com.original"];
    appStateOnLookup=[input]{[input appendString:@".changed"];};NSDictionary *held=nil;
    @autoreleasepool{held=invoke(@[input],context).value;context=nil;stateApplication=nil;}
    assert([appStateBundle isEqualToString:@"com.original"]&&[held[@"state"] intValue]==4&&[held[@"running"] boolValue]&&[held[@"parts"][1] isEqualToString:@"4"]&&!held[@"pid"]);
    NSError *heldError=nil;@autoreleasepool{assert(!appStateForBundleIdentifier(@"",&heldError));}
    assert([heldError.localizedDescription isEqualToString:@"-1;;Missing bundle identifier.\r\n"]);
    const unsigned finalReads=appStateReads;gates=licenseCalls;
    failure(TLinkExecuteNativeAppState(nil,parent()),@"invalid_payload");
    failure(zx_nativeAppQueryExecute(TASK_APP_KILL,@"com.app",parent()),@"invalid_payload");
    assert(appStateReads==finalReads&&licenseCalls==gates&&!TLinkCurrentNativeBudget());
    stateApplication=nil;appStateBundle=nil;appStateQueries.clear();appStateOnLookup={};appStateOnSelector={};appStateBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed app state passed: actual selector precedence/processState/isRunning/no-app paths with frozen JS/RAW/core parity, wide state/intValue/running/output, exact Unicode ingress, task-32 authority/cancel/faults and pool lifetime. App PID shared-entry regression retained.");
}
