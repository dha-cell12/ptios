#include "../shared/TLinkModernImagePolicy.h"
#include "../shared/TLinkFrameVisionPolicy.h"
#include <new>
#include "../shared/TLinkOCRPolicy.h"
#include "../shared/TLinkNativeDispatch.h"
#import "Image.h"
#include "../shared/TLinkNativeFrameCaptureResult.h"
#import <ImageIO/ImageIO.h>
#include "../shared/TLinkImageStorage.h"
#import "Screen.h"
#import "Common.h"
#import "ScriptPlayer.h"

#include <dispatch/dispatch.h>
#include <unordered_map>
#include <climits>
#include <math.h>
#include <vector>
#include <stdint.h>
#include <string>

// From Play.xm
extern ScriptPlayer *scriptPlayer;

using namespace cv;
using namespace std;

// BEGIN immutable image payload types (also compiled by native storage tests).
struct ZXImageObject {
    std::shared_ptr<TLinkImageCharge> charge; // Destroy after pixel members.
    uint32_t imageId = 0;
    cv::Mat gray;
    int w;
    int h;
    uint64_t createdAtMs;
    uint64_t ttlMs;
    std::string ownerSessionId;
    std::string ownerRunId;
    std::string ownerRuntime;
    ZXImageObject() = default;
    ZXImageObject(const ZXImageObject &) = delete;
    ZXImageObject &operator=(const ZXImageObject &) = delete;
};

struct ZXFrameObject {
    std::shared_ptr<TLinkImageCharge> charge; // Readers keep the charge until pixels are freed.
    uint32_t frameId = 0;
    uint64_t capturedAtMs = 0; // Legacy CFAbsoluteTime wall timestamp; never used for TTL.
    int width;
    int height;
    int bytesPerRow;
    double scale;
    uint64_t createdAtMs;
    uint64_t expiresAtMs;
    uint64_t ttlMs;
    std::string ownerSessionId;
    std::string ownerRunId;
    std::string ownerRuntime;
    bool hasBGRA;
    bool hasGray;
    std::vector<uint8_t> bgra;
    cv::Mat gray;
    ZXFrameObject() = default;
    ZXFrameObject(const ZXFrameObject &) = delete;
    ZXFrameObject &operator=(const ZXFrameObject &) = delete;
};
using ZXFrameRef = std::shared_ptr<const ZXFrameObject>;
using ZXImageRef = std::shared_ptr<const ZXImageObject>;
// END immutable image payload types.

using ZXPointColor = TLinkColorPoint;

static dispatch_queue_t zx_imageQueue(void)
{
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.tlinkauto.tlinkauto.imageStore", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

// BEGIN image store globals (native tests provide the same queue/clock boundary).
static unordered_map<uint32_t, ZXImageRef> gImageStore;
static uint32_t gNextImageId = 1;
static const size_t kMaxImageObjects = 64;
static unordered_map<uint32_t, ZXFrameRef> gFrameStore;
static uint32_t gNextFrameId = 1;
static const size_t kMaxFrameObjects = 3;
static const uint64_t kDefaultFrameTtlMs = 1000;
static const uint64_t kHardFrameTtlMs = 5000;
static const size_t kMaxImagePixels = 16 * 1024 * 1024;
static TLinkImageMemory gImageMemory(96 * 1024 * 1024, 64 * 1024 * 1024, 128 * 1024 * 1024);
static TLinkImageComputeGate gImageCompute;
// END image store globals.
static uint64_t zx_nowMs(void) { return TLinkImageNowMs(); }
static bool zx_rearmFrameExpiryLocked(void);
static void zx_cleanupFramesLocked(uint64_t nowMs);
static void zx_trimFramesLocked(void);
static uint32_t zx_storeImageLocked(std::shared_ptr<ZXImageObject> image);
static uint32_t zx_storeFrameLocked(std::shared_ptr<ZXFrameObject> frame);
static ZXFrameRef zx_snapshotFrame(uint32_t frameId);
static std::shared_ptr<TLinkImageCharge> zx_reservePayload(TLinkImageKind kind, size_t bytes);

static NSError *zx_frameError(NSString *message)
{
    return [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                               code:999
                           userInfo:@{NSLocalizedDescriptionKey:message ?: @"1;;frame_error\r\n"}];
}

// BEGIN typed frame/image wire admission.
static bool zx_wireInt(NSArray *data,NSUInteger index,int &value) {
    return index<data.count && TLinkColorInt([data[index] UTF8String],value);
}
static bool zx_wireDouble(NSArray *data,NSUInteger index,double &value) {
    return index<data.count && TLinkColorDouble([data[index] UTF8String],value);
}
static bool zx_frameOptions(NSArray *data,NSUInteger coordIndex,NSUInteger ageIndex) {
    if(data.count>coordIndex){NSString *coord=[data[coordIndex] lowercaseString];if(![coord isEqualToString:@"pixel"]&&![coord isEqualToString:@"point"])return false;}
    int age=0;return data.count<=ageIndex || (zx_wireInt(data,ageIndex,age)&&age>=0&&age<=5000);
}
static bool zx_frameColorInputs(NSArray *data) {
    int id=0;if(!zx_wireInt(data,0,id)||id<=0||data.count<2)return false;
    NSString *mode=[data[1] lowercaseString];
    NSUInteger required=0,coord=0,age=0;std::vector<NSUInteger> integers,doubles;
    if([mode isEqualToString:@"pick"]){required=4;coord=4;age=5;doubles={2,3};}
    else if([mode isEqualToString:@"pick_many"]){required=3;coord=3;age=4;}
    else if([mode isEqualToString:@"search_single"]){required=13;coord=13;age=14;doubles={2,3,4,5};integers={6,7,8,9,10,11,12};}
    else if([mode isEqualToString:@"is_colors"]){required=5;coord=5;age=6;integers={3};doubles={4};}
    else if([mode isEqualToString:@"find_multi_point"]){required=10;coord=10;age=11;integers={7,9};doubles={2,3,4,5,8};}
    else return false;
    if(data.count<required||!zx_frameOptions(data,coord,age))return false;
    for(auto index:integers){int v=0;if(!zx_wireInt(data,index,v))return false;}
    for(auto index:doubles){double v=0;if(!zx_wireDouble(data,index,v)||std::fabs(v)>double(INT_MAX)-1)return false;}
    if([mode isEqualToString:@"search_single"]){
        for(NSUInteger i=6;i<12;++i)if(!TLinkColorRGB([data[i] intValue]))return false;
        if([data[6] intValue]>[data[7] intValue]||[data[8] intValue]>[data[9] intValue]||[data[10] intValue]>[data[11] intValue])return false;
        if([data[12] intValue]<0||[data[12] intValue]>1023)return false;
    }
    if([mode isEqualToString:@"is_colors"]&&!TLinkColorMode([data[3] intValue],[data[4] doubleValue]))return false;
    if([mode isEqualToString:@"find_multi_point"]&&(!TLinkColorMode([data[7] intValue],[data[8] doubleValue])||[data[9] intValue]<0||[data[9] intValue]>1023))return false;
    return true;
}
static bool zx_imageInputs(NSArray *data,bool frame) {
    const NSUInteger shift=frame?1:0;int value=0;
    if(data.count<10+shift||!zx_wireInt(data,0,value)||value<=0)return false;
    if(frame&&(!zx_wireInt(data,1,value)||value<=0))return false;
    for(NSUInteger i=1+shift;i<=4+shift;++i)if(!zx_wireInt(data,i,value))return false;
    double acceptable=0,low=0,high=0,step=0;
    if(!zx_wireDouble(data,5+shift,acceptable)||!zx_wireDouble(data,6+shift,low)||!zx_wireDouble(data,7+shift,high)||!zx_wireDouble(data,8+shift,step)||!zx_wireInt(data,9+shift,value))return false;
    if(!TLinkModernImageParameters(acceptable,float(low),float(high),float(step),value))return false;
    // Bound the float traversal before capture/queue work, including non-progressing steps.
    if(std::fabs(high-low)/step>63)return false;
    return !frame||zx_frameOptions(data,11,12);
}
static bool zx_frameBatchInputs(NSArray *data) {
    int id=0;if(data.count<2||!zx_wireInt(data,0,id)||id<=0||!zx_frameOptions(data,2,3)||[data[1] length]>65536)return false;
    if(data.count>4&&(!zx_wireInt(data,4,id)||(id!=0&&id!=1)))return false;
    NSArray *ops=[data[1] componentsSeparatedByString:@"@@"];if(ops.count>64)return false;
    for(NSString *op in ops){
        if(op.length==0)continue;
        NSArray *fields=[op componentsSeparatedByString:@","];NSString *kind=[fields[0] lowercaseString];
        if([kind isEqualToString:@"img"]){
            if(fields.count!=9||!zx_wireInt(fields,1,id)||id<=0)return false;
            for(NSUInteger i=2;i<8;++i){double value=0;if(!zx_wireDouble(fields,i,value)||std::fabs(value)>double(INT_MAX)-1)return false;}
            if(!zx_wireInt(fields,8,id)||!TLinkModernImageParameters([fields[6] doubleValue],[fields[7] floatValue],[fields[7] floatValue],1,id))return false;
        }else if([kind isEqualToString:@"pick_many"]){
            if(fields.count!=2||[fields[1] length]>32768||[[fields[1] componentsSeparatedByString:@"|"] count]>512)return false;
        }else return false;
    }
    return true;
}
// END typed frame/image wire admission.

static std::string zx_stringFromPart(NSArray *data, NSUInteger index, const char *fallback)
{
    if (index >= [data count]) return std::string(fallback ?: "");
    id value = data[index];
    NSString *text = [value isKindOfClass:[NSString class]] ? (NSString *)value : [value description];
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return std::string(fallback ?: "");
    return std::string([text UTF8String] ?: "");
}

static void zx_applyFrameOwner(ZXFrameObject &frame,const TLinkNativeFrameCaptureRequest &request){
    frame.ownerSessionId=request.sessionId;frame.ownerRunId=request.runId;frame.ownerRuntime=request.runtime;
}

static void zx_applyImageOwner(ZXImageObject &image, NSArray *data, NSUInteger startIndex)
{
    image.ownerSessionId = zx_stringFromPart(data, startIndex, "");
    image.ownerRunId = zx_stringFromPart(data, startIndex + 1, "");
    image.ownerRuntime = zx_stringFromPart(data, startIndex + 2, "legacy");
}

static bool zx_ownerMatchFields(const std::string &objSessionId,
                                const std::string &objRunId,
                                const std::string &objRuntime,
                                const std::string &sessionId,
                                const std::string &runId,
                                const std::string &runtime)
{
    bool scoped = !sessionId.empty() || !runId.empty() || !runtime.empty();
    if (!scoped) return true;
    if (!runtime.empty() && objRuntime != runtime) return false;
    if (!sessionId.empty() && objSessionId != sessionId) return false;
    if (!runId.empty() && objRunId != runId) return false;
    return true;
}

static bool zx_ownerMatchesFrame(const ZXFrameObject &frame, const std::string &sessionId, const std::string &runId, const std::string &runtime)
{
    return zx_ownerMatchFields(frame.ownerSessionId, frame.ownerRunId, frame.ownerRuntime, sessionId, runId, runtime);
}

static bool zx_ownerMatchesImage(const ZXImageObject &image, const std::string &sessionId, const std::string &runId, const std::string &runtime)
{
    return zx_ownerMatchFields(image.ownerSessionId, image.ownerRunId, image.ownerRuntime, sessionId, runId, runtime);
}

static void zx_cleanupFramesLocked(uint64_t nowMs);
static NSArray<NSString *> *zx_splitEventData(UInt8 *eventData);
static bool zx_stringIsPointCoord(NSString *coord);
static int zx_coordToPixel(double value, double scale, bool pointCoord);
static bool zx_frameTooOld(const ZXFrameObject &frame, uint64_t maxAgeMs, uint64_t nowMs, NSError **error);
static bool zx_renderBGRAFromCGImage(CGImageRef img, std::vector<uint8_t> &out, int *outW, int *outH, int *outBpr);
static bool zx_parsePointTableVector(NSString *tableStr, std::vector<ZXPointColor> &points, NSError **error);
static inline void zx_readBGRA(const ZXFrameObject &frame, int x, int y, int *r, int *g, int *b);

static NSString *zx_currentScriptDir(void)
{
    if (scriptPlayer) {
        NSString *p = [scriptPlayer getCurrentBundlePath];
        if (p && [p length] > 0) {
            return p;
        }
    }
    return nil;
}

static NSString *zx_resolveImagePath(NSString *path)
{
    if (!path) return nil;
    if ([path hasPrefix:@"/"]) {
        return path;
    }
    NSString *bundle = zx_currentScriptDir();
    if (bundle && [bundle length] > 0) {
        return [bundle stringByAppendingPathComponent:path];
    }
    return [getScriptsFolder() stringByAppendingPathComponent:path];
}

static cv::Mat zx_cvMatGrayFromCGImage(CGImageRef img, NSError **error)
{
    if (!img) {
        return cv::Mat();
    }
    const size_t cols = CGImageGetWidth(img);
    const size_t rows = CGImageGetHeight(img);
    size_t pixels = 0;
    if (!TLinkImagePixels(cols, rows, kMaxImagePixels, &pixels)) {
        return cv::Mat();
    }

    cv::Mat rgba((int)rows, (int)cols, CV_8UC4);
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(img);
    BOOL createdColorSpace = false;
    if (!colorSpace) {
        colorSpace = CGColorSpaceCreateDeviceRGB();
        createdColorSpace = true;
    }
    CGContextRef ctx = CGBitmapContextCreate(rgba.data,
                                             cols,
                                             rows,
                                             8,
                                             rgba.step[0],
                                             colorSpace,
                                             kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
    if (createdColorSpace) {
        CGColorSpaceRelease(colorSpace);
    }
    if (!ctx) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to create bitmap context.\r\n"}];
        }
        return cv::Mat();
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, cols, rows), img);
    CGContextRelease(ctx);

    cv::Mat gray;
    cv::cvtColor(rgba, gray, COLOR_RGBA2GRAY);
    return gray;
}

static long long zx_sad_match_region(const Mat &img, const Mat &templ,
                                    int x0, int y0, int x1, int y1,
                                    int step, int *bestX, int *bestY)
{
    auto nativeBudget = TLinkCurrentNativeBudget();
    auto request = TLinkModernImageSlot();
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
        if (nativeBudget && nativeBudget->stopped()) return LLONG_MAX;
        for (int x = x0; x <= x1; x += step) {
            long long sad = 0;
            for (int ty = 0; ty < h; ty++) {
                if ((ty & 31) == 0 && nativeBudget && nativeBudget->stopped()) return LLONG_MAX;
                if (request && !request->consume(size_t(w))) return LLONG_MAX;
                const unsigned char *imgRow = img.ptr<unsigned char>(y + ty) + x;
                const unsigned char *tRow = templ.ptr<unsigned char>(ty);
                for (int tx = 0; tx < w; tx++) {
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

static BOOL zx_findTemplateSAD(const Mat &img, const Mat &templ,
                              double acceptable,
                              float scaleMin, float scaleMax, float scaleStep,
                              int pixelSkip,
                              int *outX, int *outY, int *outW, int *outH,
                              double *outScore)
{
    if (outX) *outX = -1;
    if (outY) *outY = -1;
    if (outW) *outW = 0;
    if (outH) *outH = 0;
    if (outScore) *outScore = 0;

    if (img.empty() || templ.empty()) {
        return false;
    }

    auto request = TLinkModernImageSlot();
    if (!request) request = std::make_shared<TLinkModernImageRequest>(TLinkCurrentNativeBudget());
    TLinkModernImageScope requestScope(request);
    if (request->stopped()) return false;
    TLinkModernImagePlan plan;
    if (!TLinkModernImageParameters(acceptable,scaleMin,scaleMax,scaleStep,pixelSkip) ||
        !TLinkModernImageMakePlan(img.cols,img.rows,templ.cols,templ.rows,scaleMin,scaleMax,scaleStep,
            [](double value){ return cvRound(value); },plan)) return request->fail("image_scale_plan_invalid_or_too_large");
    if (!request->reserve(plan.bytes)) return false;
    float r = plan.ratio;

    Mat imgWork = img;
    if (r != 1.0f) {
        cv::resize(img, imgWork, cv::Size(0, 0), r, r, cv::INTER_AREA);
    }

    int coarseStep = pixelSkip + 1;
    if (coarseStep < 4) coarseStep = 4;

    double bestOverallScore = -1.0;
    int bestX = -1, bestY = -1, bestW = 0, bestH = 0;

    for (const auto &scale : plan.scales) {
        if (request->stopped()) return false;
        const float s = scale.factor;
        Mat templScaled;
        if (fabsf(s - 1.0f) < 0.0001f) {
            templScaled = templ;
        } else {
            int interp = s < 1.0f ? cv::INTER_AREA : cv::INTER_LINEAR;
            cv::resize(templ, templScaled, cv::Size(0, 0), s, s, interp);
        }
        if (templScaled.empty()) {
            continue;
        }
        if (request->stopped()) return false;
        Mat templWork = templScaled;
        if (r != 1.0f) {
            cv::resize(templScaled, templWork, cv::Size(0, 0), r, r, cv::INTER_AREA);
        }

        if (templWork.cols <= 0 || templWork.rows <= 0 ||
            templWork.cols > imgWork.cols || templWork.rows > imgWork.rows) {
            continue;
        }

        if (request->stopped()) return false;
        int bx = 0, by = 0;
        long long bestSad = zx_sad_match_region(imgWork, templWork,
                                               0, 0,
                                               imgWork.cols - templWork.cols,
                                               imgWork.rows - templWork.rows,
                                               coarseStep,
                                               &bx, &by);

        if (request->stopped()) return false;
        int refineRadius = coarseStep * 2;
        int rbx = bx, rby = by;
        long long refinedSad = zx_sad_match_region(imgWork, templWork,
                                                   bx - refineRadius, by - refineRadius,
                                                   bx + refineRadius, by + refineRadius,
                                                   1,
                                                   &rbx, &rby);
        if (request->stopped()) return false;
        if (refinedSad < bestSad) {
            bestSad = refinedSad;
            bx = rbx;
            by = rby;
        }

        const long long denom = 255LL * (long long)templWork.cols * (long long)templWork.rows;
        double score = (denom > 0) ? (1.0 - ((double)bestSad / (double)denom)) : 0.0;
        if (score > bestOverallScore) {
            bestOverallScore = score;
            bestX = bx;
            bestY = by;
            bestW = templWork.cols;
            bestH = templWork.rows;
        }

        if (score >= acceptable) {
            const double inv = (r == 0.0f) ? 1.0 : (1.0 / (double)r);
            if (outX) *outX = (int)round(bx * inv);
            if (outY) *outY = (int)round(by * inv);
            if (outW) *outW = (int)round(templWork.cols * inv);
            if (outH) *outH = (int)round(templWork.rows * inv);
            if (outScore) *outScore = score;
            return true;
        }
    }

    if (bestX >= 0 && bestY >= 0 && bestW > 0 && bestH > 0) {
        const double inv = (r == 0.0f) ? 1.0 : (1.0 / (double)r);
        if (outX) *outX = (int)round(bestX * inv);
        if (outY) *outY = (int)round(bestY * inv);
        if (outW) *outW = (int)round(bestW * inv);
        if (outH) *outH = (int)round(bestH * inv);
    }
    if (outScore) *outScore = (bestOverallScore < 0.0) ? 0.0 : bestOverallScore;
    return false;
}

// BEGIN numeric frame capture.
static bool zx_captureFrame(const TLinkNativeFrameCaptureRequest &request,uint32_t &publishedId,TLinkNativeFrameCaptureValue &value,NSError **error){
    const bool needGray=request.gray||!request.bgra,needBGRA=request.bgra||!request.gray;
    static_assert(kDefaultFrameTtlMs==1000&&kHardFrameTtlMs==5000,"capture TTL compatibility changed");
    const uint64_t ttlMs=TLinkNativeFrameCaptureTTL(request.ttlMs);
    CFAbsoluteTime total0 = TLinkImageNowSeconds();
    CFAbsoluteTime capture0 = TLinkImageNowSeconds();
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    double captureMs = (TLinkImageNowSeconds() - capture0) * 1000.0;
    if (!screen) {
        if (error) *error = zx_frameError(@"1;;capture_failed\r\n");
        return false;
    }

    size_t pixels = 0;
    if (!TLinkImagePixels(CGImageGetWidth(screen), CGImageGetHeight(screen), kMaxImagePixels, &pixels)) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;frame_pixel_limit\r\n");
        return false;
    }
    auto charge = zx_reservePayload(TLinkImageKind::Frame, pixels * ((needBGRA ? 4 : 0) + (needGray ? 1 : 0)));
    if (!charge) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;frame_memory_budget\r\n");
        return false;
    }
    auto pendingFrame = std::make_shared<ZXFrameObject>();
    pendingFrame->charge = std::move(charge);
    ZXFrameObject &frame = *pendingFrame;
    frame.width = (int)CGImageGetWidth(screen);
    frame.height = (int)CGImageGetHeight(screen);
    frame.bytesPerRow = frame.width * 4;
    frame.scale = [Screen getScale];
    frame.createdAtMs = zx_nowMs();
    frame.expiresAtMs = TLinkImageExpiry(frame.createdAtMs, ttlMs);
    frame.capturedAtMs = (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000.0);
    frame.ttlMs = ttlMs;
    zx_applyFrameOwner(frame, request);
    frame.hasBGRA = false;
    frame.hasGray = false;

    std::vector<uint8_t> tmpBGRA;
    int w = 0, h = 0, bpr = 0;
    CFAbsoluteTime bgra0 = TLinkImageNowSeconds();
    if (!zx_renderBGRAFromCGImage(screen, needBGRA ? frame.bgra : tmpBGRA, &w, &h, &bpr)) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;bgra_render_failed\r\n");
        return false;
    }
    double bgraMs = (TLinkImageNowSeconds() - bgra0) * 1000.0;
    CGImageRelease(screen);
    frame.width = w;
    frame.height = h;
    frame.bytesPerRow = bpr;
    frame.hasBGRA = needBGRA;

    CFAbsoluteTime gray0 = TLinkImageNowSeconds();
    if (needGray) {
        std::vector<uint8_t> &source = needBGRA ? frame.bgra : tmpBGRA;
        cv::Mat bgraMat(frame.height, frame.width, CV_8UC4, source.data(), frame.bytesPerRow);
        cv::cvtColor(bgraMat, frame.gray, COLOR_BGRA2GRAY);
        frame.hasGray = !frame.gray.empty();
    }
    double grayMs = (TLinkImageNowSeconds() - gray0) * 1000.0;
    if (needGray && !frame.hasGray) {
        if (error) *error = zx_frameError(@"1;;gray_convert_failed\r\n");
        return false;
    }

    __block uint32_t frameId = 0;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        frameId = zx_storeFrameLocked(pendingFrame);
    });
    publishedId=frameId;
    if (!frameId) {
        if (error) *error = zx_frameError(@"1;;frame_publish_failed\r\n");
        return false;
    }
    double totalMs = (TLinkImageNowSeconds() - total0) * 1000.0;
    value.id=frameId;value.width=frame.width;value.height=frame.height;value.bytesPerRow=frame.bytesPerRow;
    value.scale=frame.scale;value.hasBGRA=frame.hasBGRA;value.hasGray=frame.hasGray;value.capturedAtMs=frame.capturedAtMs;
    value.captureMs=captureMs;value.bgraMs=bgraMs;value.grayMs=grayMs;value.totalMs=totalMs;
    return true;
}

bool captureStoredFrame(const TLinkNativeFrameCaptureRequest &request,uint32_t &publishedId,TLinkNativeFrameCaptureValue &value,NSError **error){
    publishedId=0;value=TLinkNativeFrameCaptureValue{};TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"1;;image_compute_busy\r\n");return false;}
    return zx_captureFrame(request,publishedId,value,error);
}
// END numeric frame capture.

NSString* handleFrameCaptureTaskFromRawData(UInt8 *eventData,NSError **error){
    TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"1;;image_compute_busy\r\n");return nil;}
    NSArray *data=zx_splitEventData(eventData);TLinkNativeFrameCaptureRequest request;
    if(data.count>=1&&[data[0] length]>0)request.gray=[data[0] intValue]!=0;
    if(data.count>=2&&[data[1] length]>0)request.bgra=[data[1] intValue]!=0;
    if(data.count>=3&&[data[2] length]>0)request.ttlMs=uint64_t(MAX(0,[data[2] longLongValue]));
    request.sessionId=zx_stringFromPart(data,3,"");request.runId=zx_stringFromPart(data,4,"");request.runtime=zx_stringFromPart(data,5,"legacy");
    uint32_t publishedId=0;TLinkNativeFrameCaptureValue value;
    return zx_captureFrame(request,publishedId,value,error)?TLinkNativeFrameCaptureBody(value):nil;
}

// BEGIN numeric frame release.
size_t releaseStoredFrames(const TLinkNativeFrameReleaseRequest &request){
    __block size_t removed=0;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        if(request.all){
            if(request.scoped){
                std::vector<uint32_t> ids;
                for(auto const &kv:gFrameStore)if(zx_ownerMatchesFrame(*kv.second,request.sessionId,request.runId,request.runtime))ids.push_back(kv.first);
                for(uint32_t id:ids)removed+=gFrameStore.erase(id);
            }else{removed=gFrameStore.size();gFrameStore.clear();}
        }else{
            auto it=gFrameStore.find(request.frameId);
            if(it!=gFrameStore.end()&&(!request.scoped||zx_ownerMatchesFrame(*it->second,request.sessionId,request.runId,request.runtime)))removed=gFrameStore.erase(request.frameId);
        }
        zx_rearmFrameExpiryLocked();
    });
    return removed;
}
// END numeric frame release.

NSString* handleFrameReleaseTaskFromRawData(UInt8 *eventData,NSError **error){
    (void)error;
    NSString *raw=[[NSString alloc] initWithUTF8String:(char *)eventData]?:@"";
    raw=[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *data=[raw componentsSeparatedByString:@";;"];
    NSString *command=data.count?data[0]:@"",*lower=[command lowercaseString];
    TLinkNativeFrameReleaseRequest request;request.all=[lower isEqualToString:@"all"]||[lower isEqualToString:@"scoped"];
    request.scoped=data.count>=4;request.frameId=uint32_t([command intValue]);
    if(request.scoped){request.sessionId=zx_stringFromPart(data,1,"");request.runId=zx_stringFromPart(data,2,"");request.runtime=zx_stringFromPart(data,3,"");}
    // The legacy scoped command without an owner tuple is a no-op, but still rearms expiry.
    if([lower isEqualToString:@"scoped"]&&!request.scoped){TLinkNativeDispatchSync(zx_imageQueue(), ^{zx_rearmFrameExpiryLocked();});return @"0";}
    return [NSString stringWithFormat:@"%lu",(unsigned long)releaseStoredFrames(request)];
}

// BEGIN numeric frame image match.
bool matchImageInFrame(const TLinkNativeFrameImageRequest &search,TLinkNativeFrameImageValue &value,NSError **error){
    auto request=TLinkModernImageSlot();if(!request)request=std::make_shared<TLinkModernImageRequest>(TLinkCurrentNativeBudget());
    TLinkModernImageScope requestScope(request);
    if(request->stopped()){if(error)*error=zx_frameError(@"-1;;template_cancelled_or_timed_out\r\n");return false;}
    if(!TLinkNativeFrameImageParameters(search)){if(error)*error=zx_frameError(@"-1;;invalid_image_parameters\r\n");return false;}
    const uint32_t frameId=uint32_t(search.frameId),imageId=uint32_t(search.imageId);
    const int rx=search.x,ry=search.y,rw=search.width,rh=search.height,pixelSkip=search.pixelSkip;
    const double acceptable=search.acceptable;const float scaleMin=search.scaleMin,scaleMax=search.scaleMax,scaleStep=search.scaleStep;
    const bool pointCoord=search.pointCoord;const uint64_t maxAgeMs=uint64_t(search.maxAgeMs);
    bool ok=false;
    NSError *blockErr = nil;
    TLinkImageWork work(gImageCompute);
    if (!work) { if (error) *error = zx_frameError(@"1;;image_compute_busy\r\n"); return false; }
    ZXFrameRef snapshot;
    __block ZXFrameRef admittedFrame;
    __block unordered_map<uint32_t, ZXImageRef> admittedImages;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        zx_cleanupFramesLocked(zx_nowMs());
        auto it = gFrameStore.find(frameId);
        if (it != gFrameStore.end()) admittedFrame = it->second;
        auto image = gImageStore.find(imageId);
        if (image != gImageStore.end()) admittedImages.emplace(imageId, image->second);
        zx_rearmFrameExpiryLocked();
    });
    snapshot = std::move(admittedFrame);
    const auto images = std::move(admittedImages);
    [&] {
        const uint64_t nowMs = zx_nowMs();
        if (!snapshot) {
            blockErr = zx_frameError(@"1;;frame_not_found\r\n");
            return;
        }
        const ZXFrameObject &frame = *snapshot;
        if (!frame.hasGray || frame.gray.empty()) {
            blockErr = zx_frameError(@"1;;frame_missing_gray\r\n");
            return;
        }
        if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
        auto iit = images.find(imageId);
        if (iit == images.end() || iit->second->gray.empty()) {
            blockErr = zx_frameError(@"1;;image_not_found\r\n");
            return;
        }
        if(frame.gray.cols!=frame.width||frame.gray.rows!=frame.height){blockErr=zx_frameError(@"1;;frame_geometry_invalid\r\n");return;}
        uint64_t ageMs = nowMs >= frame.createdAtMs ? nowMs - frame.createdAtMs : 0;
        int workX = zx_coordToPixel(rx, frame.scale, pointCoord);
        int workY = zx_coordToPixel(ry, frame.scale, pointCoord);
        int workW = zx_coordToPixel(rw, frame.scale, pointCoord);
        int workH = zx_coordToPixel(rh, frame.scale, pointCoord);
        if(workX==INT_MIN||workY==INT_MIN||workW==INT_MIN||workH==INT_MIN){blockErr=zx_frameError(@"1;;frame_coordinate_invalid\r\n");return;}
        if (workX < 0) workX = 0;
        if (workY < 0) workY = 0;
        if (workX >= frame.width) workX = frame.width - 1;
        if (workY >= frame.height) workY = frame.height - 1;
        if (workW <= 0 || workW > frame.width - workX) workW = frame.width - workX;
        if (workH <= 0 || workH > frame.height - workY) workH = frame.height - workY;

        CFAbsoluteTime total0 = TLinkImageNowSeconds();
        cv::Rect roi(workX, workY, workW, workH);
        cv::Mat region = frame.gray(roi);
        int mx = -1, my = -1, mw = 0, mh = 0;
        double score = 0.0;
        bool match = zx_findTemplateSAD(region, iit->second->gray, acceptable, scaleMin, scaleMax, scaleStep, pixelSkip,
                                        &mx, &my, &mw, &mh, &score);
        double totalMs = (TLinkImageNowSeconds() - total0) * 1000.0;
        value.ageMs=ageMs;value.score=score;value.totalMs=totalMs;
        value.x=match?workX+mx:-1;value.y=match?workY+my:-1;value.width=match?mw:0;value.height=match?mh:0;
        value.centerX=match?value.x+mw/2.0:-1;value.centerY=match?value.y+mh/2.0:-1;ok=true;
    }();
    if (request->stopped()) blockErr = zx_frameError([NSString stringWithFormat:@"-1;;%s\r\n",request->error()]);
    if (blockErr) {
        if (error) *error = blockErr;
        return false;
    }
    return ok;
}

// END numeric frame image match.

NSString* handleFindImageInFrameTaskFromRawData(UInt8 *eventData,NSError **error){
    auto request=std::make_shared<TLinkModernImageRequest>(TLinkCurrentNativeBudget());TLinkModernImageScope requestScope(request);
    if(request->stopped()){if(error)*error=zx_frameError(@"-1;;template_cancelled_or_timed_out\r\n");return nil;}
    NSArray<NSString *> *data=zx_splitEventData(eventData);
    if(data.count<11){if(error)*error=zx_frameError(@"1;;Find image in frame format should be frame_id;;image_id;;x;;y;;w;;h;;acceptable;;scale_min;;scale_max;;scale_step;;pixel_skip[;;coord;;max_age_ms]\r\n");return nil;}
    if(!zx_imageInputs(data,true)){if(error)*error=zx_frameError(@"-1;;invalid_image_parameters\r\n");return nil;}
    TLinkNativeFrameImageRequest search;search.frameId=[data[0] intValue];search.imageId=[data[1] intValue];
    for(unsigned i=0;i<4;++i){search.regionPart(i,[data[i+2] UTF8String],[data[i+2] length]);search.scalarPart(i,[data[i+6] UTF8String],[data[i+6] length]);}
    search.pixelSkip=[data[10] intValue];search.pointCoord=data.count>=12?zx_stringIsPointCoord(data[11]):false;search.maxAgeMs=data.count>=13?int(MAX(0,[data[12] longLongValue])):int(kDefaultFrameTtlMs);
    TLinkNativeFrameImageValue value;if(!matchImageInFrame(search,value,error))return nil;
    if(value.x<0||value.y<0)return [NSString stringWithFormat:@"-1;;-1;;0;;0;;-1;;-1;;%.4f;;%llu;;%.3f;;%.3f",value.score,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];
    return [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%.2f;;%.2f;;%.4f;;%llu;;%.3f;;%.3f",value.x,value.y,value.width,value.height,value.centerX,value.centerY,value.score,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];
}

// BEGIN numeric frame color pick.
static bool zx_framePickBGRA(const ZXFrameRef &snapshot,NSError **error) {
    NSString *message=nil;
    if(!snapshot)message=@"1;;frame_not_found\r\n";
    else if(!snapshot->hasBGRA||snapshot->bgra.empty())message=@"1;;frame_missing_bgra\r\n";
    else if(!TLinkFrameColorGeometry(snapshot->width,snapshot->height,snapshot->bytesPerRow,snapshot->bgra.size()))message=@"1;;frame_geometry_invalid\r\n";
    if(message){if(error)*error=zx_frameError(message);return false;}return true;
}
static bool zx_framePickPixel(const ZXFrameObject &frame,double px,double py,bool pointCoord,TLinkColorRequest &request,TLinkNativeFramePickValue &value,NSError **error) {
    int x=zx_coordToPixel(px,frame.scale,pointCoord),y=zx_coordToPixel(py,frame.scale,pointCoord);
    if(x<0||y<0||x>=frame.width||y>=frame.height){if(error)*error=zx_frameError(@"1;;point_out_of_bounds\r\n");return false;}
    if(!request.consume())return false;
    zx_readBGRA(frame,x,y,&value.red,&value.green,&value.blue);return true;
}
bool readFramePixel(const TLinkNativeFramePickRequest &pick,TLinkNativeFramePickValue &value,NSError **error) {
    TLinkColorRequest request(TLinkCurrentNativeBudget());
    if(!request.admitted()){if(error)*error=zx_frameError(@"1;;color_compute_busy\r\n");return false;}
    if(!TLinkFramePickParameters(pick)){if(error)*error=zx_frameError(@"1;;invalid_frame_color_parameters\r\n");return false;}
    TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"1;;image_compute_busy\r\n");return false;}
    ZXFrameRef snapshot=zx_snapshotFrame(uint32_t(pick.frameId));NSError *failure=nil;bool ok=false;
    [&] {
        const uint64_t nowMs=zx_nowMs();
        if(!zx_framePickBGRA(snapshot,&failure))return;
        const ZXFrameObject &frame=*snapshot;
        value.ageMs=nowMs>=frame.createdAtMs?nowMs-frame.createdAtMs:0;
        const double started=TLinkImageNowSeconds();
        if(zx_frameTooOld(frame,uint64_t(pick.maxAgeMs),nowMs,&failure))return;
        if(!zx_framePickPixel(frame,pick.x,pick.y,pick.pointCoord,request,value,&failure))return;
        value.totalMs=(TLinkImageNowSeconds()-started)*1000.0;ok=true;
    }();
    if(request.stopped())failure=zx_frameError([NSString stringWithFormat:@"1;;%s\r\n",request.error()]);
    if(failure){if(error)*error=failure;return false;}return ok;
}
// END numeric frame color pick.

// BEGIN numeric frame color pick-many.
static bool zx_framePickManyPixel(const ZXFrameObject &frame,double px,double py,bool pointCoord,TLinkColorRequest &request,TLinkNativeFrameColor &value,NSError **error) {
    if(!TLinkFrameColorCoordinate(px,frame.scale,pointCoord,value.x)||!TLinkFrameColorCoordinate(py,frame.scale,pointCoord,value.y)){
        if(error)*error=zx_frameError(@"1;;invalid_pick_many_point\r\n");return false;
    }
    if(value.x<0||value.y<0||value.x>=frame.width||value.y>=frame.height){if(error)*error=zx_frameError(@"1;;point_out_of_bounds\r\n");return false;}
    if(!request.consume())return false;
    zx_readBGRA(frame,value.x,value.y,&value.red,&value.green,&value.blue);return true;
}
bool readFramePixels(const TLinkNativeFramePickManyRequest &pick,TLinkNativeFramePickManyValue &value,NSError **error) {
    TLinkColorRequest request(TLinkCurrentNativeBudget());
    if(!request.admitted()){if(error)*error=zx_frameError(@"1;;color_compute_busy\r\n");return false;}
    if(!TLinkFramePickParameters(pick.frame)){if(error)*error=zx_frameError(@"1;;invalid_frame_color_parameters\r\n");return false;}
    TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"1;;image_compute_busy\r\n");return false;}
    ZXFrameRef snapshot=zx_snapshotFrame(uint32_t(pick.frame.frameId));NSError *failure=nil;bool ok=false;
    [&] {
        const uint64_t nowMs=zx_nowMs();if(!zx_framePickBGRA(snapshot,&failure))return;
        const ZXFrameObject &frame=*snapshot;value.ageMs=nowMs>=frame.createdAtMs?nowMs-frame.createdAtMs:0;
        const double started=TLinkImageNowSeconds();
        if(zx_frameTooOld(frame,uint64_t(pick.frame.maxAgeMs),nowMs,&failure))return;
        if(pick.tableUnits>32768||pick.pointCount>512){failure=zx_frameError(@"1;;point_table_limit\r\n");return;}
        if(!pick.pointCount||pick.pointCount!=pick.points.size()){failure=zx_frameError(@"1;;invalid_pick_many_point\r\n");return;}
        value.colors.clear();value.colors.reserve(pick.pointCount);
        for(const auto &point:pick.points){
            TLinkNativeFrameColor pixel;
            if(!zx_framePickManyPixel(frame,point.x,point.y,pick.frame.pointCoord,request,pixel,&failure))return;
            value.colors.push_back(pixel);
        }
        value.totalMs=(TLinkImageNowSeconds()-started)*1000.0;ok=true;
    }();
    if(request.stopped())failure=zx_frameError([NSString stringWithFormat:@"1;;%s\r\n",request.error()]);
    if(failure){if(error)*error=failure;return false;}return ok;
}
// END numeric frame color pick-many.

// BEGIN numeric frame color search.
bool searchFrameColor(const TLinkNativeFrameSearchRequest &search,TLinkNativeFrameSearchValue &value,NSError **error) {
    TLinkColorRequest request(TLinkCurrentNativeBudget());
    if(!request.admitted()){if(error)*error=zx_frameError(@"1;;color_compute_busy\r\n");return false;}
    if(!TLinkFrameSearchParameters(search)){if(error)*error=zx_frameError(@"1;;invalid_frame_color_parameters\r\n");return false;}
    TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"1;;image_compute_busy\r\n");return false;}
    ZXFrameRef snapshot=zx_snapshotFrame(uint32_t(search.frame.frameId));NSError *failure=nil;bool ok=false;
    [&] {
        const uint64_t nowMs=zx_nowMs();if(!zx_framePickBGRA(snapshot,&failure))return;
        const ZXFrameObject &frame=*snapshot;value.ageMs=nowMs>=frame.createdAtMs?nowMs-frame.createdAtMs:0;
        const double started=TLinkImageNowSeconds();
        if(zx_frameTooOld(frame,uint64_t(search.frame.maxAgeMs),nowMs,&failure))return;
        const auto status=TLinkFrameSearchScan(frame.bgra.data(),frame.width,frame.height,size_t(frame.bytesPerRow),frame.scale,search,request,value);
        if(status==TLinkFrameSearchStatus::CoordinateInvalid){failure=zx_frameError(@"1;;frame_coordinate_invalid\r\n");return;}
        if(status==TLinkFrameSearchStatus::Stopped)return;
        value.totalMs=(TLinkImageNowSeconds()-started)*1000.0;ok=true;
    }();
    if(request.stopped())failure=zx_frameError([NSString stringWithFormat:@"1;;%s\r\n",request.error()]);
    if(failure){if(error)*error=failure;return false;}return ok;
}
// END numeric frame color search.

// BEGIN numeric frame color comparison.
bool testFrameColors(const TLinkNativeFrameColorsRequest &check,TLinkNativeFrameColorsValue &value,NSError **error){
    TLinkColorRequest request(TLinkCurrentNativeBudget());
    if(!request.admitted()){if(error)*error=zx_frameError(@"1;;color_compute_busy\r\n");return false;}
    if(!TLinkFrameColorsParameters(check)){if(error)*error=zx_frameError(@"1;;invalid_frame_color_parameters\r\n");return false;}
    TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"1;;image_compute_busy\r\n");return false;}
    ZXFrameRef snapshot=zx_snapshotFrame(uint32_t(check.frame.frameId));NSError *failure=nil;bool ok=false;
    [&] {
        const uint64_t nowMs=zx_nowMs();if(!zx_framePickBGRA(snapshot,&failure))return;
        const ZXFrameObject &frame=*snapshot;value.ageMs=nowMs>=frame.createdAtMs?nowMs-frame.createdAtMs:0;
        const double started=TLinkImageNowSeconds();
        if(zx_frameTooOld(frame,uint64_t(check.frame.maxAgeMs),nowMs,&failure))return;
        if(const char *code=TLinkFrameColorsTableError(check)){failure=zx_frameError([NSString stringWithFormat:@"1;;%s\r\n",code]);return;}
        if(!TLinkFrameColorsEvaluate(frame.bgra.data(),frame.width,frame.height,size_t(frame.bytesPerRow),frame.scale,check.points,check.frame.pointCoord,check.mode,check.tolerance,request,value.matched))return;
        value.totalMs=(TLinkImageNowSeconds()-started)*1000.0;ok=true;
    }();
    if(request.stopped())failure=zx_frameError([NSString stringWithFormat:@"1;;%s\r\n",request.error()]);
    if(failure){if(error)*error=failure;return false;}return ok;
}
// END numeric frame color comparison.

// BEGIN numeric frame multi search.
bool findFrameColors(const TLinkNativeFrameMultiRequest &check,TLinkNativeFrameMultiValue &value,NSError **error){
    TLinkColorRequest request(TLinkCurrentNativeBudget());
    if(!request.admitted()){if(error)*error=zx_frameError(@"1;;color_compute_busy\r\n");return false;}
    if(!TLinkFrameMultiParameters(check)){if(error)*error=zx_frameError(@"1;;invalid_frame_color_parameters\r\n");return false;}
    TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"1;;image_compute_busy\r\n");return false;}
    ZXFrameRef snapshot=zx_snapshotFrame(uint32_t(check.colors.frame.frameId));NSError *failure=nil;bool ok=false;
    [&] {
        const uint64_t nowMs=zx_nowMs();if(!zx_framePickBGRA(snapshot,&failure))return;
        const ZXFrameObject &frame=*snapshot;value.ageMs=nowMs>=frame.createdAtMs?nowMs-frame.createdAtMs:0;
        const double started=TLinkImageNowSeconds();
        if(zx_frameTooOld(frame,uint64_t(check.colors.frame.maxAgeMs),nowMs,&failure))return;
        TLinkColorRect region;
        if(!TLinkFrameMultiRegion(frame.width,frame.height,frame.scale,check,region)){failure=zx_frameError(@"1;;frame_coordinate_invalid\r\n");return;}
        if(const char *code=TLinkFrameColorsTableError(check.colors)){failure=zx_frameError([NSString stringWithFormat:@"1;;%s\r\n",code]);return;}
        auto points=check.colors.points;
        if(!TLinkFrameMultiOffsets(points,frame.scale,check.colors.frame.pointCoord)){failure=zx_frameError(@"1;;frame_coordinate_invalid\r\n");return;}
        if(!TLinkFrameMultiScan(frame.bgra.data(),frame.width,frame.height,size_t(frame.bytesPerRow),region,points,check.colors.mode,check.colors.tolerance,check.skip,request,value))return;
        value.totalMs=(TLinkImageNowSeconds()-started)*1000.0;ok=true;
    }();
    if(request.stopped())failure=zx_frameError([NSString stringWithFormat:@"1;;%s\r\n",request.error()]);
    if(failure){if(error)*error=failure;return false;}return ok;
}
// END numeric frame multi search.

NSString* handleColorInFrameTaskFromRawData(UInt8 *eventData, NSError **error)
{
    TLinkColorRequest request(TLinkCurrentNativeBudget());
    if(!request.admitted()){if(error)*error=zx_frameError(@"1;;color_compute_busy\r\n");return nil;}
    NSArray<NSString *> *data = zx_splitEventData(eventData);
    if ([data count] < 2) {
        if (error) *error = zx_frameError(@"1;;Color in frame format should be frame_id;;mode;;...\r\n");
        return nil;
    }
    if(!zx_frameColorInputs(data)){if(error)*error=zx_frameError(@"1;;invalid_frame_color_parameters\r\n");return nil;}
    uint32_t frameId = (uint32_t)[data[0] intValue];
    NSString *mode = [[data[1] lowercaseString] copy];

    NSString *ret = nil;
    NSError *blockErr = nil;
    TLinkImageWork work(gImageCompute);
    if (!work) { if (error) *error = zx_frameError(@"1;;image_compute_busy\r\n"); return nil; }
    ZXFrameRef snapshot;
    snapshot = zx_snapshotFrame(frameId);
    [&] {
        const uint64_t nowMs = zx_nowMs();
        if(!zx_framePickBGRA(snapshot,&blockErr))return;
        const ZXFrameObject &frame = *snapshot;
        uint64_t ageMs = nowMs >= frame.createdAtMs ? nowMs - frame.createdAtMs : 0;
        CFAbsoluteTime total0 = TLinkImageNowSeconds();

        if ([mode isEqualToString:@"pick"]) {
            if ([data count] < 4) { blockErr = zx_frameError(@"1;;pick format should be frame_id;;pick;;x;;y[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 5) ? zx_stringIsPointCoord(data[4]) : false;
            uint64_t maxAgeMs = ([data count] >= 6) ? (uint64_t)MAX(0, [data[5] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
            TLinkNativeFramePickValue pixel;
            if(!zx_framePickPixel(frame,[data[2] doubleValue],[data[3] doubleValue],pointCoord,request,pixel,&blockErr))return;
            double totalMs = (TLinkImageNowSeconds() - total0) * 1000.0;
            ret = [NSString stringWithFormat:@"%d;;%d;;%d;;%llu;;%.3f;;%.3f", pixel.red, pixel.green, pixel.blue, (unsigned long long)ageMs, totalMs, totalMs];
            return;
        }

        if ([mode isEqualToString:@"pick_many"]) {
            if ([data count] < 3) { blockErr = zx_frameError(@"1;;pick_many format should be frame_id;;pick_many;;x,y|x,y|...[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 4) ? zx_stringIsPointCoord(data[3]) : false;
            uint64_t maxAgeMs = ([data count] >= 5) ? (uint64_t)MAX(0, [data[4] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;

            if([data[2] length]>32768){blockErr=zx_frameError(@"1;;point_table_limit\r\n");return;}
            NSArray<NSString *> *items = [data[2] componentsSeparatedByString:@"|"];
            if(items.count>512){blockErr=zx_frameError(@"1;;point_table_limit\r\n");return;}
            NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:[items count]];
            for (NSString *item in items) {
                if (!item || [item length] == 0) continue;
                NSArray<NSString *> *xy = [item componentsSeparatedByString:@","];
                if ([xy count] != 2) { blockErr = zx_frameError(@"1;;invalid_pick_many_point\r\n"); return; }
                double px=0,py=0;
                if(!TLinkColorDouble([xy[0] UTF8String],px)||!TLinkColorDouble([xy[1] UTF8String],py)){
                    blockErr=zx_frameError(@"1;;invalid_pick_many_point\r\n");return;
                }
                TLinkNativeFrameColor pixel;
                if(!zx_framePickManyPixel(frame,px,py,pointCoord,request,pixel,&blockErr))return;
                [parts addObject:[NSString stringWithFormat:@"%d,%d,%d,%d,%d",pixel.x,pixel.y,pixel.red,pixel.green,pixel.blue]];
            }
            double totalMs = (TLinkImageNowSeconds() - total0) * 1000.0;
            ret = [NSString stringWithFormat:@"%@;;%llu;;%.3f;;%.3f", [parts componentsJoinedByString:@"|"], (unsigned long long)ageMs, totalMs, totalMs];
            return;
        }

        if ([mode isEqualToString:@"search_single"]) {
            if ([data count] < 13) { blockErr = zx_frameError(@"1;;search_single format should be frame_id;;search_single;;x;;y;;w;;h;;rmin;;rmax;;gmin;;gmax;;bmin;;bmax;;skip[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 14) ? zx_stringIsPointCoord(data[13]) : false;
            uint64_t maxAgeMs = ([data count] >= 15) ? (uint64_t)MAX(0, [data[14] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
            TLinkNativeFrameSearchRequest search;search.frame.pointCoord=pointCoord;
            search.x=[data[2] doubleValue];search.y=[data[3] doubleValue];search.width=[data[4] doubleValue];search.height=[data[5] doubleValue];
            search.redMin=[data[6] intValue];search.redMax=[data[7] intValue];search.greenMin=[data[8] intValue];search.greenMax=[data[9] intValue];
            search.blueMin=[data[10] intValue];search.blueMax=[data[11] intValue];search.skip=[data[12] intValue];
            TLinkNativeFrameSearchValue found;
            const auto status=TLinkFrameSearchScan(frame.bgra.data(),frame.width,frame.height,size_t(frame.bytesPerRow),frame.scale,search,request,found);
            if(status==TLinkFrameSearchStatus::CoordinateInvalid){blockErr=zx_frameError(@"1;;frame_coordinate_invalid\r\n");return;}
            if(status==TLinkFrameSearchStatus::Stopped)return;
            double totalMs=(TLinkImageNowSeconds()-total0)*1000.0;
            ret=[NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d;;%llu;;%.3f;;%.3f",found.x,found.y,found.red,found.green,found.blue,(unsigned long long)ageMs,totalMs,totalMs];
            return;
        }

        if ([mode isEqualToString:@"is_colors"]) {
            if ([data count] < 5) { blockErr = zx_frameError(@"1;;is_colors format should be frame_id;;is_colors;;table;;mode;;value[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 6) ? zx_stringIsPointCoord(data[5]) : false;
            uint64_t maxAgeMs = ([data count] >= 7) ? (uint64_t)MAX(0, [data[6] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
            std::vector<ZXPointColor> points;
            if (!zx_parsePointTableVector(data[2], points, &blockErr)) return;
            int colorMode = [data[3] intValue];
            double value = [data[4] doubleValue];
            bool matched=false;
            if(!TLinkFrameColorsEvaluate(frame.bgra.data(),frame.width,frame.height,size_t(frame.bytesPerRow),frame.scale,points,pointCoord,colorMode,value,request,matched))return;
            double totalMs = (TLinkImageNowSeconds() - total0) * 1000.0;
            ret = [NSString stringWithFormat:@"%d;;%llu;;%.3f;;%.3f", matched ? 1 : 0, (unsigned long long)ageMs, totalMs, totalMs];
            return;
        }

        if ([mode isEqualToString:@"find_multi_point"]) {
            if ([data count] < 10) { blockErr = zx_frameError(@"1;;find_multi_point format should be frame_id;;find_multi_point;;x;;y;;w;;h;;table;;mode;;value;;skip[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 11) ? zx_stringIsPointCoord(data[10]) : false;
            uint64_t maxAgeMs = ([data count] >= 12) ? (uint64_t)MAX(0, [data[11] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
            TLinkNativeFrameMultiRequest search;search.colors.frame.pointCoord=pointCoord;
            search.x=[data[2] doubleValue];search.y=[data[3] doubleValue];search.width=[data[4] doubleValue];search.height=[data[5] doubleValue];
            TLinkColorRect region;
            if(!TLinkFrameMultiRegion(frame.width,frame.height,frame.scale,search,region)){blockErr=zx_frameError(@"1;;frame_coordinate_invalid\r\n");return;}
            std::vector<ZXPointColor> points;
            if(!zx_parsePointTableVector(data[6],points,&blockErr))return;
            if(!TLinkFrameMultiOffsets(points,frame.scale,pointCoord)){blockErr=zx_frameError(@"1;;frame_coordinate_invalid\r\n");return;}
            TLinkNativeFrameMultiValue found;
            if(!TLinkFrameMultiScan(frame.bgra.data(),frame.width,frame.height,size_t(frame.bytesPerRow),region,points,[data[7] intValue],[data[8] doubleValue],[data[9] intValue],request,found))return;
            double totalMs=(TLinkImageNowSeconds()-total0)*1000.0;
            ret=[NSString stringWithFormat:@"%d;;%d;;%llu;;%.3f;;%.3f",found.x,found.y,(unsigned long long)ageMs,totalMs,totalMs];
            return;
        }

        blockErr = zx_frameError(@"1;;unknown_color_frame_mode\r\n");
    }();
    if(request.stopped())blockErr=zx_frameError([NSString stringWithFormat:@"1;;%s\r\n",request.error()]);
    if (blockErr) {
        if (error) *error = blockErr;
        return nil;
    }
    return ret;
}

NSString* handleFrameBatchTaskFromRawData(UInt8 *eventData, NSError **error)
{
    auto request = std::make_shared<TLinkModernImageRequest>(TLinkCurrentNativeBudget());
    TLinkModernImageScope requestScope(request);
    if(request->stopped()){if(error)*error=zx_frameError(@"-1;;template_cancelled_or_timed_out\r\n");return nil;}

    NSArray<NSString *> *data = zx_splitEventData(eventData);
    if ([data count] < 2) {
        if (error) *error = zx_frameError(@"1;;Frame batch format should be frame_id;;op@@op...[;;coord;;max_age_ms;;auto_release]\r\n");
        return nil;
    }
    if(!zx_frameBatchInputs(data)){if(error)*error=zx_frameError(@"1;;invalid_frame_batch_parameters\r\n");return nil;}
    uint32_t frameId = (uint32_t)[data[0] intValue];
    NSString *opsRaw = data[1];
    bool pointCoord = ([data count] >= 3) ? zx_stringIsPointCoord(data[2]) : false;
    uint64_t maxAgeMs = ([data count] >= 4) ? (uint64_t)MAX(0, [data[3] longLongValue]) : kDefaultFrameTtlMs;
    bool autoRelease = ([data count] >= 5) ? ([data[4] intValue] != 0) : false;

    NSString *ret = nil;
    NSError *blockErr = nil;
    TLinkImageWork work(gImageCompute);
    if (!work) { if (error) *error = zx_frameError(@"1;;image_compute_busy\r\n"); return nil; }
    ZXFrameRef snapshot;
    __block ZXFrameRef admittedFrame;
    __block unordered_map<uint32_t, ZXImageRef> admittedImages;
    NSArray<NSString *> *ops = [opsRaw componentsSeparatedByString:@"@@"];
    for (NSString *opRaw in ops) {
        if(request->stopped()){if(error)*error=zx_frameError([NSString stringWithFormat:@"-1;;%s\r\n",request->error()]);return nil;}
        NSArray<NSString *> *fields = [opRaw componentsSeparatedByString:@","];
        if ([fields count] >= 2 && [[fields[0] lowercaseString] isEqualToString:@"img"]) {
            admittedImages.emplace((uint32_t)[fields[1] intValue], ZXImageRef());
            if (admittedImages.size() > kMaxImageObjects) {
                if (error) *error = zx_frameError(@"1;;image_not_found\r\n");
                return nil;
            }
        }
    }
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        zx_cleanupFramesLocked(zx_nowMs());
        auto it = gFrameStore.find(frameId);
        if (it != gFrameStore.end()) admittedFrame = it->second;
        for (auto &entry : admittedImages) {
            auto image = gImageStore.find(entry.first);
            if (image != gImageStore.end()) entry.second = image->second;
        }
        zx_rearmFrameExpiryLocked();
    });
    snapshot = std::move(admittedFrame);
    const auto images = std::move(admittedImages);
    [&] {
        const uint64_t nowMs = zx_nowMs();
        if (!snapshot) {
            blockErr = zx_frameError(@"1;;frame_not_found\r\n");
            return;
        }
        const ZXFrameObject &frame = *snapshot;
        if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
        uint64_t ageMs = nowMs >= frame.createdAtMs ? nowMs - frame.createdAtMs : 0;
        CFAbsoluteTime total0 = TLinkImageNowSeconds();
        NSMutableArray<NSString *> *results = [NSMutableArray array];

        for (NSString *opRaw in ops) {
            if (request->stopped()) return;
            if (!opRaw || [opRaw length] == 0) continue;
            NSArray<NSString *> *fields = [opRaw componentsSeparatedByString:@","];
            if ([fields count] < 1) { blockErr = zx_frameError(@"1;;invalid_batch_op\r\n"); return; }
            NSString *kind = [[fields[0] lowercaseString] copy];

            if ([kind isEqualToString:@"img"]) {
                if ([fields count] < 9) { blockErr = zx_frameError(@"1;;batch img format should be img,image_id,x,y,w,h,acceptable,scale,pixel_skip\r\n"); return; }
                if (!frame.hasGray || frame.gray.empty()) { blockErr = zx_frameError(@"1;;frame_missing_gray\r\n"); return; }
                uint32_t imageId = (uint32_t)[fields[1] intValue];
                auto iit = images.find(imageId);
                if (iit == images.end() || !iit->second || iit->second->gray.empty()) { blockErr = zx_frameError(@"1;;image_not_found\r\n"); return; }

                if(frame.gray.cols!=frame.width||frame.gray.rows!=frame.height){blockErr=zx_frameError(@"1;;frame_geometry_invalid\r\n");return;}
                int workX = zx_coordToPixel([fields[2] doubleValue], frame.scale, pointCoord);
                int workY = zx_coordToPixel([fields[3] doubleValue], frame.scale, pointCoord);
                int workW = zx_coordToPixel([fields[4] doubleValue], frame.scale, pointCoord);
                int workH = zx_coordToPixel([fields[5] doubleValue], frame.scale, pointCoord);
                if(workX==INT_MIN||workY==INT_MIN||workW==INT_MIN||workH==INT_MIN){blockErr=zx_frameError(@"1;;frame_coordinate_invalid\r\n");return;}
                if (workX < 0) workX = 0;
                if (workY < 0) workY = 0;
                if (workX >= frame.width) workX = frame.width - 1;
                if (workY >= frame.height) workY = frame.height - 1;
                if (workW <= 0 || workW > frame.width - workX) workW = frame.width - workX;
                if (workH <= 0 || workH > frame.height - workY) workH = frame.height - workY;

                double acceptable = [fields[6] doubleValue];
                float scale = [fields[7] floatValue];
                int pixelSkip = [fields[8] intValue];
                CFAbsoluteTime op0 = TLinkImageNowSeconds();
                cv::Rect roi(workX, workY, workW, workH);
                cv::Mat region = frame.gray(roi);
                int mx = -1, my = -1, mw = 0, mh = 0;
                double score = 0.0;
                bool match = zx_findTemplateSAD(region, iit->second->gray, acceptable, scale, scale, 1.0f, pixelSkip,
                                                &mx, &my, &mw, &mh, &score);
                double opMs = (TLinkImageNowSeconds() - op0) * 1000.0;
                if(request->stopped())return;
                if (!match) {
                    [results addObject:[NSString stringWithFormat:@"img:-1,-1,0,0,-1,-1,%.4f,%.3f", score, opMs]];
                } else {
                    int absX = workX + mx;
                    int absY = workY + my;
                    double cx = absX + mw / 2.0;
                    double cy = absY + mh / 2.0;
                    [results addObject:[NSString stringWithFormat:@"img:%d,%d,%d,%d,%.2f,%.2f,%.4f,%.3f", absX, absY, mw, mh, cx, cy, score, opMs]];
                }
                continue;
            }

            if ([kind isEqualToString:@"pick_many"]) {
                if ([fields count] < 2) { blockErr = zx_frameError(@"1;;batch pick_many format should be pick_many,x,y|x,y\r\n"); return; }
                if (!frame.hasBGRA || frame.bgra.empty()) { blockErr = zx_frameError(@"1;;frame_missing_bgra\r\n"); return; }
                if(!TLinkFrameColorGeometry(frame.width,frame.height,frame.bytesPerRow,frame.bgra.size())){blockErr=zx_frameError(@"1;;frame_geometry_invalid\r\n");return;}
                CFAbsoluteTime op0 = TLinkImageNowSeconds();
                NSArray<NSString *> *items = [fields[1] componentsSeparatedByString:@"|"];
                NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:[items count]];
                for (NSString *item in items) {
                    if (!item || [item length] == 0) continue;
                    NSArray<NSString *> *xy = [item componentsSeparatedByString:@":"];
                    if ([xy count] != 2) xy = [item componentsSeparatedByString:@"/"];
                    if ([xy count] != 2) { blockErr = zx_frameError(@"1;;invalid_batch_pick_many_point\r\n"); return; }
                    double px=0,py=0;int x=0,y=0;
                    if(!TLinkColorDouble([xy[0] UTF8String],px)||!TLinkColorDouble([xy[1] UTF8String],py)||
                       !TLinkFrameColorCoordinate(px,frame.scale,pointCoord,x)||!TLinkFrameColorCoordinate(py,frame.scale,pointCoord,y)){
                        blockErr=zx_frameError(@"1;;invalid_batch_pick_many_point\r\n");return;
                    }
                    if(!request->consume(1))return;
                    if (x < 0 || y < 0 || x >= frame.width || y >= frame.height) { blockErr = zx_frameError(@"1;;point_out_of_bounds\r\n"); return; }
                    int r = 0, g = 0, b = 0;
                    zx_readBGRA(frame, x, y, &r, &g, &b);
                    [parts addObject:[NSString stringWithFormat:@"%d,%d,%d,%d,%d", x, y, r, g, b]];
                }
                double opMs = (TLinkImageNowSeconds() - op0) * 1000.0;
                [results addObject:[NSString stringWithFormat:@"pick_many:%@,%.3f", [parts componentsJoinedByString:@"|"], opMs]];
                continue;
            }

            blockErr = zx_frameError(@"1;;unknown_batch_op\r\n");
            return;
        }

        double totalMs = (TLinkImageNowSeconds() - total0) * 1000.0;
        ret = [NSString stringWithFormat:@"%@;;%llu;;%.3f", [results componentsJoinedByString:@"@@"], (unsigned long long)ageMs, totalMs];
        if(request->stopped())return;
        if (autoRelease) {
            TLinkNativeDispatchSync(zx_imageQueue(), ^{
                gFrameStore.erase(frameId); // IDs are never reused; admitted readers retain their snapshot.
                zx_rearmFrameExpiryLocked();
            });
        }
    }();
    if (request->stopped()) blockErr = zx_frameError([NSString stringWithFormat:@"-1;;%s\r\n",request->error()]);
    if (blockErr) {
        if (error) *error = blockErr;
        return nil;
    }
    return ret;
}

bool zx_copyFrameGrayRegionForOCR(uint32_t frameId,
                                  int rx,
                                  int ry,
                                  int rw,
                                  int rh,
                                  NSString *coord,
                                  uint64_t maxAgeMs,
                                  cv::Mat &outGray,
                                  uint64_t *outAgeMs,
                                  NSError **error,
                                  int ocrScaleUp)
{
    bool ok = false;
    NSError *blockErr = nil;
    cv::Mat copied;
    uint64_t ageMs = 0;
    bool pointCoord = zx_stringIsPointCoord(coord ?: @"");

    TLinkImageWork work(gImageCompute);
    if (!work) { if (error) *error = zx_frameError(@"1;;image_compute_busy\r\n"); return false; }
    ZXFrameRef snapshot;
    snapshot = zx_snapshotFrame(frameId);
    [&] {
        const uint64_t nowMs = zx_nowMs();
        if (!snapshot) {
            blockErr = zx_frameError(@"1;;frame_not_found\r\n");
            return;
        }

        const ZXFrameObject &frame = *snapshot;
        if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
        ageMs = nowMs >= frame.createdAtMs ? nowMs - frame.createdAtMs : 0;

        int workX = zx_coordToPixel(rx, frame.scale, pointCoord);
        int workY = zx_coordToPixel(ry, frame.scale, pointCoord);
        int workW = zx_coordToPixel(rw, frame.scale, pointCoord);
        int workH = zx_coordToPixel(rh, frame.scale, pointCoord);
        if (workX < 0) workX = 0;
        if (workY < 0) workY = 0;
        if (workX >= frame.width) workX = frame.width - 1;
        if (workY >= frame.height) workY = frame.height - 1;
        if (workW <= 0 || workX + workW > frame.width) workW = frame.width - workX;
        if (workH <= 0 || workY + workH > frame.height) workH = frame.height - workY;
        if (workW <= 0 || workH <= 0) {
            blockErr = zx_frameError(@"1;;empty_ocr_region\r\n");
            return;
        }

        TLinkOCRImagePlan plan;
        if (!TLinkOCRPlanImage(workW, workH, ocrScaleUp, true, plan)) {
            blockErr = zx_frameError(@"1;;ocr_scaled_image_too_large\r\n"); return;
        }
        if (TLinkNativeStopped()) return;
        cv::Rect roi(workX, workY, workW, workH);
        if (frame.hasGray && !frame.gray.empty()) {
            copied = frame.gray(roi).clone();
            ok = !copied.empty();
            return;
        }

        if (frame.hasBGRA && !frame.bgra.empty()) {
            cv::Mat bgra(frame.height, frame.width, CV_8UC4, const_cast<uint8_t *>(frame.bgra.data()), frame.bytesPerRow);
            cv::Mat region = bgra(roi);
            cv::cvtColor(region, copied, COLOR_BGRA2GRAY);
            ok = !copied.empty();
            return;
        }

        blockErr = zx_frameError(@"1;;frame_missing_gray_bgra\r\n");
    }();

    if (!ok) {
        if (error) *error = blockErr ?: zx_frameError(@"1;;ocr_region_copy_failed\r\n");
        return false;
    }

    outGray = copied;
    if (outAgeMs) *outAgeMs = ageMs;
    return true;
}

@implementation Image
@end

// BEGIN image store core (serialized by zx_imageQueue).
static void zx_cleanupFramesLocked(uint64_t nowMs)
{
    for (auto it = gFrameStore.begin(); it != gFrameStore.end();) {
        if (nowMs >= it->second->expiresAtMs) it = gFrameStore.erase(it);
        else ++it;
    }
}

static void zx_trimFramesLocked(void)
{
    while (gFrameStore.size() >= kMaxFrameObjects) {
        auto oldest = gFrameStore.begin();
        for (auto it = gFrameStore.begin(); it != gFrameStore.end(); ++it) {
            if (it->second->createdAtMs < oldest->second->createdAtMs ||
                (it->second->createdAtMs == oldest->second->createdAtMs && it->first < oldest->first)) oldest = it;
        }
        gFrameStore.erase(oldest);
    }
}

static uint32_t zx_storeImageLocked(std::shared_ptr<ZXImageObject> image)
{
    if (!image || !image->charge || image->gray.empty() || gImageStore.size() >= kMaxImageObjects) return 0;
    const uint32_t imageId = TLinkImageNextId(gNextImageId);
    if (!imageId) return 0;
    image->imageId = imageId;
    gImageStore.emplace(imageId, std::move(image));
    return imageId;
}

static uint32_t zx_storeFrameLocked(std::shared_ptr<ZXFrameObject> frame)
{
    const uint64_t nowMs = zx_nowMs();
    zx_cleanupFramesLocked(nowMs);
    if (!frame || !frame->charge || nowMs >= frame->expiresAtMs || !zx_rearmFrameExpiryLocked()) return 0;
    const uint32_t frameId = TLinkImageNextId(gNextFrameId);
    if (!frameId) return 0;
    zx_trimFramesLocked();
    frame->frameId = frameId;
    gFrameStore.emplace(frameId, std::move(frame));
    zx_rearmFrameExpiryLocked();
    return frameId;
}
// END image store core.

// BEGIN image store dispatch adapter.
static dispatch_source_t gFrameExpiryTimer;
static bool zx_rearmFrameExpiryLocked(void)
{
    if (!gFrameExpiryTimer) {
        gFrameExpiryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, zx_imageQueue());
        if (!gFrameExpiryTimer) return false;
        dispatch_source_set_event_handler(gFrameExpiryTimer, ^{
            zx_cleanupFramesLocked(zx_nowMs());
            zx_rearmFrameExpiryLocked();
        });
        dispatch_resume(gFrameExpiryTimer);
    }
    uint64_t earliest = UINT64_MAX;
    for (const auto &entry : gFrameStore) earliest = std::min(earliest, entry.second->expiresAtMs);
    const uint64_t now = zx_nowMs();
    const uint64_t delay = earliest <= now ? 0 : std::min(earliest - now, kHardFrameTtlMs);
    dispatch_source_set_timer(gFrameExpiryTimer,
        gFrameStore.empty() ? DISPATCH_TIME_FOREVER : dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay * NSEC_PER_MSEC),
        DISPATCH_TIME_FOREVER, NSEC_PER_MSEC);
    return true;
}

static ZXFrameRef zx_snapshotFrame(uint32_t frameId)
{
    __block ZXFrameRef snapshot;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        zx_cleanupFramesLocked(zx_nowMs());
        auto it = gFrameStore.find(frameId);
        if (it != gFrameStore.end()) snapshot = it->second;
        zx_rearmFrameExpiryLocked();
    });
    return snapshot;
}

static std::shared_ptr<TLinkImageCharge> zx_reservePayload(TLinkImageKind kind, size_t bytes)
{
    __block std::shared_ptr<TLinkImageCharge> charge;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        if (kind == TLinkImageKind::Frame) {
            zx_cleanupFramesLocked(zx_nowMs());
            zx_trimFramesLocked();
            if (!zx_rearmFrameExpiryLocked()) return;
        } else if (gImageStore.size() >= kMaxImageObjects) return;
        charge = gImageMemory.reserve(kind, bytes);
    });
    return charge;
}
// END image store dispatch adapter.

// BEGIN frame Vision provider.
CGImageRef TLinkCreateVisionImageFromFrame(uint32_t frameId,CGRect region,NSString *coord,uint64_t maxAgeMs,
                                          CGRect *pixelRegion,uint64_t *ageMs,NSError **error)
{
    if(TLinkNativeStopped()){if(error)*error=zx_frameError(@"-1;;vision_cancelled_or_timed_out\r\n");return NULL;}
    if(!frameId||frameId>INT_MAX||maxAgeMs>5000||(![coord isEqualToString:@"pixel"]&&![coord isEqualToString:@"point"])){
        if(error)*error=zx_frameError(@"-1;;vision_frame_parameters_invalid\r\n");return NULL;
    }
    TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"-1;;vision_frame_compute_busy\r\n");return NULL;}
    auto frame=zx_snapshotFrame(frameId);
    if(TLinkNativeStopped()){if(error)*error=zx_frameError(@"-1;;vision_cancelled_or_timed_out\r\n");return NULL;}
    if(!frame){if(error)*error=zx_frameError(@"-1;;vision_frame_not_found\r\n");return NULL;}
    const uint64_t now=zx_nowMs(),age=now>=frame->createdAtMs?now-frame->createdAtMs:0;
    if(now>=frame->expiresAtMs||age>(maxAgeMs?maxAgeMs:1000)){
        if(error)*error=zx_frameError(@"-1;;vision_frame_expired\r\n");return NULL;
    }
    TLinkVisionROI roi;
    if(!TLinkFrameVisionRegion(frame->width,frame->height,frame->scale,[coord isEqualToString:@"point"],
        region.origin.x,region.origin.y,region.size.width,region.size.height,roi)){
        if(error)*error=zx_frameError(@"-1;;vision_frame_roi_invalid_or_too_large\r\n");return NULL;
    }
    if(!frame->hasBGRA||frame->bgra.empty()||frame->bytesPerRow<frame->width*4||
        size_t(frame->bytesPerRow)>frame->bgra.size()/size_t(frame->height)){
        if(error)*error=zx_frameError(@"-1;;vision_frame_missing_bgra\r\n");return NULL;
    }
    // This reader holds the original ledger charge after store erase/TTL/eviction.
    auto holder=std::unique_ptr<ZXFrameRef>(new(std::nothrow) ZXFrameRef(frame));
    if(!holder){if(error)*error=zx_frameError(@"-1;;vision_frame_provider_failed\r\n");return NULL;}
    CGDataProviderRef provider=CGDataProviderCreateWithData(holder.get(),frame->bgra.data(),
        size_t(frame->bytesPerRow)*frame->height,[](void *info,const void *,size_t){delete static_cast<ZXFrameRef *>(info);});
    if(!provider){if(error)*error=zx_frameError(@"-1;;vision_frame_provider_failed\r\n");return NULL;}
    holder.release(); // Provider now owns the reader; failed creation below also releases it.
    CGImageRef image=NULL;
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    if(color){
        image=CGImageCreate(frame->width,frame->height,8,32,frame->bytesPerRow,color,
            kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst,provider,NULL,false,kCGRenderingIntentDefault);
        CGColorSpaceRelease(color);
    }
    CGDataProviderRelease(provider);
    if(!image){if(error)*error=zx_frameError(@"-1;;vision_frame_image_failed\r\n");return NULL;}
    if(TLinkNativeStopped()){CGImageRelease(image);if(error)*error=zx_frameError(@"-1;;vision_cancelled_or_timed_out\r\n");return NULL;}
    if(pixelRegion)*pixelRegion=CGRectMake(roi.x,roi.y,roi.width,roi.height);
    if(ageMs)*ageMs=age;
    return image;
}
// END frame Vision provider.


static NSArray<NSString *> *zx_splitEventData(UInt8 *eventData)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw) return @[];
    return [raw componentsSeparatedByString:@";;"];
}

static bool zx_stringIsPointCoord(NSString *coord)
{
    return coord && [[coord lowercaseString] isEqualToString:@"point"];
}

static int zx_coordToPixel(double value, double scale, bool pointCoord)
{
    int result=INT_MIN;
    return TLinkFrameColorCoordinate(value,scale,pointCoord,result) ? result : INT_MIN;
}

static bool zx_frameTooOld(const ZXFrameObject &frame, uint64_t maxAgeMs, uint64_t nowMs, NSError **error)
{
    uint64_t age = nowMs >= frame.createdAtMs ? nowMs - frame.createdAtMs : 0;
    if (maxAgeMs == 0) maxAgeMs = kDefaultFrameTtlMs;
    if (nowMs >= frame.expiresAtMs || age > maxAgeMs) {
        if (error) {
            *error = zx_frameError([NSString stringWithFormat:@"1;;frame_expired;;%llu\r\n", (unsigned long long)age]);
        }
        return true;
    }
    return false;
}

static bool zx_renderBGRAFromCGImage(CGImageRef img, std::vector<uint8_t> &out, int *outW, int *outH, int *outBpr)
{
    if (!img) return false;
    size_t pixels = 0;
    if (!TLinkImagePixels(CGImageGetWidth(img), CGImageGetHeight(img), kMaxImagePixels, &pixels)) return false;
    int width = (int)CGImageGetWidth(img);
    int height = (int)CGImageGetHeight(img);
    int bytesPerRow = width * 4;
    out.assign((size_t)bytesPerRow * (size_t)height, 0);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(out.data(),
                                             width,
                                             height,
                                             8,
                                             bytesPerRow,
                                             colorSpace,
                                             kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) {
        out.clear();
        return false;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), img);
    CGContextRelease(ctx);
    if (outW) *outW = width;
    if (outH) *outH = height;
    if (outBpr) *outBpr = bytesPerRow;
    return true;
}

static bool zx_parsePointTableVector(NSString *tableStr, std::vector<ZXPointColor> &points, NSError **error)
{
    points.clear();
    if (!tableStr || tableStr.length==0 || tableStr.length>32768) {
        if(error)*error=zx_frameError(@"1;;point_table_limit_or_empty\r\n");return false;
    }
    NSArray<NSString *> *items=[tableStr componentsSeparatedByString:@"|"];
    if(items.count>512){if(error)*error=zx_frameError(@"1;;point_table_limit\r\n");return false;}
    for(NSString *item in items){
        if(item.length==0)continue;
        NSArray<NSString *> *parts=[item componentsSeparatedByString:@",,"];
        ZXPointColor pc;
        if(parts.count!=5 || !TLinkColorInt([parts[0] UTF8String],pc.dx) || !TLinkColorInt([parts[1] UTF8String],pc.dy) ||
           !TLinkColorInt([parts[2] UTF8String],pc.r) || !TLinkColorInt([parts[3] UTF8String],pc.g) || !TLinkColorInt([parts[4] UTF8String],pc.b) ||
           !TLinkColorRGB(pc.r)||!TLinkColorRGB(pc.g)||!TLinkColorRGB(pc.b)){
            if(error)*error=zx_frameError(@"1;;invalid_point_table\r\n");return false;
        }
        points.push_back(pc);
    }
    if(points.empty()){if(error)*error=zx_frameError(@"1;;point_table_empty\r\n");return false;}
    return true;
}

static inline void zx_readBGRA(const ZXFrameObject &frame, int x, int y, int *r, int *g, int *b)
{
    const uint8_t *p = frame.bgra.data() + ((size_t)y * (size_t)frame.bytesPerRow) + ((size_t)x * 4);
    if (b) *b = p[0];
    if (g) *g = p[1];
    if (r) *r = p[2];
}

// Decode the same bounded byte sequence whose dimensions were checked. OpenCV keeps
// its legacy IMREAD_GRAYSCALE semantics; ImageIO is metadata-only preflight.
static cv::Mat zx_decodeBoundedImage(NSString *path, std::shared_ptr<TLinkImageCharge> &charge, NSError **error)
{
    static const NSUInteger maxEncodedBytes = 32 * 1024 * 1024;
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!file) return cv::Mat();
    NSData *encoded = nil;
    @try { encoded = [file readDataOfLength:maxEncodedBytes + 1]; }
    @catch (NSException *exception) { (void)exception; }
    @finally { [file closeFile]; }
    if (!encoded.length || encoded.length > maxEncodedBytes) {
        if (error) *error = zx_frameError(@"-1;;image_encoded_limit_or_read_failed\r\n");
        return cv::Mat();
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)encoded,
        (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@(false)});
    NSDictionary *properties = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr)) : nil;
    if (source) CFRelease(source);
    const unsigned long long width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue];
    const unsigned long long height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    size_t pixels = 0;
    if (width > 8192 || height > 8192 || !TLinkImagePixels((size_t)width, (size_t)height, kMaxImagePixels, &pixels)) {
        if (error) *error = zx_frameError(@"-1;;image_pixel_limit_or_invalid_metadata\r\n");
        return cv::Mat();
    }
    charge = zx_reservePayload(TLinkImageKind::Image, pixels);
    if (!charge) {
        if (error) *error = zx_frameError(@"-1;;image_memory_budget\r\n");
        return cv::Mat();
    }
    cv::Mat bytes(1, (int)encoded.length, CV_8UC1, const_cast<void *>(encoded.bytes));
    cv::Mat gray = cv::imdecode(bytes, IMREAD_GRAYSCALE);
    // OpenCV may apply EXIF rotation while ImageIO reports encoded dimensions.
    const bool sameDimensions = gray.cols == (int)width && gray.rows == (int)height;
    const bool rotatedDimensions = gray.cols == (int)height && gray.rows == (int)width;
    if (gray.empty() || (!sameDimensions && !rotatedDimensions)) {
        if (error) *error = zx_frameError(@"-1;;image_decode_dimension_mismatch\r\n");
        return cv::Mat();
    }
    return gray;
}

// BEGIN structured image open.
static NSString *zx_openImage(const TLinkNativeImageOpenRequest &request,uint32_t &publishedId,NSError **error){
    NSString *inputPath=request.path;
    NSString *path = zx_resolveImagePath(inputPath);
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Image not found. Path: %@\r\n", path ?: inputPath]}];
        }
        return nil;
    }
    std::shared_ptr<TLinkImageCharge> charge;
    NSError *decodeError = nil;
    Mat gray = zx_decodeBoundedImage(path, charge, &decodeError);
    if (gray.empty()) {
        if (error) {
            *error = decodeError ?: [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to read image. Path: %@\r\n", path]}];
        }
        return nil;
    }
    auto pendingImage = std::make_shared<ZXImageObject>();
    ZXImageObject &image = *pendingImage;
    image.charge = std::move(charge);
    image.gray = std::move(gray);
    image.w = image.gray.cols;
    image.h = image.gray.rows;
    image.createdAtMs = zx_nowMs();
    image.ttlMs = 0;
    image.ownerSessionId=request.sessionId;image.ownerRunId=request.runId;image.ownerRuntime=request.runtime;
    __block uint32_t imageId = 0;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        imageId = zx_storeImageLocked(pendingImage);
    });
    publishedId=imageId;
    if (imageId == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image object limit reached. Release unused images.\r\n"}];
        }
        return nil;
    }
    return [NSString stringWithFormat:@"%u;;%d;;%d", imageId, image.w, image.h];
}
NSString *openStoredImage(const TLinkNativeImageOpenRequest &request,uint32_t &publishedId,NSError **error){
    publishedId=0;TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"-1;;image_compute_busy\r\n");return nil;}
    return zx_openImage(request,publishedId,error);
}
// END structured image open.

NSString* handleImageObjectTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithFormat:@"%s", (const char *)eventData] componentsSeparatedByString:@";;"];
    if ([data count] < 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image task missing action.\r\n"}];
        }
        return nil;
    }
    int action = [data[0] intValue];
    if (action == 1) {
        TLinkImageWork work(gImageCompute);
        if (!work) { if (error) *error = zx_frameError(@"-1;;image_compute_busy\r\n"); return nil; }
        if ([data count] < 5) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image capture format should be action;;x;;y;;w;;h\r\n"}];
            }
            return nil;
        }
        int x = [data[1] intValue];
        int y = [data[2] intValue];
        int w = [data[3] intValue];
        int h = [data[4] intValue];

        CGImageRef screen = [Screen createScreenShotCGImageRef];
        if (!screen) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screenshot.\r\n"}];
            }
            return nil;
        }
        int sw = (int)CGImageGetWidth(screen);
        int sh = (int)CGImageGetHeight(screen);
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x >= sw) x = sw - 1;
        if (y >= sh) y = sh - 1;
        if (w <= 0 || x + w > sw) w = sw - x;
        if (h <= 0 || y + h > sh) h = sh - y;

        CGRect cropRect = CGRectMake(x, y, w, h);
        CGImageRef cropped = CGImageCreateWithImageInRect(screen, cropRect);
        CGImageRelease(screen);
        if (!cropped) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to crop screenshot.\r\n"}];
            }
            return nil;
        }
        size_t pixels = 0;
        auto charge = TLinkImagePixels(CGImageGetWidth(cropped), CGImageGetHeight(cropped), kMaxImagePixels, &pixels)
            ? zx_reservePayload(TLinkImageKind::Image, pixels) : nullptr;
        if (!charge) {
            CGImageRelease(cropped);
            if (error) *error = zx_frameError(@"-1;;image_pixel_or_memory_limit\r\n");
            return nil;
        }
        NSError *convErr = nil;
        Mat gray = zx_cvMatGrayFromCGImage(cropped, &convErr);
        CGImageRelease(cropped);
        if (gray.empty()) {
            if (error) {
                *error = convErr ?: [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to convert screenshot to mat.\r\n"}];
            }
            return nil;
        }

        auto pendingImage = std::make_shared<ZXImageObject>();
        ZXImageObject &image = *pendingImage;
        image.charge = std::move(charge);
        image.gray = std::move(gray);
        image.w = image.gray.cols;
        image.h = image.gray.rows;
        image.createdAtMs = zx_nowMs();
        image.ttlMs = 0;
        zx_applyImageOwner(image, data, 5);
        __block uint32_t imageId = 0;
        TLinkNativeDispatchSync(zx_imageQueue(), ^{
            imageId = zx_storeImageLocked(pendingImage);
        });
        if (imageId == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image object limit reached. Release unused images.\r\n"}];
            }
            return nil;
        }
        return [NSString stringWithFormat:@"%u;;%d;;%d", imageId, image.w, image.h];
    }
    else if (action == 2) {
        TLinkImageWork work(gImageCompute);
        if (!work) { if (error) *error = zx_frameError(@"-1;;image_compute_busy\r\n"); return nil; }
        if (data.count<2) {if(error)*error=zx_frameError(@"-1;;Image open format should be action;;path\r\n");return nil;}
        TLinkNativeImageOpenRequest request;request.path=data[1];
        request.sessionId=zx_stringFromPart(data,2,"");request.runId=zx_stringFromPart(data,3,"");request.runtime=zx_stringFromPart(data,4,"legacy");
        uint32_t publishedId=0;return zx_openImage(request,publishedId,error);
    }
    // BEGIN raw image release action.
    else if (action == 3) {
        if(data.count<2)return nil;
        NSString *target=[data[1] isKindOfClass:[NSString class]]?data[1]:@"",*lower=[target lowercaseString];
        TLinkNativeImageReleaseRequest request;request.imageId=uint32_t([target intValue]);request.all=[lower isEqualToString:@"all"]||[lower isEqualToString:@"scoped"];request.scoped=data.count>=5;
        if(request.scoped){request.sessionId=zx_stringFromPart(data,2,"");request.runId=zx_stringFromPart(data,3,"");request.runtime=zx_stringFromPart(data,4,"");}
        if([lower isEqualToString:@"scoped"]&&!request.scoped){TLinkNativeDispatchSync(zx_imageQueue(), ^{});return @"0";}
        return [NSString stringWithFormat:@"%lu",(unsigned long)releaseStoredImages(request)];
    }
    // END raw image release action.

    if (error) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unknown image task action.\r\n"}];
    }
    return nil;
}

// BEGIN numeric image release.
size_t releaseStoredImages(const TLinkNativeImageReleaseRequest &request){
    __block size_t removed=0;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        if(request.all){
            if(request.scoped){
                std::vector<uint32_t> ids;
                for(auto const &kv:gImageStore)if(zx_ownerMatchesImage(*kv.second,request.sessionId,request.runId,request.runtime))ids.push_back(kv.first);
                for(uint32_t id:ids)removed+=gImageStore.erase(id);
            }else{removed=gImageStore.size();gImageStore.clear();}
        }else{
            auto it=gImageStore.find(request.imageId);
            if(it!=gImageStore.end()&&(!request.scoped||zx_ownerMatchesImage(*it->second,request.sessionId,request.runId,request.runtime)))removed=gImageStore.erase(request.imageId);
        }
    });
    return removed;
}
// END numeric image release.

NSString* handleFindImageTaskFromRawData(UInt8 *eventData, NSError **error)
{
    auto request = std::make_shared<TLinkModernImageRequest>(TLinkCurrentNativeBudget());
    TLinkModernImageScope requestScope(request);
    if(request->stopped()){if(error)*error=zx_frameError(@"-1;;template_cancelled_or_timed_out\r\n");return nil;}

    TLinkImageWork work(gImageCompute);
    if (!work) { if (error) *error = zx_frameError(@"-1;;image_compute_busy\r\n"); return nil; }

    NSArray *data = [[NSString stringWithFormat:@"%s", eventData] componentsSeparatedByString:@";;"];
    if ([data count] < 10) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Find image format should be template_id;;x;;y;;w;;h;;acceptable;;scale_min;;scale_max;;scale_step;;pixel_skip\r\n"}];
        }
        return nil;
    }
    if(!zx_imageInputs(data,false)){if(error)*error=zx_frameError(@"-1;;invalid_image_parameters\r\n");return nil;}
    uint32_t templateId = (uint32_t)[data[0] intValue];
    int rx = [data[1] intValue];
    int ry = [data[2] intValue];
    int rw = [data[3] intValue];
    int rh = [data[4] intValue];
    double acceptable = [data[5] doubleValue];
    float scaleMin = [data[6] floatValue];
    float scaleMax = [data[7] floatValue];
    float scaleStep = [data[8] floatValue];
    int pixelSkip = [data[9] intValue];

    __block ZXImageRef templObj;
    __block bool found = false;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        auto it = gImageStore.find(templateId);
        if (it != gImageStore.end()) {
            templObj = it->second;
            found = true;
        }
    });
    if (!found || !templObj || templObj->gray.empty()) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Template image object not found.\r\n"}];
        }
        return nil;
    }

    if(request->stopped()){if(error)*error=zx_frameError(@"-1;;template_cancelled_or_timed_out\r\n");return nil;}
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    if (!screen) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screenshot.\r\n"}];
        }
        return nil;
    }
    struct ImageOwner {
        CGImageRef image;
        explicit ImageOwner(CGImageRef value):image(value){}
        ~ImageOwner(){reset();}
        void reset(){if(image){CGImageRelease(image);image=NULL;}}
        ImageOwner(const ImageOwner &)=delete;ImageOwner &operator=(const ImageOwner &)=delete;
    };
    ImageOwner screenOwner(screen);
    size_t pixels=0;
    if(!TLinkImagePixels(CGImageGetWidth(screen),CGImageGetHeight(screen),8388608,&pixels)){
        screenOwner.reset();if(error)*error=zx_frameError(@"-1;;image_source_pixel_limit\r\n");return nil;
    }
    int sw = (int)CGImageGetWidth(screen);
    int sh = (int)CGImageGetHeight(screen);
    if (rx < 0) rx = 0;
    if (ry < 0) ry = 0;
    if (rx >= sw) rx = sw - 1;
    if (ry >= sh) ry = sh - 1;
    if (rw <= 0 || rw > sw - rx) rw = sw - rx;
    if (rh <= 0 || rh > sh - ry) rh = sh - ry;

    TLinkModernImagePlan plan;
    if(!TLinkModernImageMakePlan(rw,rh,templObj->gray.cols,templObj->gray.rows,scaleMin,scaleMax,scaleStep,
       [](double value){return cvRound(value);},plan)||!request->reserve(plan.bytes)||request->stopped()){
        screenOwner.reset();if(error)*error=zx_frameError(@"-1;;image_preparation_limit_or_cancelled\r\n");return nil;
    }
    CGRect cropRect = CGRectMake(rx, ry, rw, rh);
    CGImageRef cropped = CGImageCreateWithImageInRect(screen, cropRect);
    screenOwner.reset();
    if (!cropped) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to crop screenshot.\r\n"}];
        }
        return nil;
    }
    ImageOwner cropOwner(cropped);
    NSError *convErr = nil;
    Mat imgGray = zx_cvMatGrayFromCGImage(cropped, &convErr);
    cropOwner.reset();
    if (imgGray.empty()) {
        if (error) {
            *error = convErr ?: [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to convert screenshot to mat.\r\n"}];
        }
        return nil;
    }

    int mx = -1, my = -1, mw = 0, mh = 0;
    double score = 0.0;
    BOOL match = zx_findTemplateSAD(imgGray, templObj->gray, acceptable, scaleMin, scaleMax, scaleStep, pixelSkip,
                                   &mx, &my, &mw, &mh, &score);
    if(request->stopped()){if(error)*error=zx_frameError([NSString stringWithFormat:@"-1;;%s\r\n",request->error()]);return nil;}
    if (!match) {
        // Provide best score to help tuning acceptable threshold.
        return [NSString stringWithFormat:@"-1;;-1;;0;;0;;-1;;-1;;%.4f", score];
    }

    int absX = rx + mx;
    int absY = ry + my;
    double cx = absX + mw / 2.0;
    double cy = absY + mh / 2.0;
    return [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%.2f;;%.2f;;%.4f", absX, absY, mw, mh, cx, cy, score];
}
