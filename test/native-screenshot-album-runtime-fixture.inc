// Actual Screen album methods; real PNG/ImageIO, controlled UIKit and Photos boundaries.
#include <ImageIO/ImageIO.h>
#include "ScreenshotAlbumConstants.h"
static bool albumAvailable=true,albumExists=true,albumClearing=false,albumHideCreated=false,albumErrorAfterCommit=false;
static unsigned albumCreated=0,albumAdded=0,albumDeleted=0,albumChanges=0,albumFault=0;
static unsigned albumSources=0,albumSourceReleases=0,albumImages=0,albumImageReleases=0;
static NSString *albumErrorStage=nil,*albumSkipStage=nil,*albumErrorText=nil,*albumFaultStage=nil,*albumReadPath=nil;
static std::vector<std::string> albumOrder;
static std::function<void(NSString *)> albumOnStage;
static TLinkNativeBudgetPtr albumBudget;
static void albumObserve(NSString *stage){
    albumOrder.push_back(stage.UTF8String);albumBudget=TLinkCurrentNativeBudget();assert(albumBudget&&!albumBudget->cleanup());
    if([stage isEqual:albumFaultStage]&&albumFault==1)[NSException raise:@"AlbumFixture" format:@"Photos boundary throws"];
    if([stage isEqual:albumFaultStage]&&albumFault==2)throw std::runtime_error("Photos boundary throws");
    if(albumOnStage)albumOnStage(stage);
}
@interface NativeAlbumImage : NSObject
@property(nonatomic) NSUInteger width;
@property(nonatomic) NSUInteger height;
+ (instancetype)imageWithContentsOfFile:(NSString *)path;
@end
@implementation NativeAlbumImage
+ (instancetype)imageWithContentsOfFile:(NSString *)path {
    albumReadPath=[path copy];albumObserve(@"image");BOOL directory=false;
    if(![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory]||directory)return nil;
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);if(!source)return nil;++albumSources;
    CGImageRef decoded=CGImageSourceCreateImageAtIndex(source,0,NULL);CFRelease(source);++albumSourceReleases;if(!decoded)return nil;++albumImages;
    const size_t width=CGImageGetWidth(decoded),height=CGImageGetHeight(decoded);CGImageRelease(decoded);++albumImageReleases;
    NativeAlbumImage *image=[self new];image.width=width;image.height=height;return image;
}
@end
@interface NativeAlbumOptions : NSObject
@property(nonatomic,copy) NSPredicate *predicate;
@end
@implementation NativeAlbumOptions
@end
@interface NativeAlbumFetch<ObjectType> : NSObject
@property(nonatomic,copy) NSArray<ObjectType> *objects;
- (ObjectType)firstObject;
- (NSUInteger)count;
@end
@implementation NativeAlbumFetch
- (id)firstObject {return self.objects.firstObject;}
- (NSUInteger)count {return self.objects.count;}
@end
@class NativeAlbumAsset;
static NSMutableArray<NativeAlbumAsset *> *albumAssets=nil;
static bool albumLastFetch=false;
@interface NativeAlbumCollection : NSObject
+ (NativeAlbumFetch<NativeAlbumCollection *> *)fetchAssetCollectionsWithType:(NSInteger)type subtype:(NSInteger)subtype options:(NativeAlbumOptions *)options;
@end
static NativeAlbumCollection *albumCollection=nil;
@implementation NativeAlbumCollection
+ (NativeAlbumFetch<NativeAlbumCollection *> *)fetchAssetCollectionsWithType:(NSInteger)type subtype:(NSInteger)subtype options:(NativeAlbumOptions *)options {
    assert(type==1&&subtype==2&&options.predicate&&[options.predicate evaluateWithObject:@{@"title":@"TLinkauto"}]&&![options.predicate evaluateWithObject:@{@"title":@"other"}]);
    albumObserve(@"fetch");albumLastFetch=albumAvailable&&albumExists&&!(albumHideCreated&&albumCreated);
    NativeAlbumFetch *result=[NativeAlbumFetch new];result.objects=albumLastFetch?@[albumCollection]:@[];return result;
}
@end
@interface NativeAlbumAsset : NSObject
@property(nonatomic,strong) NativeAlbumImage *image;
+ (NativeAlbumFetch<NativeAlbumAsset *> *)fetchAssetsInAssetCollection:(NativeAlbumCollection *)collection options:(NativeAlbumOptions *)options;
@end
@implementation NativeAlbumAsset
+ (NativeAlbumFetch<NativeAlbumAsset *> *)fetchAssetsInAssetCollection:(NativeAlbumCollection *)collection options:(NativeAlbumOptions *)options {
    assert(collection==albumCollection&&!options);albumObserve(@"assets");NativeAlbumFetch *result=[NativeAlbumFetch new];result.objects=[albumAssets copy];return result;
}
@end
@interface NativeAlbumChange : NSObject
+ (instancetype)creationRequestForAssetCollectionWithTitle:(NSString *)title;
+ (instancetype)changeRequestForAssetCollection:(NativeAlbumCollection *)collection;
- (void)addAssets:(NSArray<NativeAlbumAsset *> *)assets;
@end
@implementation NativeAlbumChange
+ (instancetype)creationRequestForAssetCollectionWithTitle:(NSString *)title {
    assert([title isEqualToString:@"TLinkauto"]);albumObserve(@"create_request");albumExists=true;++albumCreated;return [self new];
}
+ (instancetype)changeRequestForAssetCollection:(NativeAlbumCollection *)collection {assert(collection==albumCollection);albumObserve(@"album_request");return [self new];}
- (void)addAssets:(NSArray<NativeAlbumAsset *> *)assets {assert(assets.count==1);[albumAssets addObjectsFromArray:assets];++albumAdded;albumObserve(@"added");}
@end
@interface NativeAlbumAssetChange : NSObject
@property(nonatomic,strong) NativeAlbumAsset *placeholderForCreatedAsset;
+ (instancetype)creationRequestForAssetFromImage:(NativeAlbumImage *)image;
+ (void)deleteAssets:(NativeAlbumFetch<NativeAlbumAsset *> *)assets;
@end
@implementation NativeAlbumAssetChange
+ (instancetype)creationRequestForAssetFromImage:(NativeAlbumImage *)image {
    assert(image.width==2&&image.height==2);albumObserve(@"asset_request");NativeAlbumAssetChange *request=[self new];NativeAlbumAsset *asset=[NativeAlbumAsset new];asset.image=image;request.placeholderForCreatedAsset=asset;return request;
}
+ (void)deleteAssets:(NativeAlbumFetch<NativeAlbumAsset *> *)assets {assert(assets.count==albumAssets.count);albumDeleted+=unsigned(assets.count);[albumAssets removeAllObjects];albumObserve(@"deleted");}
@end
@interface NativeAlbumLibrary : NSObject
+ (instancetype)sharedPhotoLibrary;
- (BOOL)performChangesAndWait:(dispatch_block_t)changes error:(NSError **)error;
@end
@implementation NativeAlbumLibrary
+ (instancetype)sharedPhotoLibrary {albumObserve(@"library");static NativeAlbumLibrary *library=nil;if(!library)library=[self new];return library;}
- (BOOL)performChangesAndWait:(dispatch_block_t)changes error:(NSError **)error {
    assert(changes&&error);NSString *stage=!albumLastFetch?@"create":(albumClearing?@"delete":@"save");++albumChanges;albumObserve([@"begin_" stringByAppendingString:stage]);
    const bool failed=[stage isEqual:albumErrorStage],skip=[stage isEqual:albumSkipStage]||(failed&&!albumErrorAfterCommit);
    if(!skip){changes();albumObserve([@"commit_" stringByAppendingString:stage]);}
    if(failed)*error=[NSError errorWithDomain:@"fixture.photos" code:7 userInfo:@{NSLocalizedDescriptionKey:albumErrorText?:@"provider failure"}];
    return !skip&&!failed;
}
@end
static Class nativeAlbumLookup(NSString *name){if([name isEqualToString:@"PHPhotoLibrary"]){albumObserve(@"framework");return albumAvailable?[NativeAlbumLibrary class]:Nil;}return NSClassFromString(name);}
static NSString *const kTLinkautoAlbumName=@"TLinkauto";
enum {PHAssetCollectionTypeAlbum=1,PHAssetCollectionSubtypeAlbumRegular=2};
@interface Screen (NativeAlbumFixture)
+ (NativeAlbumCollection *)fetchTLinkautoAlbum;
+ (NativeAlbumCollection *)ensureTLinkautoAlbumWithError:(NSError **)error;
+ (void)saveToSystemAlbum:(NSString *)path error:(NSError **)error;
+ (void)clearSystemAlbum:(NSError **)error;
@end
@implementation Screen (NativeAlbumFixture)
#define UIImage NativeAlbumImage
#define PHPhotoLibrary NativeAlbumLibrary
#define PHAssetCollection NativeAlbumCollection
#define PHFetchOptions NativeAlbumOptions
#define PHFetchResult NativeAlbumFetch
#define PHAsset NativeAlbumAsset
#define PHAssetCollectionChangeRequest NativeAlbumChange
#define PHAssetChangeRequest NativeAlbumAssetChange
#define NSClassFromString nativeAlbumLookup
#include "ScreenshotAlbumCore.inc"
#undef NSClassFromString
#undef PHAssetChangeRequest
#undef PHAssetCollectionChangeRequest
#undef PHAsset
#undef PHFetchResult
#undef PHFetchOptions
#undef PHAssetCollection
#undef PHPhotoLibrary
#undef UIImage
@end
#include "ScreenshotAlbumParser.inc"
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeScreenshotAlbumEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void screenshotAlbumLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_SCREENSHOT;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=29\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#include "fixtures/screenshot-handler-legacy-v1.inc"
}
static void nativeAlbumWritePNG(NSString *path){
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();assert(space);CGContextRef context=CGBitmapContextCreate(NULL,2,2,8,8,space,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(space);assert(context);
    CGContextClearRect(context,CGRectMake(0,0,2,2));CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);assert(image);
    CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],CFSTR("public.png"),1,NULL);assert(destination);
    CGImageDestinationAddImage(destination,image,NULL);bool saved=CGImageDestinationFinalize(destination);CFRelease(destination);CGImageRelease(image);assert(saved);
}
static void typedScreenshotAlbumCases(TLinkInProcessNativeBridge *bridge){
    @try {try{
    mode=@"screenshotAlbumRuntime";puts("Screenshot album Foundation: actual Photos adapters and real PNG decode with controlled library");fflush(stdout);
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-native-album-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    NSFileManager *fm=[NSFileManager defaultManager];assert([fm createDirectoryAtPath:directory withIntermediateDirectories:false attributes:nil error:NULL]);
    NSString *path=[directory stringByAppendingPathComponent:@"ảnh;测试.png"];nativeAlbumWritePNG(path);
    const auto reset=[](TLinkTaskExecutionContext *context,bool clear){
        assert(albumSources==albumSourceReleases&&albumImages==albumImageReleases);albumClearing=clear;albumAvailable=albumExists=true;albumHideCreated=albumErrorAfterCommit=false;
        albumCreated=albumAdded=albumDeleted=albumChanges=albumFault=0;albumSources=albumSourceReleases=albumImages=albumImageReleases=0;
        albumErrorStage=albumSkipStage=albumFaultStage=albumReadPath=nil;albumErrorText=@"provider failure";albumOrder.clear();albumOnStage={};albumBudget.reset();albumLastFetch=false;
        albumCollection=[NativeAlbumCollection new];albumAssets=[NSMutableArray arrayWithObjects:[NativeAlbumAsset new],[NativeAlbumAsset new],nil];
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](bool clear,NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:clear?TLinkJSNativeMethodClearScreenshotAlbum:TLinkJSNativeMethodSaveScreenshotToAlbum arguments:args];};
    const auto invoke=[bridge,request](bool clear,NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(clear,args) context:context error:nil];assert(!TLinkCurrentNativeBudget()&&albumSources==albumSourceReleases&&albumImages==albumImageReleases);return result;
    };
    const auto setup=[](unsigned scenario){
        if(scenario==1)albumExists=false;if(scenario==2)albumAvailable=false;if(scenario==3)[albumAssets removeAllObjects];
        if(scenario==4){albumExists=false;albumErrorStage=@"create";}if(scenario==5)albumErrorStage=albumClearing?@"delete":@"save";
        if(scenario==6){albumExists=false;albumHideCreated=true;}if(scenario==7)albumSkipStage=albumClearing?@"delete":@"save";
        if(scenario==8){albumErrorStage=albumClearing?@"delete":@"save";albumErrorAfterCommit=true;}
    };
    const auto parity=[bridge,reset,request,invoke,setup](bool clear,NSArray *args,NSUInteger cap,unsigned scenario=0,NSString *errorText=nil){
        auto context=parent(30,cap);reset(context,clear);setup(scenario);if(errorText)albumErrorText=errorText;int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyScreenshotAlbum:request(clear,args) context:context];const auto order=albumOrder;
        const NSUInteger assets=albumAssets.count;const unsigned created=albumCreated,added=albumAdded,deleted=albumDeleted,changes=albumChanges,sources=albumSources,images=albumImages;const bool exists=albumExists;
        NSString *readPath=albumReadPath;const int gateDelta=licenseCalls-gates;
        context=parent(30,cap);reset(context,clear);setup(scenario);if(errorText)albumErrorText=errorText;gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(clear,args,context);const bool matches=actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]);
        if(!matches){fprintf(stdout,"Screenshot album parity failure: %s\n",[NSString stringWithFormat:@"clear=%d scenario=%u cap=%lu args=%@ expected=%@ actual=%@",clear,scenario,(unsigned long)cap,args,expected.value,actual.value].UTF8String);fflush(stdout);}assert(matches);
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(albumOrder==order&&albumAssets.count==assets&&albumCreated==created&&albumAdded==added&&albumDeleted==deleted&&albumChanges==changes&&albumExists==exists&&albumSources==sources&&albumImages==images);
        assert((albumReadPath==readPath)||[albumReadPath isEqual:readPath]);assert(calls==rawCalls&&licenseCalls==gates+gateDelta);
        if(gateDelta)assert(lastLicenseTask==29);if(!order.empty())assert(albumBudget&&!albumBudget->capturesResponse()&&albumBudget->response().capacity()==0);
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    for(unsigned n=0;n<160;++n)parity(bool(n%2),@[path,@"ignored"],4096,n%4);
    for(bool clear:{false,true})for(unsigned scenario=0;scenario<=8;++scenario){const NSUInteger size=parity(clear,@[path],4096,scenario);assert(size>0);parity(clear,@[path],size,scenario);if(size>1)parity(clear,@[path],size-1,scenario);}
    for(id invalid in @[@"",@"a;;b",@"a\r",@"a\n",[NSNull null],@17]){parity(false,@[invalid],4096);parity(true,@[invalid],4096);}parity(false,@[],4096);parity(true,@[],4096);
    parity(false,@[[directory stringByAppendingPathComponent:@"missing"]],4096);parity(false,@[directory],4096);
    NSString *bad=[directory stringByAppendingPathComponent:@"not-image.png"];assert([[@"invalid" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:bad atomically:true]);parity(false,@[bad],4096);
    for(NSString *unit in @[@"x",@"界"]){NSString *exact=[@"" stringByPaddingToLength:8187 withString:unit startingAtIndex:0];parity(false,@[exact],4096);parity(false,@[[exact stringByAppendingString:@"x"]],4096);}
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];parity(false,@[nul],4096);const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];if(invalid)parity(false,@[invalid],4096);
    for(bool clear:{false,true})for(NSString *description in @[@"Unicode 测试;;detail\r\n",nul,invalid?:@"fallback"]){parity(clear,@[path],4096,5,description);parity(clear,@[path],2,5,description);}
    puts("Screenshot album Foundation: ordinary task-29 gates, accepted effects and faults");fflush(stdout);
    for(bool clear:{false,true}){
        auto context=parent();reset(context,clear);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};failure(invoke(clear,@[path],context).value,@"license_required task=29");assert(albumOrder.empty());
        context=parent();reset(context,clear);const int gates=licenseCalls;[context.cancellationToken cancel];failure(invoke(clear,@[path],context).value,@"AbortError");assert(licenseCalls==gates&&albumOrder.empty());
        context=parent();reset(context,clear);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(clear,@[path],context).value,@"TimeoutError");assert(licenseCalls==gates&&albumOrder.empty());
        context=parent();reset(context,clear);stopInLicense=true;failure(invoke(clear,@[path],context).value,@"AbortError");assert(albumOrder.empty());
        context=parent(0.1);reset(context,clear);licenseDelayMs=150;failure(invoke(clear,@[path],context).value,@"TimeoutError");assert(albumOrder.empty());
        context=parent();reset(context,clear);TLinkCancellationToken *token=context.cancellationToken;albumOnStage=[token,clear](NSString *stage){if([stage isEqualToString:clear?@"fetch":@"image"])[token cancel];};
        failure(invoke(clear,@[path],context).value,@"AbortError");assert(albumAdded==(clear?0U:1U)&&albumDeleted==(clear?2U:0U));
        context=parent(0.1);reset(context,clear);albumOnStage=[](NSString *stage){if([stage hasPrefix:@"begin_"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};
        failure(invoke(clear,@[path],context).value,@"TimeoutError");assert(albumAdded==(clear?0U:1U)&&albumDeleted==(clear?2U:0U));
        context=parent(1,2);reset(context,clear);failure(invoke(clear,@[path],context).value,@"response_too_large");assert(albumAdded==(clear?0U:1U)&&albumDeleted==(clear?2U:0U));
        for(unsigned fault:{1U,2U})for(bool after:{false,true}){context=parent();reset(context,clear);albumFault=fault;albumFaultStage=after?(clear?@"deleted":@"added"):@"fetch";
            failure(invoke(clear,@[path],context).value,@"native_exception");assert(albumAdded==(!clear&&after?1U:0U)&&albumDeleted==(clear&&after?2U:0U));}
    }
    auto context=parent();reset(context,false);NSMutableString *mutablePath=[path mutableCopy];albumOnStage=[mutablePath](NSString *stage){if([stage isEqualToString:@"image"])[mutablePath setString:@"changed"];};
    NSDictionary *held=nil;NativeAlbumImage *heldImage=nil;@autoreleasepool{held=invoke(false,@[mutablePath],context).value;heldImage=albumAssets.lastObject.image;context=nil;}
    assert([held[@"ok"] boolValue]&&[albumReadPath isEqual:path]&&heldImage.width==2&&heldImage.height==2);
    for(NSString *raw in @[@"2",@"2;;",[@"2;;" stringByAppendingString:path],[[ @"2;;" stringByAppendingString:path] stringByAppendingString:@";;ignored"],@"3",@"3;;ignored"]){
        context=parent();const bool clear=[raw hasPrefix:@"3"];reset(context,clear);
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *error=nil;NSString *result=handleScreenshotTaskFromRawData((UInt8 *)raw.UTF8String,&error);
            const bool expectedError=[raw isEqualToString:@"2"]||[raw isEqualToString:@"2;;"];assert(!result&&((error!=nil)==expectedError));}
    }
    // The direct field API retains first-field truncation even outside strict JS validation.
    context=parent();reset(context,false);NSString *delimited=[path stringByAppendingString:@";;ignored"];NSDictionary *old=[bridge executeRawPayload:[@"292;;" stringByAppendingString:delimited] context:context];reset(context,false);
    assert([TLinkExecuteNativeScreenshotAlbum(false,delimited,context) isEqual:old]&&albumAdded==1&&!TLinkCurrentNativeBudget());
    for(unsigned n=0;n<128;++n){context=parent();reset(context,bool(n%2));assert([invoke(bool(n%2),@[path],context).value[@"ok"] boolValue]);}
    assert(albumSources==albumSourceReleases&&albumImages==albumImageReleases);assert([fm removeItemAtPath:directory error:NULL]);albumAssets=nil;albumCollection=nil;albumReadPath=albumErrorText=albumErrorStage=albumSkipStage=albumFaultStage=nil;albumOrder.clear();albumBudget.reset();albumOnStage={};licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());puts("Typed screenshot album passed: actual Screen/Photos adapters and RAW/JS parity, real PNG/ImageIO, create/save/delete errors and silent failures, ingress/output/task-29 gates, committed stop/fault behavior and lifetime. Photos is controlled; no real album changed.");
    }catch(const std::exception &exception){fprintf(stdout,"Screenshot album fixture: uncaught C++ exception: %s\n",exception.what());fflush(stdout);throw;}catch(...){puts("Screenshot album fixture: uncaught non-standard C++ exception");fflush(stdout);throw;}}
    @catch(NSException *exception){fprintf(stdout,"Screenshot album fixture: uncaught Objective-C exception: %s\n",exception.description.UTF8String?:"(no description)");fflush(stdout);@throw;}
}
