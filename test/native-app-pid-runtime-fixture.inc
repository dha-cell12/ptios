// Actual app PID Process core/RAW parser and shared app bridge; counted PID lookup from the preceding fixture.
NSString *appPidForBundleIdentifier(NSString *,NSError **);
NSString *appStateForBundleIdentifier(NSString *,NSError **);
NSString *appInfoForBundleIdentifier(NSString *,NSError **);
#include "AppPidCoreUnderTest.inc"
#define appPidFromRawData legacyAppPidFromRawData
#include "fixtures/app-pid-core-legacy-v1.inc"
#undef appPidFromRawData
static void appPidLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_APP_PID;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=50\r\n",writeStreamRef);return;}
    if(false){}
#define appPidFromRawData legacyAppPidFromRawData
#include "fixtures/app-pid-handler-legacy-v1.inc"
#undef appPidFromRawData
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeAppQueryEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedAppPidCases(TLinkInProcessNativeBridge *bridge){
    mode=@"appPidRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        frontPidFault=0;frontPidOnRead={};frontPidBundle=nil;
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodAppPid arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,pid_t pid,NSUInteger cap){
        frontPidValue=pid;TLinkTaskExecutionContext *context=parent(1,cap);reset(context);
        const unsigned oldReads=frontPidReads;const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyAppQuery:request(args) context:context];NSString *expectedBundle=frontPidBundle;
        const unsigned readDelta=frontPidReads-oldReads;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(context);const unsigned reads=frontPidReads;const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(frontPidReads==reads+readDelta&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        assert((frontPidBundle==expectedBundle)||[frontPidBundle isEqual:expectedBundle]);
        if(readDelta)assert(lastLicenseTask==TASK_APP_PID&&!frontPidBudget->capturesResponse()&&frontPidBudget->response().capacity()==0&&!frontPidBudget->cleanup());
    };
    for(int n=0;n<160;++n)parity(@[[NSString stringWithFormat:@"com.example.app%d",n]],pid_t(n*7919),1024*1024);
    for(int pid:{0,-1,INT_MIN,INT_MAX}){
        NSString *raw=[NSString stringWithFormat:@"0;;%d\r\n",pid];const NSUInteger bytes=[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        parity(@[@"com.example.app"],pid_t(pid),bytes);parity(@[@"com.example.app"],pid_t(pid),bytes-1);
    }
    NSString *nul=[NSString stringWithFormat:@"com.app%Cignored",(unichar)0];
    const unichar invalidUTF16=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *args=[@[@[],@[@0],@[[NSNull null]],@[@""],@[@"a;;b"],@[@"a\r"],@[@"a\n"],@[nul],@[@"ứng.dụng.测试"],@[@"app😀"],@[@" space|tab\tapp "],@[@"||"],@[@"com.app",@"ignored"]] mutableCopy];
    if(invalid)[args addObject:@[invalid]];
    for(NSArray *input in args)parity(input,77,1024);
    for(NSString *unit in @[@"x",@"界",@"😀"]){
        NSString *exact=[@"" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];
        parity(@[exact],88,1024);parity(@[[exact stringByAppendingString:@"x"]],88,1024);
    }
    // The ordinary gate is preserved; rejected ingress never reaches it or the lookup.
    auto context=parent();reset(context);unsigned reads=frontPidReads;int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@"com.app"],context).value,@"license_required task=50");assert(frontPidReads==reads&&licenseCalls==gates+1);
    context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(frontPidReads==reads&&licenseCalls==gates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(frontPidReads==reads&&licenseCalls==gates);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(frontPidReads==reads);
    context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(frontPidReads==reads);
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;
    frontPidOnRead=[token]{[token cancel];};failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(frontPidReads==reads+1);
    context=parent(0.01);reset(context);frontPidOnRead=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(frontPidReads==reads+2);
    for(unsigned fault:{1U,2U}){context=parent();reset(context);frontPidFault=fault;failure(invoke(@[@"com.app"],context).value,@"native_exception");}
    // The actual RAW parser retains its C-string normalization and NSError contract.
    for(NSString *raw in @[@"",@"com.app",@"ứng.dụng.测试",@"a;;b",@"a\r\n",nul]){
        context=parent();reset(context);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);
        NSError *oldError=nil;NSString *expected=legacyAppPidFromRawData((UInt8 *)raw.UTF8String,&oldError);NSString *expectedBundle=frontPidBundle;
        frontPidBundle=nil;NSError *error=nil;NSString *actual=appPidFromRawData((UInt8 *)raw.UTF8String,&error);
        assert((actual==expected)||[actual isEqual:expected]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
        assert((frontPidBundle==expectedBundle)||[frontPidBundle isEqual:expectedBundle]);
    }
    context=parent();reset(context);frontPidValue=123;NSMutableString *input=[NSMutableString stringWithString:@"com.original"];
    frontPidOnRead=[input]{[input appendString:@".changed"];};NSDictionary *held=nil;
    @autoreleasepool{held=invoke(@[input],context).value;context=nil;}
    assert([frontPidBundle isEqualToString:@"com.original"]&&[input isEqualToString:@"com.original.changed"]&&[held[@"pid"] intValue]==123&&[held[@"parts"][1] isEqualToString:@"123"]);
    NSError *heldError=nil;
    @autoreleasepool{assert(!appPidForBundleIdentifier(@"",&heldError));}
    assert([heldError.localizedDescription isEqualToString:@"-1;;Missing bundle identifier.\r\n"]);
    reads=frontPidReads;gates=licenseCalls;
    failure(TLinkExecuteNativeAppPid(nil,parent()),@"invalid_payload");failure(TLinkExecuteNativeAppPid(@"a;;b",parent()),@"invalid_payload");
    assert(frontPidReads==reads&&licenseCalls==gates&&!TLinkCurrentNativeBudget());
    frontPidBundle=nil;frontPidOnRead={};frontPidBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed app PID passed: frozen JS/RAW/core parity, exact 8192-unit ingress, Unicode/C-string/NUL/encoding, signed PID/output, ordinary task-50 authority, stop/faults, immutable input/error pool lifetime and no typed RAW dispatch/response vector.");
}
