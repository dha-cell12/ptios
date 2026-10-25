#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dispatch/dispatch.h>
#include <atomic>
#include <thread>
#include <cassert>
#include <cstring>
#include <cstdio>
#include <stdexcept>
#include "../shared/TLinkNativeDispatch.h"
static std::atomic<uint64_t> clockOffset{0};
static uint64_t FixtureNow() { return TLinkNativeNowNs()+clockOffset.load(); }
#include "OCRPolicyUnderTest.h"
#import "../pccontrol/TesseractOCRTask.h"
#import "../third_party/TesseractOCR/TesseractOCR/G8Constants.h"
static std::atomic<unsigned> engines{0}, maxEngines{0}, images{0}, roiCalls{0}, recognizes{0};
static std::atomic<bool> holdCopy{false}, failInit{false}, slowInit{false}, pressureInit{false}, pressure{false}, throwNS{false}, throwCPP{false};
static dispatch_semaphore_t entered, releaseCopy;
static void zx_tessMemoryPressure(void);
static unsigned clones = 0, resizes = 0;
static NSString *const UIApplicationDidReceiveMemoryWarningNotification = @"fixture.memory.warning";
#define CV_8UC1 0
namespace cv {
struct Size { int width,height; Size(int w,int h):width(w),height(h){} };
struct Mat {
    int cols=0,rows=0; uint8_t *data=nullptr; size_t step[1]={0};
    std::shared_ptr<std::vector<uint8_t>> storage;
    Mat(){} Mat(int h,int w):cols(w),rows(h),storage(std::make_shared<std::vector<uint8_t>>(size_t(h)*w,23)) { data=storage->data();step[0]=size_t(w); }
    bool empty()const{return !storage;} int type()const{return CV_8UC1;}
    bool isContinuous()const{return true;} size_t total()const{return size_t(cols)*rows;} size_t elemSize()const{return 1;}
    Mat clone()const{++clones;Mat out(rows,cols);*out.storage=*storage;return out;}
    void release(){storage.reset();data=nullptr;cols=rows=0;}
};
static const int INTER_CUBIC=1,THRESH_BINARY=2,THRESH_OTSU=4,ADAPTIVE_THRESH_GAUSSIAN_C=8;
static void resize(const Mat &,Mat &out,Size size,double,double,int){++resizes;out=Mat(size.height,size.width);}
static void threshold(Mat &input,Mat &,double,double,int){input.data[0]=99;}
static void adaptiveThreshold(Mat &input,Mat &,double,int,int,int,double){input.data[0]=88;}
}
@interface UIImage : NSObject { CGImageRef _cg; }
@property(nonatomic,readonly) CGSize size;
@property(nonatomic,readonly) CGImageRef CGImage;
+ (instancetype)imageWithCGImage:(CGImageRef)image;
@end
@implementation UIImage
+ (instancetype)imageWithCGImage:(CGImageRef)image { UIImage *value=[UIImage new]; value->_cg=CGImageRetain(image);images.fetch_add(1);return value; }
- (CGSize)size { return CGSizeMake(CGImageGetWidth(_cg),CGImageGetHeight(_cg)); }
- (CGImageRef)CGImage { return _cg; }
- (void)dealloc { if(_cg){CGImageRelease(_cg);images.fetch_sub(1);} }
@end
@class G8Tesseract;
@protocol G8TesseractDelegate <NSObject>
- (BOOL)shouldCancelImageRecognitionForTesseract:(G8Tesseract *)engine;
@end
@interface G8RecognizedBlock : NSObject
@property(nonatomic,assign) double confidence;
@end
@implementation G8RecognizedBlock
@end
struct FixtureEngine { unsigned clears=0; size_t imageBytes=0; void Clear(){++clears;imageBytes=0;} };
@interface G8Tesseract : NSObject {
@public
    std::unique_ptr<FixtureEngine> _tesseract;
    UIImage *_image;
    CGRect _rect;
}
@property(nonatomic,assign) BOOL configured;
@property(nonatomic,assign) CGSize imageSize;
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,assign) CGRect rect;
@property(nonatomic,assign) G8PageSegmentationMode pageSegmentationMode;
@property(nonatomic,copy) NSString *charWhitelist;
@property(nonatomic,assign) double maximumRecognitionTime;
@property(nonatomic,weak) id<G8TesseractDelegate> delegate;
@property(nonatomic,readonly) NSString *recognizedText;
- (instancetype)initWithLanguage:(NSString *)language configDictionary:(NSDictionary *)config configFileNames:(NSArray *)files absoluteDataPath:(NSString *)path engineMode:(G8OCREngineMode)mode;
- (BOOL)isEngineConfigured;
- (void)resetFlags;
- (void)setEngineImage:(UIImage *)image;
- (BOOL)recognize;
- (NSArray *)recognizedBlocksByIteratorLevel:(G8PageIteratorLevel)level;
@end
@implementation G8Tesseract
@synthesize image=_image,rect=_rect;
- (instancetype)initWithLanguage:(NSString *)language configDictionary:(NSDictionary *)config configFileNames:(NSArray *)files absoluteDataPath:(NSString *)path engineMode:(G8OCREngineMode)mode {
    (void)language;(void)config;(void)files;(void)path;(void)mode;
    self=[super init];if(self){_tesseract.reset(new FixtureEngine);self.configured=!failInit.exchange(false);unsigned count=engines.fetch_add(1)+1,old=maxEngines.load();while(count>old&&!maxEngines.compare_exchange_weak(old,count)){} if(slowInit.exchange(false))clockOffset.fetch_add(4000000000ULL);if(pressureInit.exchange(false))zx_tessMemoryPressure();}return self;
}
- (void)dealloc { engines.fetch_sub(1); }
- (BOOL)isEngineConfigured{return self.configured;}
- (void)resetFlags{}
#include "OCRImageSetterUnderTest.inc"
// Execute the actual vendor nil/Clear branch; image conversion for non-nil input is doubled.
- (void)setEngineImage:(UIImage *)image {
#include "OCRImageClearUnderTest.inc"
    CFDataRef bytes=CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage));
    assert(bytes && CFDataGetLength(bytes)==(CFIndex)(image.size.width*image.size.height));
    const uint8_t first=CFDataGetBytePtr(bytes)[0];assert(first==23||first==99||first==88);CFRelease(bytes);
    _image=image;self.imageSize=image.size;_tesseract->imageBytes=size_t(image.size.width*image.size.height);
}
- (BOOL)recognize {
    recognizes.fetch_add(1);assert(self.image && self.maximumRecognitionTime>0 && self.maximumRecognitionTime<=3.0);
    if(pressure.exchange(false))zx_tessMemoryPressure();
    if(throwNS.exchange(false))@throw [NSException exceptionWithName:@"fixture" reason:@"recognition failed" userInfo:nil];
    if(throwCPP.exchange(false))throw std::runtime_error("fixture recognition failure");
    return ![self.delegate shouldCancelImageRecognitionForTesseract:self];
}
- (NSString *)recognizedText{return @" fixture result \n";}
- (NSArray *)recognizedBlocksByIteratorLevel:(G8PageIteratorLevel)level{(void)level;G8RecognizedBlock *block=[G8RecognizedBlock new];block.confidence=83;return @[block];}
@end
static bool zx_copyFrameGrayRegionForOCR(uint32_t,int,int,int w,int h,NSString *,uint64_t,cv::Mat &out,uint64_t *age,NSError **error,int scale) {
    TLinkOCRImagePlan plan;if(!TLinkOCRPlanImage(w>0?w:16,h>0?h:16,scale,true,plan)){if(error)*error=[NSError errorWithDomain:@"fixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"1;;ocr_scaled_image_too_large\r\n"}];return false;}
    ++roiCalls;if(holdCopy.exchange(false)){dispatch_semaphore_signal(entered);assert(dispatch_semaphore_wait(releaseCopy,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    out=cv::Mat(h>0?h:16,w>0?w:16);if(age)*age=42;return true;
}
#define ENABLE_TESSERACT_OCR 1
#include "OCRTaskUnderTest.inc"
static NSString *run(NSString *whitelist=@"",int scale=1,int threshold=0,int width=16,int height=16,NSError **failure=nullptr) {
    NSString *raw=[NSString stringWithFormat:@"1;;0;;0;;%d;;%d;;eng;;1;;7;;%@;;%d;;%d;;pixel;;1000",width,height,[[whitelist dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0],scale,threshold];
    NSError *error=nil;NSString *value=handleTesseractOCRTaskFromRawData((UInt8 *)raw.UTF8String,&error);
    if(failure)*failure=error;else assert(value&&!error);return value;
}
static void purge(){dispatch_sync(zx_tessQueue(),^{zx_tessPurgeCache();});}
static void typedOCRCases(){
    for(int scale:{0,1,2,4})for(int threshold:{0,1,2}){
        TLinkNativeFrameOCRRequest r;r.frameId=1;r.width=r.height=16;r.lang=@"eng";r.whitelist=@"typed-đọc";r.scaleUp=scale;r.thresholdMode=threshold;
        NSError *error=nil;NSString *raw=run(r.whitelist,scale,threshold,16,16,&error);assert(raw&&!error);NSString *typed=recognizeFrameWithTesseract(r,&error);assert(typed&&!error);
        NSArray *a=[raw componentsSeparatedByString:@";;"],*b=[typed componentsSeparatedByString:@";;"];assert(a.count==6&&b.count==6);for(unsigned i=0;i<3;++i)assert([a[i] isEqual:b[i]]);assert(images==0&&sZXTessActive==0);
    }
    TLinkNativeFrameOCRRequest r;r.frameId=1;r.width=r.height=16;r.lang=@"eng";NSError *error=nil;
    throwNS=true;assert(!recognizeFrameWithTesseract(r,&error)&&[error.localizedDescription containsString:@"ocr_exception"]);purge();
    throwCPP=true;assert(!recognizeFrameWithTesseract(r,&error)&&[error.localizedDescription containsString:@"ocr_exception"]);purge();
    failInit=true;assert(!recognizeFrameWithTesseract(r,&error)&&[error.localizedDescription containsString:@"engine_init_failed"]);purge();
    slowInit=true;assert(!recognizeFrameWithTesseract(r,&error)&&[error.localizedDescription containsString:@"ocr_cancelled_or_timed_out"]);clockOffset=0;purge();
    r.width=501;r.height=500;r.scaleUp=4;assert(!recognizeFrameWithTesseract(r,&error)&&[error.localizedDescription containsString:@"ocr_scaled_image_too_large"]);r.width=r.height=16;r.scaleUp=1;
    {TLinkOCRAdmission a(sZXTessActive),b(sZXTessActive);assert(a&&b);assert(!recognizeFrameWithTesseract(r,&error)&&[error.localizedDescription containsString:@"ocr_busy"]);}
    auto token=std::make_shared<TLinkNativeCancellation>();auto parent=std::make_shared<TLinkNativeBudget>(token,0,4096);token->cancel();{TLinkNativeBudgetScope scope(parent);assert(!recognizeFrameWithTesseract(r,&error)&&[error.localizedDescription containsString:@"ocr_cancelled_or_timed_out"]);}purge();
    assert(engines==0&&images==0&&sZXTessActive==0);puts("Typed OCR Foundation passed: shared actual queue/cache/CV/engine adapter, 12 RAW/typed comparisons, busy/scaled preflight, NS/C++ faults, cold expiry/cancel and released resources.");
}
int main(){@autoreleasepool{
    // The old setter's nil call must clear both Objective-C and native request state.
    @autoreleasepool {G8Tesseract *engine=[[G8Tesseract alloc]initWithLanguage:@"eng" configDictionary:nil configFileNames:nil absoluteDataPath:@"" engineMode:G8OCREngineModeLSTMOnly];
        cv::Mat gray(8,8);UIImage *image=zx_tessUIImageFromGrayMat(gray);engine.image=image;assert(engine->_tesseract->imageBytes==64);engine.image=nil;
        assert(!engine.image&&engine->_tesseract->imageBytes==0&&engine->_tesseract->clears==1&&CGSizeEqualToSize(engine.imageSize,CGSizeZero));}
    assert(engines==0&&images==0);
    typedOCRCases();
    fputs("OCR runtime: actual task orchestration/cache/conversion and vendor nil cleanup\n",stderr);
    for(unsigned n=0;n<1000;++n){@autoreleasepool{NSString *value=run([NSString stringWithFormat:@"list-%u",n]);assert([value componentsSeparatedByString:@";;"].count==6);assert(engines<=2);}}
    assert(images==0&&engines==2&&maxEngines<=2);
    uint64_t hits=sZXTessHits.load();run(@"list-999");assert(sZXTessHits==hits+1);
    dispatch_sync(zx_tessQueue(),^{assert(zx_tessCache().size()==2);});
    unsigned beforeClones=clones;run(@"",1,0);assert(clones==beforeClones);run(@"",1,1);assert(clones==beforeClones+1);
    unsigned beforeROI=roiCalls.load(),beforeResize=resizes;NSError *error=nil;
    assert(!run(@"",4,0,501,500,&error)&&[error.localizedDescription containsString:@"ocr_scaled_image_too_large"]);assert(roiCalls==beforeROI&&resizes==beforeResize);
    run(@"",4,0,500,500);assert(resizes==beforeResize+1);
    pressure=true;run();purge();assert(engines==0&&sZXTessEntries==0);
    run();[NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];purge();assert(engines==0&&sZXTessPressure>=2);
    pressureInit=true;run(@"pressure-init");purge();assert(engines==0&&sZXTessEntries==0);
    slowInit=true;assert(!run(@"slow-init",1,0,16,16,&error)&&[error.localizedDescription containsString:@"ocr_cancelled_or_timed_out"]);clockOffset=0;hits=sZXTessHits.load();run(@"slow-init");assert(sZXTessHits==hits+1);purge();
    throwNS=true;assert(!run(@"throw",1,0,16,16,&error)&&[error.localizedDescription containsString:@"ocr_exception"]);purge();assert(engines==0);
    throwCPP=true;assert(!run(@"throw-cpp",1,0,16,16,&error)&&[error.localizedDescription containsString:@"ocr_exception"]);purge();assert(engines==0);
    failInit=true;assert(!run(@"bad-init",1,0,16,16,&error)&&[error.localizedDescription containsString:@"engine_init_failed"]);purge();
    fputs("OCR runtime: queue residence, bounded admission and inherited cancellation\n",stderr);
    entered=dispatch_semaphore_create(0);releaseCopy=dispatch_semaphore_create(0);holdCopy=true;
    std::atomic<unsigned> expired{0};beforeROI=roiCalls.load();unsigned beforeRecognize=recognizes.load();
    auto waiting=[&]{@autoreleasepool{NSError *failure=nil;assert(!run(@"queued",1,0,16,16,&failure)&&[failure.localizedDescription containsString:@"ocr_cancelled_or_timed_out"]);++expired;}};
    std::thread first(waiting);assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);std::thread second(waiting);
    while(sZXTessActive<2)std::this_thread::yield();
    assert(!run(@"third",1,0,16,16,&error)&&[error.localizedDescription containsString:@"ocr_busy"]);
    clockOffset.fetch_add(4000000000ULL);dispatch_semaphore_signal(releaseCopy);first.join();second.join();clockOffset=0;
    assert(expired==2&&roiCalls==beforeROI+1&&recognizes==beforeRecognize&&sZXTessActive==0);
    auto cancellation=std::make_shared<TLinkNativeCancellation>();auto parent=std::make_shared<TLinkNativeBudget>(cancellation,0,4096);
    cancellation->cancel();{TLinkNativeBudgetScope scope(parent);assert(!run(@"cancelled",1,0,16,16,&error)&&[error.localizedDescription containsString:@"ocr_cancelled_or_timed_out"]);}
    purge();dispatch_sync(zx_tessQueue(),^{});assert(engines==0&&sZXTessActive==0);
    puts("OCR Foundation passed: actual root adapter with doubled CV/engine, real CG provider ownership, vendor nil/Clear branch, 1000 identities, no scale-1 clone, preflight, pressure, exceptions, stale queued jobs and cancellation.");
}}
