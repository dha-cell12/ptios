#ifndef TLINK_IMAGE_STORAGE_FIXTURE_H
#define TLINK_IMAGE_STORAGE_FIXTURE_H
#include "../shared/TLinkImageStorage.h"
#include "../shared/TLinkNativeFrameRelease.h"
#include "../shared/TLinkNativeImageRelease.h"
#include "../shared/TLinkNativeFrameCapture.h"
#include "../shared/TLinkNativeImageOpen.h"
#include <cassert>
#include <climits>
#include <cstdio>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <vector>
namespace cv {
// Storage/ownership double only. No claim of exercising OpenCV pixel math.
class Mat {
    std::shared_ptr<std::vector<uint8_t>> pixels_;
public:
    int rows = 0, cols = 0;
    Mat() = default;
    Mat(int r, int c) : pixels_(std::make_shared<std::vector<uint8_t>>(static_cast<size_t>(r) * c)), rows(r), cols(c) {}
    Mat(int r, int c, int, void *) : rows(r), cols(c) {} // Borrowed encoded input header.
    Mat(int r,int c,int,void *,size_t) : rows(r),cols(c) {}
    bool empty() const { return !pixels_ || pixels_->empty(); }
    const uint8_t *data() const { return pixels_ ? pixels_->data() : nullptr; }
};
}
using namespace std;
#include "ImagePayloadUnderTest.inc"
#include "ImageGlobalsUnderTest.inc"
#include "ImageOwnerUnderTest.inc"
static_assert(!std::is_copy_constructible<ZXFrameObject>::value, "Frame copies must not compile");
static_assert(!std::is_copy_assignable<ZXFrameObject>::value, "Frame assignment must not compile");
static_assert(!std::is_copy_constructible<ZXImageObject>::value, "Image metadata must retain its charge");
static std::shared_ptr<ZXFrameObject> frameFixture(uint64_t now, uint64_t ttl, size_t bytes = 256) {
    auto p = std::make_shared<ZXFrameObject>();
    p->createdAtMs = now; p->ttlMs = ttl; p->expiresAtMs = TLinkImageExpiry(now, ttl);
    p->charge = gImageMemory.reserve(TLinkImageKind::Frame, bytes); assert(p->charge);
    p->width = 8; p->height = 8; p->bytesPerRow = 32; p->scale = 2;
    p->hasBGRA = true; p->hasGray = false; p->bgra.resize(256, 42);
    return p;
}
static std::shared_ptr<ZXImageObject> imageFixture() {
    auto p = std::make_shared<ZXImageObject>();
    p->gray = cv::Mat(8, 8); p->w = 8; p->h = 8; p->createdAtMs = 1; p->ttlMs = 0;
    p->charge = gImageMemory.reserve(TLinkImageKind::Image, 64); assert(p->charge);
    return p;
}
#endif
