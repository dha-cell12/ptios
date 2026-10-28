// Actual compatibility executor/entry and frozen pre-adapter JS/RAW oracle.
// Touch frames and clocks are controlled; no real HID events are submitted.
#define zx_handleNativeBatch legacyCompatibilityBatchCore
#include "fixtures/compatibility-batch-core-legacy-v1.inc"
#undef zx_handleNativeBatch
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeCompatibilityBatchEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void compatibilityBatchLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_NATIVE_BATCH;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=65\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#define zx_handleNativeBatch legacyCompatibilityBatchCore
#include "fixtures/compatibility-batch-handler-legacy-v1.inc"
#undef zx_handleNativeBatch
}
static void typedCompatibilityBatchCases(TLinkInProcessNativeBridge *bridge){
    puts("Compatibility batch Foundation: frozen JS/RAW versus actual shared executor and direct entry");fflush(stdout);
    mode=@"compatibilityBatchRuntime";fakeTiming=true;
    const auto reset=[](TLinkTaskExecutionContext *context,unsigned scenario){
        injected.clear();frameTimes.clear();fakeNow=1000000;frameWork=7000000;oversleep=2000000;fakeWaits=0;
        touchToken=context.cancellationToken;licenseAllowed=scenario!=1;stopInLicense=scenario==2;licenseDelayMs=0;
        cancelAt=scenario==4?3:0;throwAt=(scenario==5||scenario==6)?3:0;throwCpp=scenario==6;licenseBudget.reset();
        if(scenario==3)[touchToken cancel];
        if(scenario==7)[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    };
    const auto request=[](NSArray *commands){return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodBatch arguments:@[commands]];};
    const auto parity=[bridge,reset,request](NSArray *commands,NSUInteger cap=4096,unsigned scenario=0,bool direct=false){
        auto context=parent(30,cap);reset(context,scenario);int gates=licenseCalls;
        TLinkJSNativeResponse *expected=nil;
        if(direct)expected=[TLinkJSNativeResponse responseWithValue:[bridge executeRawPayload:[@"65" stringByAppendingString:[commands componentsJoinedByString:@"||"]] context:context]];
        else expected=[bridge legacyCompatibilityBatch:request(commands) context:context];
        const auto points=injected;const auto times=frameTimes;const unsigned waits=fakeWaits;const int gateDelta=licenseCalls-gates;
        context=parent(30,cap);reset(context,scenario);gates=licenseCalls;const int rawBefore=calls;
        TLinkJSNativeResponse *actual=direct?[TLinkJSNativeResponse responseWithValue:TLinkExecuteNativeCompatibilityBatch(commands,context)]:[bridge executeRequest:request(commands) context:context error:nil];
        const bool same=actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]);
        if(!same){fprintf(stdout,"Compatibility batch parity failure: %s\n",[NSString stringWithFormat:@"commands=%@ cap=%lu scenario=%u direct=%d expected=%@ actual=%@",commands,(unsigned long)cap,scenario,direct,expected.value,actual.value].UTF8String);fflush(stdout);}assert(same);
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(calls==rawBefore&&licenseCalls==gates+gateDelta&&points.size()==injected.size()&&times==frameTimes&&waits==fakeWaits&&!TLinkCurrentNativeBudget());
        for(size_t i=0;i<points.size();++i)assert(points[i].type==injected[i].type&&points[i].index==injected[i].index&&points[i].x==injected[i].x&&points[i].y==injected[i].y);
        if(gateDelta){assert(gateDelta==1&&lastLicenseTask==65&&licenseBudget&&!licenseBudget->cleanup()&&!licenseBudget->capturesResponse()&&licenseBudget->response().capacity()==0);}
    };
    NSDictionary *tap=@{@"type":@"tap",@"x":@20,@"y":@30,@"duration":@0};
    NSArray *normal=@[@"6220;;30;;0",tap,@"6340;;50;;80;;90;;16",tap];
    for(unsigned n=0;n<160;++n){
        parity(@[[NSString stringWithFormat:@"62%.2f;;%.2f;;%u",double(n)*0.945,-0.0,n%17],
            @{@"type":@"TAP",@"x":@(n*0.125),@"y":@50,@"duration":@"16"},
            @{@"type":@"gesture",@"points":@[@[@20,@30],@[@40,@50]],@"durationMs":@(n%25),@"finger":@(n%20)},tap]);
    }
    for(id duration:@[@-1,@60001,@(1e100),@"16",@(-0.0)])parity(@[@"6220;;30;;0",@{@"type":@"swipe",@"x1":@20,@"y1":@30,@"x2":@50,@"y2":@60,@"duration":duration}]);
    for(NSString *raw in @[@"62",@"63",@"64",@"6220;;30;;0|",@"640;;0;;20,30|40,50",@"64-1;;0;;20,30|40,50",@"6220;;30;;0 trailing",@"62ảnh;测试",@"62||62",@"62\r",@"62\n",@"99",@"",@"6"])parity(@[tap,raw,tap]);
    for(id bad in @[[NSNull null],@42,@{@"type":@"unknown"},@{@"type":@"tap",@"x":@(NAN)},@{@"type":@"gesture",@"points":@[@[]]}])parity(@[@"6220;;30;;0",tap,bad]);
    NSMutableArray *many=[NSMutableArray array];for(unsigned n=0;n<256;++n)[many addObject:@"62"];
    parity(many);[many addObject:@"62"];parity(many);
    for(NSString *unit in @[@"x",@"界"]){NSString *exact=[@"62" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];parity(@[exact]);parity(@[[exact stringByAppendingString:@"x"]]);}
    const unichar zero=0,lone=0xd800;NSString *nul=[@"62" stringByAppendingString:[NSString stringWithCharacters:&zero length:1]];
    NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];parity(@[tap,nul]);if(invalid)parity(@[[@"62" stringByAppendingString:invalid]]);
    // Entire UTF16 length is admitted before UTF8/NUL checks across all items.
    parity(@[nul,[@"62" stringByPaddingToLength:8190 withString:@"x" startingAtIndex:0]]);
    // The old RAW bridge catches NS exceptions only. Exercise C++ unwind on
    // the new entry separately rather than invoking the unsafe frozen route.
    for(unsigned scenario=0;scenario<=7;++scenario)if(scenario!=6)parity(normal,4096,scenario);
    for(NSUInteger cap:{NSUInteger(2),NSUInteger(3),NSUInteger(32)}){parity(normal,cap);parity(@[@"62"],cap);parity(normal,cap,4);}
    for(NSArray *commands in @[@[],@[@""],@[@"",@""],@[@"x",@""],@[@"6220;;30;;0|",@"6220;;30;;0"],@[@"6220;;30;;0||62"],@[@"1011190020000300",@"99bad"],@[@"1011190020000300",@"62"],@[@"1011190020000300",@"6220;;30;;0"]])parity(commands,4096,0,true);
    auto context=parent();reset(context,0);const int gates=licenseCalls;
    failure(TLinkExecuteNativeCompatibilityBatch((NSArray *)@"bad",context),@"invalid_payload");
    NSArray *nonStringCommands=@[@42]; // Deliberately erase generics for the runtime rejection probe.
    failure(TLinkExecuteNativeCompatibilityBatch(nonStringCommands,context),@"invalid_payload");
    failure(TLinkExecuteNativeCompatibilityBatch(many,context),@"invalid_payload");assert(licenseCalls==gates&&injected.empty());
    context=parent();reset(context,6);
    failure([bridge executeRequest:request(normal) context:context error:nil].value,@"native_exception");assert(injected.size()==4&&injected.back().type==TOUCH_UP);
    context=parent();reset(context,1);context.allowsAutomationForOwner=^BOOL(__unused NSString *owner){return YES;};
    assert([[bridge executeRequest:request(normal) context:context error:nil].value[@"raw"] isEqual:@"-1;;license_required task=65\r\n"]&&injected.empty());
    context=parent(0.1);reset(context,0);licenseDelayMs=150;
    failure([bridge executeRequest:request(normal) context:context error:nil].value,@"TimeoutError");assert(injected.empty());
    // Result ownership survives the adapter and caller pools.
    NSDictionary *held=nil;@autoreleasepool{context=parent();reset(context,0);held=TLinkExecuteNativeCompatibilityBatch(@[@"62"],context);}
    assert([held[@"parts"][1] hasPrefix:@"Native tap format"]);
    for(unsigned n=0;n<128;++n)parity(normal);
    mode=@"echo";fakeTiming=false;cancelAt=throwAt=0;throwCpp=false;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;touchToken=nil;licenseBudget.reset();
    puts("Compatibility batch passed: frozen JS/RAW frame/time/reply parity, mixed/raw/duration grammar, pipe overlap, full preflight, 256/257 and 8192/8193 ingress, UTF/NUL precedence, one task-65 gate, stop/fault/output, raw-owned UP and pool lifetime; no direct RAW dispatch or response buffer.");
}
