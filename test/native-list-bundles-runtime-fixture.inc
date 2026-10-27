// Actual workspace/selector/KVC/JSON core and typed entry; controlled LS objects, real Foundation codecs.
static int bundlesMode=3,bundlesFaultStage=-1;
static unsigned bundlesFault=0,bundlesJSONFailure=0,bundlesKVCThrows=0;
static NSArray *bundlesApps=nil;
static NSData *bundlesJSONData=nil;
static std::vector<int> bundlesOrder;
static TLinkNativeBudgetPtr bundlesBudget;
static std::function<void(int)> bundlesOnRead;
static void bundlesObserve(int stage){
    bundlesOrder.push_back(stage);bundlesBudget=TLinkCurrentNativeBudget();assert(bundlesBudget&&!bundlesBudget->cleanup());
    if(stage==bundlesFaultStage&&bundlesFault==1)[NSException raise:@"BundlesFixture" format:@"boundary throws"];
    if(stage==bundlesFaultStage&&bundlesFault==2)throw std::runtime_error("boundary throws");
    if(bundlesOnRead)bundlesOnRead(stage);
}
@interface NativeBundleProxyFixture : NSObject
@property(nonatomic,strong) NSArray *fields;
@property(nonatomic) unsigned mask;
- (NSString *)bundleIdentifier;
- (NSString *)localizedName;
- (NSString *)shortVersionString;
- (NSString *)bundleVersion;
@end
static int bundlesField(NSString *key){return [@[@"bundleIdentifier",@"localizedName",@"shortVersionString",@"bundleVersion"] indexOfObject:key]==NSNotFound?-1:int([@[@"bundleIdentifier",@"localizedName",@"shortVersionString",@"bundleVersion"] indexOfObject:key]);}
@implementation NativeBundleProxyFixture
- (BOOL)respondsToSelector:(SEL)selector {
    const int field=bundlesField(NSStringFromSelector(selector));
    if(field>=0){bundlesObserve(100+field);return (self.mask&(1U<<field))!=0;}
    return [super respondsToSelector:selector];
}
- (id)valueForKey:(NSString *)key {
    const int field=bundlesField(key);if(field<0)return [super valueForKey:key];
    bundlesObserve(300+field);if(bundlesKVCThrows&(1U<<field))[NSException raise:@"BundlesFixture" format:@"KVC unavailable"];
    id value=self.fields[NSUInteger(field)];return value==[NSNull null]?nil:value;
}
- (NSString *)bundleIdentifier {bundlesObserve(200);id value=self.fields[0];return value==[NSNull null]?nil:value;}
- (NSString *)localizedName {bundlesObserve(201);id value=self.fields[1];return value==[NSNull null]?nil:value;}
- (NSString *)shortVersionString {bundlesObserve(202);id value=self.fields[2];return value==[NSNull null]?nil:value;}
- (NSString *)bundleVersion {bundlesObserve(203);id value=self.fields[3];return value==[NSNull null]?nil:value;}
@end
@interface NativeBundleWorkspaceFixture : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (NSArray *)allApplications;
@end
static NativeBundleWorkspaceFixture *bundlesWorkspace=nil;
@implementation NativeBundleWorkspaceFixture
+ (BOOL)respondsToSelector:(SEL)selector {
    if(sel_isEqual(selector,@selector(defaultWorkspace))){bundlesObserve(1);return bundlesMode!=1;}
    return [super respondsToSelector:selector];
}
+ (instancetype)defaultWorkspace {bundlesObserve(2);return bundlesMode==2?nil:bundlesWorkspace;}
- (BOOL)respondsToSelector:(SEL)selector {
    if(sel_isEqual(selector,@selector(allInstalledApplications))){bundlesObserve(3);return bundlesMode==3||bundlesMode==6;}
    if(sel_isEqual(selector,@selector(allApplications))){bundlesObserve(4);return bundlesMode==3||bundlesMode==4;}
    return [super respondsToSelector:selector];
}
- (NSArray *)allInstalledApplications {bundlesObserve(5);return bundlesMode==6?nil:bundlesApps;}
- (NSArray *)allApplications {bundlesObserve(6);return bundlesApps;}
@end
static Class bundlesClass(NSString *name){assert([name isEqualToString:@"LSApplicationWorkspace"]);bundlesObserve(0);return bundlesMode==0?Nil:[NativeBundleWorkspaceFixture class];}
@interface NativeBundlesJSONFixture : NSObject
+ (NSData *)dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error;
@end
@implementation NativeBundlesJSONFixture
+ (NSData *)dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error {
    bundlesObserve(400);assert(options==0);bundlesJSONData=[NSJSONSerialization dataWithJSONObject:object options:options error:error];
    if(bundlesJSONFailure==1)return nil;
    if(bundlesJSONFailure==2&&error)*error=[NSError errorWithDomain:@"BundlesFixture" code:1 userInfo:nil];
    return bundlesJSONData;
}
@end
NSString *listBundlesWithInfo(BOOL,NSError **);
#include "SafeStringUnderTest.inc"
#define NSClassFromString bundlesClass
#define NSJSONSerialization NativeBundlesJSONFixture
#include "ListBundlesCoreUnderTest.inc"
#define zx_safeString legacyBundlesSafeString
#include "fixtures/safe-string-legacy-v1.inc"
#define listBundlesFromRawData legacyListBundlesFromRawData
#include "fixtures/list-bundles-core-legacy-v1.inc"
#undef listBundlesFromRawData
#undef zx_safeString
#undef NSJSONSerialization
#undef NSClassFromString
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeListBundlesEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void listBundlesLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_LIST_BUNDLES;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=53\r\n",writeStreamRef);return;}
    if(false){}
#define listBundlesFromRawData legacyListBundlesFromRawData
#include "fixtures/list-bundles-handler-legacy-v1.inc"
#undef listBundlesFromRawData
}
static void typedListBundlesCases(TLinkInProcessNativeBridge *bridge){
    mode=@"listBundlesRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,int selection=3){
        bundlesMode=selection;bundlesFaultStage=-1;bundlesFault=bundlesJSONFailure=bundlesKVCThrows=0;
        bundlesOrder.clear();bundlesJSONData=nil;bundlesBudget.reset();bundlesOnRead={};bundlesWorkspace=[NativeBundleWorkspaceFixture new];
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto proxy=[](NSArray *fields,unsigned mask)->NativeBundleProxyFixture *{NativeBundleProxyFixture *p=[NativeBundleProxyFixture new];p.fields=fields;p.mask=mask;return p;};
    const auto decode=[](NSString *body)->id {NSData *data=[[NSData alloc] initWithBase64EncodedString:body options:0];return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;};
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodListBundles arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,decode,request,invoke](NSArray *args,int selection,NSUInteger cap,unsigned kvc=0)->NSUInteger{
        const bool info=args.count&&[args[0] boolValue];TLinkTaskExecutionContext *context=parent(1,cap);reset(context,selection);bundlesKVCThrows=kvc;
        const int oldGates=licenseCalls;TLinkJSNativeResponse *expected=[bridge legacyListBundles:request(args) context:context];const auto order=bundlesOrder;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(context,selection);bundlesKVCThrows=kvc;const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);NSDictionary *want=expected.value,*got=actual.value;
        assert(actual.ok==expected.ok&&actual.ok&&bundlesOrder==order&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        if(info&&[want[@"ok"] boolValue]){
            // Foundation JSON dictionary key order is unspecified; compare decoded payloads and exact captured wire.
            assert([decode(got[@"parts"][1]) isEqual:decode(want[@"parts"][1])]&&[got[@"items"] isEqual:want[@"items"]]);
            NSString *wire=[NSString stringWithFormat:@"0;;%@\r\n",[bundlesJSONData base64EncodedStringWithOptions:0]];
            assert([got[@"raw"] isEqual:wire]&&[got[@"parts"] count]==2&&got.count==want.count);
        }else assert([got isEqual:want]);
        assert(lastLicenseTask==TASK_LIST_BUNDLES);
        if(!bundlesOrder.empty())assert(!bundlesBudget->capturesResponse()&&bundlesBudget->response().capacity()==0&&!bundlesBudget->cleanup());
        return [got[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    NSArray *ordinary=@[@"com.example.app",@"Example",@"1.2",@"123"];
    for(unsigned n=0;n<160;++n){bundlesApps=@[proxy(ordinary,n%16),proxy(@[@"",@"ignored",@"",@""],15),proxy(@[@"com.second",@"Ứng dụng",@"2",@"5"],15)];parity(@[@(n%2)],3,1024*1024);}
    for(int selection:{0,1,2,3,4,5,6})for(bool info:{false,true}){
        bundlesApps=@[proxy(ordinary,15)];const NSUInteger bytes=parity(@[@(info)],selection,1024);
        parity(@[@(info)],selection,bytes);parity(@[@(info)],selection,bytes-1);
    }
    for(NSArray *args in @[@[],@[@0],@[@1],@[@2],@[@-1],@[@"YES"],@[@"true"],@[@"0"],@[@"1"],@[@1,@"ignored"]])parity(args,3,1024);
    NSString *nul=[NSString stringWithFormat:@"visible%Cignored",(unichar)0];
    for(id bid in @[@"",[NSNull null],@"ứng.dụng.测试",@"a,,b",@"a;;b",@"a\r\n",nul]){
        bundlesApps=@[proxy(@[bid,@"Name",@"1",@"2"],15)];for(bool info:{false,true})parity(@[@(info)],3,4096);
    }
    for(unsigned mask:{0U,1U,2U,4U,8U,15U}){
        bundlesApps=@[proxy(@[@"com.app",@17,[NSNull null],@99],mask)];parity(@[@1],3,4096);
        for(unsigned throws:{1U,2U,4U,8U,15U})parity(@[@1],3,4096,throws);
    }
    bundlesApps=@[];parity(@[@0],3,1024);parity(@[@1],3,1024);
    bundlesApps=@[proxy(ordinary,15)];auto context=parent();reset(context);int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@1],context).value,@"license_required task=53");assert(bundlesOrder.empty()&&licenseCalls==gates+1);
    context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@1],context).value,@"AbortError");assert(bundlesOrder.empty()&&licenseCalls==gates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@1],context).value,@"TimeoutError");assert(bundlesOrder.empty()&&licenseCalls==gates);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@1],context).value,@"AbortError");assert(bundlesOrder.empty());
    context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(@[@1],context).value,@"TimeoutError");assert(bundlesOrder.empty());
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;bundlesOnRead=[token](int stage){if(stage==5)[token cancel];};
    failure(invoke(@[@1],context).value,@"AbortError");assert(std::find(bundlesOrder.begin(),bundlesOrder.end(),400)!=bundlesOrder.end());
    context=parent(0.01);reset(context);bundlesOnRead=[](int stage){if(stage==5)std::this_thread::sleep_for(std::chrono::milliseconds(30));};failure(invoke(@[@0],context).value,@"TimeoutError");
    for(unsigned fault:{1U,2U})for(int stage:{0,2,5,200,201,400}){
        context=parent();reset(context);bundlesFault=fault;bundlesFaultStage=stage;failure(invoke(@[@1],context).value,@"native_exception");
    }
    for(unsigned fault:{1U,2U}){context=parent();reset(context);bundlesJSONFailure=fault;failure(invoke(@[@1],context).value,@"Failed to encode bundles JSON.");}
    for(NSString *raw in @[@"",@"0",@"1",@"01",@" 1junk",@"2",@"YES",@"-1",nul]){
        context=parent();reset(context);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *oldError=nil;
        NSString *expected=legacyListBundlesFromRawData((UInt8 *)raw.UTF8String,&oldError);const auto order=bundlesOrder;
        reset(context);NSError *error=nil;NSString *actual=listBundlesFromRawData((UInt8 *)raw.UTF8String,&error);
        assert(!error&&!oldError&&bundlesOrder==order);
        if(raw.intValue==1)assert([decode(actual) isEqual:decode(expected)]);else assert([actual isEqual:expected]);
    }
    context=parent();reset(context);{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *error=nil;assert(listBundlesFromRawData(nullptr,&error)&&!error);}
    for(int selection:{0,2}){context=parent();reset(context,selection);NSError *heldError=nil;@autoreleasepool{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);assert(!listBundlesWithInfo(true,&heldError));}assert(heldError.localizedDescription.length>0);}
    context=parent();reset(context);NSDictionary *held=nil;@autoreleasepool{held=invoke(@[@1],context).value;context=nil;bundlesApps=nil;bundlesWorkspace=nil;bundlesJSONData=nil;}assert([held[@"ok"] boolValue]&&[held[@"items"] count]==1);
    bundlesApps=nil;bundlesWorkspace=nil;bundlesJSONData=nil;bundlesOrder.clear();bundlesOnRead={};bundlesBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed listBundles passed: actual workspace/selector/KVC/JSON/RAW with frozen bridge/task/core parity, fallback precedence, metadata codecs, delimiters/NUL, exact output, task-53 authority/stop/faults and pool lifetime. Private LS/device qualification pending.");
}
