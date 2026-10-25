#include "../shared/TLinkNativeFrameCaptureResult.h"
// Hardware/renderer/CV doubles; compile the actual capture/owner/store adapters.
static unsigned liveCaptureImages=0,captureScreenCalls=0;
static bool failCaptureScreen=false,failCaptureRender=false,failCaptureGray=false,capturePixelOverflow=false;
static unsigned captureTicks=0;
static double captureFixtureSeconds(){return double(captureTicks++)*.000125;}
static double captureFixtureWall(){return 123.456;}
static size_t captureFixtureWidth(CGImageRef image){return capturePixelOverflow?kMaxImagePixels+1:CGImageGetWidth(image);}
static void captureFixtureProviderRelease(void *info,const void *,size_t){delete static_cast<std::vector<uint8_t> *>(info);--liveCaptureImages;}
@interface Screen : NSObject
+ (CGImageRef)createScreenShotCGImageRef;
+ (CGFloat)getScale;
@end
@implementation Screen
+ (CGFloat)getScale{return 2;}
+ (CGImageRef)createScreenShotCGImageRef{
    ++captureScreenCalls;if(failCaptureScreen)return NULL;
    auto *pixels=new std::vector<uint8_t>(256,23);++liveCaptureImages;
    CGDataProviderRef provider=CGDataProviderCreateWithData(pixels,pixels->data(),pixels->size(),captureFixtureProviderRelease);assert(provider);
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();assert(color);
    CGImageRef image=CGImageCreate(8,8,8,32,32,color,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little,provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(color);CGDataProviderRelease(provider);assert(image);return image;
}
@end
static bool zx_renderBGRAFromCGImage(CGImageRef image,std::vector<uint8_t> &out,int *w,int *h,int *stride){
    if(failCaptureRender)return false;*w=int(CGImageGetWidth(image));*h=int(CGImageGetHeight(image));*stride=*w*4;out.assign(size_t(*h)*size_t(*stride),23);return true;
}
#define CV_8UC4 4
static const int COLOR_BGRA2GRAY=1;
namespace cv {static void cvtColor(const Mat &source,Mat &out,int mode){assert(mode==COLOR_BGRA2GRAY);out=failCaptureGray?Mat():Mat(source.rows,source.cols);}}
#include "FrameCaptureParserUnderTest.inc"
#include "FrameCaptureOwnerUnderTest.inc"
#define TLinkImageNowSeconds captureFixtureSeconds
#define CFAbsoluteTimeGetCurrent captureFixtureWall
#define CGImageGetWidth captureFixtureWidth
#include "FrameCaptureUnderTest.inc"
#include "fixtures/frame-capture-handler-legacy-v1.inc"
#undef CGImageGetWidth
#undef CFAbsoluteTimeGetCurrent
#undef TLinkImageNowSeconds
static void clearCaptureFixtureFrames(){TLinkNativeFrameReleaseRequest cleanup;cleanup.all=true;releaseStoredFrames(cleanup);assert(gImageMemory.stats().frames==0&&liveCaptureImages==0);}
static void frameCaptureRuntimeCases(){
    captureClockOverride=100;
    for(unsigned n=0;n<48;++n){
        NSString *raw=[NSString stringWithFormat:@"%d;;%d;;%d;;session;;run;;js \t",int(n%3)-1,int((n/3)%3)-1,n%2?0:int(n)*200];NSError *error=nil;
        captureTicks=0;NSString *old=legacyFrameCaptureTaskFromRawData((UInt8 *)raw.UTF8String,&error);assert(old&&!error);
        NSArray *a=[old componentsSeparatedByString:@";;"];ZXFrameRef oldReader=zx_snapshotFrame(uint32_t([a[0] intValue]));assert(oldReader);
        TLinkNativeFrameCaptureRequest expected;expected.gray=[@((int(n%3)-1)) boolValue];expected.bgra=[@((int((n/3)%3)-1)) boolValue];expected.ttlMs=n%2?0:uint64_t(n)*200;expected.sessionId="session";expected.runId="run";expected.runtime="js \t";
        TLinkNativeFrameReleaseRequest cleanup;cleanup.all=true;releaseStoredFrames(cleanup);
        captureTicks=0;uint32_t id=0;TLinkNativeFrameCaptureValue value;assert(captureStoredFrame(expected,id,value,&error)&&!error&&id);NSString *current=TLinkNativeFrameCaptureBody(value);
        NSArray *b=[current componentsSeparatedByString:@";;"];assert(a.count==14&&b.count==14);for(unsigned i=1;i<14;++i)assert([a[i] isEqual:b[i]]);
        auto reader=zx_snapshotFrame(id);assert(reader&&reader->hasGray==oldReader->hasGray&&reader->hasBGRA==oldReader->hasBGRA&&reader->ttlMs==oldReader->ttlMs&&reader->ownerRuntime==oldReader->ownerRuntime&&reader->ownerSessionId==oldReader->ownerSessionId&&reader->ownerRunId==oldReader->ownerRunId);
        oldReader.reset();reader.reset();clearCaptureFixtureFrames();
    }
    TLinkNativeFrameCaptureRequest request;uint32_t id=0;TLinkNativeFrameCaptureValue value;NSError *error=nil;const unsigned before=captureScreenCalls;
    {TLinkImageWork a(gImageCompute),b(gImageCompute);assert(a&&b);assert(!captureStoredFrame(request,id,value,&error)&&[error.localizedDescription containsString:@"image_compute_busy"]&&captureScreenCalls==before);}
    failCaptureScreen=true;assert(!captureStoredFrame(request,id,value,&error)&&[error.localizedDescription containsString:@"capture_failed"]);failCaptureScreen=false;
    capturePixelOverflow=true;assert(!captureStoredFrame(request,id,value,&error)&&[error.localizedDescription containsString:@"frame_pixel_limit"]);capturePixelOverflow=false;
    {auto full=gImageMemory.reserve(TLinkImageKind::Frame,96*1024*1024);assert(full);assert(!captureStoredFrame(request,id,value,&error)&&[error.localizedDescription containsString:@"frame_memory_budget"]);}
    failCaptureRender=true;assert(!captureStoredFrame(request,id,value,&error)&&[error.localizedDescription containsString:@"bgra_render_failed"]);failCaptureRender=false;
    failCaptureGray=true;assert(!captureStoredFrame(request,id,value,&error)&&[error.localizedDescription containsString:@"gray_convert_failed"]);failCaptureGray=false;
    __block uint32_t saved=0;dispatch_sync(zx_imageQueue(),^{saved=gNextFrameId;gNextFrameId=0;});
    assert(!captureStoredFrame(request,id,value,&error)&&[error.localizedDescription containsString:@"frame_publish_failed"]&&!id);dispatch_sync(zx_imageQueue(),^{gNextFrameId=saved;});
    clearCaptureFixtureFrames();captureClockOverride=0;
    puts("Frame capture Foundation passed: 48 frozen RAW/numeric channel/TTL/owner/metadata cases, real CG ownership and controlled clock, busy/pixel/memory/render/gray/publish faults and zero final charges.");
}
