// Actual Process metadata assembly/RAW parser and typed entry; controlled LS proxy plus real state core.
static id appInfoName=nil,appInfoShortVersion=nil,appInfoBundleVersion=nil;
static unsigned appInfoReads=0,appInfoFault=0;
static int appInfoFaultStage=0;
static bool appInfoMissing=false;
static NSString *appInfoBundle=nil;
static std::vector<int> appInfoOrder;
static TLinkNativeBudgetPtr appInfoBudget;
static std::function<void(int)> appInfoOnRead;
static void appInfoObserve(int stage){
    ++appInfoReads;appInfoOrder.push_back(stage);appInfoBudget=TLinkCurrentNativeBudget();assert(appInfoBudget&&!appInfoBudget->cleanup());
    if(stage==appInfoFaultStage&&appInfoFault==1)[NSException raise:@"AppInfoFixture" format:@"proxy throws"];
    if(stage==appInfoFaultStage&&appInfoFault==2)throw std::runtime_error("proxy throws");
    if(appInfoOnRead)appInfoOnRead(stage);
}
@interface NativeInfoProxyFixture : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property(nonatomic,readonly) NSString *localizedName;
@property(nonatomic,readonly) NSString *shortVersionString;
@property(nonatomic,readonly) NSString *bundleVersion;
@end
static NativeInfoProxyFixture *infoProxy=nil;
@implementation NativeInfoProxyFixture
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier {
    appInfoBundle=[identifier copy];appInfoObserve(0);return appInfoMissing?nil:infoProxy;
}
- (NSString *)localizedName {appInfoObserve(1);return appInfoName;}
- (NSString *)shortVersionString {appInfoObserve(2);return appInfoShortVersion;}
- (NSString *)bundleVersion {appInfoObserve(3);return appInfoBundleVersion;}
@end
#define LSApplicationProxy NativeInfoProxyFixture
#include "AppInfoCoreUnderTest.inc"
#define appInfoFromRawData legacyAppInfoFromRawData
#define appStateFromRawData legacyAppStateFromRawData
#include "fixtures/app-info-core-legacy-v1.inc"
#undef appStateFromRawData
#undef appInfoFromRawData
#undef LSApplicationProxy
static void appInfoLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_APP_INFO;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=33\r\n",writeStreamRef);return;}
    if(false){}
#define appInfoFromRawData legacyAppInfoFromRawData
#include "fixtures/app-info-handler-legacy-v1.inc"
#undef appInfoFromRawData
}
static void typedAppInfoCases(TLinkInProcessNativeBridge *bridge){
    mode=@"appInfoRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,NSArray *fields,int selectors=0,bool missing=false){
        appInfoName=fields[0]==[NSNull null]?nil:fields[0];appInfoShortVersion=fields[1]==[NSNull null]?nil:fields[1];appInfoBundleVersion=fields[2]==[NSNull null]?nil:fields[2];
        appInfoFault=0;appInfoFaultStage=0;appInfoOnRead={};appInfoOrder.clear();appInfoBundle=nil;appInfoMissing=missing;infoProxy=[NativeInfoProxyFixture new];
        appStateSelectors=selectors;stateApplication=selectors==4?nil:[NativeStateApplicationFixture new];appStateFault=0;appStateQueries.clear();
        appStateOnLookup=[]{appInfoOrder.push_back(4);};appStateOnSelector=[]{appInfoOrder.push_back(5);};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodAppInfo arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,NSArray *fields,int selectors,bool missing,NSUInteger cap)->NSUInteger{
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context,fields,selectors,missing);
        const unsigned oldReads=appInfoReads,oldStateReads=appStateReads;const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyAppQuery:request(args) context:context];NSString *bundle=appInfoBundle;const auto order=appInfoOrder,queries=appStateQueries;
        const unsigned readDelta=appInfoReads-oldReads,stateDelta=appStateReads-oldStateReads;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(context,fields,selectors,missing);const unsigned reads=appInfoReads,stateReads=appStateReads;const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(appInfoReads==reads+readDelta&&appStateReads==stateReads+stateDelta&&appInfoOrder==order&&appStateQueries==queries);
        assert(licenseCalls==gates+gateDelta&&calls==rawCalls&&((appInfoBundle==bundle)||[appInfoBundle isEqual:bundle]));
        if(readDelta)assert(lastLicenseTask==TASK_APP_INFO&&!appInfoBudget->capturesResponse()&&appInfoBudget->response().capacity()==0&&appInfoBudget==appStateBudget);
        return [expected.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    NSArray *ordinary=@[@"Example",@"1.2",@"123"];
    for(int n=0;n<160;++n){appStateValue=NSInteger(n-80);appStateRunning=bool(n%2);parity(@[[NSString stringWithFormat:@"com.example.info%d",n]],ordinary,n%5,bool(n%7==0),1024*1024);}
    NSString *nul=[NSString stringWithFormat:@"visible%Cignored",(unichar)0];
    const unichar invalidUTF16=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *edges=[@[[NSNull null],@"",@"普通.ứng.dụng",@"a;;b",@"a\r\n",@"a\u2028",nul,@17] mutableCopy];
    if(invalid)[edges addObject:invalid];
    appStateValue=4;appStateRunning=false;
    for(id edge in edges)for(NSUInteger field=0;field<3;++field){
        NSMutableArray *fields=[ordinary mutableCopy];fields[field]=edge;
        const NSUInteger bytes=parity(@[@"com.app"],fields,0,false,1024*1024);
        assert(bytes>1);parity(@[@"com.app"],fields,0,false,bytes);parity(@[@"com.app"],fields,0,false,bytes-1);
    }
    NSArray *nilFields=@[[NSNull null],[NSNull null],[NSNull null]];
    parity(@[@"com.app"],nilFields,4,true,1024);
    for(NSInteger state:{NSInteger(-1),NSInteger(0),NSInteger(1),NSInteger(INT_MAX)+1,NSInteger(LONG_MIN),NSInteger(LONG_MAX)}){
        appStateValue=state;parity(@[@"com.app"],ordinary,0,false,1024);
    }
    NSString *longName=[@"" stringByPaddingToLength:40000 withString:@"x" startingAtIndex:0];
    parity(@[@"com.app"],@[longName,@"v",@"b"],0,false,1024);
    NSString *inputNul=[NSString stringWithFormat:@"app%Ctail",(unichar)0];
    NSMutableArray *inputs=[@[@[],@[@0],@[[NSNull null]],@[@""],@[@"a;;b"],@[@"a\r"],@[@"a\n"],@[inputNul],@[@"ứng.dụng.测试"],@[@"app😀"],@[@"com.app",@"ignored"]] mutableCopy];
    if(invalid)[inputs addObject:@[invalid]];
    for(NSArray *args in inputs)parity(args,ordinary,0,false,1024);
    for(NSString *unit in @[@"x",@"界",@"😀"]){
        NSString *exact=[@"" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];
        parity(@[exact],ordinary,0,false,64*1024);parity(@[[exact stringByAppendingString:@"x"]],ordinary,0,false,64*1024);
    }
    auto context=parent();reset(context,ordinary);unsigned reads=appInfoReads;int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@"com.app"],context).value,@"license_required task=33");assert(appInfoReads==reads&&licenseCalls==gates+1);
    context=parent();reset(context,ordinary);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appInfoReads==reads&&licenseCalls==gates);
    context=parent();reset(context,ordinary);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appInfoReads==reads&&licenseCalls==gates);
    context=parent();reset(context,ordinary);stopInLicense=true;failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appInfoReads==reads);
    context=parent(0.01);reset(context,ordinary);licenseDelayMs=30;failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appInfoReads==reads);
    context=parent();reset(context,ordinary);TLinkCancellationToken *token=context.cancellationToken;
    appInfoOnRead=[token](int stage){if(stage==1)[token cancel];};failure(invoke(@[@"com.app"],context).value,@"AbortError");
    context=parent(0.01);reset(context,ordinary);appStateOnSelector=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");
    for(int stage:{0,1,2,3})for(unsigned fault:{1U,2U}){
        context=parent();reset(context,ordinary);appInfoFaultStage=stage;appInfoFault=fault;failure(invoke(@[@"com.app"],context).value,@"native_exception");
    }
    for(unsigned fault:{1U,2U,3U,4U}){context=parent();reset(context,ordinary);appStateFault=fault;failure(invoke(@[@"com.app"],context).value,@"native_exception");}
    for(NSString *raw in @[@"",@"com.app",@"ứng.dụng.测试",@"a;;b",@"a\r\n",inputNul]){
        context=parent();reset(context,ordinary);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);
        NSError *oldError=nil;NSString *expected=legacyAppInfoFromRawData((UInt8 *)raw.UTF8String,&oldError);NSString *bundle=appInfoBundle;
        appInfoBundle=nil;NSError *error=nil;NSString *actual=appInfoFromRawData((UInt8 *)raw.UTF8String,&error);
        assert((actual==expected)||[actual isEqual:expected]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
        assert((appInfoBundle==bundle)||[appInfoBundle isEqual:bundle]);
    }
    context=parent();NSMutableString *name=[NSMutableString stringWithString:@"Snapshot"],*input=[NSMutableString stringWithString:@"com.original"];
    reset(context,@[name,@"1",@"2"]);appStateValue=4;NSDictionary *held=nil;
    @autoreleasepool{held=invoke(@[input],context).value;infoProxy=nil;stateApplication=nil;context=nil;}
    [name appendString:@" changed"];[input appendString:@".changed"];
    assert([held[@"name"] isEqualToString:@"Snapshot"]&&[held[@"bundleId"] isEqualToString:@"com.original"]&&[held[@"state"] intValue]==4&&!held[@"running"]&&!held[@"pid"]);
    NSError *heldError=nil;@autoreleasepool{assert(!appInfoForBundleIdentifier(@"",&heldError));}
    assert([heldError.localizedDescription isEqualToString:@"-1;;Missing bundle identifier.\r\n"]);
    reads=appInfoReads;gates=licenseCalls;failure(TLinkExecuteNativeAppInfo(nil,parent()),@"invalid_payload");assert(appInfoReads==reads&&licenseCalls==gates);
    infoProxy=nil;stateApplication=nil;appInfoName=nil;appInfoShortVersion=nil;appInfoBundleVersion=nil;appInfoBundle=nil;appInfoOrder.clear();
    appInfoOnRead={};appInfoBudget.reset();appStateOnLookup={};appStateOnSelector={};appStateBudget.reset();appStateBundle=nil;appStateQueries.clear();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed app info passed: actual proxy/state/core/RAW and frozen bridge/task parity, six-column metadata including delimiter/NUL/encoding behavior, exact Unicode ingress/output, one task-33 gate, stop/faults and snapshot/error/result pool lifetime. Private LS/SpringBoard qualification pending.");
}
