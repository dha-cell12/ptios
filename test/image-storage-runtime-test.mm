#include "../shared/TLinkNativeDispatch.h"
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
#include "ImageReleaseUnderTest.inc"
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
static void publishImage(std::shared_ptr<ZXImageObject> value) {
    dispatch_sync(zx_imageQueue(), ^{ assert(zx_storeImageLocked(value)); });
}
static void barrier() { dispatch_sync(zx_imageQueue(), ^{}); }
int main(int argc, char **argv) {
    assert(argc == 2);
    @autoreleasepool {
        fputs("Image runtime: bounded file/ImageIO preflight fixtures\n", stderr);
        decodeFixtures([NSString stringWithUTF8String:argv[1]]);
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
