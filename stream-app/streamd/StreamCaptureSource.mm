#import "StreamCaptureSource.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <mach/kern_return.h>
#import <mach/mach_time.h>
#import <os/lock.h>
#import <errno.h>
#import <math.h>
#import <dlfcn.h>

typedef struct __IOSurface *IOSurfaceRef;
typedef struct __IOSurfaceAccelerator *IOSurfaceAcceleratorRef;

extern "C" {
IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
kern_return_t IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
size_t IOSurfaceGetWidth(IOSurfaceRef buffer);
size_t IOSurfaceGetHeight(IOSurfaceRef buffer);
IOSurfaceRef CVPixelBufferGetIOSurface(CVPixelBufferRef pixelBuffer);
CGImageRef UICreateCGImageFromIOSurface(IOSurfaceRef surface);
void CARenderServerRenderDisplay(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);
}

typedef kern_return_t (*SCIOSurfaceAcceleratorCreateFn)(CFAllocatorRef allocator,
                                                        CFDictionaryRef properties,
                                                        IOSurfaceAcceleratorRef *accelerator);
typedef kern_return_t (*SCIOSurfaceAcceleratorTransferSurfaceFn)(IOSurfaceAcceleratorRef accelerator,
                                                                 IOSurfaceRef source,
                                                                 IOSurfaceRef destination,
                                                                 CFDictionaryRef options,
                                                                 void *completion);

static const NSUInteger kSCCaptureSurfacePoolSize = 2;
static os_unfair_lock sSCCaptureLock = OS_UNFAIR_LOCK_INIT;
static IOSurfaceRef sSCCaptureSurfaces[kSCCaptureSurfacePoolSize] = { NULL, NULL };
static NSUInteger sSCCaptureSurfaceIndex = 0;
static int sSCCaptureWidth = 0;
static int sSCCaptureHeight = 0;
static IOSurfaceAcceleratorRef sSCSurfaceAccelerator = NULL;
static SCIOSurfaceAcceleratorCreateFn sSCAcceleratorCreate = NULL;
static SCIOSurfaceAcceleratorTransferSurfaceFn sSCAcceleratorTransfer = NULL;
static NSString *sSCActiveBackend = @"not_started";
static NSString *sSCLastResult = @"not_started";
static uint64_t sSCCaptureCount = 0;
static uint64_t sSCAcceleratedCount = 0;
static uint64_t sSCFallbackCount = 0;
static uint64_t sSCFailureCount = 0;
static uint64_t sSCLastCaptureUs = 0;
static uint64_t sSCLastScaleUs = 0;
static uint64_t sSCLastTotalUs = 0;
static int sSCLastTransferResult = 0;

static void SCResolveSurfaceAcceleratorSymbols(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *createSymbol = dlsym(RTLD_DEFAULT, "IOSurfaceAcceleratorCreate");
        void *transferSymbol = dlsym(RTLD_DEFAULT, "IOSurfaceAcceleratorTransferSurface");
        if (!createSymbol || !transferSymbol) {
            void *framework = dlopen(
                "/System/Library/Frameworks/IOSurface.framework/IOSurface",
                RTLD_LAZY | RTLD_LOCAL);
            if (framework) {
                createSymbol = dlsym(framework, "IOSurfaceAcceleratorCreate");
                transferSymbol = dlsym(framework, "IOSurfaceAcceleratorTransferSurface");
            }
        }
        sSCAcceleratorCreate = (SCIOSurfaceAcceleratorCreateFn)createSymbol;
        sSCAcceleratorTransfer = (SCIOSurfaceAcceleratorTransferSurfaceFn)transferSymbol;
    });
}

static uint64_t SCMonotonicMicroseconds(void)
{
    static mach_timebase_info_data_t timebase = {0, 0};
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&timebase);
    });
    uint64_t ticks = mach_continuous_time();
    __uint128_t nanos = (__uint128_t)ticks * timebase.numer / timebase.denom;
    return (uint64_t)(nanos / 1000);
}

static int SCRoundUp(int value, int multiple)
{
    if (multiple <= 0) return value;
    int rem = value % multiple;
    return rem == 0 ? value : value + multiple - rem;
}

static void SCReleaseCaptureSurfacesLocked(void)
{
    for (NSUInteger i = 0; i < kSCCaptureSurfacePoolSize; i++) {
        if (sSCCaptureSurfaces[i]) {
            CFRelease(sSCCaptureSurfaces[i]);
            sSCCaptureSurfaces[i] = NULL;
        }
    }
    sSCCaptureSurfaceIndex = 0;
    sSCCaptureWidth = 0;
    sSCCaptureHeight = 0;
}

static BOOL SCDisplayPixelSize(int *outWidth, int *outHeight)
{
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize bounds = [UIScreen mainScreen].bounds.size;
    int rawWidth = (int)llround(bounds.width * scale);
    int rawHeight = (int)llround(bounds.height * scale);
    int width = MIN(rawWidth, rawHeight);
    int height = MAX(rawWidth, rawHeight);
    if (width <= 0 || height <= 0) return NO;
    if (outWidth) *outWidth = width;
    if (outHeight) *outHeight = height;
    return YES;
}

static IOSurfaceRef SCCreateBGRAIOSurface(int width, int height)
{
    int bytesPerRow = SCRoundUp(width * 4, 32);
    NSMutableDictionary *properties = [@{
        @"IOSurfaceAllocSize": @(bytesPerRow * height),
        @"IOSurfaceBytesPerElement": @4,
        @"IOSurfaceBytesPerRow": @(bytesPerRow),
        @"IOSurfaceWidth": @(width),
        @"IOSurfaceHeight": @(height),
        @"IOSurfacePixelFormat": @(1111970369), // 'BGRA'
        @"IOSurfaceIsGlobal": @YES,
    } mutableCopy];
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!surface) {
        properties[@"IOSurfaceIsGlobal"] = @NO;
        surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    }
    return surface;
}

static BOOL SCEnsureCaptureSurfacesLocked(int width, int height)
{
    if (sSCCaptureWidth == width && sSCCaptureHeight == height) {
        BOOL complete = YES;
        for (NSUInteger i = 0; i < kSCCaptureSurfacePoolSize; i++) {
            complete = complete && sSCCaptureSurfaces[i] != NULL;
        }
        if (complete) return YES;
    }

    SCReleaseCaptureSurfacesLocked();
    for (NSUInteger i = 0; i < kSCCaptureSurfacePoolSize; i++) {
        sSCCaptureSurfaces[i] = SCCreateBGRAIOSurface(width, height);
        if (!sSCCaptureSurfaces[i]) {
            SCReleaseCaptureSurfacesLocked();
            return NO;
        }
    }
    sSCCaptureWidth = width;
    sSCCaptureHeight = height;
    return YES;
}

static BOOL SCEnsureSurfaceAcceleratorLocked(void)
{
    if (sSCSurfaceAccelerator) return YES;
    SCResolveSurfaceAcceleratorSymbols();
    if (!sSCAcceleratorCreate || !sSCAcceleratorTransfer) {
        sSCLastTransferResult = KERN_FAILURE;
        return NO;
    }
    IOSurfaceAcceleratorRef accelerator = NULL;
    kern_return_t result = sSCAcceleratorCreate(kCFAllocatorDefault, NULL, &accelerator);
    if (result != KERN_SUCCESS || !accelerator) {
        sSCLastTransferResult = result;
        return NO;
    }
    sSCSurfaceAccelerator = accelerator;
    return YES;
}

static BOOL SCCopySurfaceWithCoreGraphics(IOSurfaceRef source, CVPixelBufferRef target)
{
    CGImageRef image = UICreateCGImageFromIOSurface(source);
    if (!image) return NO;

    BOOL succeeded = NO;
    if (CVPixelBufferLockBaseAddress(target, 0) == kCVReturnSuccess) {
        void *baseAddress = CVPixelBufferGetBaseAddress(target);
        size_t width = CVPixelBufferGetWidth(target);
        size_t height = CVPixelBufferGetHeight(target);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(target);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = colorSpace && baseAddress
            ? CGBitmapContextCreate(baseAddress,
                                    width,
                                    height,
                                    8,
                                    bytesPerRow,
                                    colorSpace,
                                    kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst)
            : NULL;
        if (context) {
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
            CGContextRelease(context);
            succeeded = YES;
        }
        if (colorSpace) CGColorSpaceRelease(colorSpace);
        CVPixelBufferUnlockBaseAddress(target, 0);
    }
    CGImageRelease(image);
    return succeeded;
}

BOOL SCCaptureScreenIntoPixelBuffer(CVPixelBufferRef target)
{
    if (!target || CVPixelBufferGetPixelFormatType(target) != kCVPixelFormatType_32BGRA) return NO;

    uint64_t totalStartedUs = SCMonotonicMicroseconds();
    os_unfair_lock_lock(&sSCCaptureLock);

    int sourceWidth = 0;
    int sourceHeight = 0;
    if (!SCDisplayPixelSize(&sourceWidth, &sourceHeight) ||
        !SCEnsureCaptureSurfacesLocked(sourceWidth, sourceHeight)) {
        sSCFailureCount++;
        sSCLastResult = @"source_surface_unavailable";
        sSCActiveBackend = @"failed";
        sSCLastTotalUs = SCMonotonicMicroseconds() - totalStartedUs;
        os_unfair_lock_unlock(&sSCCaptureLock);
        return NO;
    }

    IOSurfaceRef source = sSCCaptureSurfaces[sSCCaptureSurfaceIndex];
    sSCCaptureSurfaceIndex = (sSCCaptureSurfaceIndex + 1) % kSCCaptureSurfacePoolSize;

    uint64_t captureStartedUs = SCMonotonicMicroseconds();
    IOSurfaceLock(source, 0, NULL);
    CARenderServerRenderDisplay(0, CFSTR("LCD"), source, 0, 0);
    sSCLastCaptureUs = SCMonotonicMicroseconds() - captureStartedUs;

    BOOL succeeded = NO;
    IOSurfaceRef destination = CVPixelBufferGetIOSurface(target);
    if (destination && SCEnsureSurfaceAcceleratorLocked()) {
        uint64_t scaleStartedUs = SCMonotonicMicroseconds();
        IOSurfaceLock(destination, 0, NULL);
        kern_return_t transfer = sSCAcceleratorTransfer(
            sSCSurfaceAccelerator, source, destination, NULL, NULL);
        IOSurfaceUnlock(destination, 0, NULL);
        sSCLastScaleUs = SCMonotonicMicroseconds() - scaleStartedUs;
        sSCLastTransferResult = transfer;
        if (transfer == KERN_SUCCESS) {
            succeeded = YES;
            sSCAcceleratedCount++;
            sSCActiveBackend = @"iosurface_accelerator";
            sSCLastResult = @"accelerated";
        }
    }

    if (!succeeded) {
        uint64_t fallbackStartedUs = SCMonotonicMicroseconds();
        succeeded = SCCopySurfaceWithCoreGraphics(source, target);
        sSCLastScaleUs = SCMonotonicMicroseconds() - fallbackStartedUs;
        if (succeeded) {
            sSCFallbackCount++;
            sSCActiveBackend = @"coregraphics_fallback";
            sSCLastResult = @"fallback";
        }
    }

    IOSurfaceUnlock(source, 0, NULL);
    sSCCaptureCount++;
    if (!succeeded) {
        sSCFailureCount++;
        sSCActiveBackend = @"failed";
        sSCLastResult = @"capture_copy_failed";
    }
    sSCLastTotalUs = SCMonotonicMicroseconds() - totalStartedUs;
    os_unfair_lock_unlock(&sSCCaptureLock);
    return succeeded;
}

NSDictionary *SCCapturePipelineStatus(void)
{
    os_unfair_lock_lock(&sSCCaptureLock);
    NSDictionary *status = @{
        @"schema": @"capture_pipeline_v2",
        @"preferred_backend": @"iosurface_accelerator",
        @"active_backend": sSCActiveBackend ?: @"unknown",
        @"fallback_backend": @"coregraphics",
        @"source_pool_size": @(kSCCaptureSurfacePoolSize),
        @"source_width": @(sSCCaptureWidth),
        @"source_height": @(sSCCaptureHeight),
        @"capture_count": @(sSCCaptureCount),
        @"accelerated_count": @(sSCAcceleratedCount),
        @"fallback_count": @(sSCFallbackCount),
        @"failure_count": @(sSCFailureCount),
        @"last_capture_us": @(sSCLastCaptureUs),
        @"last_scale_us": @(sSCLastScaleUs),
        @"last_total_us": @(sSCLastTotalUs),
        @"last_transfer_result": @(sSCLastTransferResult),
        @"accelerator_symbols_available": @(sSCAcceleratorCreate != NULL && sSCAcceleratorTransfer != NULL),
        @"last_result": sSCLastResult ?: @"unknown",
    };
    os_unfair_lock_unlock(&sSCCaptureLock);
    return status;
}

void SCResetCapturePipeline(void)
{
    os_unfair_lock_lock(&sSCCaptureLock);
    SCReleaseCaptureSurfacesLocked();
    if (sSCSurfaceAccelerator) {
        CFRelease((CFTypeRef)sSCSurfaceAccelerator);
        sSCSurfaceAccelerator = NULL;
    }
    sSCActiveBackend = @"reset";
    sSCLastResult = @"reset";
    os_unfair_lock_unlock(&sSCCaptureLock);
}

CGImageRef SCCreateScreenShotCGImage(void)
{
    @autoreleasepool {
        int width = 0;
        int height = 0;
        if (!SCDisplayPixelSize(&width, &height)) return NULL;

        errno = 0;
        IOSurfaceRef surface = SCCreateBGRAIOSurface(width, height);
        if (!surface) return NULL;

        CGImageRef image = NULL;
        IOSurfaceLock(surface, 0, NULL);
        CARenderServerRenderDisplay(0, CFSTR("LCD"), surface, 0, 0);
        image = UICreateCGImageFromIOSurface(surface);
        IOSurfaceUnlock(surface, 0, NULL);
        CFRelease(surface);
        return image; // retained by UICreateCGImageFromIOSurface
    }
}
