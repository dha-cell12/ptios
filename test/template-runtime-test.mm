#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <cstdio>
#include <cassert>
#include <cstring>
#include <thread>
#include <stdexcept>
#include "../shared/TLinkNativeBudget.h"
static std::atomic<uint64_t> offset{0};
static uint64_t FixtureNow(){return TLinkNativeNowNs()+offset.load();}
#include "TemplatePolicyUnderTest.h"
static std::atomic<bool> expireDecode{false},expireResize{false},purgeDecode{false},purgeResize{false},blockDecode{false},failDecode{false};
static std::atomic<unsigned> decodes{0},resizes{0},threadSettings{0};
static dispatch_semaphore_t decodeEntered,decodeRelease;
static void zx_tmPurge(void);
static bool failContext=false;
static CGContextRef FixtureBitmapContext(void *data,size_t width,size_t height,size_t bits,size_t stride,CGColorSpaceRef color,uint32_t flags){
    if(failContext){failContext=false;return NULL;}return CGBitmapContextCreate(data,width,height,bits,stride,color,flags);
}
static int cvRound(double value){return static_cast<int>(std::nearbyint(value));}
#define CV_8UC1 1
#define CV_8UC4 4
namespace cv {
static const int IMREAD_GRAYSCALE=0,INTER_AREA=1,INTER_LINEAR=2,COLOR_RGBA2GRAY=3,COLOR_BGR2GRAY=4;
struct Size {int width,height;Size(int w,int h):width(w),height(h){}};
struct Mat {
    int rows=0,cols=0,kind=CV_8UC1;uint8_t *data=nullptr;size_t step[1]={0};
    std::shared_ptr<std::vector<uint8_t>> storage;
    Mat(){}
    Mat(int h,int w,int type):rows(h),cols(w),kind(type),storage(std::make_shared<std::vector<uint8_t>>(size_t(h)*w*type)){data=storage->data();step[0]=size_t(w)*type;}
    Mat(int h,int w,int type,void *bytes,size_t stride=0):rows(h),cols(w),kind(type),data((uint8_t *)bytes){step[0]=stride?stride:size_t(w)*type;}
    bool empty()const{return !data||rows<=0||cols<=0;}int type()const{return kind;}size_t total()const{return size_t(rows)*cols;}
    template<class T>const T *ptr(int row)const{return reinterpret_cast<const T *>(data+size_t(row)*step[0]);}
    void release(){storage.reset();data=nullptr;rows=cols=0;}
};
static void setNumThreads(int count){assert(count==1);threadSettings.fetch_add(1);}
static void resize(const Mat &input,Mat &out,Size size,double fx=0,double fy=0,int interpolation=INTER_LINEAR){
    (void)interpolation;resizes.fetch_add(1);
    int w=size.width?size.width:cvRound(input.cols*fx),h=size.height?size.height:cvRound(input.rows*fy);assert(w>0&&h>0);
    Mat result(h,w,input.kind);
    for(int y=0;y<h;++y)for(int x=0;x<w;++x)for(int c=0;c<input.kind;++c)
        result.data[(size_t(y)*w+x)*input.kind+c]=input.data[(size_t(std::min(input.rows-1,int(y*double(input.rows)/h)))*input.cols+std::min(input.cols-1,int(x*double(input.cols)/w)))*input.kind+c];
    out=result;
    if(expireResize.exchange(false))offset.fetch_add(9000000000ULL);
    if(purgeResize.exchange(false))zx_tmPurge();
}
static void cvtColor(const Mat &input,Mat &out,int mode){(void)mode;Mat result(input.rows,input.cols,CV_8UC1);for(int y=0;y<input.rows;++y)for(int x=0;x<input.cols;++x)result.data[size_t(y)*input.cols+x]=input.data[size_t(y)*input.step[0]+size_t(x)*input.kind];out=result;}
static Mat imdecode(const Mat &encoded,int flags){
    (void)flags;decodes.fetch_add(1);
    if(blockDecode.exchange(false)){dispatch_semaphore_signal(decodeEntered);assert(dispatch_semaphore_wait(decodeRelease,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    if(failDecode.exchange(false))throw std::runtime_error("fixture decode failure");
    NSData *bytes=[NSData dataWithBytes:encoded.data length:encoded.total()];
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)bytes,NULL);assert(source);
    CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);CFRelease(source);assert(image);
    Mat out((int)CGImageGetHeight(image),(int)CGImageGetWidth(image),CV_8UC1);
    CGColorSpaceRef gray=CGColorSpaceCreateDeviceGray();
    CGContextRef context=CGBitmapContextCreate(out.data,out.cols,out.rows,8,out.step[0],gray,kCGImageAlphaNone);CGColorSpaceRelease(gray);assert(context);
    CGContextDrawImage(context,CGRectMake(0,0,out.cols,out.rows),image);CGContextRelease(context);CGImageRelease(image);
    if(expireDecode.exchange(false))offset.fetch_add(9000000000ULL);
    if(purgeDecode.exchange(false))zx_tmPurge();
    return out;
}
}
@interface UIImage:NSObject
@property(nonatomic,readonly) CGImageRef CGImage;
@property(nonatomic,readonly) CGSize size;
@end
@implementation UIImage
- (CGImageRef)CGImage{return NULL;}
- (CGSize)size{return CGSizeZero;}
@end
static NSString *const UIApplicationDidReceiveMemoryWarningNotification=@"fixture.template.memory-warning";
@interface TemplateMatch:NSObject
@property(nonatomic,strong) UIImage *templateImage;
- (void)setScaleRation:(float)value;
- (void)setAcceptableValue:(float)value;
- (void)setMaxTryTimes:(int)value;
- (CGRect)templateMatchWithPath:(NSString *)path templatePath:(NSString *)templ error:(NSError **)error;
- (CGRect)templateMatchWithCGImage:(CGImageRef)image templatePath:(NSString *)templ error:(NSError **)error;
@end
#include "TemplateUnderTest.inc"
static NSData *png(const cv::Mat &image){
    CGColorSpaceRef gray=CGColorSpaceCreateDeviceGray();
    CGContextRef context=CGBitmapContextCreate(image.data,image.cols,image.rows,8,image.step[0],gray,kCGImageAlphaNone);CGColorSpaceRelease(gray);assert(context);
    CGImageRef source=CGBitmapContextCreateImage(context);CGContextRelease(context);
    NSMutableData *bytes=[NSMutableData data];CGImageDestinationRef dest=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)bytes,CFSTR("public.png"),1,NULL);assert(dest);
    CGImageDestinationAddImage(dest,source,NULL);assert(CGImageDestinationFinalize(dest));CFRelease(dest);CGImageRelease(source);return bytes;
}
static TemplateMatch *matcher(){TemplateMatch *value=[TemplateMatch new];[value setMaxTryTimes:2];[value setAcceptableValue:1];[value setScaleRation:.8f];return value;}
static void noLiveWork(){auto bytes=sZXTemplateMemory.stats();assert(bytes.frames==0&&bytes.images<=32*1024*1024&&bytes.total<=96*1024*1024);}
int main(int argc,char **argv){assert(argc==2);@autoreleasepool{
    NSString *root=[NSString stringWithUTF8String:argv[1]],*screenPath=[root stringByAppendingPathComponent:@"screen.png"],*templPath=[root stringByAppendingPathComponent:@"needle.png"];
    cv::Mat image(24,32,CV_8UC1),needle(8,8,CV_8UC1);
    for(size_t i=0;i<image.total();++i)image.data[i]=(uint8_t)((i*17+11)%251);
    for(size_t i=0;i<needle.total();++i)needle.data[i]=(uint8_t)(200+i*5);
    for(int y=0;y<needle.rows;++y)memcpy(image.data+size_t(y+8)*image.cols+12,needle.ptr<uint8_t>(y),needle.cols);
    assert([png(image) writeToFile:screenPath atomically:true]&&[png(needle) writeToFile:templPath atomically:true]);
    fputs("Template Foundation: actual loader/cache/plan/matcher with real PNG/ImageIO and controlled CV\n",stderr);
    NSError *error=nil;TemplateMatch *tm=matcher();CGRect rect=[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];
    assert(!error&&rect.origin.x==12&&rect.origin.y==8&&rect.size.width==8&&rect.size.height==8);noLiveWork();
    uint64_t hits=sZXTemplateHits.load();rect=[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];assert(!error&&rect.size.width==8&&sZXTemplateHits>=hits+2&&threadSettings==1);noLiveWork();
    cv::Mat rgba(image.rows,image.cols,CV_8UC4);
    for(size_t i=0;i<image.total();++i){rgba.data[i*4]=rgba.data[i*4+1]=rgba.data[i*4+2]=image.data[i];rgba.data[i*4+3]=255;}
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(rgba.data,rgba.cols,rgba.rows,8,rgba.step[0],rgb,kCGImageAlphaNoneSkipLast|kCGBitmapByteOrderDefault);CGColorSpaceRelease(rgb);assert(context);
    CGImageRef captured=CGBitmapContextCreateImage(context);CGContextRelease(context);assert(captured);
    error=nil;rect=[tm templateMatchWithCGImage:captured templatePath:templPath error:&error];assert(!error&&rect.size.width==8);noLiveWork();
    failContext=true;error=nil;(void)[tm templateMatchWithCGImage:captured templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_context_failed"]);CGImageRelease(captured);noLiveWork();error=nil;
    auto held=zx_tmLoad(templPath,true,NULL,&error);size_t retained=sZXTemplateMemory.stats().images;zx_tmPurge();assert(sZXTemplateMemory.stats().images>0&&sZXTemplateMemory.stats().images<=retained);held.reset();assert(sZXTemplateMemory.stats().total==0);
    // Atomic replacement at the same path/mtime must get a new immutable payload.
    auto old=zx_tmLoad(templPath,true,NULL,&error);NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:templPath error:NULL];
    cv::Mat replacement=needle;replacement.storage=std::make_shared<std::vector<uint8_t>>(*needle.storage);replacement.data=replacement.storage->data();std::fill(replacement.storage->begin(),replacement.storage->end(),uint8_t(37));
    assert([png(replacement) writeToFile:templPath atomically:true]);assert([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:attrs[NSFileModificationDate]} ofItemAtPath:templPath error:NULL]);
    auto fresh=zx_tmLoad(templPath,true,NULL,&error);assert(old!=fresh&&old->mats[0].data[0]!=fresh->mats[0].data[0]);old.reset();fresh.reset();zx_tmPurge();
    assert([png(needle) writeToFile:templPath atomically:true]);
    unsigned before=decodes.load();[tm setMaxTryTimes:100000];error=nil;(void)[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_parameters_invalid"]&&decodes==before);[tm setMaxTryTimes:2];
    NSString *broken=[root stringByAppendingPathComponent:@"broken.png"];assert([[@"bad image" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:broken atomically:true]);
    error=nil;(void)[tm templateMatchWithPath:broken templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_pixel_limit"]);noLiveWork();
    cv::Mat wide(1,8193,CV_8UC1);NSString *widePath=[root stringByAppendingPathComponent:@"wide.png"];assert([png(wide) writeToFile:widePath atomically:true]);
    before=decodes.load();error=nil;(void)[tm templateMatchWithPath:screenPath templatePath:widePath error:&error];assert([error.localizedDescription containsString:@"template_pixel_limit"]&&decodes==before);noLiveWork();
    NSString *large=[root stringByAppendingPathComponent:@"large.dat"];int fd=open(large.fileSystemRepresentation,O_CREAT|O_RDWR,0600);assert(fd>=0&&ftruncate(fd,kTLinkTemplateEncodedBytes+1)==0);close(fd);
    error=nil;(void)[tm templateMatchWithPath:large templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_file_invalid_or_too_large"]);noLiveWork();
    zx_tmPurge();expireDecode=true;error=nil;(void)[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_cancelled_or_timed_out"]);offset=0;noLiveWork();
    zx_tmPurge();failDecode=true;error=nil;(void)[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_operation_failed"]);noLiveWork();
    purgeDecode=true;error=nil;(void)[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];assert(!error);{std::lock_guard<std::mutex> lock(sZXTemplateLock);assert(sZXTemplateBases.size()==0&&sZXTemplateScales.size()==0);}noLiveWork();
    // Force a large-screen downscale; the eight-second budget includes this preparation.
    cv::Mat big(800,800,CV_8UC1);NSString *bigPath=[root stringByAppendingPathComponent:@"big.png"];assert([png(big) writeToFile:bigPath atomically:true]);
    expireResize=true;error=nil;(void)[tm templateMatchWithPath:bigPath templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_cancelled_or_timed_out"]);offset=0;noLiveWork();
    zx_tmPurge();purgeResize=true;error=nil;(void)[tm templateMatchWithPath:bigPath templatePath:templPath error:&error];assert(!error);
    {std::lock_guard<std::mutex> lock(sZXTemplateLock);assert(sZXTemplateBases.size()==0&&sZXTemplateScales.size()==0);}noLiveWork();
    zx_tmPurge();auto active=sZXTemplateMemory.reserve(TLinkImageKind::Image,32*1024*1024);assert(active);
    error=nil;(void)[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_memory_budget"]);active.reset();zx_tmPurge();assert(sZXTemplateMemory.stats().total==0);
    fputs("Template Foundation: two compute admissions, cancellation and all resources released\n",stderr);
    decodeEntered=dispatch_semaphore_create(0);decodeRelease=dispatch_semaphore_create(0);blockDecode=true;
    std::thread first([&]{@autoreleasepool{NSError *failure=nil;(void)[matcher() templateMatchWithPath:screenPath templatePath:templPath error:&failure];assert(!failure);}});
    assert(dispatch_semaphore_wait(decodeEntered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    {TLinkImageWork second(sZXTemplateCompute);assert(second);error=nil;(void)[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_compute_busy"]);}
    dispatch_semaphore_signal(decodeRelease);first.join();
    auto token=std::make_shared<TLinkNativeCancellation>();auto budget=std::make_shared<TLinkNativeBudget>(token,0,4096);token->cancel();
    {TLinkNativeBudgetScope scope(budget);error=nil;(void)[tm templateMatchWithPath:screenPath templatePath:templPath error:&error];assert([error.localizedDescription containsString:@"template_cancelled_or_timed_out"]);}
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];assert(sZXTemplateMemory.stats().total==0);
    NSDictionary *stats=TLinkTemplateMatchPerformance();assert([stats[@"payload_bytes"] unsignedLongLongValue]==0&&[stats[@"work_bytes"] unsignedLongLongValue]==0);
    puts("Template Foundation passed: file bounds, real metadata/PNG/provider lifetime, immutable replacement snapshots, cache hits, pressure epochs, preparation expiry, exceptions, live-byte rejection and compute admission. Real OpenCV interpolation/device qualification remains pending.");
}}
