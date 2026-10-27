// Actual RAW parser/numeric enqueue/bridge/entry; queue and UIKit effects are controlled.
static NSMutableArray *toastPending=nil,*toastEffects=nil;
static unsigned toastEnqueues=0,toastFault=0;
static TLinkNativeBudgetPtr toastBudget;
static std::function<void()> toastOnEnqueue;
@interface NativeToastFixture : NSObject
+ (void)hideToast;
+ (void)showToastWithContent:(NSString *)content type:(int)type duration:(float)duration position:(int)position fontSize:(int)fontSize;
@end
@implementation NativeToastFixture
+ (void)hideToast {assert(!TLinkCurrentNativeBudget());[toastEffects addObject:@{@"hide":@(true)}];}
+ (void)showToastWithContent:(NSString *)content type:(int)type duration:(float)duration position:(int)position fontSize:(int)fontSize {
    assert(!TLinkCurrentNativeBudget());
    [toastEffects addObject:@{@"message":content?:@"",@"type":@(type),@"duration":@(duration),@"position":@(position),@"fontSize":@(fontSize)}];
}
@end
static void toastEnqueue(dispatch_queue_t queue,dispatch_block_t block){
    assert(queue==dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0)&&toastPending);
    ++toastEnqueues;toastBudget=TLinkCurrentNativeBudget();assert(toastBudget&&!toastBudget->cleanup());
    if(toastFault==1)[NSException raise:@"ToastFixture" format:@"before enqueue"];
    if(toastFault==2)throw std::runtime_error("before enqueue");
    [toastPending addObject:[block copy]];
    if(toastOnEnqueue)toastOnEnqueue();
    if(toastFault==3)[NSException raise:@"ToastFixture" format:@"after enqueue"];
    if(toastFault==4)throw std::runtime_error("after enqueue");
}
static void toastDrain(){
    while(toastPending.count){dispatch_block_t block=toastPending[0];[toastPending removeObjectAtIndex:0];block();}
}
void TLinkShowToast(int,NSString *,int,int,int,NSError **);
#define Toast NativeToastFixture
#define dispatch_async toastEnqueue
#include "ToastCoreUnderTest.inc"
#define showToastFromRawData legacyShowToastFromRawData
#include "ToastLegacyCoreUnderTest.inc"
#undef showToastFromRawData
#undef dispatch_async
#undef Toast
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeToastEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void toastLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_SHOW_TOAST;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=22\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#define showToastFromRawData legacyShowToastFromRawData
#include "fixtures/toast-handler-legacy-v1.inc"
#undef showToastFromRawData
}
@interface NativeToastValueFixture : NSObject
@property(nonatomic,copy) NSString *text;
@end
static std::function<void()> toastOnValue;
@implementation NativeToastValueFixture
- (NSString *)description {if(toastOnValue)toastOnValue();return self.text;}
- (int)intValue {if(toastOnValue)toastOnValue();return self.text.intValue;}
@end
static void typedToastCases(TLinkInProcessNativeBridge *bridge){
    mode=@"toastRuntime";toastPending=[NSMutableArray array];toastEffects=[NSMutableArray array];
    const auto reset=[](TLinkTaskExecutionContext *context){
        assert(!toastPending.count);[toastEffects removeAllObjects];toastBudget.reset();toastFault=0;toastOnEnqueue={};toastOnValue={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodToast arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](NSArray *args,NSUInteger cap){
        auto context=parent(30,cap);reset(context);int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyToast:request(args) context:context];const NSUInteger pending=toastPending.count;const int gateDelta=licenseCalls-gates;
        assert(!toastEffects.count);toastDrain();NSArray *effects=[toastEffects copy];
        context=parent(30,cap);reset(context);const int rawCalls=calls;gates=licenseCalls;
        TLinkJSNativeResponse *actual=invoke(args,context);assert(actual.ok==expected.ok);
        if(actual.ok)assert([actual.value isEqual:expected.value]);else assert([actual.errorMessage isEqual:expected.errorMessage]&&[actual.errorCode isEqual:expected.errorCode]);
        assert(calls==rawCalls&&licenseCalls==gates+gateDelta&&toastPending.count==pending&&!toastEffects.count);
        if(pending)assert(lastLicenseTask==22&&!toastBudget->capturesResponse()&&toastBudget->response().capacity()==0);
        toastDrain();assert([effects isEqual:toastEffects]);
    };
    for(unsigned n=0;n<160;++n)parity(@[[NSString stringWithFormat:@"toast %u 测试",n],@{@"type":@(int(n%8)-2),@"duration":@(int(n%9)-3),@"position":@(int(n%7)-3),@"fontSize":@(int(n%41)-5)}],4096);
    for(NSString *text in @[@"",@"hello",@"a;;b\r\nc",@"Ứng dụng 😀",[@"界" stringByPaddingToLength:180 withString:@"界" startingAtIndex:0],[@"x" stringByPaddingToLength:181 withString:@"x" startingAtIndex:0]])for(int type:{0,1,2,3,4}){
        parity(@[text,@{@"type":@(type),@"duration":@(-1)}],4096);parity(@[text,@{@"type":@(type)}],3);parity(@[text,@{@"type":@(type)}],2);
    }
    for(id value in @[[NSNull null],@(-1),@0,@1,@4,@5,@INT_MIN,@INT_MAX,@"3.8",@"bad",@3.9])for(NSString *key in @[@"type",@"duration",@"position",@"fontSize"])parity(@[@"options",@{key:value}],4096);
    NativeToastValueFixture *value=[NativeToastValueFixture new];value.text=@"3";
    parity(@[value],4096);parity(@[@"value",@{@"duration":value}],4096);parity(@[@17],4096);parity(@[[NSNull null]],4096);parity(@[],4096);
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];parity(@[nul],4096);
    parity(@[[[@"x" stringByPaddingToLength:180 withString:@"x" startingAtIndex:0] stringByAppendingString:nul]],4096);
    NSString *splitEmoji=[[@"x" stringByPaddingToLength:179 withString:@"x" startingAtIndex:0] stringByAppendingString:@"😀"];
    parity(@[splitEmoji],4096);const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];if(invalid)parity(@[invalid],4096);
    for(bool hide:{false,true}){
        NSArray *args=@[@"accepted",@{@"type":hide?@0:@3}];auto context=parent();reset(context);const int gates=licenseCalls;
        licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(args,context).value,@"license_required task=22");assert(licenseCalls==gates+1&&!toastPending.count);
        context=parent();reset(context);[context.cancellationToken cancel];failure(invoke(args,context).value,@"AbortError");assert(!toastPending.count);
        context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(args,context).value,@"TimeoutError");assert(!toastPending.count);
        context=parent();reset(context);stopInLicense=true;failure(invoke(args,context).value,@"AbortError");assert(!toastPending.count);
        context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(args,context).value,@"TimeoutError");assert(!toastPending.count);
        context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;toastOnEnqueue=[token]{[token cancel];};
        failure(invoke(args,context).value,@"AbortError");assert(toastPending.count==1&&!toastEffects.count);toastDrain();assert(toastEffects.count==1);
        context=parent(0.1);reset(context);toastOnEnqueue=[]{std::this_thread::sleep_for(std::chrono::milliseconds(150));};
        failure(invoke(args,context).value,@"TimeoutError");assert(toastPending.count==1);toastDrain();
        for(unsigned fault:{1U,2U,3U,4U}){context=parent();reset(context);toastFault=fault;failure(invoke(args,context).value,@"native_exception");assert(toastPending.count==(fault>=3?1U:0U));toastDrain();}
    }
    // Normalization can cancel before the gate; accepted work retains content after caller teardown.
    auto context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;toastOnValue=[token]{[token cancel];};
    int gates=licenseCalls;failure(invoke(@[value],context).value,@"AbortError");assert(licenseCalls==gates&&!toastPending.count);
    context=parent();reset(context);token=context.cancellationToken;toastOnValue=[token]{[token cancel];};gates=licenseCalls;
    failure(invoke(@[@"value",@{@"duration":value}],context).value,@"AbortError");assert(licenseCalls==gates&&!toastPending.count);
    context=parent();reset(context);NSDictionary *held=nil;NSMutableString *source=[@"snapshot" mutableCopy];
    @autoreleasepool{held=invoke(@[source],context).value;assert([held[@"ok"] boolValue]&&!toastEffects.count);}
    [source setString:@"changed"];[context.cancellationToken cancel];context=nil;toastDrain();assert([toastEffects[0][@"message"] isEqualToString:@"snapshot"]&&[held[@"raw"] isEqualToString:@"0\r\n"]);
    // RAW fields/errors remain compatible, including permissive intValue parsing and optional columns.
    for(NSString *raw in @[@"",@"0;;",@"0;;hide;;0",@"1;;x;;1",@"3;;x;;1.5;;-2;;17;;ignored",@"4;;Ü测试;;2",@"5;;x;;1",@"-1;;x;;1",@"3;;x;;0",@"bad;;x;;bad"]){
        context=parent();reset(context);NSError *oldError=nil,*error=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);legacyShowToastFromRawData((UInt8 *)raw.UTF8String,&oldError);}
        const NSUInteger pending=toastPending.count;toastDrain();NSArray *effects=[toastEffects copy];
        reset(context);{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);showToastFromRawData((UInt8 *)raw.UTF8String,&error);}
        assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);assert(toastPending.count==pending);toastDrain();assert([effects isEqual:toastEffects]);
    }
    // The numeric backend retains the RAW validation even when invoked directly.
    context=parent();reset(context);failure(TLinkExecuteNativeToast(5,@"x",1,0,14,context),@"Unknown type. The type ranges from 0-3. Please refer to the documentation on Github.");assert(!toastPending.count);
    failure(TLinkExecuteNativeToast(3,@"x",0,0,14,context),@"Duration should be a positive float number.");assert(!toastPending.count);
    NSError *heldError=nil;
    @autoreleasepool{showToastFromRawData((UInt8 *)"bad",&heldError);}
    assert([heldError.localizedDescription hasPrefix:@"-1;;The data format should be"]);
    NSError *existing=heldError;
    @autoreleasepool{showToastFromRawData((UInt8 *)"0;;hide;;0",&heldError);}
    assert(heldError==existing&&toastPending.count==1);toastDrain();
    // Public native-field ingress counts every decimal column and separator,
    // independent of the JS adapter's much smaller 180-unit sanitized message.
    for(NSString *unit in @[@"x",@"界"])for(NSUInteger length:{NSUInteger(8177),NSUInteger(8178)}){
        NSString *message=[@"" stringByPaddingToLength:length withString:unit startingAtIndex:0];
        context=parent();reset(context);NSDictionary *expected=[bridge executeRawPayload:[NSString stringWithFormat:@"223;;%@;;2;;0;;14",message] context:context];
        const NSUInteger pending=toastPending.count;toastDrain();NSArray *effects=[toastEffects copy];
        context=parent();reset(context);const int rawCalls=calls;NSDictionary *actual=TLinkExecuteNativeToast(3,message,2,0,14,context);
        assert([expected isEqual:actual]&&calls==rawCalls&&toastPending.count==pending&&!TLinkCurrentNativeBudget());toastDrain();assert([effects isEqual:toastEffects]);
    }
    // Real global dispatch delivery reaches the controlled UI boundary outside the native scope.
    context=parent();reset(context);assert([invoke(@[@"global dispatch"],context).value[@"ok"] boolValue]);
    dispatch_block_t block=toastPending[0];[toastPending removeObjectAtIndex:0];dispatch_group_t group=dispatch_group_create();
    dispatch_group_async(group,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),block);
    assert(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0&&toastEffects.count==1);
    [toastEffects removeAllObjects];toastPending=nil;toastEffects=nil;toastBudget.reset();toastOnEnqueue={};toastOnValue={};toastFault=0;licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed toast passed: actual normalization/parser/numeric enqueue with frozen JS/RAW replies/effects, type/duration/options, sanitization/180-unit/Unicode/NUL boundaries, task-22 gates, queued stop/fault/output behavior, late snapshots, real global dispatch and result lifetime. No real toast displayed.");
}
