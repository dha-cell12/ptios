// Actual enqueue/core/parser/bridge/entry; controlled main-queue and UIKit boundary.
static NSMutableArray *awakePending=nil;
static std::vector<bool> awakeApplied;
static unsigned awakeFault=0,awakeEnqueues=0;
static BOOL awakeState=false;
static TLinkNativeBudgetPtr awakeBudget;
static std::function<void()> awakeOnEnqueue;
@interface KeepAwakeApplicationFixture : NSObject
+ (instancetype)sharedApplication;
@property(nonatomic) BOOL idleTimerDisabled;
@end
@implementation KeepAwakeApplicationFixture
+ (instancetype)sharedApplication {
    static KeepAwakeApplicationFixture *application=nil;
    if(!application)application=[KeepAwakeApplicationFixture new];return application;
}
- (BOOL)idleTimerDisabled{return awakeState;}
- (void)setIdleTimerDisabled:(BOOL)value {
    assert(!TLinkCurrentNativeBudget());awakeState=value;awakeApplied.push_back(bool(value));
}
@end
static void awakeEnqueue(dispatch_queue_t queue,dispatch_block_t block){
    assert(queue==dispatch_get_main_queue()&&awakePending);
    ++awakeEnqueues;awakeBudget=TLinkCurrentNativeBudget();
    if(awakeFault==1)[NSException raise:@"KeepAwakeFixture" format:@"before enqueue"];
    if(awakeFault==2)throw std::runtime_error("before enqueue");
    [awakePending addObject:[block copy]];
    if(awakeOnEnqueue)awakeOnEnqueue();
    if(awakeFault==3)[NSException raise:@"KeepAwakeFixture" format:@"after enqueue"];
    if(awakeFault==4)throw std::runtime_error("after enqueue");
}
static void awakeDrain(){
    while(awakePending.count){dispatch_block_t block=awakePending[0];[awakePending removeObjectAtIndex:0];block();}
}
void TLinkSetKeepAwakeEnabled(BOOL);
#define UIApplication KeepAwakeApplicationFixture
#define dispatch_async awakeEnqueue
#include "KeepAwakeCoreUnderTest.inc"
#define keepAwakeFromRawData legacyKeepAwakeFromRawData
#include "KeepAwakeLegacyCoreUnderTest.inc"
#undef keepAwakeFromRawData
#undef dispatch_async
#undef UIApplication
static void keepAwakeLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_KEEP_AWAKE;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=40\r\n",writeStreamRef);return;}
    if(false){}
#define keepAwakeFromRawData legacyKeepAwakeFromRawData
#include "fixtures/keep-awake-handler-legacy-v1.inc"
#undef keepAwakeFromRawData
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeKeepAwakeEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedKeepAwakeCases(TLinkInProcessNativeBridge *bridge){
    mode=@"keepAwakeRuntime";awakePending=[NSMutableArray new];
    const auto reset=[](TLinkTaskExecutionContext *context){
        assert(awakePending.count==0);awakeApplied.clear();awakeFault=0;awakeOnEnqueue={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodKeepAwake arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->NSDictionary *{
        NSDictionary *result=[bridge executeRequest:request(args) context:context error:nil].value;
        assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,NSUInteger cap){
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context);
        NSDictionary *expected=[bridge legacyKeepAwake:request(args) context:context].value;
        assert(awakeApplied.empty()&&awakePending.count==1);awakeDrain();const auto applied=awakeApplied;
        context=parent(1,cap);reset(context);const unsigned enqueues=awakeEnqueues;const int gates=licenseCalls,rawCalls=calls;
        NSDictionary *actual=invoke(args,context);
        assert([actual isEqual:expected]&&awakeEnqueues==enqueues+1&&awakePending.count==1&&awakeApplied.empty());
        assert(licenseCalls==gates+1&&lastLicenseTask==TASK_KEEP_AWAKE&&calls==rawCalls);
        assert(awakeBudget&&!awakeBudget->cleanup()&&!awakeBudget->capturesResponse()&&awakeBudget->response().capacity()==0);
        awakeDrain();assert(awakeApplied==applied&&awakeApplied.size()==1);
    };
    for(NSArray *args in @[@[],@[@0],@[@1],@[@(-1)],@[@2],@[@0.5],@[@"YES"],@[@"false"],@[@"1"],@[@"0"],@[@"bad"],@[@1,@"ignored"]]){
        parity(args,1024);parity(args,3);parity(args,2);
    }
    // RAW keeps integer conversion, including values unlike the JS boolValue contract.
    for(NSString *text in @[@"",@"0",@"1",@"-1",@"2",@"0.5",@"YES",@"false",@"bad",@" 1suffix"]){
        NSError *oldError=nil;NSString *expected=legacyKeepAwakeFromRawData((UInt8 *)text.UTF8String,&oldError);
        awakeApplied.clear();awakeDrain();const auto applied=awakeApplied;
        NSError *error=nil;NSString *actual=keepAwakeFromRawData((UInt8 *)text.UTF8String,&error);
        awakeApplied.clear();awakeDrain();assert([actual isEqual:expected]&&error==oldError&&awakeApplied==applied);
    }
    // Disabling is an ordinary licensed action, never an exempt cleanup operation.
    for(NSNumber *enabled in @[@0,@1]){
        auto context=parent();reset(context);licenseAllowed=false;
        context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};const int gates=licenseCalls;
        failure(invoke(@[enabled],context),@"license_required task=40");assert(licenseCalls==gates+1&&awakePending.count==0);
        context=parent();reset(context);[context.cancellationToken cancel];const unsigned enqueues=awakeEnqueues;
        failure(invoke(@[enabled],context),@"AbortError");assert(awakeEnqueues==enqueues&&awakePending.count==0);
        context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
        failure(invoke(@[enabled],context),@"TimeoutError");assert(awakePending.count==0);
        context=parent();reset(context);stopInLicense=true;
        failure(invoke(@[enabled],context),@"AbortError");assert(awakePending.count==0);
        context=parent(0.01);reset(context);licenseDelayMs=30;
        failure(invoke(@[enabled],context),@"TimeoutError");assert(awakePending.count==0);
    }
    auto context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;
    awakeOnEnqueue=[token]{[token cancel];};failure(invoke(@[@1],context),@"AbortError");
    assert(awakePending.count==1&&awakeApplied.empty());awakeDrain();assert(awakeApplied==std::vector<bool>({true}));
    context=parent(0.01);reset(context);awakeOnEnqueue=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
    failure(invoke(@[@0],context),@"TimeoutError");assert(awakePending.count==1);awakeDrain();assert(!awakeState);
    for(unsigned fault:{1U,2U,3U,4U}){
        context=parent();reset(context);awakeFault=fault;failure(invoke(@[@1],context),@"native_exception");
        assert(awakePending.count==(fault>=3?1U:0U));awakeDrain();
    }
    // Enqueue ACK precedes application; caller teardown/cancel cannot retract accepted work.
    context=parent();reset(context);NSDictionary *retained=nil;
    @autoreleasepool{retained=invoke(@[@1],context);assert([retained[@"ok"] boolValue]&&awakeApplied.empty());}
    [context.cancellationToken cancel];context=nil;awakeDrain();assert(awakeState&&[retained[@"raw"] isEqualToString:@"0\r\n"]);
    context=parent();reset(context);
    for(NSNumber *value in @[@1,@0,@1,@0])assert([invoke(@[value],context)[@"ok"] boolValue]);
    assert(awakePending.count==4&&awakeApplied.empty());awakeDrain();assert(awakeApplied==std::vector<bool>({true,false,true,false}));
    awakeApplied.clear();awakePending=nil;awakeBudget.reset();licenseBudget.reset();awakeOnEnqueue={};awakeFault=0;touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed keep awake passed: frozen JS/RAW normalization/replies, one task-40 gate for enable/disable, stop/output/fault bounds, enqueue ACK and ordered late main effects, pool lifetime and no typed RAW dispatch/response vector.");
}
