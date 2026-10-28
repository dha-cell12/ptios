// Actual shared keyboard notification core, direct entry and full bridge; no real notification is posted.
static std::vector<std::string> keyboardNotificationOrder;
static TLinkNativeBudgetPtr keyboardNotificationBudget;
static unsigned keyboardNotificationFault=0;
static NSString *keyboardNotificationFaultStage=nil;
static std::function<void(NSString *)> keyboardNotificationOnPost;
static void keyboardNotificationObserve(NSString *stage){
    keyboardNotificationOrder.push_back(stage.UTF8String);keyboardNotificationBudget=TLinkCurrentNativeBudget();
    assert(keyboardNotificationBudget&&!keyboardNotificationBudget->cleanup());
    if([stage isEqual:keyboardNotificationFaultStage]&&keyboardNotificationFault==1)[NSException raise:@"KeyboardNotificationFixture" format:@"post throws"];
    if([stage isEqual:keyboardNotificationFaultStage]&&keyboardNotificationFault==2)throw std::runtime_error("post throws");
    if(keyboardNotificationOnPost)keyboardNotificationOnPost(stage);
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeKeyboardNotificationEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedKeyboardNotificationCases(TLinkInProcessNativeBridge *bridge){
    mode=@"keyboardNotificationRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        keyboardNotificationOrder.clear();keyboardNotificationBudget.reset();keyboardNotificationFault=0;keyboardNotificationFaultStage=nil;keyboardNotificationOnPost={};
        clipboardNotification=nil;clipboardNotificationObserver=keyboardNotificationObserve;clipboardOnDescription={};clipboardDescriptions=0;clipboardOrder.clear();
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodKeyboard arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](NSArray *args,NSUInteger cap)->NSUInteger{
        auto context=parent(30,cap);reset(context);int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyKeyboardNotification:request(args) context:context];NSDictionary *notification=clipboardNotification;
        const auto order=keyboardNotificationOrder;const int gateDelta=licenseCalls-gates;const unsigned descriptions=clipboardDescriptions;
        context=parent(30,cap);reset(context);gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);assert(actual.ok&&expected.ok&&[actual.value isEqual:expected.value]);
        assert(calls==rawCalls&&licenseCalls==gates+gateDelta&&keyboardNotificationOrder==order&&clipboardDescriptions==descriptions&&clipboardOrder.empty());
        assert((notification==clipboardNotification)||[notification isEqual:clipboardNotification]);
        if(!order.empty())assert(lastLicenseTask==24&&!keyboardNotificationBudget->capturesResponse()&&keyboardNotificationBudget->response().capacity()==0);
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    for(unsigned n=0;n<160;++n){const int kind=n%2?-int(n+1):int(n+10);parity(@[@(kind),[NSString stringWithFormat:@"key %u 测试",n]],4096);}
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];
    NSArray *contents=@[@"",@"hello",@"Ứng dụng 测试 😀",@"line\r\nnext",@"a;;b",@";;",@"a;;b;;c",nul,[NSNull null],@17];
    for(int kind:{INT_MIN,-1,0,1,2,3,4,5,9,123,INT_MAX}){
        parity(@[@(kind)],4096);
        for(id content in contents){const NSUInteger bytes=parity(@[@(kind),content],4096);parity(@[@(kind),content],bytes);if(bytes>1)parity(@[@(kind),content],bytes-1);}
        const NSUInteger prefix=4+[[NSString stringWithFormat:@"%d",kind] length];
        for(NSString *unit in @[@"x",@"界"]){NSString *exact=[@"" stringByPaddingToLength:8192-prefix withString:unit startingAtIndex:0];
            parity(@[@(kind),exact],32768);parity(@[@(kind),[exact stringByAppendingString:@"x"]],32768);
            parity(@[@(kind),[@"a;;" stringByPaddingToLength:8193-prefix withString:unit startingAtIndex:0]],32768);
        }
    }
    for(id kind in @[@"0",@"-1",@"0003",@"bad",@3.8,@(-3.8)])parity(@[kind,@"content"],4096);parity(@[],4096);
    NativeClipboardContentFixture *object=[NativeClipboardContentFixture new];object.value=@"description;;ignored";
    for(id content in @[object,@[@"a",@"b"],@{@"one":@1}])parity(@[@1,content],4096);
    const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];if(invalid)parity(@[@1,invalid],4096);
    // Compare actual payload fields directly, rather than relying only on ACK parity.
    auto context=parent();reset(context);NSDictionary *result=invoke(@[@(-1),@"a;;b"],context).value;
    assert([result[@"ok"] boolValue]&&[clipboardNotification[@"task_id"] isEqualToString:@"-1"]&&[clipboardNotification[@"task_content"] isEqualToString:@""]);
    // The accepted post can commit while caller cancellation/deadline is being observed.
    for(unsigned scenario=0;scenario<9;++scenario){
        NSDictionary *expected=nil,*expectedNotification=nil;
        for(bool native:{false,true}){
            if(scenario==8&&!native)continue;
            context=parent(scenario==4||scenario==6?0.1:30);reset(context);const int gates=licenseCalls,rawCalls=calls;
            switch(scenario){
                case 0:licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};break;
                case 1:[context.cancellationToken cancel];break;
                case 2:[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];break;
                case 3:stopInLicense=true;break;
                case 4:licenseDelayMs=150;break;
                case 5:{TLinkCancellationToken *token=context.cancellationToken;keyboardNotificationOnPost=[token](NSString *stage){if([stage isEqualToString:@"before"])[token cancel];};break;}
                case 6:keyboardNotificationOnPost=[](NSString *stage){if([stage isEqualToString:@"before"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};break;
                case 7:keyboardNotificationFault=1;keyboardNotificationFaultStage=@"committed";break;
                case 8:keyboardNotificationFault=2;keyboardNotificationFaultStage=@"committed";break;
            }
            TLinkJSNativeResponse *response=native?invoke(@[@1,@"accepted"],context):[bridge legacyKeyboardNotification:request(@[@1,@"accepted"]) context:context];assert(response.ok);
            if(!native){expected=response.value;expectedNotification=clipboardNotification;}else if(expected){assert([expected isEqual:response.value]);assert((expectedNotification==clipboardNotification)||[expectedNotification isEqual:clipboardNotification]);}
            if(native)assert(calls==rawCalls);assert(licenseCalls==gates+((scenario==1||scenario==2)?0:1));
            if(scenario==0)failure(response.value,@"license_required task=24");else if(scenario==2||scenario==4||scenario==6)failure(response.value,@"TimeoutError");else if(scenario==7||scenario==8)failure(response.value,@"native_exception");else failure(response.value,@"AbortError");
            assert((clipboardNotification!=nil)==(scenario>=5));
        }
    }
    for(NSString *stage in @[@"before",@"committed"])for(unsigned fault:{1U,2U}){
        context=parent();reset(context);keyboardNotificationFault=fault;keyboardNotificationFaultStage=stage;
        failure(invoke(@[@1,@"fault"],context).value,@"native_exception");assert((clipboardNotification!=nil)==[stage isEqualToString:@"committed"]);
    }
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;clipboardOnDescription=[token]{[token cancel];};int gates=licenseCalls;
    failure(invoke(@[@1,object],context).value,@"AbortError");assert(clipboardDescriptions==1&&licenseCalls==gates&&keyboardNotificationOrder.empty());
    // Content snapshots survive changes during the synchronous provider call and caller teardown.
    context=parent();reset(context);NSMutableString *source=[@"snapshot" mutableCopy];keyboardNotificationOnPost=[source](NSString *stage){if([stage isEqualToString:@"before"])[source setString:@"mutated"];};
    NSDictionary *held=nil,*payload=nil;@autoreleasepool{held=invoke(@[@1,source],context).value;payload=clipboardNotification;context=nil;}
    assert([held[@"ok"] boolValue]&&[payload[@"task_content"] isEqualToString:@"snapshot"]&&[source isEqualToString:@"mutated"]);
    context=parent();reset(context);gates=licenseCalls;for(int kind:{6,7,8})failure(TLinkExecuteNativeKeyboardNotification(kind,@"x",context),@"invalid_payload");assert(licenseCalls==gates&&keyboardNotificationOrder.empty());
    // The RAW parser retains noncanonical task_id text and its exactly-two-fields rule.
    for(NSString *raw in @[@"",@"bad",@"0003;;text",@"-1;;text",@"1;;",@"1;;a;;b",@"1;;line\r\ntext",@"9;;Ứng dụng"]){
        context=parent();reset(context);NSError *oldError=nil,*error=nil;NSString *expectedBody=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);expectedBody=legacyClipboardInputTextFromRawData((UInt8 *)raw.UTF8String,&oldError);}
        NSDictionary *notification=clipboardNotification;reset(context);NSString *actualBody=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);actualBody=inputTextFromRawData((UInt8 *)raw.UTF8String,&error);}
        assert((expectedBody==actualBody)||[expectedBody isEqual:actualBody]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);assert([notification isEqual:clipboardNotification]);
    }
    clipboardNotification=nil;clipboardNotificationObserver={};clipboardOnDescription={};keyboardNotificationOrder.clear();keyboardNotificationBudget.reset();keyboardNotificationOnPost={};keyboardNotificationFault=0;keyboardNotificationFaultStage=nil;licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed keyboard notification passed: frozen JS/RAW ACK/payload parity, signed/unknown kinds, exact field-count rule, descriptions/Unicode/NUL/ingress/output, task-24 gates, accepted cancellation/faults, snapshots and RAW spelling. No real keyboard notification delivered.");
}
