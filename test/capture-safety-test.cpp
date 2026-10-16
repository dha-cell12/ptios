// Compiles the actual Screen.xm ownership core with fault-injected API doubles.
// These doubles verify caller ownership; real IOSurface/provider behavior needs iOS validation.
#define _USE_MATH_DEFINES
#include <cassert>
#include <climits>
#include <cstdint>
#include <cstdio>
#include <cmath>
#include <limits>
#include <initializer_list>
using std::isfinite;
using CGFloat = double;
struct Properties { size_t width = 1200, height = 800; };
using CFDictionaryRef = const Properties *;
struct Surface { int refs = 1; bool locked = false; };
struct Color { int refs = 1; };
struct Image { size_t width, height, bits; Color *color; Surface *surface; };
struct Context { size_t width, height, row; Color *color; int transforms = 0; bool drawn = false; };
using IOSurfaceRef = Surface *;
using CGColorSpaceRef = Color *;
using CGImageRef = Image *;
using CGContextRef = Context *;
struct Rect { double x, y, width, height; };
static Rect CGRectMake(double x, double y, double w, double h) { return {x, y, w, h}; }
#define CFSTR(value) value
static const int KERN_SUCCESS = 0;
static const int kCGImageAlphaPremultipliedFirst = 2;
enum Failure { None, SurfaceCreate, Lock, ImageCreate, ZeroWidth, ZeroHeight, NoColor, BadBits, BitmapCreate, RotatedCreate, Unlock };
static Failure failure = None;
static int surfaces = 0, colors = 0, images = 0, contexts = 0;
static int locks = 0, unlocks = 0, renders = 0;
static Properties captureProperties;
static void releaseColor(Color *color) {
    if (!color) return;
    assert(color->refs > 0);
    if (--color->refs == 0) { --colors; delete color; }
}
static void CFRelease(Surface *surface) {
    assert(surface && surface->refs > 0);
    if (--surface->refs == 0) { assert(!surface->locked); --surfaces; delete surface; }
}
static void CGImageRelease(Image *image) {
    assert(image);
    releaseColor(image->color);
    if (image->surface) CFRelease(image->surface);
    --images;
    delete image;
}
static Surface *IOSurfaceCreate(CFDictionaryRef props) {
    assert(props == &captureProperties);
    if (failure == SurfaceCreate) return nullptr;
    ++surfaces;
    return new Surface;
}
static int IOSurfaceLock(Surface *surface, int options, void *seed) {
    assert(surface && !surface->locked && options == 0 && !seed);
    ++locks;
    if (failure == Lock) return 1;
    surface->locked = true;
    return KERN_SUCCESS;
}
static int IOSurfaceUnlock(Surface *surface, int options, void *seed) {
    assert(surface && surface->locked && options == 0 && !seed);
    ++unlocks;
    surface->locked = false;
    return failure == Unlock ? 1 : KERN_SUCCESS;
}
static void CARenderServerRenderDisplay(int, const char *, Surface *surface, int, int) {
    assert(surface && surface->locked);
    ++renders;
}
static Image *UICreateCGImageFromIOSurface(Surface *surface) {
    assert(surface && surface->locked);
    if (failure == ImageCreate) return nullptr;
    Color *color = nullptr;
    if (failure != NoColor) { color = new Color; ++colors; }
    ++images;
    ++surface->refs; // Model a provider that retains its surface; validate this assumption on iOS.
    return new Image{failure == ZeroWidth ? 0 : captureProperties.width,
                     failure == ZeroHeight ? 0 : captureProperties.height,
                     failure == BadBits ? size_t(16) : size_t(8), color, surface};
}
static size_t CGImageGetWidth(Image *image) { assert(image); return image->width; }
static size_t CGImageGetHeight(Image *image) { assert(image); return image->height; }
static size_t CGImageGetBitsPerComponent(Image *image) { assert(image); return image->bits; }
static Color *CGImageGetColorSpace(Image *image) { assert(image); return image->color; }
static Context *CGBitmapContextCreate(void *data, size_t width, size_t height, size_t bits,
                                      size_t row, Color *color, int info) {
    assert(!data && width == captureProperties.height && height == captureProperties.width);
    assert(bits == 8 && row == ((width * 4 + 31) & ~size_t(31)));
    assert(color && color->refs > 0 && info == kCGImageAlphaPremultipliedFirst);
    if (failure == BitmapCreate) return nullptr;
    ++color->refs;
    ++contexts;
    return new Context{width, height, row, color};
}
static void CGContextTranslateCTM(Context *context, CGFloat x, CGFloat y) {
    assert(context && context->color->refs > 0);
    if (context->transforms == 0) assert(x == 0.5 * captureProperties.height && y == 0.5 * captureProperties.width);
    else { assert(context->transforms == 2); assert(x == -0.5 * captureProperties.width && y == -0.5 * captureProperties.height); }
    ++context->transforms;
}
static void CGContextRotateCTM(Context *context, CGFloat radians) {
    assert(context && context->transforms == 1 && std::abs(radians + M_PI / 2) < 1e-12);
    ++context->transforms;
}
static void CGContextDrawImage(Context *context, Rect rect, Image *image) {
    assert(context && context->transforms == 3 && image && image->color == context->color);
    assert(context->color->refs == 2); // Source still owns the borrowed color space.
    assert(rect.x == 0 && rect.y == 0 && rect.width == image->width && rect.height == image->height);
    context->drawn = true;
}
static Image *CGBitmapContextCreateImage(Context *context) {
    assert(context && context->drawn && context->color->refs == 2);
    if (failure == RotatedCreate) return nullptr;
    ++context->color->refs;
    ++images;
    return new Image{context->width, context->height, 8, context->color, nullptr};
}
static void CGContextRelease(Context *context) {
    assert(context && context->drawn);
    releaseColor(context->color);
    --contexts;
    delete context;
}
#include "CaptureCoreUnderTest.inc"
static void assertEmpty() { assert(surfaces == 0 && colors == 0 && images == 0 && contexts == 0); }
static void testGeometry() {
    TLinkCaptureGeometry g;
    assert(zx_captureGeometry(390, 844, 3, false, &g));
    assert(g.width == 1170 && g.height == 2532 && g.bytesPerRow == 4704 && g.allocationSize == 4704 * 2532);
    assert(zx_captureGeometry(844, 390, 3, false, &g) && g.width == 1170 && g.height == 2532);
    assert(zx_captureGeometry(768, 1024, 2, true, &g) && g.width == 2048 && g.height == 1536);
    assert(zx_captureGeometry(1024, 768, 2, true, &g) && g.width == 2048 && g.height == 1536);
    assert(zx_captureGeometry(10.9, 20.9, 1, false, &g) && g.width == 10 && g.height == 20);
    assert(!zx_captureGeometry(1, 1, 1, false, nullptr));
    for (double bad : {0.0, -1.0, std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN()}) {
        assert(!zx_captureGeometry(bad, 10, 1, false, &g));
        assert(!zx_captureGeometry(10, bad, 1, false, &g));
        assert(!zx_captureGeometry(10, 10, bad, false, &g));
        assert(g.width == 0 && g.height == 0 && g.allocationSize == 0);
    }
    assert(!zx_captureGeometry(0.1, 10, 1, false, &g));
    assert(!zx_captureGeometry(10, 0.1, 1, false, &g));
    assert(!zx_captureGeometry(double(INT_MAX) + 1, 10, 1, false, &g));
    assert(!zx_captureGeometry(10, double(INT_MAX) + 1, 1, false, &g));
    assert(!zx_captureGeometry(1e308, 10, 1e308, false, &g));
    assert(zx_captureAlignedRowBytes(0) == 0);
    assert(zx_captureAlignedRowBytes(SIZE_MAX) == 0);
    assert(zx_captureAlignedRowBytes((SIZE_MAX - 31) / 4 + 1) == 0);
    assert(zx_captureRotatedImage(nullptr) == nullptr);
}
static void testFrame(Failure fail, bool rotate) {
    failure = fail;
    const int oldLocks = locks, oldUnlocks = unlocks, oldRenders = renders;
    Image *result = zx_captureSurfaceImage(&captureProperties, rotate);
    const bool expectedSuccess = fail == None || (!rotate && (fail == NoColor || fail == BadBits || fail == BitmapCreate || fail == RotatedCreate));
    assert(bool(result) == expectedSuccess);
    assert(locks - oldLocks == (fail == SurfaceCreate ? 0 : 1));
    const int acquired = fail == SurfaceCreate || fail == Lock ? 0 : 1;
    assert(unlocks - oldUnlocks == acquired && renders - oldRenders == acquired);
    assert(contexts == 0);
    if (result) {
        assert(images == 1);
        assert(result->width == (rotate ? captureProperties.height : captureProperties.width));
        assert(result->height == (rotate ? captureProperties.width : captureProperties.height));
        if (result->color) assert(result->color->refs == 1);
        assert(surfaces == (rotate ? 0 : 1));
        CGImageRelease(result);
    }
    assertEmpty();
}
int main() {
    testGeometry();
    for (bool rotate : {false, true}) {
        for (Failure fail : {None, SurfaceCreate, Lock, ImageCreate, ZeroWidth, ZeroHeight, NoColor, BadBits, BitmapCreate, RotatedCreate, Unlock}) testFrame(fail, rotate);
    }
    // Asymmetric, non-aligned dimensions catch reuse of the pre-rotation stride.
    captureProperties = {1201, 803};
    for (int i = 0; i < 10000; ++i) { testFrame(None, false); testFrame(None, true); }
    std::puts("Capture safety passed: geometry, 22 fault/success paths, 20,000 frames; zero live test resources.");
}
