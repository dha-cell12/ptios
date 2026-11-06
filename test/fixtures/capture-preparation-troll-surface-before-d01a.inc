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
    SCResolveSurfaceAcceleratorSymbols();
    size_t minimumBytesPerRow = (size_t)width * 4;
    size_t alignedBytesPerRow = sSCIOSurfaceAlignProperty
        ? sSCIOSurfaceAlignProperty(CFSTR("IOSurfaceBytesPerRow"), minimumBytesPerRow)
        : (size_t)SCRoundUp((int)minimumBytesPerRow, 128);
    if (alignedBytesPerRow < minimumBytesPerRow) {
        alignedBytesPerRow = (size_t)SCRoundUp((int)minimumBytesPerRow, 128);
    }
    size_t allocSize = alignedBytesPerRow * (size_t)height;
    NSMutableDictionary *properties = [@{
        @"IOSurfaceAllocSize": @(allocSize),
        @"IOSurfaceBytesPerElement": @4,
        @"IOSurfaceBytesPerRow": @(alignedBytesPerRow),
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

