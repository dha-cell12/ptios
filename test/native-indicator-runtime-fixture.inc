// Actual bridge/entry/parser/public wrappers/reload; controlled main/UI/config/start/stop boundaries.
#include "IndicatorNativeStateUnderTest.inc"
#include "IndicatorNativeColorUnderTest.inc"
static bool indicatorOwner=false;
static unsigned indicatorOwnerCalls=0,indicatorStarts=0,indicatorStops=0,indicatorLoads=0,indicatorWrites=0;
static unsigned indicatorFault=0;
static bool indicatorConfigFails=false,indicatorStartFails=false;
static std::vector<double> indicatorColors;
static TLinkNativeBudgetPtr indicatorBudget;
static std::function<void()> indicatorOnOwner;
@interface NativeIndicatorWindowFixture : NSObject
- (void)setIndicatorColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
@end
@implementation NativeIndicatorWindowFixture
- (void)setIndicatorColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha {
    assert(indicatorOwner);++indicatorWrites;indicatorColors={red,green,blue,alpha};
}
@end
static NativeIndicatorWindowFixture *touchIndicatorWindow=nil;
static void zx_indicatorPerformOnMain(dispatch_block_t operation){
    const bool previous=indicatorOwner;indicatorOwner=true;++indicatorOwnerCalls;indicatorBudget=TLinkCurrentNativeBudget();
    @try {
        @autoreleasepool {
            if(indicatorFault==1)[NSException raise:@"IndicatorFixture" format:@"before owner"];
            if(indicatorFault==2)throw std::runtime_error("before owner");
            if(indicatorOnOwner)indicatorOnOwner();operation();
            if(indicatorFault==3)[NSException raise:@"IndicatorFixture" format:@"after owner"];
            if(indicatorFault==4)throw std::runtime_error("after owner");
        }
    } @finally {indicatorOwner=previous;}
}
static NSError *zx_indicatorStartOnMain(){
    assert(indicatorOwner);++indicatorStarts;
    if(indicatorState!=TLinkIndicatorStopped)return zx_indicatorError(@"Touch indicator is already showing.");
    if(indicatorStartFails)return zx_indicatorError(@"fixture start failure");
    indicatorState=TLinkIndicatorRunning;touchIndicatorWindow=[NativeIndicatorWindowFixture new];return nil;
}
static void zx_indicatorStopOnMain(){
    assert(indicatorOwner);++indicatorStops;indicatorState=TLinkIndicatorStopped;touchIndicatorWindow=nil;
}
static NSError *zx_indicatorLoadColor(BOOL requireFile,TLinkIndicatorColor *color){
    assert(indicatorOwner&&requireFile&&color);++indicatorLoads;
    if(indicatorConfigFails)return zx_indicatorError(@"Touch indicator configuration file is missing.");
    color->red=17;color->green=31;color->blue=47;color->alpha=0.25;return nil;
}
void handleTouchIndicatorAction(int,NSError **);
#include "IndicatorNativeCoreUnderTest.inc"
#define handleTouchIndicatorTaskWithRawData legacyHandleTouchIndicatorTaskWithRawData
#include "fixtures/indicator-parser-legacy-v1.inc"
#undef handleTouchIndicatorTaskWithRawData
static void indicatorLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_TOUCH_INDICATOR;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=26\r\n",writeStreamRef);return;}
    if(false){}
#define handleTouchIndicatorTaskWithRawData legacyHandleTouchIndicatorTaskWithRawData
#include "fixtures/indicator-handler-legacy-v1.inc"
#undef handleTouchIndicatorTaskWithRawData
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeIndicatorEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedIndicatorCases(TLinkInProcessNativeBridge *bridge){
    mode=@"indicatorRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,bool running=false,bool configFails=false,bool startFails=false){
        assert(!indicatorOwner);indicatorFault=0;indicatorOnOwner={};indicatorColors.clear();
        indicatorState=running?TLinkIndicatorRunning:TLinkIndicatorStopped;
        touchIndicatorWindow=running?[NativeIndicatorWindowFixture new]:nil;
        indicatorConfigFails=configFails;indicatorStartFails=startFails;
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodTouchIndicator arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];
        assert(!TLinkCurrentNativeBudget()&&!indicatorOwner);return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,NSUInteger cap,bool running,bool configFails,bool startFails){
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context,running,configFails,startFails);
        const std::vector<unsigned> before={indicatorOwnerCalls,indicatorStarts,indicatorStops,indicatorLoads,indicatorWrites};
        TLinkJSNativeResponse *expected=[bridge legacyIndicator:request(args) context:context];
        const int state=indicatorState;const auto colors=indicatorColors;
        const std::vector<unsigned> after={indicatorOwnerCalls,indicatorStarts,indicatorStops,indicatorLoads,indicatorWrites};
        context=parent(1,cap);reset(context,running,configFails,startFails);const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(indicatorState==state&&indicatorColors==colors&&calls==rawCalls);
        const std::vector<unsigned> actualAfter={indicatorOwnerCalls,indicatorStarts,indicatorStops,indicatorLoads,indicatorWrites};
        for(size_t i=0;i<before.size();++i)assert(actualAfter[i]-after[i]==after[i]-before[i]);
        const bool valid=args.count>0&&[args[0] intValue]>=0;
        assert(licenseCalls==gates+(valid?1:0));
        if(valid)assert(lastLicenseTask==TASK_TOUCH_INDICATOR);
        if(valid&&[args[0] intValue]<=2)assert(indicatorBudget&&!indicatorBudget->cleanup()&&!indicatorBudget->capturesResponse()&&indicatorBudget->response().capacity()==0);
    };
    for(NSArray *args in @[@[],@[@(-1)],@[@0],@[@1],@[@2],@[@3],@[@(INT_MAX)],@[@1.9],@[@(-0.9)],@[@"01"],@[@"2junk"],@[@"bad"],@[@1,@"ignored"]]){
        for(bool running:{false,true})for(NSUInteger cap:{NSUInteger(1024),NSUInteger(3),NSUInteger(2)})parity(args,cap,running,false,false);
    }
    parity(@[@1],1024,false,false,true);parity(@[@2],1024,true,true,false);
    // RAW strict strings stay distinct from the bridge's Foundation integer normalization.
    for(NSString *raw in @[@"",@"0",@"1",@"2",@" 2\r\n",@"01",@"+1",@"1.0",@"1;;extra",@"3",@"-1",@"bad"]){
        auto context=parent();reset(context,true);NSError *oldError=nil;
        legacyHandleTouchIndicatorTaskWithRawData((UInt8 *)raw.UTF8String,&oldError);const int state=indicatorState;const auto colors=indicatorColors;
        reset(context,true);NSError *error=nil;handleTouchIndicatorTaskWithRawData((UInt8 *)raw.UTF8String,&error);
        assert(indicatorState==state&&indicatorColors==colors&&((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]));
    }
    {auto context=parent();reset(context,true);NSError *error=nil;handleTouchIndicatorTaskWithRawData(nullptr,&error);assert(error&&indicatorState==TLinkIndicatorRunning);}
    // Stop is licensed ordinary work, just like start/reload; no owner exemption.
    for(NSNumber *action in @[@0,@1,@2]){
        auto context=parent();reset(context,true);licenseAllowed=false;
        context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};const unsigned owners=indicatorOwnerCalls;
        failure(invoke(@[action],context).value,@"license_required task=26");assert(indicatorOwnerCalls==owners);
        context=parent();reset(context,true);[context.cancellationToken cancel];
        failure(invoke(@[action],context).value,@"AbortError");assert(indicatorOwnerCalls==owners);
        context=parent();reset(context,true);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
        failure(invoke(@[action],context).value,@"TimeoutError");assert(indicatorOwnerCalls==owners);
        context=parent();reset(context,true);stopInLicense=true;
        failure(invoke(@[action],context).value,@"AbortError");assert(indicatorOwnerCalls==owners);
        context=parent(0.01);reset(context,true);licenseDelayMs=30;
        failure(invoke(@[action],context).value,@"TimeoutError");assert(indicatorOwnerCalls==owners);
    }
    auto context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;
    indicatorOnOwner=[token]{[token cancel];};failure(invoke(@[@1],context).value,@"AbortError");assert(indicatorState==TLinkIndicatorRunning);
    context=parent(0.01);reset(context,true);indicatorOnOwner=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(@[@0],context).value,@"TimeoutError");assert(indicatorState==TLinkIndicatorStopped);
    for(unsigned fault:{1U,2U,3U,4U}){
        context=parent();reset(context);indicatorFault=fault;failure(invoke(@[@1],context).value,@"native_exception");
        assert(!indicatorOwner&&indicatorState==(fault>=3?TLinkIndicatorRunning:TLinkIndicatorStopped));
    }
    context=parent();reset(context);NSDictionary *retained=nil;
    @autoreleasepool{retained=invoke(@[@2],context).value;}
    failure(retained,@"Cannot reload configuration while the touch indicator is stopped.");
    context=parent();reset(context,true,true);retained=invoke(@[@2],context).value;
    failure(retained,@"Touch indicator configuration file is missing.");
    const unsigned owners=indicatorOwnerCalls;const int gates=licenseCalls;
    failure(TLinkExecuteNativeIndicator(-1,parent()),@"invalid_payload");assert(indicatorOwnerCalls==owners&&licenseCalls==gates);
    touchIndicatorWindow=nil;indicatorState=TLinkIndicatorStopped;indicatorColors.clear();indicatorOnOwner={};indicatorBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget()&&!indicatorOwner);
    puts("Typed indicator passed: frozen JS/strict RAW action/reply parity, synchronous public wrappers/reload and error pool lifetime, ordinary task-26 authority including stop, deadline/output/fault effects and no typed RAW dispatch/response vector. Real main/UI/HID qualification pending.");
}
