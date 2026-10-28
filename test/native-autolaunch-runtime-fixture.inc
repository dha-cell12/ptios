// Actual shared flock/atomic persistence and list codec; a private temporary document root.
#include "../shared/TLinkAutoLaunchConfig.h"
static NSString *autoLaunchRoot=nil,*autoLaunchRootOverride=nil;
static NSData *autoLaunchSeed=nil;
static unsigned autoLaunchRoots=0,autoLaunchUpdates=0,autoLaunchCommits=0,autoLaunchFault=0;
static NSString *autoLaunchFaultStage=nil;
static TLinkNativeBudgetPtr autoLaunchBudget;
static std::vector<std::string> autoLaunchOrder;
static std::function<void(NSString *)> autoLaunchOnStage;
static std::function<void()> autoLaunchOnBool;
@interface NativeAutoLaunchBoolFixture : NSObject
- (BOOL)boolValue;
@end
@implementation NativeAutoLaunchBoolFixture
- (BOOL)boolValue {if(autoLaunchOnBool)autoLaunchOnBool();return true;}
@end
static void autoLaunchObserve(NSString *stage){
    autoLaunchOrder.push_back(stage.UTF8String);autoLaunchBudget=TLinkCurrentNativeBudget();assert(autoLaunchBudget&&!autoLaunchBudget->cleanup());
    if([stage isEqual:autoLaunchFaultStage]&&autoLaunchFault==1)[NSException raise:@"AutoLaunchFixture" format:@"provider throws"];
    if([stage isEqual:autoLaunchFaultStage]&&autoLaunchFault==2)throw std::runtime_error("auto-launch provider throws");
    if(autoLaunchOnStage)autoLaunchOnStage(stage);
}
static NSString *autoLaunchDocumentRoot(){++autoLaunchRoots;autoLaunchObserve(@"root");return autoLaunchRootOverride?:autoLaunchRoot;}
static BOOL autoLaunchTransaction(NSString *path,NSString *name,NSDictionary *entry,NSError **error){
    ++autoLaunchUpdates;autoLaunchObserve(@"before");
    BOOL saved=TLinkAutoLaunchSetEntry(path,name,entry,error);if(saved)++autoLaunchCommits;
    autoLaunchObserve(@"after");return saved;
}
static NSString *const kAutoLaunchFileName=@"autolaunch.plist";
#define getDocumentRoot autoLaunchDocumentRoot
#include "AutoLaunchError.inc"
NSString* TLinkSetAutoLaunch(NSString *,NSString *,BOOL,NSError **);
#define TLinkAutoLaunchSetEntry autoLaunchTransaction
#include "AutoLaunchCoreUnderTest.inc"
#define autoLaunchFilePath legacyAutoLaunchFilePath
#define loadAutoLaunchConfig legacyLoadAutoLaunchConfig
#define setAutoLaunchFromRawData legacySetAutoLaunchFromRawData
#define listAutoLaunch legacyListAutoLaunch
#include "LegacyAutoLaunchCore.inc"
#undef listAutoLaunch
#undef setAutoLaunchFromRawData
#undef loadAutoLaunchConfig
#undef autoLaunchFilePath
#undef TLinkAutoLaunchSetEntry
#undef getDocumentRoot
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeAutoLaunchEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void autoLaunchLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=(bytes[0]-'0')*10+bytes[1]-'0';UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){NSString *denial=[NSString stringWithFormat:@"-1;;license_required task=%d\r\n",taskType];notifyClient((UInt8 *)denial.UTF8String,writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#define setAutoLaunchFromRawData legacySetAutoLaunchFromRawData
#define listAutoLaunch legacyListAutoLaunch
#include "fixtures/autolaunch-handler-legacy-v1.inc"
#undef listAutoLaunch
#undef setAutoLaunchFromRawData
}
static NSData *autoLaunchEncode(id value){
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];assert(data);return data;
}
static NSString *autoLaunchFixturePath(){return [autoLaunchRoot stringByAppendingPathComponent:kAutoLaunchFileName];}
static id autoLaunchSnapshot(){
    NSData *data=[NSData dataWithContentsOfFile:autoLaunchFixturePath()];
    id value=data?[NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL]:nil;return value?:data;
}
static void typedAutoLaunchCases(TLinkInProcessNativeBridge *bridge){
    mode=@"autoLaunchRuntime";
    autoLaunchRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-native-autolaunch-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    NSFileManager *fm=[NSFileManager defaultManager];bool created=[fm createDirectoryAtPath:autoLaunchRoot withIntermediateDirectories:false attributes:nil error:NULL];assert(created);
    autoLaunchSeed=autoLaunchEncode(@{@"legacy":@{@"script":@"old",@"enabled":@(false),@"unknown":@42},@"skip":@17});
    const auto reset=[](TLinkTaskExecutionContext *context){
        NSFileManager *manager=[NSFileManager defaultManager];NSString *path=autoLaunchFixturePath();
        if([manager fileExistsAtPath:path])assert([manager removeItemAtPath:path error:NULL]);
        [manager removeItemAtPath:[path stringByAppendingString:@".lock"] error:NULL];
        if(autoLaunchSeed)assert([autoLaunchSeed writeToFile:path atomically:true]);
        autoLaunchRootOverride=nil;autoLaunchRoots=autoLaunchUpdates=autoLaunchCommits=autoLaunchFault=0;autoLaunchFaultStage=nil;
        autoLaunchBudget.reset();autoLaunchOrder.clear();autoLaunchOnStage={};autoLaunchOnBool={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](bool list,NSArray *args)->TLinkJSNativeRequest *{
        return [[TLinkJSNativeRequest alloc] initWithMethod:list?TLinkJSNativeMethodListAutoLaunch:TLinkJSNativeMethodSetAutoLaunch arguments:args];
    };
    const auto invoke=[bridge,request](bool list,NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(list,args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](bool list,NSArray *args,NSUInteger cap){
        auto context=parent(30,cap);reset(context);int gates=licenseCalls;TLinkJSNativeResponse *expected=[bridge legacyAutoLaunch:request(list,args) context:context];
        id state=autoLaunchSnapshot();const auto order=autoLaunchOrder;const unsigned roots=autoLaunchRoots,updates=autoLaunchUpdates,commits=autoLaunchCommits;const int gateDelta=licenseCalls-gates;
        context=parent(30,cap);reset(context);gates=licenseCalls;const int rawCalls=calls;TLinkJSNativeResponse *actual=invoke(list,args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        id actualState=autoLaunchSnapshot();assert((actualState==state)||[actualState isEqual:state]);
        assert(autoLaunchRoots==roots&&autoLaunchUpdates==updates&&autoLaunchCommits==commits&&autoLaunchOrder==order&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        if(gateDelta)assert(lastLicenseTask==(list?37:36));
        if(roots)assert(autoLaunchBudget&&!autoLaunchBudget->capturesResponse()&&autoLaunchBudget->response().capacity()==0);
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    for(unsigned n=0;n<160;++n)parity(false,@[[NSString stringWithFormat:@"entry-%u",n],[NSString stringWithFormat:@"/script/测试-%u.js",n],@(n%2)],4096);
    for(id name in @[@"job",@"Ứng dụng 😀",@"a;",@";",@"a,,b",@" space "])for(id script in @[@"/script.js",@"b;",@";path",@"3",@"路径"]){parity(false,@[name,script,@1],4096);}
    for(id value in @[@0,@1,@(-1),@17,@"YES",@"false",@"1",@""])parity(false,@[@"job",@"/script",value],4096);
    parity(false,@[@"job",@"/script"],4096);parity(false,@[@"job",@"/script",@1,@"ignored"],4096);
    for(id invalid in @[@"",@"a;;b",@"a\r",@"a\n",[NSNull null],@17]){parity(false,@[invalid,@"/script"],4096);parity(false,@[@"job",invalid],4096);}
    parity(false,@[],4096);parity(false,@[@"job"],4096);
    for(bool list:{false,true}){const NSUInteger bytes=parity(list,list?@[]:@[@"job",@"/script",@1],4096);assert(bytes>1);parity(list,list?@[]:@[@"job",@"/script",@1],bytes);parity(list,list?@[]:@[@"job",@"/script",@1],bytes-1);}
    for(NSString *unit in @[@"x",@"界"])for(bool name:{false,true}){
        NSString *exact=[@"" stringByPaddingToLength:8184 withString:unit startingAtIndex:0];
        parity(false,name?@[exact,@"s",@1]:@[@"n",exact,@1],4096);parity(false,name?@[[exact stringByAppendingString:@"x"],@"s",@1]:@[@"n",[exact stringByAppendingString:@"x"],@1],4096);
    }
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];
    parity(false,@[nul,@"script",@1],4096);parity(false,@[@"job",nul,@1],4096);if(invalid){parity(false,@[invalid,@"s"],4096);parity(false,@[@"n",invalid],4096);}
    for(id config in @[@{},@{@"entry":@{@"script":@"x",@"enabled":@1}},@{@"a,,b":@{@"script":@"x;;y\r\n",@"enabled":@"YES"},@"skip":@1},@{@"x":@{@"script":@17,@"enabled":[NSNull null]}},@{@"x":@{@"script":nul,@"enabled":@1}},@[]]){
        autoLaunchSeed=autoLaunchEncode(config);const NSUInteger bytes=parity(true,@[@"ignored"],4096);assert(bytes>0);parity(true,@[],bytes);if(bytes>1)parity(true,@[],bytes-1);
    }
    for(NSData *seed in @[[NSData data],[@"broken plist" dataUsingEncoding:NSUTF8StringEncoding],autoLaunchEncode(@[])]){
        autoLaunchSeed=seed;parity(true,@[],4096);parity(false,@[@"job",@"script",@1],4096);
    }
    autoLaunchSeed=nil;parity(true,@[],4096);parity(false,@[@"job",@"script",@1],4096);
    autoLaunchSeed=autoLaunchEncode(@{@"legacy":@{@"script":@"old",@"enabled":@(false),@"unknown":@42}});
    for(bool list:{false,true}){
        auto context=parent();reset(context);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(list,@[@"job",@"script",@1],context).value,list?@"license_required task=37":@"license_required task=36");assert(!autoLaunchRoots&&!autoLaunchCommits);
        context=parent();reset(context);const int gates=licenseCalls;[context.cancellationToken cancel];failure(invoke(list,@[@"job",@"script",@1],context).value,@"AbortError");assert(licenseCalls==gates&&!autoLaunchRoots);
        context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(list,@[@"job",@"script",@1],context).value,@"TimeoutError");assert(licenseCalls==gates&&!autoLaunchRoots);
        context=parent();reset(context);stopInLicense=true;failure(invoke(list,@[@"job",@"script",@1],context).value,@"AbortError");assert(!autoLaunchRoots);
        context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(list,@[@"job",@"script",@1],context).value,@"TimeoutError");assert(!autoLaunchRoots);
        context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;autoLaunchOnStage=[token](NSString *stage){if([stage isEqualToString:@"root"])[token cancel];};
        failure(invoke(list,@[@"job",@"script",@1],context).value,@"AbortError");assert(autoLaunchRoots==1&&autoLaunchCommits==(list?0U:1U));
        context=parent(0.1);reset(context);autoLaunchOnStage=[](NSString *stage){if([stage isEqualToString:@"root"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};
        failure(invoke(list,@[@"job",@"script",@1],context).value,@"TimeoutError");assert(autoLaunchRoots==1&&autoLaunchCommits==(list?0U:1U));
        for(unsigned fault:{1U,2U}){context=parent();reset(context);autoLaunchFault=fault;autoLaunchFaultStage=@"root";failure(invoke(list,@[@"job",@"script",@1],context).value,@"native_exception");assert(!autoLaunchCommits);}
    }
    for(unsigned fault:{1U,2U})for(NSString *stage in @[@"before",@"after"]){auto context=parent();reset(context);autoLaunchFault=fault;autoLaunchFaultStage=stage;
        failure(invoke(false,@[@"job",@"script",@1],context).value,@"native_exception");assert(autoLaunchCommits==([stage isEqualToString:@"after"]?1U:0U));}
    auto context=parent(1,2);reset(context);failure(invoke(false,@[@"job",@"script",@1],context).value,@"response_too_large");assert(autoLaunchCommits==1&&[autoLaunchSnapshot()[@"job"][@"script"] isEqualToString:@"script"]);
    context=parent();reset(context);NSString *lock=[autoLaunchFixturePath() stringByAppendingString:@".lock"];
    assert([fm createSymbolicLinkAtPath:lock withDestinationPath:[autoLaunchRoot stringByAppendingPathComponent:@"absent/file"] error:NULL]);
    failure(invoke(false,@[@"job",@"script",@1],context).value,@"Failed to lock auto launch config.");assert(!autoLaunchCommits);
    context=parent();reset(context);NSString *blocked=[autoLaunchRoot stringByAppendingPathComponent:@"blocked"];
    assert([[@"file" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:blocked atomically:true]);autoLaunchRootOverride=[blocked stringByAppendingPathComponent:@"child"];
    failure(invoke(false,@[@"job",@"script",@1],context).value,@"Failed to create auto launch directory.");assert(!autoLaunchCommits);
    context=parent();reset(context);NSMutableString *name=[@"snapshot" mutableCopy],*script=[@"original" mutableCopy];autoLaunchOnStage=[name,script](NSString *stage){if([stage isEqualToString:@"root"]){[name setString:@"changed"];[script setString:@"changed"];}};
    NSDictionary *held=nil;@autoreleasepool{held=invoke(false,@[name,script,@1],context).value;context=nil;}assert([held[@"ok"] boolValue]&&[autoLaunchSnapshot()[@"snapshot"][@"script"] isEqualToString:@"original"]);
    context=parent();reset(context);NativeAutoLaunchBoolFixture *enabled=[NativeAutoLaunchBoolFixture new];TLinkCancellationToken *token=context.cancellationToken;
    autoLaunchOnBool=[token]{[token cancel];};const int boolGates=licenseCalls;
    failure(invoke(false,@[@"job",@"script",enabled],context).value,@"AbortError");assert(licenseCalls==boolGates&&!autoLaunchRoots);
    // boolValue is intentionally left at the unchanged JS boundary; unsupported objects throw there.
    for(bool legacy:{false,true}){context=parent();reset(context);unsigned exceptions=0;const int gates=licenseCalls;
        @try{if(legacy)[bridge legacyAutoLaunch:request(false,@[@"job",@"script",[NSNull null]]) context:context];else invoke(false,@[@"job",@"script",[NSNull null]],context);}
        @catch(NSException *exception){(void)exception;++exceptions;}assert(exceptions==1&&licenseCalls==gates&&!autoLaunchRoots&&!TLinkCurrentNativeBudget());}
    for(NSString *raw in @[@"",@"a;;b",@";;script;;1",@"name;;;;1",@"job;;path;;-2;;ignored",@"a;;;path;;1"]){
        context=parent();reset(context);NSError *oldError=nil,*error=nil;NSString *expected=nil,*actual=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);expected=legacySetAutoLaunchFromRawData((UInt8 *)raw.UTF8String,&oldError);}id state=autoLaunchSnapshot();reset(context);
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);actual=setAutoLaunchFromRawData((UInt8 *)raw.UTF8String,&error);}
        assert((actual==expected)||[actual isEqual:expected]);assert((error==oldError)||[error.localizedDescription isEqual:oldError.localizedDescription]);id actualState=autoLaunchSnapshot();assert((actualState==state)||[actualState isEqual:state]);
    }
    for(unsigned n=0;n<64;++n){context=parent();reset(context);assert([invoke(false,@[@"cycle",@"script",@(n%2)],context).value[@"ok"] boolValue]);NSDictionary *result=invoke(true,@[],context).value;assert([result[@"ok"] boolValue]&&[result[@"items"] count]==2);}
    context=parent();reset(context);NSError *sentinel=[NSError errorWithDomain:@"fixture" code:7 userInfo:nil],*untouched=sentinel;
    {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);listAutoLaunch(&untouched);}assert(untouched==sentinel);
    assert([fm removeItemAtPath:autoLaunchRoot error:NULL]);autoLaunchRoot=nil;autoLaunchRootOverride=nil;autoLaunchSeed=nil;autoLaunchBudget.reset();autoLaunchFaultStage=nil;autoLaunchOrder.clear();autoLaunchOnStage={};autoLaunchOnBool={};licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed auto-launch passed: actual flock/atomic persistence/list codec with frozen JS/RAW file/reply/metadata parity, delimiter overlap, ingress/output/task-36/37 authority, malformed/lock/directory errors, opaque stop/fault/commit behavior, snapshots and repeated lifecycles. Only private temporary config changed.");
}
