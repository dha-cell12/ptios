// Actual URL parser/core/main-owner wrapper and app entry; real NSURL, controlled main/UIKit boundary.
static bool urlOwner=false,urlMainThread=false,urlModern=true,urlFirst=true,urlSecond=false;
static unsigned urlQueueCalls=0,urlFault=0;
static int urlFaultStage=-1;
static NSMutableArray *urlInvocations=nil,*urlCompletions=nil;
static std::vector<int> urlOrder;
static TLinkNativeBudgetPtr urlBudget;
static std::function<void(int)> urlOnRead;
static void urlObserve(int stage){
    urlOrder.push_back(stage);urlBudget=TLinkCurrentNativeBudget();assert(urlBudget&&!urlBudget->cleanup());
    if(stage==urlFaultStage&&urlFault==1)[NSException raise:@"URLFixture" format:@"boundary throws"];
    if(stage==urlFaultStage&&urlFault==2)throw std::runtime_error("URL boundary throws");
    if(urlOnRead)urlOnRead(stage);
}
@interface NativeURLThreadFixture : NSObject
+ (BOOL)isMainThread;
@end
@implementation NativeURLThreadFixture
+ (BOOL)isMainThread {return urlMainThread;}
@end
@interface NativeURLApplicationFixture : NSObject
+ (instancetype)sharedApplication;
- (BOOL)openURL:(NSURL *)url;
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion;
@end
@implementation NativeURLApplicationFixture
+ (instancetype)sharedApplication {
    assert(urlOwner);urlObserve(1);static NativeURLApplicationFixture *app=nil;
    if(!app)app=[NativeURLApplicationFixture new];return app;
}
- (BOOL)respondsToSelector:(SEL)selector {
    if(sel_isEqual(selector,@selector(openURL:options:completionHandler:))){assert(urlOwner);urlObserve(2);return urlModern;}
    return [super respondsToSelector:selector];
}
- (BOOL)openURL:(NSURL *)url {
    assert(urlOwner&&url);urlObserve(3);const bool accepted=urlInvocations.count?urlSecond:urlFirst;
    [urlInvocations addObject:url.absoluteString];urlObserve(4);return accepted;
}
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    assert(urlOwner&&url&&options.count==0&&completion);urlObserve(3);
    [urlInvocations addObject:url.absoluteString];[urlCompletions addObject:[completion copy]];urlObserve(4);
}
@end
static void urlDispatch(dispatch_queue_t queue,dispatch_block_t operation){
    assert(queue==dispatch_get_main_queue()&&!urlMainThread);++urlQueueCalls;const bool previous=urlOwner;
    @try {urlObserve(0);urlOwner=true;operation();} @finally {urlOwner=previous;}
}
#define NSThread NativeURLThreadFixture
#define UIApplication NativeURLApplicationFixture
#define dispatch_sync urlDispatch
#include "OpenUrlCoreUnderTest.inc"
#define openUrlFromRawData legacyOpenUrlFromRawData
#include "fixtures/open-url-core-legacy-v1.inc"
#undef openUrlFromRawData
#undef dispatch_sync
#undef UIApplication
#undef NSThread
static void openUrlLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_OPEN_URL;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=54\r\n",writeStreamRef);return;}
    if(false){}
#define openUrlFromRawData legacyOpenUrlFromRawData
#include "fixtures/open-url-handler-legacy-v1.inc"
#undef openUrlFromRawData
}
static void typedOpenUrlCases(TLinkInProcessNativeBridge *bridge){
    mode=@"openUrlRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,bool modern=true,bool first=true,bool second=false,bool main=false){
        urlModern=modern;urlFirst=first;urlSecond=second;urlOwner=urlMainThread=main;
        urlQueueCalls=urlFault=0;urlFaultStage=-1;urlOrder.clear();urlOnRead={};urlBudget.reset();
        urlInvocations=[NSMutableArray array];urlCompletions=[NSMutableArray array];
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodOpenUrl arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget()&&urlOwner==urlMainThread);return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,bool modern,bool first,bool second,NSUInteger cap)->NSUInteger{
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context,modern,first,second);const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyOpenUrl:request(args) context:context];const auto order=urlOrder;
        NSArray *invocations=[urlInvocations copy];const NSUInteger callbacks=urlCompletions.count;const unsigned dispatches=urlQueueCalls;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(context,modern,first,second);const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(urlOrder==order&&[urlInvocations isEqual:invocations]&&urlCompletions.count==callbacks&&urlQueueCalls==dispatches&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        if(dispatches)assert(lastLicenseTask==TASK_OPEN_URL&&!urlBudget->capturesResponse()&&urlBudget->response().capacity()==0&&!urlBudget->cleanup());
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    for(int n=0;n<160;++n){NSString *url=n%2?[NSString stringWithFormat:@"prefs:root=Fixture%d",n]:[NSString stringWithFormat:@"https://example.invalid/path/%d",n];parity(@[url],bool(n%3),bool(n%2),bool(n%5),1024);}
    for(bool modern:{false,true})for(bool first:{false,true})for(bool second:{false,true}){
        for(NSString *url in @[@"prefs:root=General",@"PREFS:root=Privacy",@"App-Prefs:root=General",@"https://example.invalid",@"http://[",@"relative/path"]){
            const NSUInteger bytes=parity(@[url],modern,first,second,4096);
            parity(@[url],modern,first,second,bytes);if(bytes)parity(@[url],modern,first,second,bytes-1);
        }
    }
    NSString *nul=[NSString stringWithFormat:@"url%Ctail",(unichar)0];const unichar invalidUTF16=0xd800;
    NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *inputs=[@[@[],@[@0],@[[NSNull null]],@[@""],@[@"a;;b"],@[@"a\r"],@[@"a\n"],@[nul],@[@"https://example.invalid/ứng.dụng/测试"],@[@"custom:😀"],@[@"https://example.invalid",@"ignored"]] mutableCopy];if(invalid)[inputs addObject:@[invalid]];
    for(NSArray *args in inputs)parity(args,true,true,false,4096);
    for(NSString *unit in @[@"x",@"界",@"😀"]){
        NSString *exact=[@"" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];
        parity(@[exact],true,true,false,4096);parity(@[[exact stringByAppendingString:@"x"]],true,true,false,4096);
    }
    auto context=parent();reset(context);int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@"prefs:root=General"],context).value,@"license_required task=54");assert(urlInvocations.count==0&&urlQueueCalls==0&&licenseCalls==gates+1);
    context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@"https://example.invalid"],context).value,@"AbortError");assert(urlQueueCalls==0&&licenseCalls==gates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@"https://example.invalid"],context).value,@"TimeoutError");assert(urlQueueCalls==0&&licenseCalls==gates);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@"https://example.invalid"],context).value,@"AbortError");assert(urlQueueCalls==0);
    context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(@[@"https://example.invalid"],context).value,@"TimeoutError");assert(urlQueueCalls==0);
    // Accepted opaque owner work preserves effect semantics; the task observes stop on return.
    for(int stage:{0,4}){context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;urlOnRead=[token,stage](int point){if(point==stage)[token cancel];};failure(invoke(@[@"https://example.invalid"],context).value,@"AbortError");assert(urlInvocations.count==1);}
    context=parent(0.01);reset(context);urlOnRead=[](int stage){if(stage==0)std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(@[@"https://example.invalid"],context).value,@"TimeoutError");assert(urlInvocations.count==1);
    context=parent(1,2);reset(context);failure(invoke(@[@"https://example.invalid"],context).value,@"response_too_large");assert(urlInvocations.count==1);
    for(unsigned fault:{1U,2U})for(int stage:{0,1,2,3,4}){
        context=parent();reset(context);urlFault=fault;urlFaultStage=stage;failure(invoke(@[@"https://example.invalid"],context).value,@"native_exception");
        assert(urlInvocations.count==(stage==4?1U:0U)&&!urlOwner);
    }
    // Safety correction: the actual owner wrapper runs inline on main. Do not execute the deadlocking legacy path there.
    for(bool modern:{false,true}){context=parent();reset(context,modern,false,true,true);NSDictionary *result=invoke(@[@"prefs:root=General"],context).value;
        assert([result[@"ok"] boolValue]&&urlQueueCalls==0&&urlInvocations.count==(modern?1U:2U)&&urlOwner);}
    // Modern ACK ignores later completion outcome; retained completion does not capture caller state.
    context=parent();reset(context);NSDictionary *held=nil;NSArray *pending=nil;
    @autoreleasepool{held=invoke(@[@"prefs:root=General"],context).value;pending=[urlCompletions copy];context=nil;}
    assert([held[@"ok"] boolValue]&&pending.count==1&&urlInvocations.count==1);void (^completion)(BOOL)=pending[0];completion(false);completion(true);assert(urlInvocations.count==1);
    for(NSString *raw in @[@"",@"prefs:root=General",@"PREFS:root=Privacy",@"https://example.invalid/ứng.dụng",@"a;;b",@"a\r\n",nul]){
        context=parent();reset(context,false,false,true);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *oldError=nil;
        NSString *expected=legacyOpenUrlFromRawData((UInt8 *)raw.UTF8String,&oldError);NSArray *invocations=[urlInvocations copy];const auto order=urlOrder;
        reset(context,false,false,true);NSError *error=nil;NSString *actual=openUrlFromRawData((UInt8 *)raw.UTF8String,&error);
        assert((actual==expected)||[actual isEqual:expected]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
        assert(urlOrder==order&&[urlInvocations isEqual:invocations]);
    }
    context=parent();reset(context);NSError *heldError=nil;
    @autoreleasepool{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);assert(!openUrlFromRawData(nullptr,&heldError));}
    assert([heldError.localizedDescription isEqualToString:@"-1;;Missing URL.\r\n"]);
    context=parent();reset(context);NSMutableString *input=[NSMutableString stringWithString:@"https://example.invalid/original"];urlOnRead=[input](int stage){if(stage==0)[input appendString:@"/changed"];};
    held=invoke(@[input],context).value;assert([held[@"ok"] boolValue]&&[urlInvocations[0] isEqualToString:@"https://example.invalid/original"]);
    gates=licenseCalls;failure(TLinkExecuteNativeOpenUrl(nil,parent()),@"invalid_payload");assert(licenseCalls==gates);
    urlInvocations=nil;urlCompletions=nil;urlOrder.clear();urlOnRead={};urlBudget.reset();licenseBudget.reset();touchToken=nil;urlOwner=urlMainThread=false;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed openUrl passed: actual NSURL/parser/core/main wrapper with frozen bridge/task parity, modern ACK/late completion, legacy prefs fallback, main inline safety, exact Unicode ingress/output, task-54 authority, stop/fault/effect and pool lifetime. UIKit/GCD/device qualification pending.");
}
