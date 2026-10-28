// Actual ScreenMatch adapter/RAW parser; controlled matcher, real owned CGImage.
#include "../shared/TLinkTemplatePolicy.h"
#include <cfloat>
static NSString *matchPNG=nil,*matchSeenPath=nil,*matchErrorText=nil;
static unsigned matchCreated=0,matchReleased=0,matchCalls=0,matchFault=0,matchEngines=0,matchDestroyed=0;
static bool matchNoScreen=false,matchFail=false;
static CGRect matchRect;
static std::vector<std::string> matchTrace;
static TLinkNativeBudgetPtr matchBudget;
static uint64_t matchEnteredOffset=0;
static std::function<void(NSString *)> matchOnStage;
static void matchObserve(NSString *stage){
    matchTrace.push_back(stage.UTF8String);matchBudget=TLinkCurrentNativeBudget();assert(matchBudget&&!matchBudget->cleanup());
    if(matchOnStage)matchOnStage(stage);
}
@interface NativeMatchScreen : NSObject
+ (CGImageRef)createScreenShotCGImageRef;
@end
@implementation NativeMatchScreen
+ (CGImageRef)createScreenShotCGImageRef {
    matchObserve(@"capture");if(matchNoScreen)return NULL;
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:matchPNG],NULL);assert(source);
    CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);CFRelease(source);assert(image);++matchCreated;return image;
}
@end
static void matchRelease(CGImageRef image){assert(image);++matchReleased;CGImageRelease(image);}
static bool matchResultsEqual(id left,id right){
    if(left==right)return true;
    if(![left isKindOfClass:[NSDictionary class]]||![right isKindOfClass:[NSDictionary class]])return [left isEqual:right];
    NSDictionary *a=left,*b=right;if(a.count!=b.count)return false;
    for(id key in a){id av=a[key],bv=b[key];
        // NaN metadata has no portable NSNumber equality guarantee. Wire/parts
        // remain exact, and both decoded numeric fields must still be NaN.
        if([av isKindOfClass:[NSNumber class]]&&[bv isKindOfClass:[NSNumber class]]&&std::isnan([av doubleValue])&&std::isnan([bv doubleValue]))continue;
        if(av!=bv&&![av isEqual:bv])return false;
    }
    return true;
}
@interface NativeMatchEngine : NSObject
- (void)setAcceptableValue:(float)value;
- (void)setScaleRation:(float)value;
- (void)setMaxTryTimes:(int)value;
- (CGRect)templateMatchWithCGImage:(CGImageRef)image templatePath:(NSString *)path error:(NSError **)error;
@end
@implementation NativeMatchEngine
- (instancetype)init {self=[super init];if(self)++matchEngines;return self;}
- (void)dealloc {++matchDestroyed;}
- (void)setAcceptableValue:(float)value {matchObserve([NSString stringWithFormat:@"acceptable:%a",double(value)]);}
- (void)setScaleRation:(float)value {matchObserve([NSString stringWithFormat:@"ratio:%a",double(value)]);}
- (void)setMaxTryTimes:(int)value {matchObserve([NSString stringWithFormat:@"tries:%d",value]);}
- (CGRect)templateMatchWithCGImage:(CGImageRef)image templatePath:(NSString *)path error:(NSError **)error {
    assert(CGImageGetWidth(image)==2&&CGImageGetHeight(image)==2);++matchCalls;matchSeenPath=[path copy];matchObserve(@"match");
    if(matchFault==1)[NSException raise:@"MatchFixture" format:@"matcher throws"];
    if(matchFault==2)throw std::runtime_error("matcher throws");
    if(matchFail&&error)*error=[NSError errorWithDomain:@"MatchFixture" code:1 userInfo:@{NSLocalizedDescriptionKey:matchErrorText}];
    return matchRect;
}
@end
@interface NativeMatchOwner : NSObject
+ (CGRect)matchCurrentScreenWithTemplate:(NSString *)path maxTryTimes:(int)tries acceptableValue:(float)acceptable scaleRation:(float)ratio error:(NSError **)error;
@end
@interface LegacyMatchOwner : NSObject
+ (CGRect)matchCurrentScreenWithTemplate:(NSString *)path maxTryTimes:(int)tries acceptableValue:(float)acceptable scaleRation:(float)ratio error:(NSError **)error;
@end
#define Screen NativeMatchScreen
#define TemplateMatch NativeMatchEngine
#define CGImageRelease matchRelease
#define ScreenMatch NativeMatchOwner
#include "ScreenMatchUnderTest.inc"
#undef ScreenMatch
#define ScreenMatch LegacyMatchOwner
#define screenMatchFromRawData legacyScreenMatchFromRawData
#include "LegacyScreenMatch.inc"
#undef screenMatchFromRawData
#undef ScreenMatch
#undef CGImageRelease
#undef TemplateMatch
#undef Screen
// Exercise local expiry using the real duration/factory with an earlier entry
// timestamp, without delaying every probe for eight seconds.
static TLinkNativeBudgetPtr matchC01Budget(const uint8_t *bytes,size_t length,TLinkNativeBudgetPtr parentBudget){
    assert(TLinkC01DurationNs(bytes,length)==8000000000ULL);
    const uint64_t now=TLinkNativeNowNs();assert(now>matchEnteredOffset);
    return TLinkC01TaskBudget(bytes,length,std::move(parentBudget),now-matchEnteredOffset);
}
#define ScreenMatch NativeMatchOwner
#define TLinkC01TaskBudget matchC01Budget
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeTemplateMatchEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
#undef TLinkC01TaskBudget
#undef ScreenMatch
static void templateMatchLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef writeStreamRef){
    auto outer=TLinkCurrentNativeBudget();TLinkNativeBudgetScope c01(matchC01Budget(bytes,length,outer));
    const int taskType=TASK_TEMPLATE_MATCH;UInt8 *eventData=bytes+2;
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=21\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
#define screenMatchFromRawData legacyScreenMatchFromRawData
    if(false){}
#include "fixtures/screen-match-handler-legacy-v1.inc"
#undef screenMatchFromRawData
}
static void typedTemplateMatchCases(TLinkInProcessNativeBridge *bridge){
    @try {try{
    puts("Template match Foundation: actual adapter/parser and owned CGImage; matcher controlled");fflush(stdout);mode=@"templateMatchRuntime";
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-native-match-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    NSFileManager *fm=NSFileManager.defaultManager;assert([fm createDirectoryAtPath:directory withIntermediateDirectories:false attributes:nil error:NULL]);
    // Successful backend/fault probes must not depend on the host's %s decoding.
    NSString *path=[directory stringByAppendingPathComponent:@"sample.png"];matchPNG=path;nativeAlbumWritePNG(path);
    const auto reset=[](TLinkTaskExecutionContext *context){
        assert(matchCreated==matchReleased&&matchEngines==matchDestroyed);matchCreated=matchReleased=matchCalls=matchFault=matchEngines=matchDestroyed=0;
        matchNoScreen=matchFail=false;matchSeenPath=nil;matchErrorText=@"-1;;controlled matcher failure\r\n";matchRect=CGRectMake(1.235,-2.345,3.455,4.565);
        matchTrace.clear();matchOnStage={};matchBudget.reset();matchEnteredOffset=0;touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodMatchTemplate arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];
        assert(!TLinkCurrentNativeBudget()&&matchCreated==matchReleased&&matchEngines==matchDestroyed);return result;
    };
    const auto configure=[](unsigned scenario,NSString *errorText){
        matchNoScreen=scenario==1;matchFail=scenario==2;if(errorText)matchErrorText=errorText;
        if(scenario==3)matchRect=CGRect();if(scenario==4)matchRect=CGRectMake(-0.0,INFINITY,NAN,-4.5);
        if(scenario==5)matchRect=CGRectMake(DBL_MAX,-DBL_MAX,DBL_MAX,DBL_MAX);
        if(scenario==6){matchEnteredOffset=7900000000ULL;matchOnStage=[](NSString *stage){if([stage isEqualToString:@"match"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};}
        if(scenario==7)matchEnteredOffset=8100000000ULL;
    };
    const auto parity=[bridge,reset,request,invoke,configure](NSArray *args,NSUInteger cap=4096,unsigned scenario=0,NSString *errorText=nil){
        auto context=parent(30,cap);reset(context);configure(scenario,errorText);int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyTemplateMatch:request(args) context:context];
        const auto trace=matchTrace;NSString *seen=matchSeenPath;const unsigned created=matchCreated,matched=matchCalls;const int gateDelta=licenseCalls-gates;
        context=parent(30,cap);reset(context);configure(scenario,errorText);gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);const bool same=actual.ok==expected.ok&&matchResultsEqual(actual.value,expected.value);
        if(!same){fprintf(stdout,"Template match parity failure: %s\n",[NSString stringWithFormat:@"args=%@ scenario=%u cap=%lu expected=%@ actual=%@",args,scenario,(unsigned long)cap,expected.value,actual.value].UTF8String);fflush(stdout);}assert(same);
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(matchTrace==trace&&matchCreated==created&&matchCalls==matched&&((seen==matchSeenPath)||[seen isEqual:matchSeenPath]));
        assert(calls==rawCalls&&licenseCalls==gates+gateDelta);if(gateDelta)assert(lastLicenseTask==21);
        if(matchBudget)assert(!matchBudget->capturesResponse()&&matchBudget->response().capacity()==0);
        if(scenario==6)assert([actual.value[@"ok"] boolValue]&&matchBudget->stopped()&&matchCalls==1);
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    for(unsigned n=0;n<160;++n)parity(@[path,@{@"maxTryTimes":@(n%9),@"acceptable":@(0.12345+(n%8)*0.1),@"scaleRatio":@(0.2+(n%12)*0.1)}]);
    puts("Template match Foundation: legacy %s Unicode paths, missing and decoded-name files");fflush(stdout);
    NSString *semicolonPath=[directory stringByAppendingPathComponent:@"sample;tag.png"];nativeAlbumWritePNG(semicolonPath);parity(@[semicolonPath]);
    for(NSString *leaf in @[@"ảnh;测试.png",@"é.png",@"emoji-😀.png"]){
        NSString *unicodePath=[directory stringByAppendingPathComponent:leaf];nativeAlbumWritePNG(unicodePath);
        // The frozen RAW parser supplies the host-specific decoder oracle.
        // First compare with only the original file, then provide the decoded
        // spelling too, so passing cannot mean merely rejecting Unicode paths.
        parity(@[unicodePath]);
        NSString *decoded=[NSString stringWithFormat:@"%s",unicodePath.UTF8String];
        assert(decoded&&decoded.length);if(![fm fileExistsAtPath:decoded])nativeAlbumWritePNG(decoded);
        parity(@[unicodePath]);parity(@[unicodePath],4096,1);parity(@[unicodePath],4096,2);
        auto unicodeContext=parent();reset(unicodeContext);
        assert([invoke(@[unicodePath],unicodeContext).value[@"ok"] boolValue]&&matchCalls==1&&[matchSeenPath isEqual:decoded]);
    }
    for(unsigned scenario=0;scenario<=5;++scenario){const NSUInteger size=parity(@[path],4096,scenario);assert(size);parity(@[path],size,scenario);if(size>1)parity(@[path],size-1,scenario);}
    parity(@[path],4096,6);parity(@[path],4096,7);
    for(NSNumber *value in @[@(-1),@0,@8,@9,@(INT_MIN),@(INT_MAX)])parity(@[path,@{@"maxTryTimes":value}]);
    for(NSString *key in @[@"acceptable",@"scaleRatio"])for(NSNumber *value in @[@(-0.0),@(-0.00004),@(-0.00006),@0.09995,@0.10005,@0.99995,@1.00006,@1.89995,@1.90006,@(NAN),@(INFINITY),@(-INFINITY),@(DBL_MAX)])parity(@[path,@{key:value}]);
    for(NSString *candidate in @[@"",@"bad;;path",@"bad\rpath",@"bad\npath",[directory stringByAppendingPathComponent:@"missing"],[path stringByAppendingString:@";"],[path stringByAppendingString:@";尾"],directory])parity(@[candidate]);
    parity(@[]);parity(@[path,@{@"maxTryTimes":@"3text",@"acceptable":@"0.84505",@"scaleRatio":@"0.99995"}]);
    // Default numeric suffix plus task 21 consumes 21 UTF-16 units.
    for(NSString *unit in @[@"x",@"界"]){NSString *exact=[@"" stringByPaddingToLength:8171 withString:unit startingAtIndex:0];parity(@[exact]);parity(@[[exact stringByAppendingString:@"x"]]);}
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];parity(@[nul]);const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];if(invalid)parity(@[invalid]);
    for(NSString *text in @[@"-1;;测试;;detail\r\n",nul,@"",invalid?:@"fallback"])parity(@[path],4096,2,text);
    puts("Template match Foundation: authority, C01/caller budgets, unwind ownership and snapshots");fflush(stdout);
    auto context=parent(30);reset(context);const uint64_t entered=TLinkNativeNowNs();assert([invoke(@[path],context).value[@"ok"] boolValue]);
    assert(matchBudget&&matchBudget->deadline()>=entered+7000000000ULL&&matchBudget->deadline()<=TLinkNativeNowNs()+8000000000ULL);
    context=parent();reset(context);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};failure(invoke(@[path],context).value,@"license_required task=21");assert(matchTrace.empty());
    context=parent();reset(context);int gates=licenseCalls;[context.cancellationToken cancel];failure(invoke(@[path],context).value,@"AbortError");assert(licenseCalls==gates&&matchTrace.empty());
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(@[path],context).value,@"TimeoutError");assert(licenseCalls==gates&&matchTrace.empty());
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[path],context).value,@"AbortError");assert(matchTrace.empty());
    context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(@[path],context).value,@"TimeoutError");assert(matchTrace.empty());
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;matchOnStage=[token](NSString *stage){if([stage isEqualToString:@"match"])[token cancel];};failure(invoke(@[path],context).value,@"AbortError");assert(matchCalls==1);
    context=parent(0.1);reset(context);matchOnStage=[](NSString *stage){if([stage isEqualToString:@"match"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};failure(invoke(@[path],context).value,@"TimeoutError");assert(matchCalls==1);
    context=parent(1,2);reset(context);failure(invoke(@[path],context).value,@"response_too_large");assert(matchCalls==1);
    for(unsigned fault:{1U,2U}){context=parent();reset(context);matchFault=fault;failure(invoke(@[path],context).value,@"native_exception");assert(matchCreated==1&&matchReleased==1);}
    context=parent();reset(context);NSMutableString *mutablePath=[path mutableCopy];matchOnStage=[mutablePath](NSString *stage){if([stage isEqualToString:@"capture"])[mutablePath setString:@"changed"];};NSDictionary *held=nil;
    @autoreleasepool{held=invoke(@[mutablePath],context).value;context=nil;}assert([held[@"ok"] boolValue]&&[matchSeenPath isEqual:path]);
    // Parser defaults/errors remain usable outside JS and NSError survives its pool.
    for(NSString *body in @[path,[path stringByAppendingString:@";;2"],[path stringByAppendingString:@";;2;;0.8;;0.8"],[path stringByAppendingString:@";;2;;0.8;;0.8;;extra"]]){
        context=parent();reset(context);NSError *error=nil;{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);@autoreleasepool{screenMatchFromRawData((UInt8 *)body.UTF8String,&error);}}
        const bool malformed=[body componentsSeparatedByString:@";;"].count==2||[body componentsSeparatedByString:@";;"].count==5;assert((error!=nil)==malformed);if(error)assert([error.localizedDescription containsString:@"data format"]);
    }
    for(unsigned n=0;n<128;++n){context=parent();reset(context);assert([invoke(@[path],context).value[@"ok"] boolValue]);}
    assert([fm removeItemAtPath:directory error:NULL]);matchPNG=matchSeenPath=matchErrorText=nil;matchBudget.reset();matchOnStage={};matchTrace.clear();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());puts("Typed template match passed: actual ScreenMatch/RAW and frozen JS/task parity, numeric round trip, semicolon boundaries, ingress/output/task-21 authority, C01/caller budgets, faults, owned CGImage and pool lifetime. OpenCV/device qualification pending.");
    }catch(const std::exception &exception){fprintf(stdout,"Template match fixture: uncaught C++ exception: %s\n",exception.what());fflush(stdout);throw;}catch(...){puts("Template match fixture: uncaught non-standard C++ exception");fflush(stdout);throw;}}
    @catch(NSException *exception){fprintf(stdout,"Template match fixture: uncaught Objective-C exception: %s\n",exception.description.UTF8String?:"(no description)");fflush(stdout);@throw;}
}
