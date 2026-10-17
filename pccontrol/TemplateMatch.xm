#include "../shared/TLinkNativeDispatch.h"
//
//  TemplateMatch.cpp
//  OpenCVTest
//
//  Created by Yun CHEN on 2018/2/8.
//  Copyright © 2018年 Yun CHEN. All rights reserved.
//


#import "TemplateMatch.h"
#include <vector>
#include <map>
#include <string>
#include <math.h>
#include <sys/stat.h>
#import <ImageIO/ImageIO.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <mutex>
#include <cstring>

#ifndef ZX_TEMPLATE_MATCH_DEBUG
#define ZX_TEMPLATE_MATCH_DEBUG 0
#endif

#if ZX_TEMPLATE_MATCH_DEBUG && defined(ZX_DAEMON)
#include <stdarg.h>

// Minimal file logger for daemon builds.
// We intentionally avoid depending on tlinkauto-binary/SocketServer.mm static zx_logf().
static NSString *zx_tm_logFilePath(void)
{
    return @"/var/mobile/Library/TLinkauto/tlinkautod.log";
}

static void zx_tm_logf(const char *fmt, ...)
{
    @autoreleasepool {
        char msg[2048];
        va_list args;
        va_start(args, fmt);
        vsnprintf(msg, sizeof(msg), fmt, args);
        va_end(args);

        NSString *dir = @"/var/mobile/Library/TLinkauto";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:true
                                                   attributes:nil
                                                        error:nil];

        NSDate *now = [NSDate date];
        static NSDateFormatter *df = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            df = [[NSDateFormatter alloc] init];
            df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        });

        NSString *line = [NSString stringWithFormat:@"%@ [TemplateMatch] %s\n", [df stringFromDate:now], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return;

        NSString *path = zx_tm_logFilePath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSData data] writeToFile:path atomically:true];
        }

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
        } @catch (__unused NSException *e) {
        }
        @try { [fh closeFile]; } @catch (__unused NSException *e) {}
    }
}

#define TMLOGF(fmt, ...) zx_tm_logf((fmt), ##__VA_ARGS__)
#elif ZX_TEMPLATE_MATCH_DEBUG
#define TMLOGF(fmt, ...) NSLog(@"com.tlinkauto.springboard: " fmt, ##__VA_ARGS__)
#else
#define TMLOGF(fmt, ...) do { } while (0)
#endif



using namespace cv;
using namespace std;

// BEGIN bounded template storage.
struct ZXTemplatePayload {
    std::shared_ptr<TLinkImageCharge> charge;
    std::shared_ptr<const ZXTemplatePayload> dependency;
    std::vector<Mat> mats;
    uint64_t epoch = 0;
};
using ZXTemplateRef = std::shared_ptr<const ZXTemplatePayload>;
static std::mutex sZXTemplateLock;
static TLinkImageMemory sZXTemplateMemory(64*1024*1024,32*1024*1024,96*1024*1024);
static TLinkImageComputeGate sZXTemplateCompute;
static TLinkTemplateLRU<ZXTemplateRef> sZXTemplateBases, sZXTemplateScales;
static uint64_t sZXTemplateEpoch = 1;
static std::atomic<uint64_t> sZXTemplateHits{0},sZXTemplateMisses{0},sZXTemplatePressure{0};
static void zx_tmError(NSError **error, const char *code) {
    if(error) *error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%s\r\n",code]}];
}
static void zx_tmPurge(void) {
    std::lock_guard<std::mutex> lock(sZXTemplateLock); ++sZXTemplateEpoch;
    sZXTemplateScales.clear();sZXTemplateBases.clear();sZXTemplatePressure.fetch_add(1);
}
static void zx_tmObservePressure(void) {
    static dispatch_once_t once;static dispatch_source_t source;static id observer;
    dispatch_once(&once, ^{
        observer=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil
            usingBlock:^(NSNotification *note){(void)note;zx_tmPurge();}];(void)observer;
        source=dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE,0,DISPATCH_MEMORYPRESSURE_WARN|DISPATCH_MEMORYPRESSURE_CRITICAL,
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0));
        if(source){dispatch_source_set_event_handler(source,^{zx_tmPurge();});dispatch_resume(source);}
    });
}
static std::shared_ptr<TLinkImageCharge> zx_tmReserve(TLinkImageKind kind,size_t bytes) {
    // Cache eviction cannot free frame/work-category capacity.
    if(kind==TLinkImageKind::Frame)return sZXTemplateMemory.reserve(kind,bytes);
    std::lock_guard<std::mutex> lock(sZXTemplateLock);
    auto charge=sZXTemplateMemory.reserve(kind,bytes);
    while(!charge&&(sZXTemplateScales.evict()||sZXTemplateBases.evict())) charge=sZXTemplateMemory.reserve(kind,bytes);
    return charge;
}
struct ZXTemplateFile {
    int fd;
    explicit ZXTemplateFile(NSString *path):fd(path ? open(path.fileSystemRepresentation,O_RDONLY|O_CLOEXEC|O_NONBLOCK) : -1){}
    ~ZXTemplateFile(){if(fd>=0)close(fd);}
};
static std::string zx_tmFingerprint(NSString *path,const struct stat &st) {
    const char *text=path.UTF8String;std::string key=text?text:"";
    char suffix[256];snprintf(suffix,sizeof(suffix),"|%llu|%llu|%lld|%lld:%ld|%lld:%ld",
        (unsigned long long)st.st_dev,(unsigned long long)st.st_ino,(long long)st.st_size,
        (long long)st.st_mtimespec.tv_sec,st.st_mtimespec.tv_nsec,(long long)st.st_ctimespec.tv_sec,st.st_ctimespec.tv_nsec);
    return std::to_string(key.size())+":"+key+suffix;
}
// The caller owns the pool and encoded-data reservation through its drainage.
static ZXTemplateRef zx_tmLoadInPool(NSString *path,bool base,std::string *identity,NSError **error,
                                    std::shared_ptr<TLinkImageCharge> &encodedCharge) {
    auto request=TLinkTemplateCurrentRequest();
    if(request&&request->stopped()){zx_tmError(error,request->error());return {};}
    ZXTemplateFile file(path);struct stat before;
    if(file.fd<0||fstat(file.fd,&before)||!S_ISREG(before.st_mode)||before.st_size<=0||uint64_t(before.st_size)>kTLinkTemplateEncodedBytes){zx_tmError(error,"template_file_invalid_or_too_large");return {};}
    std::string key=zx_tmFingerprint(path,before);if(identity)*identity=key;
    uint64_t epoch;
    {
        std::lock_guard<std::mutex> lock(sZXTemplateLock);epoch=sZXTemplateEpoch;
        if(base){auto hit=sZXTemplateBases.get(key);if(hit){sZXTemplateHits.fetch_add(1);return hit;}}
    }
    sZXTemplateMisses.fetch_add(1);
    encodedCharge=zx_tmReserve(TLinkImageKind::Frame,size_t(before.st_size)+1);
    if(!encodedCharge){zx_tmError(error,"template_memory_budget");return {};}
    NSMutableData *encoded=[NSMutableData dataWithLength:size_t(before.st_size)+1];
    if(!encoded){zx_tmError(error,"template_decode_failed");return {};}
    size_t readBytes=0;
    while(readBytes<size_t(before.st_size)+1){
        if(request&&request->stopped()){zx_tmError(error,request->error());return {};}
        ssize_t count=read(file.fd,(uint8_t *)encoded.mutableBytes+readBytes,std::min(size_t(65536),size_t(before.st_size)+1-readBytes));
        if(count<0&&errno==EINTR)continue;
        if(count<0){zx_tmError(error,"template_read_failed");return {};}if(!count)break;readBytes+=size_t(count);
    }
    struct stat after;
    if(readBytes!=size_t(before.st_size)||fstat(file.fd,&after)||key!=zx_tmFingerprint(path,after)){zx_tmError(error,"template_file_changed");return {};}
    [encoded setLength:readBytes];
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)encoded,NULL);
    NSDictionary *properties=source?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)):nil;
    if(source)CFRelease(source);
    size_t pixels=0;
    if(!TLinkImagePixels([properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue],
        [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue],base?kTLinkTemplatePixels:kTLinkTemplateScreenPixels,&pixels)){
        zx_tmError(error,"template_pixel_limit");return {};
    }
    auto charge=zx_tmReserve(base?TLinkImageKind::Image:TLinkImageKind::Frame,pixels);
    if(!charge){zx_tmError(error,"template_memory_budget");return {};}
    if(request&&request->stopped()){zx_tmError(error,request->error());return {};}
    cv::Mat input(1,(int)encoded.length,CV_8UC1,encoded.mutableBytes);
    cv::Mat gray=cv::imdecode(input,IMREAD_GRAYSCALE);
    if(gray.empty()||gray.type()!=CV_8UC1||uint64_t(gray.rows)*gray.cols!=pixels){zx_tmError(error,"template_decode_failed");return {};}
    auto result=std::make_shared<ZXTemplatePayload>();result->epoch=epoch;result->charge=std::move(charge);result->mats.push_back(gray);
    if(request&&request->stopped()){zx_tmError(error,request->error());return {};}
    if(base){std::lock_guard<std::mutex> lock(sZXTemplateLock);if(epoch==sZXTemplateEpoch)sZXTemplateBases.put(key,result,16);}
    return result;
}
static ZXTemplateRef zx_tmLoad(NSString *path,bool base,std::string *identity,NSError **error) {
    // ARC writes the helper's autoreleasing result back to this strong local BEFORE
    // the pool drains. Forward to the caller only AFTER drainage, in its own pool.
    NSError *failure=nil;
    std::shared_ptr<TLinkImageCharge> encodedCharge;
    ZXTemplateRef result;
    @autoreleasepool {
        result=zx_tmLoadInPool(path,base,identity,&failure,encodedCharge);
    }
    if(error&&failure)*error=failure;
    return result;
}
static std::string zx_tmScaledKey(const std::string &base,const TLinkTemplatePlan &plan,float sr,int tries) {
    uint32_t ratioBits,scaleBits;std::memcpy(&ratioBits,&plan.ratio,sizeof(ratioBits));std::memcpy(&scaleBits,&sr,sizeof(scaleBits));
    char suffix[192];snprintf(suffix,sizeof(suffix),"|%d:%d:%d:%d|%08x:%08x:%d",plan.screenWidth,plan.screenHeight,
        plan.templateWidth,plan.templateHeight,ratioBits,scaleBits,tries);return base+suffix;
}
NSDictionary *TLinkTemplateMatchPerformance(void) {
    auto bytes=sZXTemplateMemory.stats();std::lock_guard<std::mutex> lock(sZXTemplateLock);
    return @{@"base_entries":@(sZXTemplateBases.size()),@"scaled_entries":@(sZXTemplateScales.size()),
        @"payload_bytes":@(bytes.images),@"work_bytes":@(bytes.frames),@"total_bytes":@(bytes.total),@"peak_bytes":@(bytes.peak),
        @"payload_limit_bytes":@(32*1024*1024),@"total_limit_bytes":@(96*1024*1024),@"cache_hits":@(sZXTemplateHits.load()),
        @"cache_misses":@(sZXTemplateMisses.load()),@"purge_count":@(sZXTemplatePressure.load()),@"max_tries":@8,@"request_budget_ms":@8000,
        @"max_concurrent_calls":@2,@"work_comparison_limit":@256000000,@"max_pyramid_bytes":@(kTLinkTemplatePyramidBytes),
        @"encoded_file_limit_bytes":@(kTLinkTemplateEncodedBytes),@"work_limit_bytes":@(64*1024*1024)};
}
// END bounded template storage.


static long long zx_sad_match_region(const Mat &img, const Mat &templ,
                                    int x0, int y0, int x1, int y1,
                                    int step, int *bestX, int *bestY)
{
    auto nativeBudget = TLinkCurrentNativeBudget();
    auto request = TLinkTemplateCurrentRequest();
    const int w = templ.cols;
    const int h = templ.rows;

    long long bestSad = LLONG_MAX;
    int bx = 0;
    int by = 0;

    if (step <= 0) step = 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    const int maxX = img.cols - w;
    const int maxY = img.rows - h;
    if (x1 > maxX) x1 = maxX;
    if (y1 > maxY) y1 = maxY;
    if (x0 > x1 || y0 > y1) {
        if (bestX) *bestX = 0;
        if (bestY) *bestY = 0;
        return bestSad;
    }

    for (int y = y0; y <= y1; y += step) {
        if ((nativeBudget && nativeBudget->stopped()) || (request && request->stopped())) return LLONG_MAX;
        for (int x = x0; x <= x1; x += step) {
            long long sad = 0;
            for (int ty = 0; ty < h; ty++) {
                if ((ty & 31) == 0 && ((nativeBudget && nativeBudget->stopped()) || (request && request->stopped()))) return LLONG_MAX;
                const unsigned char *imgRow = img.ptr<unsigned char>(y + ty) + x;
                const unsigned char *tRow = templ.ptr<unsigned char>(ty);
                for (int tx = 0; tx < w; tx++) {
                    if ((tx & 4095) == 0) {
                        if ((nativeBudget && nativeBudget->stopped()) || (request && !request->consume(std::min(size_t(4096),size_t(w-tx))))) return LLONG_MAX;
                    }
                    sad += (long long)abs((int)imgRow[tx] - (int)tRow[tx]);
                }
                if (sad >= bestSad) {
                    break;
                }
            }
            if (sad < bestSad) {
                bestSad = sad;
                bx = x;
                by = y;
            }
        }
    }

    if (bestX) *bestX = bx;
    if (bestY) *bestY = by;
    return bestSad;
}



@interface TemplateMatch() {
    UIImage *_templateImage;
    int maxTryTimes;
    float acceptableValue;
    float scaleRation;
    float resizeRatio;
}

- (CGRect)matchWithMat:(Mat)img andTemplate:(ZXTemplateRef)templ identity:(const std::string &)identity error:(NSError **)error;

@end



@implementation TemplateMatch

//static float resizeRatio = 0.35;              //原图缩放比例，越小性能越好，但识别度越低
//static int maxTryTimes = 4;                   //未达到预定识别度时，再尝试的次数限制
//static float acceptableValue = 0.9;           //达到此识别度才被认为正确
//static float scaleRation = 0.75;              //当模板未被识别时，尝试放大/缩小模板。 指定每次模板缩小的比例

- (void)setScaleRation:(float)sr {
    scaleRation = sr;
}

- (void)setAcceptableValue:(float)av {
    acceptableValue = av;
}

- (void)setMaxTryTimes:(int)mtt {
    maxTryTimes = mtt;
}

- (id)init {
    self = [super init];
    if (self) {
        resizeRatio = 1.0f;
    }
    return self;
}

- (CGRect)templateMatchWithCGImage:(CGImageRef)image templatePath:(NSString*)path error:(NSError**)error {
    auto request=std::make_shared<TLinkTemplateRequest>(TLinkCurrentNativeBudget());TLinkTemplateRequestScope scope(request);
    TLinkImageWork work(sZXTemplateCompute);
    if(!work){zx_tmError(error,"template_compute_busy");return CGRect();}
    if(!TLinkTemplateParametersValid(maxTryTimes,scaleRation,acceptableValue)){zx_tmError(error,"template_parameters_invalid");return CGRect();}
    zx_tmObservePressure();
    try { @try {
        size_t pixels=0;
        if(!image||!TLinkImagePixels(CGImageGetWidth(image),CGImageGetHeight(image),kTLinkTemplateScreenPixels,&pixels)){zx_tmError(error,"template_screen_pixel_limit");return CGRect();}
        std::string identity;auto templ=zx_tmLoad(path,true,&identity,error);if(!templ)return CGRect();
        auto charge=zx_tmReserve(TLinkImageKind::Frame,pixels*5);if(!charge){zx_tmError(error,"template_memory_budget");return CGRect();}
        if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
        Mat rgba((int)CGImageGetHeight(image),(int)CGImageGetWidth(image),CV_8UC4);
        CGColorSpaceRef color=CGImageGetColorSpace(image),owned=NULL;
        if(!color){owned=CGColorSpaceCreateDeviceRGB();color=owned;}
        CGContextRef context=CGBitmapContextCreate(rgba.data,rgba.cols,rgba.rows,8,rgba.step[0],color,kCGImageAlphaNoneSkipLast|kCGBitmapByteOrderDefault);
        if(owned)CGColorSpaceRelease(owned);
        if(!context){zx_tmError(error,"template_context_failed");return CGRect();}
        CGContextDrawImage(context,CGRectMake(0,0,rgba.cols,rgba.rows),image);CGContextRelease(context);
        Mat gray;cv::cvtColor(rgba,gray,COLOR_RGBA2GRAY);rgba.release();
        if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
        return [self matchWithMat:gray andTemplate:templ identity:identity error:error];
    } @catch(NSException *exception){(void)exception;zx_tmError(error,"template_operation_failed");return CGRect();}
    } catch(const std::exception &exception){(void)exception;zx_tmError(error,"template_operation_failed");return CGRect();}
}

- (CGRect)templateMatchWithPath:(NSString*)imagePath templatePath:(NSString*)path error:(NSError**)error {
    auto request=std::make_shared<TLinkTemplateRequest>(TLinkCurrentNativeBudget());TLinkTemplateRequestScope scope(request);
    TLinkImageWork work(sZXTemplateCompute);
    if(!work){zx_tmError(error,"template_compute_busy");return CGRect();}
    if(!TLinkTemplateParametersValid(maxTryTimes,scaleRation,acceptableValue)){zx_tmError(error,"template_parameters_invalid");return CGRect();}
    zx_tmObservePressure();
    try { @try {
        std::string identity;auto templ=zx_tmLoad(path,true,&identity,error);if(!templ)return CGRect();
        auto image=zx_tmLoad(imagePath,false,NULL,error);if(!image)return CGRect();
        return [self matchWithMat:image->mats[0] andTemplate:templ identity:identity error:error];
    } @catch(NSException *exception){(void)exception;zx_tmError(error,"template_operation_failed");return CGRect();}
    } catch(const std::exception &exception){(void)exception;zx_tmError(error,"template_operation_failed");return CGRect();}
}

//uncompleted
- (CGRect)templateMatchWithUIImage:(UIImage*)img template:(UIImage*)templ {
    //return [self matchWithMat:[self cvMatFromUIImage:img] andTemplate:[self cvMatFromUIImage:templ]];
    return CGRect();
}

//调用OpenCV进行匹配
//此方法具体解释参考OpenCV官方文档: https://docs.opencv.org/3.2.0/de/da9/tutorial_template_matching.html
- (CGRect)matchWithMat:(Mat)img andTemplate:(Mat)templ {
    auto request=std::make_shared<TLinkTemplateRequest>(TLinkCurrentNativeBudget());TLinkTemplateRequestScope scope(request);
    TLinkImageWork work(sZXTemplateCompute);if(!work)return CGRect();
    size_t pixels=0,screen=0;
    if(!TLinkImagePixels(templ.cols,templ.rows,kTLinkTemplatePixels,&pixels)||!TLinkImagePixels(img.cols,img.rows,kTLinkTemplateScreenPixels,&screen))return CGRect();
    auto charge=zx_tmReserve(TLinkImageKind::Image,pixels),screenCharge=zx_tmReserve(TLinkImageKind::Frame,screen);
    if(!charge||!screenCharge)return CGRect();
    auto payload=std::make_shared<ZXTemplatePayload>();payload->charge=charge;payload->mats.push_back(templ);
    try{return [self matchWithMat:img andTemplate:payload identity:std::string() error:NULL];}
    catch(const std::exception &exception){(void)exception;return CGRect();}
}

- (CGRect)matchWithMat:(Mat)img andTemplate:(ZXTemplateRef)base identity:(const std::string &)identity error:(NSError **)error {
    auto request=TLinkTemplateCurrentRequest();
    if(!request||request->stopped()){zx_tmError(error,"template_cancelled_or_timed_out");return CGRect();}
    if(!base||base->mats.empty()||img.empty()||img.type()!=CV_8UC1||base->mats[0].type()!=CV_8UC1||
        !TLinkTemplateParametersValid(maxTryTimes,scaleRation,acceptableValue)){zx_tmError(error,"template_parameters_invalid");return CGRect();}
    Mat templ=base->mats[0];TLinkTemplatePlan plan;
    if(!TLinkTemplateMakePlan(img.cols,img.rows,templ.cols,templ.rows,resizeRatio,maxTryTimes,scaleRation,
        [](double value){return cvRound(value);},plan)){zx_tmError(error,"template_scale_budget");return CGRect();}
    if(plan.scales.empty())return CGRect();
    static std::once_flag threads;
    std::call_once(threads,[]{cv::setNumThreads(1);});
    auto resizeCharge=plan.ratio!=1 ? zx_tmReserve(TLinkImageKind::Frame,size_t(plan.screenWidth)*plan.screenHeight) : std::shared_ptr<TLinkImageCharge>();
    // Mat releases first; another caller cannot reuse these bytes while they are live.
    Mat imgWork=img;
    if(plan.ratio!=1&&!resizeCharge){zx_tmError(error,"template_memory_budget");return CGRect();}
    if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
    if(plan.ratio!=1)cv::resize(img,imgWork,cv::Size(0,0),plan.ratio,plan.ratio,cv::INTER_AREA);
    if(imgWork.empty()||imgWork.cols!=plan.screenWidth||imgWork.rows!=plan.screenHeight){zx_tmError(error,"template_scale_geometry_changed");return CGRect();}
    const std::string key=zx_tmScaledKey(identity,plan,scaleRation,maxTryTimes);
    ZXTemplateRef pyramid;uint64_t epoch;
    {
        std::lock_guard<std::mutex> lock(sZXTemplateLock);epoch=sZXTemplateEpoch;
        if(!identity.empty())pyramid=sZXTemplateScales.get(key);
    }
    if(pyramid)sZXTemplateHits.fetch_add(1);
    else {
        sZXTemplateMisses.fetch_add(1);
        // The entire pyramid is admitted before the first template resize.
        auto charge=zx_tmReserve(TLinkImageKind::Image,plan.bytes);
        if(!charge){zx_tmError(error,"template_memory_budget");return CGRect();}
        auto pending=std::make_shared<ZXTemplatePayload>();pending->epoch=epoch;pending->charge=std::move(charge);pending->dependency=base;
        auto workCharge=plan.ratio!=1 ? zx_tmReserve(TLinkImageKind::Frame,size_t(plan.templateWidth)*plan.templateHeight) : std::shared_ptr<TLinkImageCharge>();
        if(plan.ratio!=1&&!workCharge){zx_tmError(error,"template_memory_budget");return CGRect();}
        Mat templWork=templ;
        if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
        if(plan.ratio!=1)cv::resize(templ,templWork,cv::Size(0,0),plan.ratio,plan.ratio,cv::INTER_AREA);
        for(const auto &scale:plan.scales){
            if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
            Mat resized;
            if(scale.factor==1)resized=templWork;
            else cv::resize(templWork,resized,cv::Size(0,0),scale.factor,scale.factor,cv::INTER_LINEAR);
            if(resized.empty()||resized.cols!=scale.width||resized.rows!=scale.height||resized.total()>scale.bytes){zx_tmError(error,"template_scale_geometry_changed");return CGRect();}
            pending->mats.push_back(resized);
        }
        pyramid=pending;
        if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
        if(!identity.empty()){std::lock_guard<std::mutex> lock(sZXTemplateLock);if(epoch==sZXTemplateEpoch&&base->epoch==epoch)sZXTemplateScales.put(key,pyramid,32);}
    }
    for(const Mat &current:pyramid->mats){
        if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
        if(current.cols>imgWork.cols||current.rows>imgWork.rows)continue;
        int bx=0,by=0;
        long long sad=zx_sad_match_region(imgWork,current,0,0,imgWork.cols-current.cols,imgWork.rows-current.rows,4,&bx,&by);
        if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
        int rx=bx,ry=by;
        long long refined=zx_sad_match_region(imgWork,current,bx-8,by-8,bx+8,by+8,1,&rx,&ry);
        if(request->stopped()){zx_tmError(error,request->error());return CGRect();}
        if(refined<sad){sad=refined;bx=rx;by=ry;}
        const double score=1.0-double(sad)/(255.0*current.cols*current.rows);
        if(score>=acceptableValue){const CGFloat inverse=1.0/plan.ratio;return CGRectMake(bx*inverse,by*inverse,current.cols*inverse,current.rows*inverse);}
    }
    return CGRect();
}

//UIImage转为OpenCV灰图矩阵
- (Mat)cvMatGrayFromUIImage:(UIImage *)image {
    Mat img;
    Mat img_color = [self cvMatFromUIImage:image];
    cvtColor(img_color, img, COLOR_BGR2GRAY);
    
    return img;
}

//UIImage转为OpenCV矩阵 BUGS exists for color picker!!! Do NOT USE THIS
- (Mat)cvMatFromUIImage:(UIImage *)image {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    Mat cvMat(rows, cols, CV_8UC4); // 8位图, 4通道 (颜色 通道 + alpha)
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // 数据来源
                                                    cols,                       // 宽
                                                    rows,                       // 高
                                                    8,                          // 8位
                                                    cvMat.step[0],              // 每行字节
                                                    colorSpace,                 // 颜色空间
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap图信息
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}

//Buffer转为OpenCV矩阵
- (Mat)cvMatFromBuffer:(CMSampleBufferRef)buffer {
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(buffer);
    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    
    //取得高宽，以及数据起始地址
    int bufferWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
    int bufferHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    unsigned char *pixel = (unsigned char *)CVPixelBufferGetBaseAddress(pixelBuffer);
    
    //转为OpenCV矩阵
    Mat mat = Mat(bufferHeight,bufferWidth,CV_8UC4,pixel,CVPixelBufferGetBytesPerRow(pixelBuffer));
    
    //结束处理
    CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
    
    //转为灰度图矩阵
    Mat matGray;
    cvtColor(mat, matGray, COLOR_BGR2GRAY);
    
    return matGray;
}


@end
