#include "../shared/TLinkNativeImageCapture.h"
// Real Screen CGImage/provider and crop operations; only conversion and fault boundaries are doubled.
using cv::Mat;
static bool imageCaptureStage=false,imageCapturePixelOverflow=false,imageCaptureBadGeometry=false,imageCaptureCropFails=false,imageCaptureGrayFails=false;
static int imageCaptureCropFault=0,imageCaptureGrayFault=0;
static CGRect imageCaptureLastRegion;
static size_t ImageCaptureWidth(CGImageRef image){if(!imageCaptureStage&&imageCaptureBadGeometry)return 0;if(imageCaptureStage&&imageCapturePixelOverflow)return kMaxImagePixels+1;return CGImageGetWidth(image);}
static CGImageRef ImageCaptureCrop(CGImageRef screen,CGRect rect){
    imageCaptureLastRegion=rect;if(imageCaptureCropFault==1)[NSException raise:@"CaptureFixture" format:@"crop"];
    if(imageCaptureCropFault==2)throw std::runtime_error("crop");
    imageCaptureStage=true;return imageCaptureCropFails?NULL:CGImageCreateWithImageInRect(screen,rect);
}
static cv::Mat zx_cvMatGrayFromCGImage(CGImageRef image,NSError **error){
    if(imageCaptureGrayFault==1)[NSException raise:@"CaptureFixture" format:@"convert"];
    if(imageCaptureGrayFault==2)throw std::runtime_error("convert");
    if(imageCaptureGrayFails){if(error)*error=zx_frameError(@"-1;;conversion_fixture_failed\r\n");return cv::Mat();}
    return cv::Mat(int(CGImageGetHeight(image)),int(CGImageGetWidth(image)));
}
#define CGImageGetWidth ImageCaptureWidth
#define CGImageCreateWithImageInRect ImageCaptureCrop
#include "ImageCaptureUnderTest.inc"
#include "ImageCaptureActionUnderTest.inc"
#include "fixtures/image-capture-handler-legacy-v1.inc"
#undef CGImageCreateWithImageInRect
#undef CGImageGetWidth
static void imageCaptureClear(){TLinkNativeImageReleaseRequest r;r.all=true;releaseStoredImages(r);assert(gImageMemory.stats().images==0&&liveCaptureImages==0);}
static void imageCaptureRuntimeCases(){
    for(int n=0;n<96;++n){
        NSString *command=[NSString stringWithFormat:@"1;;%d;;%d;;%d;;%d;;owner;;run;;js \t",n%17-3,(n/3)%17-3,(n/5)%19-4,(n/7)%19-4];NSError *oldError=nil;
        imageCaptureStage=false;NSString *old=legacyImageCaptureTask((UInt8 *)command.UTF8String,&oldError);assert(old&&!oldError&&liveCaptureImages==0);
        const CGRect expectedCrop=imageCaptureLastRegion;NSArray *parts=[old componentsSeparatedByString:@";;"];auto baseline=imageOpenReader(uint32_t([parts[0] intValue]));assert(baseline);
        TLinkNativeImageReleaseRequest all;all.all=true;releaseStoredImages(all);
        for(unsigned variant=0;variant<2;++variant){
            imageCaptureStage=false;NSError *error=nil;NSString *current=nil;uint32_t id=0;TLinkNativeImageValue value;
            if(!variant)current=imageCaptureActionUnderTest((UInt8 *)command.UTF8String,&error);
            else{
                NSArray *fields=[command componentsSeparatedByString:@";;"];TLinkNativeImageCaptureRequest r;r.x=[fields[1] intValue];r.y=[fields[2] intValue];r.width=[fields[3] intValue];r.height=[fields[4] intValue];r.sessionId="owner";r.runId="run";r.runtime="js \t";
                if(captureStoredImage(r,id,value,&error))current=TLinkNativeImageBody(value);
            }
            assert(current&&!error&&CGRectEqualToRect(expectedCrop,imageCaptureLastRegion)&&liveCaptureImages==0);
            NSArray *actual=[current componentsSeparatedByString:@";;"];auto reader=imageOpenReader(uint32_t([actual[0] intValue]));
            assert(actual.count==3&&[parts[1] isEqual:actual[1]]&&[parts[2] isEqual:actual[2]]&&reader);
            assert(reader->w==baseline->w&&reader->h==baseline->h&&reader->ownerSessionId==baseline->ownerSessionId&&reader->ownerRunId==baseline->ownerRunId&&reader->ownerRuntime==baseline->ownerRuntime&&reader->ttlMs==0);
            if(variant)assert(id==value.id&&value.width==reader->w&&value.height==reader->h);
            releaseStoredImages(all);assert(!reader->gray.empty());reader.reset();
        }
        baseline.reset();imageCaptureClear();
    }
    TLinkNativeImageCaptureRequest r;r.x=1;r.y=1;r.width=INT_MAX;r.height=INT_MAX;uint32_t id=0;TLinkNativeImageValue value;NSError *error=nil;
    const auto run=[&]()->bool{imageCaptureStage=false;error=nil;return captureStoredImage(r,id,value,&error);};
    assert(run()&&value.width==7&&value.height==7);imageCaptureClear(); // Previously overflowing x+w/y+h now clamp to remaining extents.
    const unsigned screens=captureScreenCalls;value.id=99;
    {TLinkImageWork a(gImageCompute),b(gImageCompute);assert(a&&b);assert(!run()&&!id&&!value.id&&captureScreenCalls==screens&&[error.localizedDescription containsString:@"image_compute_busy"]);}
    failCaptureScreen=true;assert(!run()&&[error.localizedDescription containsString:@"Unable to capture screenshot"]);failCaptureScreen=false;imageCaptureClear();
    imageCaptureBadGeometry=true;assert(!run()&&[error.localizedDescription containsString:@"image_capture_geometry_invalid"]);imageCaptureBadGeometry=false;imageCaptureClear();
    imageCaptureCropFails=true;assert(!run()&&[error.localizedDescription containsString:@"Failed to crop screenshot"]);imageCaptureCropFails=false;imageCaptureClear();
    imageCapturePixelOverflow=true;assert(!run()&&[error.localizedDescription containsString:@"image_pixel_or_memory_limit"]);imageCapturePixelOverflow=false;imageCaptureClear();
    {auto full=gImageMemory.reserve(TLinkImageKind::Image,64*1024*1024);assert(full);assert(!run()&&liveCaptureImages==0&&[error.localizedDescription containsString:@"image_pixel_or_memory_limit"]);}imageCaptureClear();
    imageCaptureGrayFails=true;assert(!run()&&[error.localizedDescription containsString:@"conversion_fixture_failed"]);imageCaptureGrayFails=false;imageCaptureClear();
    for(int kind:{1,2})for(int fault:{1,2}){
        imageCaptureCropFault=kind==1?fault:0;imageCaptureGrayFault=kind==2?fault:0;bool caught=false;
        @try{try{(void)run();}catch(...){caught=true;}}@catch(__unused NSException *exception){caught=true;}
        assert(caught&&liveCaptureImages==0&&gImageMemory.stats().images==0);imageCaptureCropFault=0;imageCaptureGrayFault=0;
    }
    for(unsigned n=0;n<64;++n)publishImage(imageFixture());assert(!run()&&[error.localizedDescription containsString:@"image_pixel_or_memory_limit"]);imageCaptureClear();
    __block uint32_t saved=0;dispatch_sync(zx_imageQueue(),^{saved=gNextImageId;gNextImageId=0;});assert(!run()&&!id&&[error.localizedDescription containsString:@"Image object limit reached"]);dispatch_sync(zx_imageQueue(),^{gNextImageId=saved;});imageCaptureClear();
    error=nil;assert(!imageCaptureActionUnderTest((UInt8 *)"1;;0",&error)&&[error.localizedDescription containsString:@"Image capture format"]);imageCaptureClear();
    puts("Image capture Foundation passed: 96 frozen old/RAW/direct crop/store cases, real CG image/crop/provider ownership, extreme extents, busy/count/byte/pixel/geometry/crop/convert/publish faults and NS/C++ cleanup. Conversion remains controlled.");
}
