static BOOL SCCopyCGImageWithCoreGraphics(CGImageRef image, CVPixelBufferRef target)
{
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
    return succeeded;
}

