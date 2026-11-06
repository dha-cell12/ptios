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

