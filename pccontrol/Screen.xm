#include "../shared/TLinkCaptureLeasePOSIX.h"
#include "../shared/TLinkImageStorage.h"
#include "Screen.h"
#include "Common.h"
#include <limits.h>
#include <stdint.h>
#include <math.h>

#include "headers/IOSurface/IOSurfaceAccelerator.h"
#include "headers/IOSurface/IOMobileFramebuffer.h"
#import "headers/IOSurface/IOSurface.h"
#include "headers/IOSurface/CoreSurface.h"
#import <Photos/Photos.h>

// BEGIN owned screenshot write adapter.
static bool zx_ownedCaptureContinue(NSError **error)
{
    auto owner=TLinkCaptureReceiverSlot();
    if(owner&&owner->valid())return true;
    if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey:@"-1;;owned_capture_lease_missing_or_expired\r\n"}];
    return false;
}
static bool zx_writeOwnedCapture(NSString *path,NSData *encoded,NSError **error)
{
    auto owner=TLinkCaptureReceiverSlot();
    if(owner&&owner->matches(path.UTF8String)&&owner->write(encoded.bytes,encoded.length))return true;
    if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey:@"-1;;owned_capture_cancelled_or_write_failed\r\n"}];
    return false;
}
// END owned screenshot write adapter.

OBJC_EXTERN void CARenderServerRenderDisplay(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);
OBJC_EXTERN kern_return_t IOSurfaceLock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t *seed);
OBJC_EXTERN IOSurfaceRef IOSurfaceCreate(CFDictionaryRef dictionary);
OBJC_EXTERN CGImageRef UICreateCGImageFromIOSurface(IOSurfaceRef surface);

static CGFloat device_screen_width = 0;
static CGFloat device_screen_height = 0;
static NSString *const kTLinkautoAlbumName = @"TLinkauto";

// Screen Keep state
static BOOL gKeepEnabled = NO;
static CGImageRef gKeepImage = NULL;
static NSString *const kTLinkautoKeepPngPath = @"/tmp/TLinkauto_keep.png";

static CGImageRef zx_captureScreenCGImageRef(void);

// BEGIN capture ownership core (also compiled by the native fault-injection harness).
struct TLinkCaptureGeometry {
    size_t width;
    size_t height;
    size_t bytesPerRow;
    size_t allocationSize;
};

static size_t zx_captureAlignedRowBytes(size_t width)
{
    if (width == 0 || width > (SIZE_MAX - 31) / 4) return 0;
    return (width * 4 + 31) & ~(size_t)31;
}

static bool zx_captureGeometry(CGFloat boundsWidth, CGFloat boundsHeight, CGFloat scale,
                               bool rotateIPad, TLinkCaptureGeometry *out)
{
    if (!out) return false;
    *out = {};
    if (!isfinite(boundsWidth) || !isfinite(boundsHeight) || !isfinite(scale) ||
        boundsWidth <= 0 || boundsHeight <= 0 || scale <= 0) return false;
    const CGFloat pixelWidth = boundsWidth * scale;
    const CGFloat pixelHeight = boundsHeight * scale;
    if (!isfinite(pixelWidth) || !isfinite(pixelHeight) || pixelWidth < 1 || pixelHeight < 1 ||
        pixelWidth > INT_MAX || pixelHeight > INT_MAX) return false;
    size_t width = (size_t)pixelWidth;
    size_t height = (size_t)pixelHeight;
    if ((rotateIPad && width < height) || (!rotateIPad && width > height)) {
        size_t temporary = width;
        width = height;
        height = temporary;
    }
    const size_t bytesPerRow = zx_captureAlignedRowBytes(width);
    if (bytesPerRow == 0 || height > SIZE_MAX / bytesPerRow) return false;
    *out = {width, height, bytesPerRow, bytesPerRow * height};
    return true;
}

// Borrow source and its color space for the whole context lifetime; return an owned image.
static CGImageRef zx_captureRotatedImage(CGImageRef source)
{
    if (!source) return NULL;
    const size_t width = CGImageGetWidth(source);
    const size_t height = CGImageGetHeight(source);
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(source); // Get-rule reference, never release here.
    const size_t bytesPerRow = zx_captureAlignedRowBytes(height); // Rotated output width is source height.
    if (width == 0 || height == 0 || !colorSpace || CGImageGetBitsPerComponent(source) != 8 ||
        bytesPerRow == 0 || width > SIZE_MAX / bytesPerRow) return NULL;
    CGContextRef bitmap = CGBitmapContextCreate(NULL, height, width, 8, bytesPerRow,
                                                colorSpace, kCGImageAlphaPremultipliedFirst);
    if (!bitmap) return NULL;
    const CGFloat radians = -90.0 * (M_PI / 180.0);
    CGContextTranslateCTM(bitmap, 0.5 * height, 0.5 * width);
    CGContextRotateCTM(bitmap, radians);
    CGContextTranslateCTM(bitmap, -0.5 * width, -0.5 * height);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), source);
    CGImageRef rotated = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    return rotated;
}

static CGImageRef zx_captureSurfaceImage(CFDictionaryRef properties, bool rotateIPad)
{
    IOSurfaceRef surface = IOSurfaceCreate(properties);
    if (!surface) return NULL;
    if (IOSurfaceLock(surface, 0, NULL) != KERN_SUCCESS) {
        CFRelease(surface);
        return NULL;
    }
    CARenderServerRenderDisplay(0, CFSTR("LCD"), surface, 0, 0);
    CGImageRef image = UICreateCGImageFromIOSurface(surface);
    if (image && (CGImageGetWidth(image) == 0 || CGImageGetHeight(image) == 0)) {
        CGImageRelease(image);
        image = NULL;
    }
    if (image && rotateIPad) {
        CGImageRef rotated = zx_captureRotatedImage(image);
        CGImageRelease(image);
        image = rotated;
    }
    // Unlock only successfully locked surfaces, and balance every owned reference on failure.
    if (IOSurfaceUnlock(surface, 0, NULL) != KERN_SUCCESS && image) {
        CGImageRelease(image);
        image = NULL;
    }
    CFRelease(surface);
    return image;
}
// END capture ownership core.

@implementation Screen
{
    // device screen size
}


/*
Get the size of the screen and set them.
*/
+ (void)setScreenSize:(CGFloat)x height:(CGFloat) y
{
	device_screen_width = x;
	device_screen_height = y;

	if (device_screen_width == 0 || device_screen_height == 0 || device_screen_width > 10000 || device_screen_height > 10000)
	{
		NSLog(@"com.tlinkauto.springboard: Unable to initialze the screen size. screen width: %f, screen height: %f", device_screen_width, device_screen_height);
	}
	else
	{
		NSLog(@"com.tlinkauto.springboard: successfully initialize the screen size. screen width: %f, screen height: %f", device_screen_width, device_screen_height);
	}
}

+ (int)getScreenOrientation
{
    __block int screenOrientation = -1;

    dispatch_sync(dispatch_get_main_queue(), ^{
        @try{
            SpringBoard *springboard = (SpringBoard*)[%c(SpringBoard) sharedApplication];
            screenOrientation = [springboard _frontMostAppOrientation];
            //NSLog(@"com.tlinkauto.springboard: orientation %d", screenOrientation);
        }
        @catch (NSException *exception) {
            NSLog(@"com.tlinkauto.springboard: Debug: %@", exception.reason);
        }
    }   
    );

    return screenOrientation;
}

+ (CGFloat)getScreenWidth
{
    if (device_screen_width == 0)
    {
        NSLog(@"com.tlinkauto.springboard: Cannot get screen width. Maybe you call [Screen getScreenWidth] before springboard getting the screen size.");
    }
    return device_screen_width;
}

+ (CGFloat)getScreenHeight
{
    if (device_screen_height == 0)
    {
        NSLog(@"com.tlinkauto.springboard: Cannot get screen height. Maybe you call [Screen getScreenHeight] before springboard getting the screen size.");
    }
    return device_screen_height;
}

+ (CGFloat)getScale
{    
    return [[UIScreen mainScreen] scale];
}

+ (CGRect)getBounds
{
    return [UIScreen mainScreen].bounds;
}


OBJC_EXTERN UIImage *_UICreateScreenUIImage(void);
+ (NSString*)screenShot
{
    UIImage *screenImage = _UICreateScreenUIImage();
    // Create path.
    NSString *filePath = [getDocumentRoot() stringByAppendingPathComponent:@"screenshot.png"];

    // Save image.
    [UIImagePNGRepresentation(screenImage) writeToFile:filePath atomically:NO];
    return filePath;
}

+ (UIImage*)screenShotUIImage // memory leak, need to be fixed
{
    return _UICreateScreenUIImage();
}

+ (CGImageRef)createScreenShotCGImageRef
{
    @synchronized([Screen class]) {
        if (gKeepEnabled && gKeepImage) {
            return CGImageRetain(gKeepImage);
        }
    }

    return zx_captureScreenCGImageRef();
}

static CGImageRef zx_captureScreenCGImageRef(void)
{
    UIScreen *screen = [UIScreen mainScreen];
    CGSize screenSize = screen.bounds.size;
    NSString *device = getDeviceName();
    NSRange range = [device rangeOfString:@"^iPad[8-9]|iPad[1-9][0-9]+" options:NSRegularExpressionSearch];
    const bool rotateIPad = range.location != NSNotFound;
    TLinkCaptureGeometry geometry;
    if (!zx_captureGeometry(screenSize.width, screenSize.height, screen.scale, rotateIPad, &geometry)) return NULL;
    NSDictionary *properties = @{
        @"IOSurfaceAllocSize": @(geometry.allocationSize),
        @"IOSurfaceBytesPerElement": @4,
        @"IOSurfaceBytesPerRow": @(geometry.bytesPerRow),
        @"IOSurfaceHeight": @(geometry.height),
        @"IOSurfaceWidth": @(geometry.width),
        @"IOSurfaceIsGlobal": @YES,
        @"IOSurfacePixelFormat": @1111970369,
    };
    return zx_captureSurfaceImage((__bridge CFDictionaryRef)properties, rotateIPad);
}

+ (BOOL)keepScreen:(NSError**)error
{
    @synchronized([Screen class]) {
        gKeepEnabled = NO;
        if (gKeepImage) {
            CGImageRelease(gKeepImage);
            gKeepImage = NULL;
        }
        [[NSFileManager defaultManager] removeItemAtPath:kTLinkautoKeepPngPath error:nil];
    }

    CGImageRef img = zx_captureScreenCGImageRef();
    if (!img) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screenshot for keep state.\r\n"}];
        }
        return NO;
    }

    UIImage *ui = [UIImage imageWithCGImage:img];
    NSData *png = UIImagePNGRepresentation(ui);
    if (!png || ![png writeToFile:kTLinkautoKeepPngPath atomically:NO]) {
        CGImageRelease(img);
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to save keep screenshot cache.\r\n"}];
        }
        return NO;
    }

    @synchronized([Screen class]) {
        gKeepImage = img; // own 1 ref
        gKeepEnabled = YES;
    }
    return YES;
}

+ (void)unkeepScreen
{
    @synchronized([Screen class]) {
        gKeepEnabled = NO;
        if (gKeepImage) {
            CGImageRelease(gKeepImage);
            gKeepImage = NULL;
        }
        [[NSFileManager defaultManager] removeItemAtPath:kTLinkautoKeepPngPath error:nil];
    }
}

+ (BOOL)isKeeping
{
    @synchronized([Screen class]) {
        return gKeepEnabled && gKeepImage != NULL;
    }
}


+ (NSString*)screenShotAlwaysUp
{
     UIImage *screenImage = _UICreateScreenUIImage();
    int orientation = [self getScreenOrientation];

    UIImageOrientation after = UIImageOrientationUp;
    if (orientation == 4)
    {
        after = UIImageOrientationRight;
    }
    else if (orientation == 3)
    {
        after = UIImageOrientationLeft;
    }
    else if (orientation == 2)
    {
        after = UIImageOrientationDown;
    }

    UIImage *result = [UIImage imageWithCGImage:[screenImage CGImage]
              scale:[screenImage scale]
              orientation: after];

    // Create path.
    NSString *filePath = [getDocumentRoot() stringByAppendingPathComponent:@"screenshot.png"];

    // Save image.
    [UIImagePNGRepresentation(result) writeToFile:filePath atomically:NO];
    return filePath;
}

+ (NSString*)screenShotToPath:(NSString*)filePath region:(CGRect)region error:(NSError**)error
{
    // Fast path: if keeping and asking for full screenshot, reuse cached PNG.
    NSString *targetPath = filePath;
    if (!targetPath || [targetPath length] == 0)
    {
        targetPath = [getDocumentRoot() stringByAppendingPathComponent:@"screenshot.png"];
    }

    auto owned=TLinkCaptureReceiverSlot();
    if(owned&&(!owned->matches(targetPath.UTF8String)||!owned->valid())){
        if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;owned_capture_lease_missing_or_expired\r\n"}];return nil;
    }
    BOOL shouldReuseKeep = NO;
    @synchronized([Screen class]) {
        shouldReuseKeep = gKeepEnabled;
    }
    if (!owned && shouldReuseKeep && CGRectIsEmpty(region) && [[NSFileManager defaultManager] fileExistsAtPath:kTLinkautoKeepPngPath])
    {
        [[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
        NSError *copyErr = nil;
        if ([[NSFileManager defaultManager] copyItemAtPath:kTLinkautoKeepPngPath toPath:targetPath error:&copyErr])
        {
            return targetPath;
        }
        // Fall back to normal screenshot if copy fails.
        (void)copyErr;
    }

    CGImageRef screenshotRef = [Screen createScreenShotCGImageRef];
    if (!screenshotRef)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screenshot.\r\n"}];
        }
        return nil;
    }

    if(owned&&!zx_ownedCaptureContinue(error)){CGImageRelease(screenshotRef);return nil;}
    size_t ownedPixels=0;
    if(owned&&!TLinkImagePixels(CGImageGetWidth(screenshotRef),CGImageGetHeight(screenshotRef),8388608,&ownedPixels)){
        CGImageRelease(screenshotRef);
        if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;owned_capture_pixel_limit\r\n"}];return nil;
    }
    CGSize imageSize = CGSizeMake(CGImageGetWidth(screenshotRef), CGImageGetHeight(screenshotRef));
    CGRect bounds = CGRectMake(0, 0, imageSize.width, imageSize.height);
    CGRect targetRegion = CGRectIsEmpty(region) ? bounds : CGRectIntersection(bounds, region);

    if (CGRectIsEmpty(targetRegion))
    {
        CGImageRelease(screenshotRef);
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid screenshot region.\r\n"}];
        }
        return nil;
    }

    BOOL isFullFrame = CGRectEqualToRect(targetRegion, bounds);
    CGImageRef outputRef = isFullFrame ? screenshotRef : CGImageCreateWithImageInRect(screenshotRef, targetRegion);
    if (!isFullFrame) {
        CGImageRelease(screenshotRef);
    }
    if (!outputRef)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to crop screenshot.\r\n"}];
        }
        return nil;
    }

    UIImage *image=nil;
    @try {image=[UIImage imageWithCGImage:outputRef];}
    @finally {CGImageRelease(outputRef);}

    if(owned&&!zx_ownedCaptureContinue(error))return nil;
    NSString *ext = [[targetPath pathExtension] lowercaseString];
    NSData *encoded = ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
        ? UIImageJPEGRepresentation(image, 0.75)
        : UIImagePNGRepresentation(image);

    if(owned)return zx_writeOwnedCapture(targetPath,encoded,error)?targetPath:nil;

    NSString *parentDir = [targetPath stringByDeletingLastPathComponent];
    if ([parentDir length] > 0 && ![[NSFileManager defaultManager] fileExistsAtPath:parentDir])
    {
        NSError *mkdirErr = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:parentDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&mkdirErr])
        {
            if (error)
            {
                NSString *message = [NSString stringWithFormat:@"-1;;Failed to create screenshot directory: %@ (%@)\r\n",
                                     parentDir,
                                     [mkdirErr localizedDescription] ?: @"unknown error"];
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                             code:999
                                         userInfo:@{NSLocalizedDescriptionKey:message}];
            }
            return nil;
        }
    }

    if (!encoded || ![encoded writeToFile:targetPath atomically:NO])
    {
        if (error)
        {
            NSString *message = [NSString stringWithFormat:@"-1;;Failed to save screenshot: %@\r\n", targetPath];
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:message}];
        }
        return nil;
    }

    return targetPath;
}

+ (PHAssetCollection*)fetchTLinkautoAlbum
{
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"title = %@", kTLinkautoAlbumName];
    PHFetchResult<PHAssetCollection*> *result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                                                         subtype:PHAssetCollectionSubtypeAlbumRegular
                                                                                         options:fetchOptions];
    return result.firstObject;
}

+ (PHAssetCollection*)ensureTLinkautoAlbumWithError:(NSError**)error
{
    if (!NSClassFromString(@"PHPhotoLibrary"))
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Photos framework is unavailable.\r\n"}];
        }
        return nil;
    }

    PHAssetCollection *album = [self fetchTLinkautoAlbum];
    if (album)
    {
        return album;
    }

    NSError *creationError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:kTLinkautoAlbumName];
    } error:&creationError];

    if (creationError)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to create album: %@\r\n", creationError.localizedDescription]}];
        }
        return nil;
    }

    album = [self fetchTLinkautoAlbum];
    if (!album && error)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to fetch created album.\r\n"}];
    }
    return album;
}

+ (void)saveToSystemAlbum:(NSString*)filePath error:(NSError**)error
{
    UIImage *image = [UIImage imageWithContentsOfFile:filePath];
    if (!image)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image not found at path.\r\n"}];
        }
        return;
    }

    PHAssetCollection *album = [self ensureTLinkautoAlbumWithError:error];
    if (!album)
    {
        return;
    }

    NSError *saveError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
        [albumRequest addAssets:@[[assetRequest placeholderForCreatedAsset]]];
    } error:&saveError];

    if (saveError && error)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to save to album: %@\r\n", saveError.localizedDescription]}];
    }
}

+ (void)clearSystemAlbum:(NSError**)error
{
    PHAssetCollection *album = [self fetchTLinkautoAlbum];
    if (!album)
    {
        return;
    }

    PHFetchResult<PHAsset*> *assets = [PHAsset fetchAssetsInAssetCollection:album options:nil];
    if (assets.count == 0)
    {
        return;
    }

    NSError *deleteError = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        [PHAssetChangeRequest deleteAssets:assets];
    } error:&deleteError];

    if (deleteError && error)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to clear album: %@\r\n", deleteError.localizedDescription]}];
    }
}
@end

NSString* handleScreenshotTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithUTF8String:(char*)eventData] componentsSeparatedByString:@";;"];
    if ([data count] < 1)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Screenshot task missing action.\r\n"}];
        }
        return nil;
    }

    int action = [data[0] intValue];
    if (action == SCREENSHOT_TASK_CAPTURE || action == kTLinkOwnedCaptureAction)
    {
        if ([data count] < 2)
        {
            if (error)
            {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                             code:999
                                         userInfo:@{NSLocalizedDescriptionKey:@"-1;;Screenshot task missing output path.\r\n"}];
            }
            return nil;
        }

        NSString *filePath = data[1];
        if(action==kTLinkOwnedCaptureAction){
            auto owner=TLinkCaptureReceiverSlot();
            if([data count]!=2||!owner||!owner->matches(filePath.UTF8String)||!owner->valid()){
                if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;owned_capture_requires_ipc_lease\r\n"}];return nil;
            }
        }
        CGRect region = CGRectZero;
        if ([data count] >= 6)
        {
            CGFloat x = [data[2] floatValue];
            CGFloat y = [data[3] floatValue];
            CGFloat width = [data[4] floatValue];
            CGFloat height = [data[5] floatValue];
            region = CGRectMake(x, y, width, height);
        }

        return [Screen screenShotToPath:filePath region:region error:error];
    }
    else if (action == SCREENSHOT_TASK_SAVE_TO_ALBUM)
    {
        if ([data count] < 2)
        {
            if (error)
            {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                             code:999
                                         userInfo:@{NSLocalizedDescriptionKey:@"-1;;Save to album missing file path.\r\n"}];
            }
            return nil;
        }

        [Screen saveToSystemAlbum:data[1] error:error];
        return nil;
    }
    else if (action == SCREENSHOT_TASK_CLEAR_ALBUM)
    {
        [Screen clearSystemAlbum:error];
        return nil;
    }

    if (error)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unknown screenshot action.\r\n"}];
    }
    return nil;
}

void handleScreenKeepTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    int action = [raw intValue];
    if (action == 1) {
        [Screen keepScreen:error];
    } else {
        [Screen unkeepScreen];
    }
}
