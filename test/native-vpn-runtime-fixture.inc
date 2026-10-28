// Actual VPN parser/core and shared numeric entry; broker and diagnostics boundary doubles.
static NSString *vpnReply=nil,*vpnError=nil,*vpnDiagnosticsReply=nil,*vpnDiagnosticsError=nil;
static bool vpnConnected=false,vpnApply=true;
static unsigned vpnFault=0,vpnDiagnosticsCalls=0;
static NSString *vpnFaultStage=nil;
static std::vector<std::string> vpnOrder,vpnCommands;
static std::vector<bool> vpnEffects;
static TLinkNativeBudgetPtr vpnBudget;
static std::function<void(NSString *)> vpnOnStage;
static void vpnObserve(NSString *stage){
    vpnOrder.push_back(stage.UTF8String);vpnBudget=TLinkCurrentNativeBudget();assert(vpnBudget&&!vpnBudget->cleanup());
    if([stage isEqual:vpnFaultStage]&&vpnFault==1)[NSException raise:@"VPNFixture" format:@"broker boundary throws"];
    if([stage isEqual:vpnFaultStage]&&vpnFault==2)throw std::runtime_error("VPN broker boundary throws");
    if(vpnOnStage)vpnOnStage(stage);
}
static NSString *nativeVPNBroker(NSString *command,NSString **error){
    vpnCommands.push_back(command.UTF8String);vpnObserve(@"request");
    if(vpnApply&&([command isEqualToString:@"connect"]||[command isEqualToString:@"disconnect"])){
        vpnConnected=[command isEqualToString:@"connect"];vpnEffects.push_back(vpnConnected);vpnObserve(@"committed");
    }
    vpnObserve(@"reply");if(error)*error=vpnError;return vpnReply;
}
static NSString *nativeVPNDiagnostics(NSString *runtime,NSString *state,NSString *query,NSString *control,NSString *backend,NSString *broker,NSNumber *effective,NSError **error){
    assert([runtime isEqual:@"rootfull"]&&[state isEqual:@"broker_unavailable"]&&[query isEqual:@"app_broker_6014"]&&[control isEqual:@"app_broker_6014"]&&[backend isEqual:@"nevpnmanager_ikev2"]&&[broker isEqual:@"tlinkauto_vpnd_6014"]&&!effective);
    ++vpnDiagnosticsCalls;vpnObserve(@"diagnostics");
    if(vpnDiagnosticsError&&error)*error=[NSError errorWithDomain:@"VPNDiagnosticsFixture" code:1 userInfo:@{NSLocalizedDescriptionKey:vpnDiagnosticsError}];
    return vpnDiagnosticsReply;
}
#define zx_vpnBrokerRequest nativeVPNBroker
#define TLinkVPNDiagnosticsBase64 nativeVPNDiagnostics
#include "VPNCoreUnderTest.inc"
#define zx_parseActionValue legacyRadioParseActionValue
#define vpnTaskFromRawData legacyVPNTaskFromRawData
#include "fixtures/vpn-core-legacy-v1.inc"
#undef vpnTaskFromRawData
#undef zx_parseActionValue
#undef TLinkVPNDiagnosticsBase64
#undef zx_vpnBrokerRequest
static void vpnLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_VPN;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=59\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
#define vpnTaskFromRawData legacyVPNTaskFromRawData
    if(false){}
#include "fixtures/vpn-handler-legacy-v1.inc"
#undef vpnTaskFromRawData
}
static void typedVPNCases(TLinkInProcessNativeBridge *bridge){
    @try {try{
    mode=@"vpnRuntime";puts("VPN Foundation: actual parser/command/error core and frozen JS/task parity; broker controlled");fflush(stdout);
    const auto reset=[](TLinkTaskExecutionContext *context){
        vpnReply=@"1";vpnError=nil;vpnDiagnosticsReply=@"ZGlhZ25vc3RpY3M=";vpnDiagnosticsError=nil;
        vpnConnected=false;vpnApply=true;vpnFault=vpnDiagnosticsCalls=0;vpnFaultStage=nil;vpnOrder.clear();vpnCommands.clear();vpnEffects.clear();vpnBudget.reset();vpnOnStage={};
        radioValueReads=0;radioOnValue={};touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodConnectivity arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](NSArray *args,NSString *reply,NSString *error,NSUInteger cap=4096,bool apply=true)->NSUInteger{
        auto context=parent(30,cap);reset(context);vpnReply=reply;vpnError=error;vpnApply=apply;int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyVPN:request(args) context:context];
        const auto order=vpnOrder,commands=vpnCommands;const auto effects=vpnEffects;const bool connected=vpnConnected;const unsigned reads=radioValueReads;const int gateDelta=licenseCalls-gates;
        context=parent(30,cap);reset(context);vpnReply=reply;vpnError=error;vpnApply=apply;gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);const bool same=actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]);
        if(!same){fprintf(stdout,"VPN parity failure: %s\n",[NSString stringWithFormat:@"args=%@ reply=%@ error=%@ cap=%lu expected=%@ actual=%@",args,reply,error,(unsigned long)cap,expected.value,actual.value].UTF8String);fflush(stdout);}assert(same);
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(vpnOrder==order&&vpnCommands==commands&&vpnEffects==effects&&vpnConnected==connected&&radioValueReads==reads&&calls==rawCalls&&licenseCalls==gates+gateDelta);
        assert(lastLicenseTask==59&&gateDelta==1&&vpnDiagnosticsCalls==0);
        if(vpnBudget)assert(!vpnBudget->capturesResponse()&&vpnBudget->response().capacity()==0);
        id raw=actual.value[@"raw"];return [raw isKindOfClass:[NSString class]]?[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding]:0;
    };
    for(unsigned n=0;n<160;++n)parity(n%3?@[@59,@"enabled",@(n%2)]:@[@59],n%2?@"1":@"0",nil);
    for(id value in @[[NSNull null],@0,@1,@(-1),@0.1,@"YES",@"true",@"0",@"bad",[NativeRadioValueFixture new]])parity(@[@59,@"enabled",value],@"1",nil);
    for(id key in @[@"enabled",@"value",@"raw",@"parts",@"ok",@"",@17,[NSNull null]])parity(@[@59,key,@0,@"ignored"],@"1",nil);
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];
    for(NSString *reply in @[@"0",@"1",@"2",@"-1",@"true",@"测试;;detail",@"trailing\n",nul,invalid?:@"fallback"]){
        const NSUInteger size=parity(@[@59,@"custom",@1],reply,@"ignored broker error");assert(size);parity(@[@59,@"custom",@1],reply,nil,size);if(size>1)parity(@[@59,@"custom",@1],reply,nil,size-1);
    }
    for(id reply in @[[NSNull null],@""])for(id error in @[[NSNull null],@"",@"vpn_broker_unavailable",@"测试;;error\r\n",nul,invalid?:@"fallback"]){
        NSString *body=reply==[NSNull null]?nil:reply,*reason=error==[NSNull null]?nil:error;
        const NSUInteger size=parity(@[@59,@"enabled",@1],body,reason);parity(@[@59,@"enabled",@1],body,reason,size);if(size>1)parity(@[@59,@"enabled",@1],body,reason,size-1);
    }
    parity(@[@59,@"enabled",@1],@"0",nil,4096,false);
    puts("VPN Foundation: ordinary authority, accepted effects, cancellation and exceptions");fflush(stdout);
    auto context=parent();reset(context);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};failure(invoke(@[@59,@"enabled",@1],context).value,@"license_required task=59");assert(vpnCommands.empty());
    context=parent();reset(context);int gates=licenseCalls;[context.cancellationToken cancel];failure(invoke(@[@59],context).value,@"AbortError");assert(licenseCalls==gates&&vpnCommands.empty());
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(@[@59],context).value,@"TimeoutError");assert(licenseCalls==gates&&vpnCommands.empty());
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@59],context).value,@"AbortError");assert(vpnCommands.empty());
    context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(@[@59],context).value,@"TimeoutError");assert(vpnCommands.empty());
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;radioOnValue=[token]{[token cancel];};gates=licenseCalls;
    failure(invoke(@[@59,@"enabled",[NativeRadioValueFixture new]],context).value,@"AbortError");assert(radioValueReads==1&&licenseCalls==gates&&vpnCommands.empty());
    for(NSString *point in @[@"request",@"committed"]){context=parent();reset(context);token=context.cancellationToken;vpnOnStage=[token,point](NSString *stage){if([stage isEqual:point])[token cancel];};
        failure(invoke(@[@59,@"enabled",@1],context).value,@"AbortError");assert(vpnEffects==std::vector<bool>({true}));}
    context=parent(0.1);reset(context);vpnOnStage=[](NSString *stage){if([stage isEqual:@"request"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};
    failure(invoke(@[@59,@"enabled",@1],context).value,@"TimeoutError");assert(vpnEffects.size()==1);
    context=parent(1,2);reset(context);failure(invoke(@[@59,@"enabled",@1],context).value,@"response_too_large");assert(vpnEffects.size()==1);
    for(unsigned fault:{1U,2U})for(NSString *point in @[@"request",@"committed",@"reply"]){context=parent();reset(context);vpnFault=fault;vpnFaultStage=point;
        failure(invoke(@[@59,@"enabled",@1],context).value,@"native_exception");assert(vpnEffects.size()==([point isEqual:@"request"]?0U:1U));}
    puts("VPN Foundation: unchanged RAW diagnostics, malformed requests and pool lifetime");fflush(stdout);
    for(unsigned scenario=0;scenario<4;++scenario)for(NSString *body in @[@"",@"0",@"1",@"1;;0",@"1;;42",@"01;;-1",@"1;;bad;;extra",@"2",@"2;;ignored",@"3",@"-1",@"bad"]){
        const auto setup=[scenario]{if(scenario){vpnReply=nil;vpnError=@"broker unavailable";}if(scenario==2)vpnDiagnosticsReply=nil;if(scenario==3){vpnDiagnosticsReply=nil;vpnDiagnosticsError=@"encode failure";}};
        context=parent();reset(context);setup();NSError *oldError=nil;NSString *expected=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);@autoreleasepool{expected=legacyVPNTaskFromRawData((UInt8 *)body.UTF8String,&oldError);}}
        const auto order=vpnOrder,commands=vpnCommands;const auto effects=vpnEffects;const unsigned diagnostics=vpnDiagnosticsCalls;
        reset(context);setup();NSError *error=nil;NSString *actual=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);@autoreleasepool{actual=vpnTaskFromRawData((UInt8 *)body.UTF8String,&error);}}
        assert(((actual==expected)||[actual isEqual:expected])&&((error==oldError)||[error.localizedDescription isEqual:oldError.localizedDescription]));
        assert(vpnOrder==order&&vpnCommands==commands&&vpnEffects==effects&&vpnDiagnosticsCalls==diagnostics);
    }
    context=parent();reset(context);NSError *heldError=nil;vpnReply=nil;vpnError=@"survives pool";
    {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);@autoreleasepool{vpnTaskWithAction(0,0,&heldError);}}assert([heldError.localizedDescription containsString:@"survives pool"]);
    context=parent();reset(context);NSMutableString *mutableReply=[@"1" mutableCopy];vpnReply=mutableReply;NSDictionary *held=nil;@autoreleasepool{held=invoke(@[@59,@"enabled",@1],context).value;context=nil;}[mutableReply setString:@"0"];assert([held[@"enabled"] boolValue]&&[held[@"raw"] isEqual:@"0;;1\r\n"]);
    for(unsigned n=0;n<128;++n){context=parent();reset(context);assert([invoke(@[@59,@"enabled",@(n%2)],context).value[@"ok"] boolValue]);assert(vpnCommands.size()==1&&vpnEffects.size()==1);}
    vpnReply=vpnError=vpnDiagnosticsReply=vpnDiagnosticsError=vpnFaultStage=nil;vpnOrder.clear();vpnCommands.clear();vpnEffects.clear();vpnOnStage={};vpnBudget.reset();radioOnValue={};licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());puts("Typed VPN passed: actual query/control/parser and frozen JS/task parity, broker command/error/metadata normalization, C-string/output bounds, task-59 authority, accepted stop/fault effects, RAW diagnostics and pool lifetime. Broker is controlled; no real VPN changed.");
    }catch(const std::exception &exception){fprintf(stdout,"VPN fixture: uncaught C++ exception: %s\n",exception.what());fflush(stdout);throw;}catch(...){puts("VPN fixture: uncaught non-standard C++ exception");fflush(stdout);throw;}}
    @catch(NSException *exception){fprintf(stdout,"VPN fixture: uncaught Objective-C exception: %s\n",exception.description.UTF8String?:"(no description)");fflush(stdout);@throw;}
}
