#include "../shared/TLinkNativeDispatch.h"
#include <new>
#include "../shared/TLinkModernImagePolicy.h"
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include "image-storage-fixture.h"
// Production serial queue, timer and snapshot/reservation adapter; real steady clock.
#include "ImageQueueUnderTest.inc"
static uint64_t zx_nowMs() { return TLinkImageNowMs(); }
static bool zx_rearmFrameExpiryLocked();
#include "ImageCoreUnderTest.inc"
#include "ImageDispatchUnderTest.inc"
#include "ImageOwnerPartsUnderTest.inc"
#include "ImageNumericReleaseUnderTest.inc"
#include "ImageReleaseUnderTest.inc"
#include "NumericImageReleaseUnderTest.inc"
#include "ImageReleaseActionUnderTest.inc"
#include "fixtures/image-release-handler-legacy-v1.inc"
#include "fixtures/frame-release-handler-legacy-v1.inc"
namespace cv {
static int decoderCalls = 0, decoderWidth = 2, decoderHeight = 3;
static Mat imdecode(const Mat &input, int) {
    assert(input.rows == 1 && input.cols > 0); ++decoderCalls;
    return Mat(decoderHeight, decoderWidth);
}
}
#define CV_8UC1 0
static const int IMREAD_GRAYSCALE = 0;
#include "ImageErrorUnderTest.inc"
#include "ImageDecoderUnderTest.inc"
#include "../shared/TLinkFrameVisionPolicy.h"
static bool failFrameProvider=false,failFrameImage=false;
static CGDataProviderRef FixtureFrameProvider(void *info,const void *data,size_t bytes,CGDataProviderReleaseDataCallback release){
    if(failFrameProvider){failFrameProvider=false;return NULL;}return CGDataProviderCreateWithData(info,data,bytes,release);
}
static CGImageRef FixtureFrameImage(size_t width,size_t height,size_t bits,size_t pixelBits,size_t stride,CGColorSpaceRef color,CGBitmapInfo flags,CGDataProviderRef provider,const CGFloat *decode,bool interpolate,CGColorRenderingIntent intent){
    if(failFrameImage){failFrameImage=false;return NULL;}return CGImageCreate(width,height,bits,pixelBits,stride,color,flags,provider,decode,interpolate,intent);
}
#include "FrameVisionUnderTest.inc"

// Compile the actual handler admission/transfer and lookup statements together:
// __block maps belong to Objective-C blocks; compute uses ordinary C++ locals.
static bool findAdmissionFixture(uint32_t frameId, uint32_t imageId, NSError **error) {
#include "ImageFindAdmissionUnderTest.inc"
    (void)blockErr;
    [&] {
#include "ImageFindLookupUnderTest.inc"
        if (snapshot && iit != images.end() && iit->second) ok = true;
    }();
    return ok;
}
static NSString *batchAdmissionFixture(uint32_t frameId, uint32_t imageId, NSString *opsRaw, NSError **error) {
    auto request=std::make_shared<TLinkModernImageRequest>(TLinkNativeBudgetPtr{});
#include "ImageBatchAdmissionUnderTest.inc"
    (void)blockErr;
    [&] {
#include "ImageBatchLookupUnderTest.inc"
        if (snapshot && iit != images.end() && iit->second) ret = @"admitted";
    }();
    return ret;
}
static void decodeFixtures(NSString *directory) {
    NSString *path = [directory stringByAppendingPathComponent:@"small.png"];
    NSMutableData *encoded = [NSMutableData data];
    uint8_t pixels[24] = {};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 2, 3, 8, 8, space, kCGImageAlphaPremultipliedLast);
    assert(context); CGColorSpaceRelease(space);
    CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context); assert(image);
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)encoded, CFSTR("public.png"), 1, nullptr);
    assert(destination); CGImageDestinationAddImage(destination, image, nullptr);
    assert(CGImageDestinationFinalize(destination)); CFRelease(destination); CGImageRelease(image);
    assert([encoded writeToFile:path atomically:true]);
    NSError *error = nil; std::shared_ptr<TLinkImageCharge> charge;
    auto decoded = zx_decodeBoundedImage(path, charge, &error);
    assert(!decoded.empty() && !error && cv::decoderCalls == 1 && charge->bytes() == 6);
    decoded = cv::Mat(); charge.reset();
    cv::decoderWidth = 3; cv::decoderHeight = 2;
    assert(!zx_decodeBoundedImage(path, charge, &error).empty()); charge.reset();
    cv::decoderWidth = 4; cv::decoderHeight = 2;
    assert(zx_decodeBoundedImage(path, charge, &error).empty() && error); charge.reset();
    cv::decoderWidth = 2; cv::decoderHeight = 3; const int calls = cv::decoderCalls;
    auto full = gImageMemory.reserve(TLinkImageKind::Image, 64 * 1024 * 1024); assert(full);
    assert(zx_decodeBoundedImage(path, charge, &error).empty() && cv::decoderCalls == calls); full.reset();
    // Corrupt metadata and oversized encoded files must be rejected before OpenCV.
    assert([[NSData dataWithBytes:"invalid" length:7] writeToFile:path atomically:true]);
    assert(zx_decodeBoundedImage(path, charge, &error).empty() && cv::decoderCalls == calls);
    NSMutableData *oversized = [NSMutableData dataWithLength:32 * 1024 * 1024 + 1];
    assert([oversized writeToFile:path atomically:true]);
    assert(zx_decodeBoundedImage(path, charge, &error).empty() && cv::decoderCalls == calls);
    assert(gImageMemory.stats().total == 0);
}
// Keep C++ block capture lifetimes inside these helpers, independent of ARC's
// stack-block cleanup placement in the enclosing test scope.
static uint32_t publishFrame(std::shared_ptr<ZXFrameObject> value) {
    __block uint32_t result = 0;
    dispatch_sync(zx_imageQueue(), ^{ result = zx_storeFrameLocked(value); });
    return result;
}
static uint32_t publishImage(std::shared_ptr<ZXImageObject> value) {
    __block uint32_t result = 0;
    dispatch_sync(zx_imageQueue(), ^{ result = zx_storeImageLocked(value); });
    assert(result);
    return result;
}
static void barrier() { dispatch_sync(zx_imageQueue(), ^{}); }
static void releaseFrame(uint32_t id){NSString *value=[NSString stringWithFormat:@"%u",id];(void)handleFrameReleaseTaskFromRawData((UInt8 *)value.UTF8String,NULL);}
static void numericReleaseParityCases(){
    for(unsigned n=0;n<120;++n){
        auto owned=frameFixture(zx_nowMs(),5000);owned->ownerSessionId="session";owned->ownerRunId="run";owned->ownerRuntime="js";
        const uint32_t id=publishFrame(owned);owned.reset();const uint32_t other=publishFrame(frameFixture(zx_nowMs(),5000));
        __block unordered_map<uint32_t,ZXFrameRef> baseline;
        dispatch_sync(zx_imageQueue(),^{baseline=gFrameStore;});
        NSString *single=[NSString stringWithFormat:@"%u;;session;;run;;js",id];
        NSArray *commands=@[single,@"all",@"ALL;;session;;run;;js",@"scoped;;session;;other;;js",@"ScOpEd;;session;;run;;js",@"scoped",@"scoped;;session",@"0",@"-1",@"invalid",@"all;;;;;;",@"all;;session;;run;;js \t"];
        NSString *command=commands[n%commands.count];NSError *error=nil;
        NSString *old=legacyFrameReleaseTaskFromRawData((UInt8 *)command.UTF8String,&error);assert(old&&!error);
        __block std::vector<uint32_t> remaining;
        dispatch_sync(zx_imageQueue(),^{for(auto const &item:gFrameStore)remaining.push_back(item.first);gFrameStore=baseline;});
        NSString *current=handleFrameReleaseTaskFromRawData((UInt8 *)command.UTF8String,&error);assert([old isEqualToString:current]&&!error);
        dispatch_sync(zx_imageQueue(),^{std::vector<uint32_t> actual;for(auto const &item:gFrameStore)actual.push_back(item.first);std::sort(remaining.begin(),remaining.end());std::sort(actual.begin(),actual.end());assert(actual==remaining);gFrameStore.clear();zx_rearmFrameExpiryLocked();});
        baseline.clear();assert(gImageMemory.stats().frames==0);(void)other;
    }
    // Actual numeric release bypasses compute admission and retains admitted readers.
    const uint32_t id=publishFrame(frameFixture(zx_nowMs(),5000));auto reader=zx_snapshotFrame(id);TLinkNativeFrameReleaseRequest request;request.frameId=id;
    {TLinkImageWork a(gImageCompute),b(gImageCompute);assert(a&&b);assert(releaseStoredFrames(request)==1);}
    assert(reader->bgra[0]==42&&gImageMemory.stats().frames==256);reader.reset();assert(gImageMemory.stats().frames==0);
    puts("Frame release Foundation passed: 120 frozen actual handler/parser/store cases, scoped/global/partial commands, busy compute and held readers.");
}
static void numericImageReleaseParityCases(){
    for(unsigned n=0;n<144;++n){
        auto owned=imageFixture();owned->ownerSessionId="session";owned->ownerRunId="run";owned->ownerRuntime="js";
        const uint32_t id=publishImage(owned);owned.reset();publishImage(imageFixture());
        __block unordered_map<uint32_t,ZXImageRef> baseline;
        dispatch_sync(zx_imageQueue(),^{baseline=gImageStore;});
        NSString *single=[NSString stringWithFormat:@"3;;%u;;session;;run;;js",id];
        NSArray *commands=@[single,[single stringByAppendingString:@" \t"],@"3;;all",@"3;;ALL;;session;;run;;js",@"3;;scoped;;session;;other;;js",@"3;;ScOpEd;;session;;run;;js",@"3;;scoped",@"3;;scoped;;session",@"3;;0",@"3;;-1",@"3;;invalid",@"3;;all;;;;;;",@"3",@"3;;all;;session;;run;;js \t",@"3;;all;;session;;run;;js;;ignored"];
        NSString *command=commands[n%commands.count];NSError *error=nil;
        NSString *old=legacyImageReleaseTaskFromRawData((UInt8 *)command.UTF8String,&error);assert(!error);
        __block std::vector<uint32_t> remaining;
        dispatch_sync(zx_imageQueue(),^{for(auto const &item:gImageStore)remaining.push_back(item.first);gImageStore=baseline;});
        NSString *current=imageReleaseActionUnderTest((UInt8 *)command.UTF8String,&error);assert((old==nil&&current==nil)||[old isEqualToString:current]);assert(!error);
        dispatch_sync(zx_imageQueue(),^{std::vector<uint32_t> actual;for(auto const &item:gImageStore)actual.push_back(item.first);std::sort(remaining.begin(),remaining.end());std::sort(actual.begin(),actual.end());assert(actual==remaining);gImageStore.clear();});
        baseline.clear();assert(gImageMemory.stats().images==0);
    }
    const uint32_t id=publishImage(imageFixture());__block ZXImageRef reader;
    dispatch_sync(zx_imageQueue(),^{reader=gImageStore.at(id);});TLinkNativeImageReleaseRequest request;request.imageId=id;
    {TLinkImageWork a(gImageCompute),b(gImageCompute);assert(a&&b);assert(releaseStoredImages(request)==1);}
    assert(!reader->gray.empty()&&gImageMemory.stats().images==64);reader.reset();assert(gImageMemory.stats().images==0);
    puts("Image release Foundation passed: 144 frozen action-3 parser/store cases, exact whitespace/scoping/partial commands, busy compute and held-reader cleanup.");
}
static void frameVisionFixtures(){
    fputs("Image runtime: actual immutable Vision provider survives store release and balances failed creation\n",stderr);
    auto frame=frameFixture(zx_nowMs(),5000);for(size_t i=0;i<frame->bgra.size();++i)frame->bgra[i]=uint8_t(i);
    uint32_t id=publishFrame(frame);std::weak_ptr<const ZXFrameObject> weak=frame;frame.reset();
    NSError *error=nil;CGRect roi=CGRectZero;uint64_t age=0;
    CGImageRef image=TLinkCreateVisionImageFromFrame(id,CGRectMake(1,1,2,2),@"point",5000,&roi,&age,&error);
    assert(image&&!error&&roi.origin.x==2&&roi.origin.y==2&&roi.size.width==4&&roi.size.height==4);
    CFDataRef data=CGDataProviderCopyData(CGImageGetDataProvider(image));assert(data&&CFDataGetLength(data)==256&&CFDataGetBytePtr(data)[17]==17);CFRelease(data);
    releaseFrame(id);assert(!weak.expired()&&gImageMemory.stats().frames==256);CGImageRelease(image);assert(weak.expired()&&gImageMemory.stats().total==0);
    id=publishFrame(frameFixture(zx_nowMs(),5000));
    failFrameProvider=true;error=nil;assert(!TLinkCreateVisionImageFromFrame(id,CGRectZero,@"pixel",5000,NULL,NULL,&error)&&[error.localizedDescription containsString:@"vision_frame_provider_failed"]);
    failFrameImage=true;error=nil;assert(!TLinkCreateVisionImageFromFrame(id,CGRectZero,@"pixel",5000,NULL,NULL,&error)&&[error.localizedDescription containsString:@"vision_frame_image_failed"]);
    releaseFrame(id);assert(gImageMemory.stats().total==0);
    id=publishFrame(frameFixture(zx_nowMs()-2000,5000));error=nil;
    assert(!TLinkCreateVisionImageFromFrame(id,CGRectZero,@"pixel",1000,NULL,NULL,&error)&&[error.localizedDescription containsString:@"vision_frame_expired"]);
    error=nil;image=TLinkCreateVisionImageFromFrame(id,CGRectZero,@"pixel",5000,NULL,NULL,&error);assert(image&&!error);CGImageRelease(image);releaseFrame(id);
    frame=frameFixture(zx_nowMs(),5000);frame->hasBGRA=false;id=publishFrame(frame);frame.reset();error=nil;
    assert(!TLinkCreateVisionImageFromFrame(id,CGRectZero,@"pixel",5000,NULL,NULL,&error)&&[error.localizedDescription containsString:@"vision_frame_missing_bgra"]);releaseFrame(id);
    assert(gImageMemory.stats().total==0);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    @autoreleasepool {
        fputs("Image runtime: bounded file/ImageIO preflight fixtures\n", stderr);
        decodeFixtures([NSString stringWithUTF8String:argv[1]]);
        frameVisionFixtures();
        numericReleaseParityCases();
        numericImageReleaseParityCases();
        assert(kDefaultFrameTtlMs == 1000 && kMaxImagePixels > 0);
        { TLinkImageWork work(gImageCompute); assert(work); }
        fputs("Image runtime: idle expiry and held readers\n", stderr);
        publishImage(imageFixture());
        uint32_t id = publishFrame(frameFixture(zx_nowMs(), 250)); assert(id);
        ZXFrameRef reader = zx_snapshotFrame(id); assert(reader && reader->bgra[0] == 42);
        // No subsequent image API call is needed for expiration.
        dispatch_semaphore_t expired = dispatch_semaphore_create(0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 700 * NSEC_PER_MSEC), zx_imageQueue(), ^{
            assert(gFrameStore.empty()); assert(gImageMemory.stats().frames == 256);
            dispatch_semaphore_signal(expired);
        });
        assert(dispatch_semaphore_wait(expired, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        reader.reset(); assert(gImageMemory.stats().frames == 0);
        id = publishFrame(frameFixture(zx_nowMs(), kHardFrameTtlMs)); assert(id);
        fputs("Image runtime: Objective-C block to C++ lambda snapshot transfer\n", stderr);
        const uint32_t imageId = publishImage(imageFixture());
        NSError *admissionError = nil;
        NSString *ops = [NSString stringWithFormat:@"img,%u,0,0,8,8,0.9,1,0", imageId];
        assert(findAdmissionFixture(id, imageId, &admissionError) && !admissionError);
        assert([batchAdmissionFixture(id, imageId, ops, &admissionError) isEqualToString:@"admitted"] && !admissionError);
        assert(!findAdmissionFixture(id, imageId + 1, &admissionError));
        NSString *missingOps = [NSString stringWithFormat:@"img,%u,0,0,8,8,0.9,1,0", imageId + 1];
        assert(!batchAdmissionFixture(id, imageId + 1, missingOps, &admissionError));
        // A worker deliberately holds a snapshot without occupying the store queue.
        dispatch_semaphore_t admitted = dispatch_semaphore_create(0), finish = dispatch_semaphore_create(0), done = dispatch_semaphore_create(0);
        const uint32_t heldId = id;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            auto held = zx_snapshotFrame(heldId); assert(held);
            dispatch_semaphore_signal(admitted); dispatch_semaphore_wait(finish, DISPATCH_TIME_FOREVER);
            assert(held->bgra[0] == 42); held.reset(); dispatch_semaphore_signal(done);
        });
        assert(dispatch_semaphore_wait(admitted, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        dispatch_sync(zx_imageQueue(), ^{
            gFrameStore.erase(id); gImageStore.clear(); zx_rearmFrameExpiryLocked();
            assert(gImageMemory.stats().frames == 256 && gImageMemory.stats().images == 0);
        });
        assert(!zx_snapshotFrame(id));
        auto reserved = zx_reservePayload(TLinkImageKind::Image, 64); assert(reserved); reserved.reset();
        dispatch_semaphore_signal(finish);
        assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        barrier(); assert(gImageMemory.stats().total == 0);
        fputs("Image runtime: scoped release while compute busy\n", stderr);
        // Actual scoped release handler must preserve mismatched owners and admit releases during busy compute.
        auto owned = frameFixture(zx_nowMs(), kHardFrameTtlMs);
        owned->ownerSessionId = "session"; owned->ownerRunId = "run"; owned->ownerRuntime = "js";
        id = publishFrame(owned); owned.reset(); assert(id);
        UInt8 mismatch[] = "scoped;;session;;other;;js";
        assert([handleFrameReleaseTaskFromRawData(mismatch, nullptr) intValue] == 0);
        assert(zx_snapshotFrame(id));
        UInt8 matching[] = "scoped;;session;;run;;js";
        { TLinkImageWork a(gImageCompute), b(gImageCompute); assert(a && b);
          assert([handleFrameReleaseTaskFromRawData(matching, nullptr) intValue] == 1); }
        assert(!zx_snapshotFrame(id));
        assert(zx_ownerMatchesImage(*imageFixture(), "", "", ""));
        // A stale timer delivery only cleans current deadlines; a new generation survives.
        id = publishFrame(frameFixture(zx_nowMs(), kHardFrameTtlMs)); assert(id);
        assert(zx_snapshotFrame(id));
        dispatch_sync(zx_imageQueue(), ^{
            zx_cleanupFramesLocked(zx_nowMs()); assert(gFrameStore.count(id));
            gFrameStore.clear(); zx_rearmFrameExpiryLocked();
            dispatch_source_cancel(gFrameExpiryTimer); gFrameExpiryTimer = nil;
        });
        barrier(); assert(gImageMemory.stats().total == 0);
        puts("Image dispatch passed: actual store/snapshot/reservation and ImageIO preflight, idle one-shot expiry, release during held compute and no leaked payload charges.");
    }
}
