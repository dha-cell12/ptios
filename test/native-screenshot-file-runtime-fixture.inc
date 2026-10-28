// Actual action-1 parser/direct entry/JS; controlled Screen boundary writes only a private PNG.
#include "../shared/TLinkCaptureLease.h"
#include <cfloat>
struct NativeFileLeaseFence {bool matches(const char *)const{return false;}bool valid()const{return false;}};
static NativeFileLeaseFence *fileNoOwner(){return nullptr;}
static NSString *filePrivateOutput=nil,*fileSeenPath=nil,*fileErrorText=nil,*fileReplyPath=nil;
static NSData *filePNG=nil;
static unsigned fileScenario=0,fileWrites=0,fileFault=0;
static NSString *fileFaultStage=nil;
static std::vector<std::string> fileOrder;
static CGRect fileSeenRegion;
static TLinkNativeBudgetPtr fileBudget;
static std::function<void(NSString *)> fileOnStage;
static void fileObserve(NSString *stage){
    fileOrder.push_back(stage.UTF8String);fileBudget=TLinkCurrentNativeBudget();assert(fileBudget&&!fileBudget->cleanup());
    if(fileOnStage)fileOnStage(stage);
    if([stage isEqual:fileFaultStage]&&fileFault==1)[NSException raise:@"ScreenshotFileFixture" format:@"capture boundary throws"];
    if([stage isEqual:fileFaultStage]&&fileFault==2)throw std::runtime_error("screenshot file boundary throws");
}
@interface NativeFileCaptureScreen : NSObject
+ (NSString *)screenShotToPath:(NSString *)path region:(CGRect)region error:(NSError **)error;
@end
@implementation NativeFileCaptureScreen
+ (NSString *)screenShotToPath:(NSString *)path region:(CGRect)region error:(NSError **)error {
    fileSeenPath=[path copy];fileSeenRegion=region;fileObserve(@"capture");
    if(fileScenario==1){if(error)*error=[NSError errorWithDomain:@"ScreenshotFileFixture" code:1 userInfo:@{NSLocalizedDescriptionKey:fileErrorText}];return nil;}
    if(fileScenario==2)return nil;
    assert([filePNG writeToFile:filePrivateOutput atomically:false]);++fileWrites;fileObserve(@"written");
    if(fileScenario==3){if(error)*error=[NSError errorWithDomain:@"ScreenshotFileFixture" code:1 userInfo:@{NSLocalizedDescriptionKey:fileErrorText}];return nil;}
    return fileScenario==4?fileReplyPath:(path.length?path:@"fixture-default.png");
}
@end
#define Screen NativeFileCaptureScreen
#define TLinkCaptureReceiverSlot fileNoOwner
#define handleScreenshotTaskFromRawData nativeFileCaptureParser
#include "NativeFileCaptureParser.inc"
#undef handleScreenshotTaskFromRawData
#define handleScreenshotTaskFromRawData legacyFileCaptureParser
#include "LegacyFileCaptureParser.inc"
#undef handleScreenshotTaskFromRawData
#undef TLinkCaptureReceiverSlot
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeScreenshotFileEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
#undef Screen
static void screenshotFileLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_SCREENSHOT;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=29\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
#define handleScreenshotTaskFromRawData legacyFileCaptureParser
    if(false){}
#include "fixtures/screenshot-handler-legacy-v1.inc"
#undef handleScreenshotTaskFromRawData
}
static std::string fileRegionKey(CGRect rect){
    return [NSString stringWithFormat:@"%a,%a,%a,%a",double(rect.origin.x),double(rect.origin.y),double(rect.size.width),double(rect.size.height)].UTF8String;
}
static void typedScreenshotFileCases(TLinkInProcessNativeBridge *bridge){
    @try {try{
    puts("Screenshot file Foundation: actual parser/entry/JS parity; controlled Screen writes a private PNG");fflush(stdout);mode=@"screenshotFileRuntime";
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-native-file-shot-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    NSFileManager *fm=NSFileManager.defaultManager;assert([fm createDirectoryAtPath:directory withIntermediateDirectories:false attributes:nil error:NULL]);filePrivateOutput=[directory stringByAppendingPathComponent:@"controlled.png"];
    nativeAlbumWritePNG(filePrivateOutput);filePNG=[NSData dataWithContentsOfFile:filePrivateOutput];assert(filePNG.length);
    NSString *path=[directory stringByAppendingPathComponent:@"ảnh;测试.png"];
    const auto reset=[](TLinkTaskExecutionContext *context,unsigned scenario=0,NSString *text=nil){
        [[NSFileManager defaultManager] removeItemAtPath:filePrivateOutput error:NULL];fileSeenPath=nil;fileSeenRegion=CGRectZero;fileScenario=scenario;fileWrites=fileFault=0;
        fileErrorText=text?:@"-1;;controlled screenshot failure\r\n";fileReplyPath=text?:@"reply.png";fileFaultStage=nil;fileOrder.clear();fileBudget.reset();fileOnStage={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](bool region,NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:region?TLinkJSNativeMethodScreenshotRegion:TLinkJSNativeMethodScreenshotTo arguments:args];};
    const auto invoke=[bridge,request](bool region,NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(region,args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](bool region,NSArray *args,NSUInteger cap=4096,unsigned scenario=0,NSString *text=nil)->NSUInteger{
        auto context=parent(30,cap);reset(context,scenario,text);int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyScreenshotFile:request(region,args) context:context];
        const auto order=fileOrder;NSString *seen=fileSeenPath;const std::string geometry=fileRegionKey(fileSeenRegion);const unsigned writes=fileWrites;const int gateDelta=licenseCalls-gates;
        NSData *data=[NSData dataWithContentsOfFile:filePrivateOutput];
        context=parent(30,cap);reset(context,scenario,text);gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(region,args,context);const bool same=actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]);
        if(!same){fprintf(stdout,"Screenshot file parity failure: %s\n",[NSString stringWithFormat:@"region=%d args=%@ cap=%lu scenario=%u expected=%@ actual=%@",region,args,(unsigned long)cap,scenario,expected.value,actual.value].UTF8String);fflush(stdout);}assert(same);
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        NSData *written=[NSData dataWithContentsOfFile:filePrivateOutput];
        assert(fileOrder==order&&((seen==fileSeenPath)||[seen isEqual:fileSeenPath])&&fileRegionKey(fileSeenRegion)==geometry&&fileWrites==writes&&((data==written)||[data isEqual:written]));
        assert(calls==rawCalls&&licenseCalls==gates+gateDelta);if(gateDelta)assert(lastLicenseTask==29);
        if(fileBudget)assert(!fileBudget->capturesResponse()&&fileBudget->response().capacity()==0);
        id raw=actual.value[@"raw"];return [raw isKindOfClass:[NSString class]]?[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding]:0;
    };
    for(unsigned n=0;n<160;++n){parity(false,@[path]);parity(true,@[path,@{@"x":@(int(n)-80+0.5),@"y":@(-0.5),@"width":@(n+0.4),@"height":@12.5}]);}
    NSArray *ordinary=@[path,@{@"x":@1.5,@"y":@(-2.5),@"width":@10.4,@"height":@12.5}];
    for(bool region:{false,true})for(unsigned scenario=0;scenario<=4;++scenario){const NSUInteger size=parity(region,ordinary,4096,scenario);assert(size);parity(region,ordinary,size,scenario);if(size>1)parity(region,ordinary,size-1,scenario);}
    for(NSNumber *value in @[@(-0.0),@(-0.5),@0.4,@0.5,@1.5,@2.5,@16777217.0,@(FLT_MAX),@(DBL_MAX),@(NAN),@(INFINITY),@(-INFINITY)]){
        parity(true,@[path,@{@"x":value,@"y":@0,@"width":@5,@"height":@6}]);parity(true,@[path,@{@"width":value,@"height":@6}]);
    }
    for(id candidate in @[@"",@"plain.png",@"bad;;path",@"bad\rpath",@"bad\npath",[path stringByAppendingString:@";"],@17,[NSNull null]]){parity(false,@[candidate]);parity(true,@[candidate,ordinary[1]]);}
    parity(false,@[]);parity(true,@[]);parity(true,@[path]);parity(true,@[path,@{@"x":@"1.5",@"width":@"12.5",@"height":@"9"}]);
    for(bool region:{false,true})for(NSString *unit in @[@"x",@"界"]){
        const NSUInteger limit=region?8175:8187; // 291;;path plus optional ;;0;;0;;1;;1
        NSString *exact=[@"" stringByPaddingToLength:limit withString:unit startingAtIndex:0];NSDictionary *options=@{@"width":@1,@"height":@1};
        parity(region,@[exact,options],65536);parity(region,@[[exact stringByAppendingString:@"x"],options],65536);
    }
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];
    for(bool region:{false,true}){parity(region,@[nul,ordinary[1]]);if(invalid)parity(region,@[invalid,ordinary[1]]);
        for(NSString *text in @[@"Unicode 测试;;detail\r\n",nul,@"",invalid?:@"fallback"]){parity(region,ordinary,4096,1,text);parity(region,ordinary,4096,4,text);}}
    puts("Screenshot file Foundation: task-29 authority, accepted writes, faults and snapshots");fflush(stdout);
    for(bool region:{false,true}){
        auto context=parent();reset(context);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};failure(invoke(region,ordinary,context).value,@"license_required task=29");assert(fileOrder.empty()&&fileWrites==0);
        context=parent();reset(context);int gates=licenseCalls;[context.cancellationToken cancel];failure(invoke(region,ordinary,context).value,@"AbortError");assert(licenseCalls==gates&&fileOrder.empty());
        context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(region,ordinary,context).value,@"TimeoutError");assert(licenseCalls==gates&&fileOrder.empty());
        context=parent();reset(context);stopInLicense=true;failure(invoke(region,ordinary,context).value,@"AbortError");assert(fileOrder.empty());
        context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(region,ordinary,context).value,@"TimeoutError");assert(fileOrder.empty());
        for(NSString *stage in @[@"capture",@"written"]){context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;fileOnStage=[stage,token](NSString *point){if([point isEqual:stage])[token cancel];};
            failure(invoke(region,ordinary,context).value,@"AbortError");assert(fileWrites==1&&[fm fileExistsAtPath:filePrivateOutput]);}
        context=parent(0.1);reset(context);fileOnStage=[](NSString *stage){if([stage isEqual:@"capture"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};failure(invoke(region,ordinary,context).value,@"TimeoutError");assert(fileWrites==1);
        context=parent(1,2);reset(context);failure(invoke(region,ordinary,context).value,@"response_too_large");assert(fileWrites==1);
        for(unsigned fault:{1U,2U})for(NSString *stage in @[@"capture",@"written"]){context=parent();reset(context);fileFault=fault;fileFaultStage=stage;failure(invoke(region,ordinary,context).value,@"native_exception");assert(fileWrites==([stage isEqual:@"written"]?1U:0U));}
    }
    auto context=parent();reset(context);NSMutableString *mutablePath=[path mutableCopy];fileOnStage=[mutablePath](NSString *stage){if([stage isEqual:@"capture"])[mutablePath setString:@"changed"];};NSDictionary *held=nil;
    @autoreleasepool{held=invoke(false,@[mutablePath],context).value;context=nil;}assert([held[@"ok"] boolValue]&&[fileSeenPath isEqual:path]&&[held[@"path"] isEqual:path]);
    // Direct field API keeps parser delimiters that strict JS rejects.
    for(NSString *body in @[@"1",@"1;;",@"1;;plain;;1;;2;;3;;4;;ignored",@"4;;not-owned"]){
        context=parent();reset(context);NSError *oldError=nil;NSString *expected=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);@autoreleasepool{expected=legacyFileCaptureParser((UInt8 *)body.UTF8String,&oldError);}}
        const auto order=fileOrder;const std::string geometry=fileRegionKey(fileSeenRegion);const unsigned writes=fileWrites;
        reset(context);NSError *error=nil;NSString *actual=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);@autoreleasepool{actual=nativeFileCaptureParser((UInt8 *)body.UTF8String,&error);}}
        assert(((expected==actual)||[expected isEqual:actual])&&((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]));assert(fileOrder==order&&fileRegionKey(fileSeenRegion)==geometry&&fileWrites==writes);
    }
    context=parent();reset(context);NSString *delimited=@"plain;;1;;2;;3;;4";
    NSDictionary *expected=[bridge executeRawPayload:[@"291;;" stringByAppendingString:delimited] context:context];reset(context);
    assert([TLinkExecuteNativeScreenshotFile(delimited,false,0,0,0,0,context) isEqual:expected]&&fileWrites==1);
    for(unsigned n=0;n<128;++n){context=parent();reset(context);assert([invoke(bool(n%2),ordinary,context).value[@"ok"] boolValue]&&fileWrites==1);}
    assert([fm removeItemAtPath:directory error:NULL]);filePrivateOutput=fileSeenPath=fileErrorText=fileReplyPath=fileFaultStage=nil;filePNG=nil;fileOrder.clear();fileOnStage={};fileBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());puts("Typed screenshot file passed: actual action-1 parser/entry and frozen JS/task parity, UTF-8 paths, %.0f/floatValue geometry, ingress/output/task-29 gates, committed writes/stop/faults and lifetime. Screen is controlled; only a private PNG is written. Real capture/crop/codec/keep/lease qualification remains separate.");
    }catch(const std::exception &exception){fprintf(stdout,"Screenshot file fixture: uncaught C++ exception: %s\n",exception.what());fflush(stdout);throw;}catch(...){puts("Screenshot file fixture: uncaught non-standard C++ exception");fflush(stdout);throw;}}
    @catch(NSException *exception){fprintf(stdout,"Screenshot file fixture: uncaught Objective-C exception: %s\n",exception.description.UTF8String?:"(no description)");fflush(stdout);@throw;}
}
