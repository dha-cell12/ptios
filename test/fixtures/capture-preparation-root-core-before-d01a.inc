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
