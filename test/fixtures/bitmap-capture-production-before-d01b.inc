+ (CaptureOutcome *)runProductionCapture {
    CaptureOutcome *outcome = [[CaptureOutcome alloc] init];
    outcome.result = CaptureResultFail;
    outcome.diagnostics = @"production_capture_failed";

    CGImageRef source = SCCreateScreenShotCGImage();
    if (!source) {
        outcome.diagnostics = @"production_capture_source_unavailable";
        return outcome;
    }

    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0 || width > 20000 || height > 20000 ||
        width > SIZE_MAX / 4 || height > SIZE_MAX / (width * 4)) {
        CGImageRelease(source);
        outcome.diagnostics = @"production_capture_bad_dimensions";
        return outcome;
    }

    size_t bytesPerRow = width * 4;
    size_t byteCount = bytesPerRow * height;
    uint8_t *pixels = (uint8_t *)calloc(1, byteCount);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = pixels && colorSpace
        ? CGBitmapContextCreate(pixels, width, height, 8, bytesPerRow, colorSpace,
                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big)
        : NULL;
    if (!context) {
        if (pixels) free(pixels);
        if (colorSpace) CGColorSpaceRelease(colorSpace);
        CGImageRelease(source);
        outcome.diagnostics = @"production_capture_bitmap_context_failed";
        return outcome;
    }

    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    CGContextRelease(context);
    CGImageRelease(source);

    NSData *ownedPixels = [NSData dataWithBytesNoCopy:pixels
                                               length:byteCount
                                         freeWhenDone:YES];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)ownedPixels);
    CGImageRef detached = provider
        ? CGImageCreate(width, height, 8, 32, bytesPerRow, colorSpace,
                        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
                        provider, NULL, false, kCGRenderingIntentDefault)
        : NULL;
    if (provider) CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    if (!detached) {
        outcome.diagnostics = @"production_capture_detached_image_failed";
        return outcome;
    }

    const int steps = 8;
    int nonBlack = 0;
    uint32_t firstColor = 0;
    BOOL haveFirst = NO;
    BOOL varied = NO;
    for (int gy = 1; gy < steps; gy++) {
        for (int gx = 1; gx < steps; gx++) {
            size_t x = (size_t)((double)gx / steps * width);
            size_t y = (size_t)((double)gy / steps * height);
            const uint8_t *pixel = pixels + y * bytesPerRow + x * 4;
            if (pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8) nonBlack++;
            uint32_t color = ((uint32_t)pixel[0] << 16) |
                             ((uint32_t)pixel[1] << 8) | pixel[2];
            if (!haveFirst) {
                firstColor = color;
                haveFirst = YES;
            } else if (color != firstColor) {
                varied = YES;
            }
        }
    }

    outcome.image = [UIImage imageWithCGImage:detached];
    outcome.rgbaData = ownedPixels;
    outcome.width = (int)width;
    outcome.height = (int)height;
    outcome.bytesPerRow = (int)bytesPerRow;
    outcome.result = nonBlack == 0 || !varied ? CaptureResultBlack : CaptureResultPass;
    outcome.diagnostics = outcome.result == CaptureResultPass
        ? @"production_capture_ready"
        : @"production_capture_uniform_or_black";
    CGImageRelease(detached);
    return outcome;
}

