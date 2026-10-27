// Actual Process selector/KVC/URL-like handling and RAW parser; controlled LS proxy, real NSURL/Objective-C dispatch.
static id appPathsBundleURL=nil,appPathsDataURL=nil,appPathsContainerURL=nil;
static unsigned appPathsReads=0,appPathsMask=0,appPathsFault=0;
static int appPathsFaultStage=0;
static bool appPathsMissing=false;
static NSString *appPathsBundle=nil;
static std::vector<int> appPathsOrder;
static TLinkNativeBudgetPtr appPathsBudget;
static std::function<void(int)> appPathsOnRead;
static void appPathsObserve(int stage){
    ++appPathsReads;appPathsOrder.push_back(stage);appPathsBudget=TLinkCurrentNativeBudget();assert(appPathsBudget&&!appPathsBudget->cleanup());
    if(stage==appPathsFaultStage&&appPathsFault==1)[NSException raise:@"AppPathsFixture" format:@"path boundary throws"];
    if(stage==appPathsFaultStage&&appPathsFault==2)throw std::runtime_error("path boundary throws");
    if(appPathsOnRead)appPathsOnRead(stage);
}
@interface NativePathLikeFixture : NSObject {NSString *_pathValue;}
- (instancetype)initWithValue:(NSString *)value;
- (NSString *)path;
@end
@implementation NativePathLikeFixture
- (instancetype)initWithValue:(NSString *)value {self=[super init];if(self)_pathValue=value;return self;}
- (NSString *)path {appPathsObserve(8);return _pathValue;}
@end
@interface NativePathsProxyFixture : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
- (id)bundleURL;
- (id)dataContainerURL;
@end
static NativePathsProxyFixture *pathsProxy=nil;
@implementation NativePathsProxyFixture
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier {appPathsBundle=[identifier copy];appPathsObserve(0);return appPathsMissing?nil:pathsProxy;}
- (BOOL)respondsToSelector:(SEL)selector {
    if(sel_isEqual(selector,@selector(bundleURL))){appPathsObserve(1);return (appPathsMask&1)!=0;}
    if(sel_isEqual(selector,@selector(dataContainerURL))){appPathsObserve(4);return (appPathsMask&2)!=0;}
    return [super respondsToSelector:selector];
}
- (id)bundleURL {appPathsObserve(2);return appPathsBundleURL;}
- (id)dataContainerURL {appPathsObserve(5);return appPathsDataURL;}
- (id)valueForKey:(NSString *)key {
    if([key isEqualToString:@"bundleURL"]){appPathsObserve(3);return appPathsBundleURL;}
    if([key isEqualToString:@"dataContainerURL"]){appPathsObserve(6);return appPathsDataURL;}
    if([key isEqualToString:@"containerURL"]){appPathsObserve(7);return appPathsContainerURL;}
    return [super valueForKey:key];
}
@end
#include "PathFromURLLikeUnderTest.inc"
#define LSApplicationProxy NativePathsProxyFixture
#include "AppPathsCoreUnderTest.inc"
#define appPathsFromRawData legacyAppPathsFromRawData
#include "fixtures/app-paths-core-legacy-v1.inc"
#undef appPathsFromRawData
#undef LSApplicationProxy
static void appPathsLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_APP_PATHS;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=52\r\n",writeStreamRef);return;}
    if(false){}
#define appPathsFromRawData legacyAppPathsFromRawData
#include "fixtures/app-paths-handler-legacy-v1.inc"
#undef appPathsFromRawData
}
static void typedAppPathsCases(TLinkInProcessNativeBridge *bridge){
    mode=@"appPathsRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,id bundle,id data,id container,unsigned mask=3,bool missing=false){
        appPathsBundleURL=bundle;appPathsDataURL=data;appPathsContainerURL=container;appPathsMask=mask;appPathsMissing=missing;
        appPathsFault=0;appPathsFaultStage=0;appPathsOnRead={};appPathsOrder.clear();appPathsBundle=nil;pathsProxy=[NativePathsProxyFixture new];
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodAppPaths arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,id bundle,id data,id container,unsigned mask,bool missing,NSUInteger cap,int nsFault=-1)->NSUInteger{
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context,bundle,data,container,mask,missing);
        if(nsFault>=0){appPathsFaultStage=nsFault;appPathsFault=1;}
        const unsigned oldReads=appPathsReads;const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyAppQuery:request(args) context:context];NSString *identifier=appPathsBundle;const auto order=appPathsOrder;
        const unsigned delta=appPathsReads-oldReads;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(context,bundle,data,container,mask,missing);if(nsFault>=0){appPathsFaultStage=nsFault;appPathsFault=1;}
        const unsigned reads=appPathsReads;const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(appPathsReads==reads+delta&&appPathsOrder==order&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        assert((appPathsBundle==identifier)||[appPathsBundle isEqual:identifier]);
        if(delta)assert(lastLicenseTask==TASK_APP_PATHS&&!appPathsBudget->cleanup()&&!appPathsBudget->capturesResponse()&&appPathsBudget->response().capacity()==0);
        return [expected.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    NSURL *bundleURL=[NSURL fileURLWithPath:@"/Applications/Example App.app"],*dataURL=[NSURL fileURLWithPath:@"/var/mobile/Containers/Data/ứng.dụng"];
    NSURL *containerURL=[NSURL fileURLWithPath:@"/fallback/container"];
    for(int n=0;n<160;++n)parity(@[[NSString stringWithFormat:@"com.example.paths%d",n]],bundleURL,n%3?dataURL:nil,containerURL,unsigned(n%4),bool(n%11==0),1024*1024);
    for(unsigned mask:{0U,1U,2U,3U}){
        parity(@[@"com.app"],nil,nil,containerURL,mask,false,1024);
        parity(@[@"com.app"],[NSNull null],[NSNull null],containerURL,mask,false,1024);
        parity(@[@"com.app"],@17,@"not-a-path-object",containerURL,mask,false,1024);
    }
    NSString *nul=[NSString stringWithFormat:@"/visible%C/ignored",(unichar)0];
    const unichar invalidUTF16=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *edges=[@[@"",@"/",@"/普通/ứng dụng",@"/a;;/shift",@"/a\r\n",@"/a\u2028",nul] mutableCopy];if(invalid)[edges addObject:invalid];
    for(NSString *edge in edges){
        NativePathLikeFixture *path=[[NativePathLikeFixture alloc] initWithValue:edge];
        for(unsigned side:{0U,1U}){
            id bundle=side?bundleURL:path,idData=side?path:dataURL;
            const NSUInteger bytes=parity(@[@"com.app"],bundle,idData,containerURL,3,false,1024*1024);assert(bytes>1);
            parity(@[@"com.app"],bundle,idData,containerURL,3,false,bytes);parity(@[@"com.app"],bundle,idData,containerURL,3,false,bytes-1);
        }
    }
    NativePathLikeFixture *nilPath=[[NativePathLikeFixture alloc] initWithValue:nil];parity(@[@"com.app"],nilPath,nilPath,nil,3,false,1024);
    // KVC NSExceptions are swallowed exactly where the production backend specifies.
    for(int stage:{3,6,7})parity(@[@"com.app"],bundleURL,nil,containerURL,0,false,1024,stage);
    NSString *inputNul=[NSString stringWithFormat:@"app%Ctail",(unichar)0];
    NSMutableArray *inputs=[@[@[],@[@0],@[[NSNull null]],@[@""],@[@"a;;b"],@[@"a\r"],@[@"a\n"],@[inputNul],@[@"ứng.dụng.测试"],@[@"app😀"],@[@"com.app",@"ignored"]] mutableCopy];if(invalid)[inputs addObject:@[invalid]];
    for(NSArray *args in inputs)parity(args,bundleURL,dataURL,containerURL,3,false,1024);
    for(NSString *unit in @[@"x",@"界",@"😀"]){
        NSString *exact=[@"" stringByPaddingToLength:8190 withString:unit startingAtIndex:0];
        parity(@[exact],bundleURL,dataURL,containerURL,3,false,1024);parity(@[[exact stringByAppendingString:@"x"]],bundleURL,dataURL,containerURL,3,false,1024);
    }
    auto context=parent();reset(context,bundleURL,dataURL,containerURL);unsigned reads=appPathsReads;int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@"com.app"],context).value,@"license_required task=52");assert(appPathsReads==reads&&licenseCalls==gates+1);
    context=parent();reset(context,bundleURL,dataURL,containerURL);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appPathsReads==reads&&licenseCalls==gates);
    context=parent();reset(context,bundleURL,dataURL,containerURL);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appPathsReads==reads&&licenseCalls==gates);
    context=parent();reset(context,bundleURL,dataURL,containerURL);stopInLicense=true;failure(invoke(@[@"com.app"],context).value,@"AbortError");assert(appPathsReads==reads);
    context=parent(0.01);reset(context,bundleURL,dataURL,containerURL);licenseDelayMs=30;failure(invoke(@[@"com.app"],context).value,@"TimeoutError");assert(appPathsReads==reads);
    context=parent();reset(context,bundleURL,dataURL,containerURL);TLinkCancellationToken *token=context.cancellationToken;
    appPathsOnRead=[token](int stage){if(stage==2)[token cancel];};failure(invoke(@[@"com.app"],context).value,@"AbortError");
    context=parent(0.01);reset(context,bundleURL,dataURL,containerURL);appPathsOnRead=[](int stage){if(stage==5)std::this_thread::sleep_for(std::chrono::milliseconds(30));};failure(invoke(@[@"com.app"],context).value,@"TimeoutError");
    for(int stage:{0,1,2,4,5,8})for(unsigned fault:{1U,2U}){
        context=parent();reset(context,nilPath,nilPath,nil);appPathsFaultStage=stage;appPathsFault=fault;failure(invoke(@[@"com.app"],context).value,@"native_exception");
    }
    for(int stage:{3,6,7}){context=parent();reset(context,bundleURL,nil,containerURL,0);appPathsFaultStage=stage;appPathsFault=2;failure(invoke(@[@"com.app"],context).value,@"native_exception");}
    for(NSString *raw in @[@"",@"com.app",@"ứng.dụng.测试",@"a;;b",@"a\r\n",inputNul]){
        context=parent();reset(context,bundleURL,dataURL,containerURL);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);
        NSError *oldError=nil;NSString *expected=legacyAppPathsFromRawData((UInt8 *)raw.UTF8String,&oldError);NSString *identifier=appPathsBundle;
        appPathsBundle=nil;NSError *error=nil;NSString *actual=appPathsFromRawData((UInt8 *)raw.UTF8String,&error);
        assert((actual==expected)||[actual isEqual:expected]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);assert((appPathsBundle==identifier)||[appPathsBundle isEqual:identifier]);
    }
    NSMutableString *pathValue=[NSMutableString stringWithString:@"/snapshot/path"],*input=[NSMutableString stringWithString:@"com.original"];
    NativePathLikeFixture *path=[[NativePathLikeFixture alloc] initWithValue:pathValue];context=parent();reset(context,path,dataURL,containerURL);NSDictionary *held=nil;
    @autoreleasepool{held=invoke(@[input],context).value;context=nil;pathsProxy=nil;}
    [pathValue appendString:@"/changed"];[input appendString:@".changed"];
    assert([held[@"bundlePath"] isEqualToString:@"/snapshot/path"]&&[held[@"dataPath"] isEqualToString:dataURL.path]&&!held[@"bundleId"]&&!held[@"state"]&&!held[@"pid"]);
    NSError *heldError=nil;@autoreleasepool{assert(!appPathsForBundleIdentifier(@"",&heldError));}assert([heldError.localizedDescription isEqualToString:@"-1;;Missing bundle identifier.\r\n"]);
    reads=appPathsReads;gates=licenseCalls;failure(TLinkExecuteNativeAppPaths(nil,parent()),@"invalid_payload");assert(appPathsReads==reads&&licenseCalls==gates);
    pathsProxy=nil;appPathsBundleURL=nil;appPathsDataURL=nil;appPathsContainerURL=nil;appPathsBundle=nil;appPathsOrder.clear();appPathsOnRead={};appPathsBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed app paths passed: frozen JS/RAW/core parity, actual selector/KVC/fallback and URL-like handling, nil/NSNull distinction, multipart/NUL/encoding/output, exact Unicode ingress, task-52 authority/stop/faults and snapshot/error/result pool lifetime. Private LS qualification pending.");
}
