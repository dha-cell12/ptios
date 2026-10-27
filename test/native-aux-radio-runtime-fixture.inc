// Actual airplane/cellular cores share the preceding actual/frozen radio helpers and controlled factory.
struct NativeAuxRadioConfig {NativeRadioConfig primary,alternate;};
static NativeAuxRadioConfig auxRadioConfig;
@interface NativeAuxRadioManagerFixture : NativeRadioManagerFixture
- (BOOL)airplaneMode;
- (BOOL)airplaneModeEnabled;
- (BOOL)isAirplaneModeEnabled;
- (BOOL)cellularDataEnabled;
- (void)setAirplaneMode:(BOOL)value;
- (void)setAirplaneModeEnabled:(BOOL)value;
- (void)setCellularDataEnabled:(BOOL)value;
@end
@implementation NativeAuxRadioManagerFixture
- (BOOL)respondsToSelector:(SEL)selector {
    NSArray *setters=radioKind==57?@[@"setAirplaneMode:",@"setAirplaneModeEnabled:"]:@[@"setCellularDataEnabled:"];
    NSArray *getters=radioKind==57?@[@"airplaneMode",@"airplaneModeEnabled",@"isAirplaneModeEnabled"]:@[@"cellularDataEnabled"];
    NSUInteger index=[setters indexOfObject:NSStringFromSelector(selector)];
    if(index!=NSNotFound){radioObserve([NSString stringWithFormat:@"hasSet%lu",(unsigned long)index]);return (radioConfig.setters&(1U<<index))!=0;}
    index=[getters indexOfObject:NSStringFromSelector(selector)];
    if(index!=NSNotFound){radioObserve([NSString stringWithFormat:@"hasGet%lu",(unsigned long)index]);return (radioConfig.getters&(1U<<index))!=0;}
    return [super respondsToSelector:selector];
}
- (BOOL)airplaneMode {return radioGet(0);}
- (BOOL)airplaneModeEnabled {return radioGet(1);}
- (BOOL)isAirplaneModeEnabled {return radioGet(2);}
- (BOOL)cellularDataEnabled {return radioGet(0);}
- (void)setAirplaneMode:(BOOL)value {radioSet(0,value);}
- (void)setAirplaneModeEnabled:(BOOL)value {radioSet(1,value);}
- (void)setCellularDataEnabled:(BOOL)value {radioSet(0,value);}
@end
static Class auxRadioClass(NSString *name){
    const bool primary=[name isEqualToString:@"RadiosPreferences"];
    assert(primary||[name isEqualToString:@"SBAirplaneModeController"]);
    radioConfig=primary?auxRadioConfig.primary:auxRadioConfig.alternate;
    radioObserve(primary?@"primaryLookup":@"alternateLookup");return radioConfig.missingClass?Nil:[NativeRadioFactoryFixture class];
}
#define NSClassFromString auxRadioClass
#include "AuxRadioCoreUnderTest.inc"
#define zx_parseActionValue legacyRadioParseActionValue
#define zx_sharedInstance legacyRadioSharedInstance
#define zx_getBool legacyRadioGetBool
#define zx_setBool legacyRadioSetBool
#define zx_boolString legacyRadioBoolString
#define airplaneTaskFromRawData legacyAirplaneTaskFromRawData
#define cellularDataTaskFromRawData legacyCellularDataTaskFromRawData
#include "fixtures/aux-radio-core-legacy-v1.inc"
#undef cellularDataTaskFromRawData
#undef airplaneTaskFromRawData
#undef zx_boolString
#undef zx_setBool
#undef zx_getBool
#undef zx_sharedInstance
#undef zx_parseActionValue
#undef NSClassFromString
static void auxRadioLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=(bytes[0]-'0')*10+bytes[1]-'0';UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){NSString *denial=[NSString stringWithFormat:@"-1;;license_required task=%d\r\n",taskType];notifyClient((UInt8 *)denial.UTF8String,writeStreamRef);return;}
    if(false){}
#define airplaneTaskFromRawData legacyAirplaneTaskFromRawData
#define cellularDataTaskFromRawData legacyCellularDataTaskFromRawData
#include "fixtures/aux-radio-handler-legacy-v1.inc"
#undef cellularDataTaskFromRawData
#undef airplaneTaskFromRawData
}
static void typedAuxRadioCases(TLinkInProcessNativeBridge *bridge){
    mode=@"auxRadioRuntime";
    const auto reset=[](int task,TLinkTaskExecutionContext *context,const NativeAuxRadioConfig &config){
        auxRadioConfig=config;radioConfig=config.primary;radioState=config.primary.state;radioKind=task;radioFault=0;radioFaultStage=nil;
        radioOrder.clear();radioEffects.clear();radioBudget.reset();radioOnRead={};radioOnValue={};radioValueReads=0;
        radioManager=[NativeAuxRadioManagerFixture new];touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodConnectivity arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](NSArray *args,const NativeAuxRadioConfig &config,NSUInteger cap)->NSUInteger{
        const int task=[args[0] intValue];TLinkTaskExecutionContext *context=parent(1,cap);reset(task,context,config);const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyRadio:request(args) context:context];const auto order=radioOrder;const auto effects=radioEffects;
        const bool state=radioState;const unsigned valueReads=radioValueReads;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(task,context,config);const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);assert(actual.ok&&expected.ok&&[actual.value isEqual:expected.value]);
        assert(radioOrder==order&&radioEffects==effects&&radioState==state&&radioValueReads==valueReads&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        assert(lastLicenseTask==task&&!radioBudget->capturesResponse()&&radioBudget->response().capacity()==0&&!radioBudget->cleanup());
        if(task==58)assert(std::find(radioOrder.begin(),radioOrder.end(),"alternateLookup")==radioOrder.end());
        id raw=actual.value[@"raw"];return [raw isKindOfClass:[NSString class]]?[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding]:0;
    };
    NativeAuxRadioConfig ordinary;
    for(unsigned n=0;n<160;++n){NativeAuxRadioConfig config;config.primary.factory=n%4;config.primary.setters=(n/4)%4;config.primary.getters=(n/8)%8;config.primary.missingClass=n%5==0;config.primary.missingInstance=n%7==0;config.primary.state=bool(n%2);config.alternate.apply=n%3!=0;parity(@[@(57+n%2),@"enabled",n%3?@(n%2):[NSNull null]],config,4096);}
    for(int task:{57,58}){
        for(unsigned factory:{0U,1U,2U,3U})for(bool missingClass:{false,true})for(bool missingInstance:{false,true}){
            NativeAuxRadioConfig config;config.primary.factory=factory;config.primary.missingClass=missingClass;config.primary.missingInstance=missingInstance;parity(@[@(task)],config,4096);
        }
        for(unsigned factory:{0U,1U,2U,3U})for(bool missing:{false,true}){
            NativeAuxRadioConfig config;config.primary.missingClass=true;config.alternate.factory=factory;config.alternate.missingInstance=missing;parity(@[@(task),@"enabled",@1],config,4096);
        }
        NativeAuxRadioConfig unavailable;unavailable.primary.missingClass=unavailable.alternate.missingClass=true;parity(@[@(task)],unavailable,4096);
        for(unsigned setters:{0U,1U,2U,3U})for(unsigned getters:{0U,1U,2U,4U,7U})for(bool setting:{false,true}){
            NativeAuxRadioConfig config;config.primary.setters=setters;config.primary.getters=getters;
            NSArray *args=@[@(task),@"enabled",setting?@1:[NSNull null]];const NSUInteger bytes=parity(args,config,4096);parity(args,config,bytes);if(bytes)parity(args,config,bytes-1);
        }
        for(bool state:{false,true})for(bool apply:{false,true}){NativeAuxRadioConfig config;config.primary.state=state;config.primary.apply=apply;parity(@[@(task)],config,4096);parity(@[@(task),@"enabled",@0],config,4096);parity(@[@(task),@"enabled",@1],config,4096);config.primary.getters=0;parity(@[@(task),@"enabled",@1],config,4096);}
        for(id value in @[[NSNull null],@0,@1,@2,@(-1),@0.1,@"YES",@"true",@"0",@"bad",[NativeRadioValueFixture new]])parity(@[@(task),@"custom",value],ordinary,4096);
        for(id key in @[@"enabled",@"value",@"raw",@"parts",@"ok",@"",@17,[NSNull null]])parity(@[@(task),key,@0,@"ignored"],ordinary,4096);
        auto context=parent();reset(task,context,ordinary);int gates=licenseCalls;licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(@[@(task),@"enabled",@1],context).value,[NSString stringWithFormat:@"license_required task=%d",task]);assert(radioOrder.empty()&&radioEffects.empty()&&licenseCalls==gates+1);
        context=parent();reset(task,context,ordinary);[context.cancellationToken cancel];gates=licenseCalls;failure(invoke(@[@(task)],context).value,@"AbortError");assert(radioOrder.empty()&&licenseCalls==gates);
        context=parent();reset(task,context,ordinary);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];failure(invoke(@[@(task)],context).value,@"TimeoutError");assert(radioOrder.empty()&&licenseCalls==gates);
        context=parent();reset(task,context,ordinary);stopInLicense=true;failure(invoke(@[@(task)],context).value,@"AbortError");assert(radioOrder.empty());
        context=parent(0.01);reset(task,context,ordinary);licenseDelayMs=30;failure(invoke(@[@(task)],context).value,@"TimeoutError");assert(radioOrder.empty());
        context=parent();reset(task,context,ordinary);TLinkCancellationToken *token=context.cancellationToken;radioOnValue=[token]{[token cancel];};gates=licenseCalls;
        failure(invoke(@[@(task),@"enabled",[NativeRadioValueFixture new]],context).value,@"AbortError");assert(radioValueReads==1&&licenseCalls==gates&&radioOrder.empty());
        for(NSString *point in @[@"primaryLookup",@"committed"]){context=parent();reset(task,context,ordinary);token=context.cancellationToken;radioOnRead=[token,point](NSString *stage){if([stage isEqual:point])[token cancel];};failure(invoke(@[@(task),@"enabled",@1],context).value,@"AbortError");assert(radioEffects==std::vector<bool>({true}));}
        context=parent(0.01);reset(task,context,ordinary);radioOnRead=[](NSString *stage){if([stage isEqualToString:@"primaryLookup"])std::this_thread::sleep_for(std::chrono::milliseconds(30));};failure(invoke(@[@(task),@"enabled",@1],context).value,@"TimeoutError");assert(radioEffects.size()==1);
        context=parent(1,2);reset(task,context,ordinary);failure(invoke(@[@(task),@"enabled",@1],context).value,@"response_too_large");assert(radioEffects.size()==1);
        for(int fault:{1,2})for(NSString *stage in @[@"primaryLookup",@"factory0",@"set0",@"committed",@"get0"]){context=parent();reset(task,context,ordinary);radioFault=fault;radioFaultStage=stage;failure(invoke(@[@(task),@"enabled",@1],context).value,@"native_exception");assert(radioEffects.size()==(([stage isEqualToString:@"committed"]||[stage isEqualToString:@"get0"])?1U:0U));}
        for(NSString *raw in @[@"",@"0",@"1",@"1;;0",@"1;;42",@"01;;-1",@"1;;bad;;extra",@"2;;1",@"bad"]){
            context=parent();reset(task,context,ordinary);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *oldError=nil;NSString *expected=task==57?legacyAirplaneTaskFromRawData((UInt8 *)raw.UTF8String,&oldError):legacyCellularDataTaskFromRawData((UInt8 *)raw.UTF8String,&oldError);const auto order=radioOrder;const auto effects=radioEffects;
            reset(task,context,ordinary);NSError *error=nil;NSString *actual=task==57?airplaneTaskFromRawData((UInt8 *)raw.UTF8String,&error):cellularDataTaskFromRawData((UInt8 *)raw.UTF8String,&error);
            assert((actual==expected)||[actual isEqual:expected]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);assert(radioOrder==order&&radioEffects==effects);
        }
        context=parent();reset(task,context,unavailable);NSError *heldError=nil;@autoreleasepool{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);if(task==57)airplaneTaskWithAction(0,0,&heldError);else cellularDataTaskWithAction(0,0,&heldError);}assert(heldError.localizedDescription.length>0);
        context=parent();reset(task,context,ordinary);NSDictionary *held=nil;@autoreleasepool{held=invoke(@[@(task),@"enabled",@1],context).value;context=nil;radioManager=nil;}assert([held[@"ok"] boolValue]&&[held[@"enabled"] boolValue]);
    }
    for(int fault:{1,2}){auto context=parent();NativeAuxRadioConfig fallback;fallback.primary.missingClass=true;reset(57,context,fallback);radioFault=fault;radioFaultStage=@"alternateLookup";failure(invoke(@[@57,@"enabled",@1],context).value,@"native_exception");assert(radioEffects.empty());}
    radioManager=nil;radioOrder.clear();radioEffects.clear();radioFaultStage=nil;radioOnRead={};radioOnValue={};radioBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed airplane/cellular passed: actual helpers/parser/controllers with frozen JS/RAW parity, primary/alternate singleton and selector order, false/missing getters, BOOL/metadata/output, ordinary license/stop/committed effects, faults and lifetime. No real radio state changed.");
}
