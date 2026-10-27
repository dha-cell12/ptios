// Actual radio parser/helpers/providers and numeric entry; controlled Objective-C managers only.
struct NativeRadioConfig {unsigned factory=3,setters=3,getters=7;bool missingClass=false,missingInstance=false,state=false,apply=true;};
static NativeRadioConfig radioConfig;
static int radioKind=55,radioFault=0;
static bool radioState=false;
static NSString *radioFaultStage=nil;
static std::vector<std::string> radioOrder;
static std::vector<bool> radioEffects;
static TLinkNativeBudgetPtr radioBudget;
static std::function<void(NSString *)> radioOnRead;
static unsigned radioValueReads=0;
static std::function<void()> radioOnValue;
static void radioObserve(NSString *stage){
    radioOrder.emplace_back(stage.UTF8String);radioBudget=TLinkCurrentNativeBudget();assert(radioBudget&&!radioBudget->cleanup());
    if([stage isEqual:radioFaultStage]&&radioFault==1)[NSException raise:@"RadioFixture" format:@"provider throws"];
    if([stage isEqual:radioFaultStage]&&radioFault==2)throw std::runtime_error("radio provider throws");
    if(radioOnRead)radioOnRead(stage);
}
static BOOL radioGet(unsigned index){radioObserve([NSString stringWithFormat:@"get%u",index]);return radioState;}
static void radioSet(unsigned index,BOOL value){
    radioObserve([NSString stringWithFormat:@"set%u",index]);radioEffects.push_back(bool(value));
    if(radioConfig.apply)radioState=value;radioObserve(@"committed");
}
@interface NativeRadioManagerFixture : NSObject
- (BOOL)wiFiEnabled;
- (BOOL)wifiEnabled;
- (BOOL)isWiFiEnabled;
- (BOOL)powered;
- (BOOL)enabled;
- (BOOL)isEnabled;
- (void)setWiFiEnabled:(BOOL)value;
- (void)setWifiEnabled:(BOOL)value;
- (void)setPowered:(BOOL)value;
- (void)setEnabled:(BOOL)value;
@end
@implementation NativeRadioManagerFixture
- (BOOL)respondsToSelector:(SEL)selector {
    NSArray *setters=radioKind==55?@[@"setWiFiEnabled:",@"setWifiEnabled:"]:@[@"setPowered:",@"setEnabled:"];
    NSArray *getters=radioKind==55?@[@"wiFiEnabled",@"wifiEnabled",@"isWiFiEnabled"]:@[@"powered",@"enabled",@"isEnabled"];
    NSUInteger index=[setters indexOfObject:NSStringFromSelector(selector)];
    if(index!=NSNotFound){radioObserve([NSString stringWithFormat:@"hasSet%lu",(unsigned long)index]);return (radioConfig.setters&(1U<<index))!=0;}
    index=[getters indexOfObject:NSStringFromSelector(selector)];
    if(index!=NSNotFound){radioObserve([NSString stringWithFormat:@"hasGet%lu",(unsigned long)index]);return (radioConfig.getters&(1U<<index))!=0;}
    return [super respondsToSelector:selector];
}
- (BOOL)wiFiEnabled {return radioGet(0);}
- (BOOL)wifiEnabled {return radioGet(1);}
- (BOOL)isWiFiEnabled {return radioGet(2);}
- (BOOL)powered {return radioGet(0);}
- (BOOL)enabled {return radioGet(1);}
- (BOOL)isEnabled {return radioGet(2);}
- (void)setWiFiEnabled:(BOOL)value {radioSet(0,value);}
- (void)setWifiEnabled:(BOOL)value {radioSet(1,value);}
- (void)setPowered:(BOOL)value {radioSet(0,value);}
- (void)setEnabled:(BOOL)value {radioSet(1,value);}
@end
@interface NativeRadioFactoryFixture : NSObject
+ (id)sharedInstance;
+ (id)sharedManager;
@end
static NativeRadioManagerFixture *radioManager=nil;
@implementation NativeRadioFactoryFixture
+ (BOOL)respondsToSelector:(SEL)selector {
    if(sel_isEqual(selector,@selector(sharedInstance))){radioObserve(@"hasFactory0");return (radioConfig.factory&1)!=0;}
    if(sel_isEqual(selector,@selector(sharedManager))){radioObserve(@"hasFactory1");return (radioConfig.factory&2)!=0;}
    return [super respondsToSelector:selector];
}
+ (id)sharedInstance {radioObserve(@"factory0");return radioConfig.missingInstance?nil:radioManager;}
+ (id)sharedManager {radioObserve(@"factory1");return radioConfig.missingInstance?nil:radioManager;}
@end
static Class radioClass(NSString *name){
    assert([name isEqualToString:@"SBWiFiManager"]||[name isEqualToString:@"BluetoothManager"]);
    radioKind=[name isEqualToString:@"SBWiFiManager"]?55:56;radioObserve(@"lookup");return radioConfig.missingClass?Nil:[NativeRadioFactoryFixture class];
}
@interface NativeRadioValueFixture : NSObject
- (BOOL)boolValue;
@end
@implementation NativeRadioValueFixture
- (BOOL)boolValue {++radioValueReads;if(radioOnValue)radioOnValue();return BOOL(42);}
@end
#include "RadioHelpersUnderTest.inc"
#define NSClassFromString radioClass
#include "RadioCoreUnderTest.inc"
#define zx_parseActionValue legacyRadioParseActionValue
#define zx_sharedInstance legacyRadioSharedInstance
#define zx_getBool legacyRadioGetBool
#define zx_setBool legacyRadioSetBool
#define zx_boolString legacyRadioBoolString
#include "fixtures/radio-helpers-legacy-v1.inc"
#define wifiTaskFromRawData legacyWifiTaskFromRawData
#define bluetoothTaskFromRawData legacyBluetoothTaskFromRawData
#include "fixtures/radio-core-legacy-v1.inc"
#undef bluetoothTaskFromRawData
#undef wifiTaskFromRawData
#undef zx_boolString
#undef zx_setBool
#undef zx_getBool
#undef zx_sharedInstance
#undef zx_parseActionValue
#undef NSClassFromString
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeRadioEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void radioLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=(bytes[0]-'0')*10+bytes[1]-'0';UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){NSString *denial=[NSString stringWithFormat:@"-1;;license_required task=%d\r\n",taskType];notifyClient((UInt8 *)denial.UTF8String,writeStreamRef);return;}
    if(false){}
#define wifiTaskFromRawData legacyWifiTaskFromRawData
#define bluetoothTaskFromRawData legacyBluetoothTaskFromRawData
#include "fixtures/radio-handler-legacy-v1.inc"
#undef bluetoothTaskFromRawData
#undef wifiTaskFromRawData
}
static void typedRadioCases(TLinkInProcessNativeBridge *bridge){
    mode=@"radioRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,const NativeRadioConfig &config){
        radioConfig=config;radioState=config.state;radioKind=55;radioFault=0;radioFaultStage=nil;radioOrder.clear();radioEffects.clear();radioBudget.reset();radioOnRead={};radioOnValue={};radioValueReads=0;
        radioManager=[NativeRadioManagerFixture new];touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodConnectivity arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,const NativeRadioConfig &config,NSUInteger cap)->NSUInteger{
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context,config);const int oldGates=licenseCalls,oldCalls=calls;
        TLinkJSNativeResponse *expected=[bridge legacyRadio:request(args) context:context];const auto order=radioOrder;const auto effects=radioEffects;
        const bool state=radioState;const unsigned valueReads=radioValueReads;const int gateDelta=licenseCalls-oldGates,callDelta=calls-oldCalls;const std::string payload=lastPayload;
        context=parent(1,cap);reset(context,config);const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);assert(actual.ok&&expected.ok&&[actual.value isEqual:expected.value]);
        assert(radioOrder==order&&radioEffects==effects&&radioState==state&&radioValueReads==valueReads&&licenseCalls==gates+gateDelta);
        const int task=args.count?[args[0] intValue]:0;const bool direct=task==55||task==56;
        assert(calls==rawCalls+(direct?0:callDelta));if(!direct&&callDelta)assert(lastPayload==payload);
        if(direct&&!order.empty())assert(lastLicenseTask==task&&!radioBudget->capturesResponse()&&radioBudget->response().capacity()==0&&!radioBudget->cleanup());
        id raw=actual.value[@"raw"];return [raw isKindOfClass:[NSString class]]?[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding]:0;
    };
    NativeRadioConfig ordinary;
    for(unsigned n=0;n<160;++n){NativeRadioConfig config;config.factory=n%4;config.setters=(n/4)%4;config.getters=(n/16)%8;config.state=bool(n%2);config.apply=bool(n%3);parity(@[@(55+n%2),@"enabled",n%3?@(n%2):[NSNull null]],config,4096);}
    for(int task:{55,56}){
        for(unsigned factory:{0U,1U,2U,3U})for(bool missing:{false,true}){NativeRadioConfig config;config.factory=factory;config.missingInstance=missing;parity(@[@(task)],config,4096);}
        NativeRadioConfig missing;missing.missingClass=true;parity(@[@(task)],missing,4096);
        for(bool state:{false,true})for(bool apply:{false,true}){NativeRadioConfig config;config.state=state;config.apply=apply;parity(@[@(task)],config,4096);parity(@[@(task),@"enabled",@0],config,4096);parity(@[@(task),@"enabled",@1],config,4096);config.getters=0;parity(@[@(task)],config,4096);parity(@[@(task),@"enabled",@1],config,4096);}
        for(unsigned setters:{0U,1U,2U,3U})for(unsigned getters:{0U,1U,2U,4U,7U})for(bool setting:{false,true}){
            NativeRadioConfig config;config.setters=setters;config.getters=getters;config.state=false;
            NSArray *args=@[@(task),@"enabled",setting?@1:[NSNull null]];const NSUInteger bytes=parity(args,config,4096);parity(args,config,bytes);if(bytes)parity(args,config,bytes-1);
        }
        for(id value in @[[NSNull null],@0,@1,@2,@(-1),@0.1,@"YES",@"true",@"0",@"bad",[NativeRadioValueFixture new]])parity(@[@(task),@"custom",value],ordinary,4096);
        for(id key in @[@"enabled",@"value",@"raw",@"parts",@"ok",@"",@17,[NSNull null]])parity(@[@(task),key,@0,@"ignored"],ordinary,4096);
        auto context=parent();reset(context,ordinary);int gates=licenseCalls;licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(@[@(task),@"enabled",@1],context).value,[NSString stringWithFormat:@"license_required task=%d",task]);assert(radioOrder.empty()&&radioEffects.empty()&&licenseCalls==gates+1);
        context=parent();reset(context,ordinary);[context.cancellationToken cancel];gates=licenseCalls;
        failure(invoke(@[@(task)],context).value,@"AbortError");assert(radioOrder.empty()&&licenseCalls==gates);
        context=parent();reset(context,ordinary);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];failure(invoke(@[@(task)],context).value,@"TimeoutError");assert(radioOrder.empty()&&licenseCalls==gates);
        context=parent();reset(context,ordinary);stopInLicense=true;failure(invoke(@[@(task)],context).value,@"AbortError");assert(radioOrder.empty());
        context=parent(0.01);reset(context,ordinary);licenseDelayMs=30;failure(invoke(@[@(task)],context).value,@"TimeoutError");assert(radioOrder.empty());
        context=parent();reset(context,ordinary);TLinkCancellationToken *token=context.cancellationToken;radioOnValue=[token]{[token cancel];};gates=licenseCalls;
        failure(invoke(@[@(task),@"enabled",[NativeRadioValueFixture new]],context).value,@"AbortError");assert(radioValueReads==1&&licenseCalls==gates&&radioOrder.empty());
        for(NSString *point in @[@"lookup",@"committed"]){context=parent();reset(context,ordinary);token=context.cancellationToken;radioOnRead=[token,point](NSString *stage){if([stage isEqual:point])[token cancel];};failure(invoke(@[@(task),@"enabled",@1],context).value,@"AbortError");assert(radioEffects==std::vector<bool>({true}));}
        context=parent(0.01);reset(context,ordinary);radioOnRead=[](NSString *stage){if([stage isEqualToString:@"lookup"])std::this_thread::sleep_for(std::chrono::milliseconds(30));};failure(invoke(@[@(task),@"enabled",@1],context).value,@"TimeoutError");assert(radioEffects.size()==1);
        context=parent(1,2);reset(context,ordinary);failure(invoke(@[@(task),@"enabled",@1],context).value,@"response_too_large");assert(radioEffects.size()==1);
        for(int fault:{1,2})for(NSString *stage in @[@"lookup",@"factory0",@"set0",@"committed",@"get0"]){context=parent();reset(context,ordinary);radioFault=fault;radioFaultStage=stage;failure(invoke(@[@(task),@"enabled",@1],context).value,@"native_exception");assert(radioEffects.size()==(([stage isEqualToString:@"committed"]||[stage isEqualToString:@"get0"])?1U:0U));}
        for(NSString *raw in @[@"",@"0",@"1",@"1;;0",@"1;;42",@"01;;-1",@"1;;bad;;extra",@"2;;1",@"bad"]){
            context=parent();reset(context,ordinary);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *oldError=nil;NSString *expected=task==55?legacyWifiTaskFromRawData((UInt8 *)raw.UTF8String,&oldError):legacyBluetoothTaskFromRawData((UInt8 *)raw.UTF8String,&oldError);const auto order=radioOrder;const auto effects=radioEffects;
            reset(context,ordinary);NSError *error=nil;NSString *actual=task==55?wifiTaskFromRawData((UInt8 *)raw.UTF8String,&error):bluetoothTaskFromRawData((UInt8 *)raw.UTF8String,&error);
            assert((actual==expected)||[actual isEqual:expected]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);assert(radioOrder==order&&radioEffects==effects);
        }
        context=parent();reset(context,missing);NSError *heldError=nil;@autoreleasepool{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);if(task==55)wifiTaskWithAction(0,0,&heldError);else bluetoothTaskWithAction(0,0,&heldError);}assert(heldError.localizedDescription.length>0);
        context=parent();reset(context,ordinary);NSDictionary *held=nil;@autoreleasepool{held=invoke(@[@(task),@"enabled",@1],context).value;context=nil;radioManager=nil;}assert([held[@"ok"] boolValue]&&[held[@"enabled"] boolValue]);
    }
    for(int task:{0,54,59,100,INT_MIN,INT_MAX})parity(@[@(task),@"enabled",@1],ordinary,4096);
    auto context=parent();reset(context,ordinary);const int gates=licenseCalls;failure(TLinkExecuteNativeRadioState(59,true,true,context),@"invalid_payload");assert(radioOrder.empty()&&licenseCalls==gates);
    radioManager=nil;radioOrder.clear();radioEffects.clear();radioFaultStage=nil;radioOnRead={};radioOnValue={};radioBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed Wi-Fi/Bluetooth passed: actual helpers/parser/managers with frozen JS/RAW parity, singleton/set/get precedence, BOOL/fallback/error/metadata keys, exact output, ordinary license/stop/committed effects, faults/lifetime and other-task RAW fallback. No real radios changed.");
}
