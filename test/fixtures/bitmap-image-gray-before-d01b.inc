static cv::Mat zx_cvMatGrayFromCGImage(CGImageRef img, NSError **error)
{
    if (!img) {
        return cv::Mat();
    }
    const size_t cols = CGImageGetWidth(img);
    const size_t rows = CGImageGetHeight(img);
    size_t pixels = 0;
    if (!TLinkImagePixels(cols, rows, kMaxImagePixels, &pixels)) {
        return cv::Mat();
    }

    cv::Mat rgba((int)rows, (int)cols, CV_8UC4);
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(img);
    BOOL createdColorSpace = false;
    if (!colorSpace) {
        colorSpace = CGColorSpaceCreateDeviceRGB();
        createdColorSpace = true;
    }
    CGContextRef ctx = CGBitmapContextCreate(rgba.data,
                                             cols,
                                             rows,
                                             8,
                                             rgba.step[0],
                                             colorSpace,
                                             kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
    if (createdColorSpace) {
        CGColorSpaceRelease(colorSpace);
    }
    if (!ctx) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to create bitmap context.\r\n"}];
        }
        return cv::Mat();
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, cols, rows), img);
    CGContextRelease(ctx);

    cv::Mat gray;
    cv::cvtColor(rgba, gray, COLOR_RGBA2GRAY);
    return gray;
}

