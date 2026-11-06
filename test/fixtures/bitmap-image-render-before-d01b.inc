static bool zx_renderBGRAFromCGImage(CGImageRef img, std::vector<uint8_t> &out, int *outW, int *outH, int *outBpr)
{
    if (!img) return false;
    size_t pixels = 0;
    if (!TLinkImagePixels(CGImageGetWidth(img), CGImageGetHeight(img), kMaxImagePixels, &pixels)) return false;
    int width = (int)CGImageGetWidth(img);
    int height = (int)CGImageGetHeight(img);
    int bytesPerRow = width * 4;
    out.assign((size_t)bytesPerRow * (size_t)height, 0);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(out.data(),
                                             width,
                                             height,
                                             8,
                                             bytesPerRow,
                                             colorSpace,
                                             kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) {
        out.clear();
        return false;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), img);
    CGContextRelease(ctx);
    if (outW) *outW = width;
    if (outH) *outH = height;
    if (outBpr) *outBpr = bytesPerRow;
    return true;
}

