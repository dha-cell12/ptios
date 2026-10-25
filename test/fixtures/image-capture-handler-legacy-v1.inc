// Frozen 5ffc503 action-1 implementation; compare only the defined (non-overflowing) input domain.
static NSString *legacyImageCaptureTask(UInt8 *eventData,NSError **error){
    NSArray *data=[[NSString stringWithFormat:@"%s",(const char *)eventData] componentsSeparatedByString:@";;"];
    int action=[data[0] intValue];
    if (action == 1) {
        TLinkImageWork work(gImageCompute);
        if (!work) { if (error) *error = zx_frameError(@"-1;;image_compute_busy\r\n"); return nil; }
        if ([data count] < 5) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image capture format should be action;;x;;y;;w;;h\r\n"}];
            }
            return nil;
        }
        int x = [data[1] intValue];
        int y = [data[2] intValue];
        int w = [data[3] intValue];
        int h = [data[4] intValue];

        CGImageRef screen = [Screen createScreenShotCGImageRef];
        if (!screen) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screenshot.\r\n"}];
            }
            return nil;
        }
        int sw = (int)CGImageGetWidth(screen);
        int sh = (int)CGImageGetHeight(screen);
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x >= sw) x = sw - 1;
        if (y >= sh) y = sh - 1;
        if (w <= 0 || x + w > sw) w = sw - x;
        if (h <= 0 || y + h > sh) h = sh - y;

        CGRect cropRect = CGRectMake(x, y, w, h);
        CGImageRef cropped = CGImageCreateWithImageInRect(screen, cropRect);
        CGImageRelease(screen);
        if (!cropped) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to crop screenshot.\r\n"}];
            }
            return nil;
        }
        size_t pixels = 0;
        auto charge = TLinkImagePixels(CGImageGetWidth(cropped), CGImageGetHeight(cropped), kMaxImagePixels, &pixels)
            ? zx_reservePayload(TLinkImageKind::Image, pixels) : nullptr;
        if (!charge) {
            CGImageRelease(cropped);
            if (error) *error = zx_frameError(@"-1;;image_pixel_or_memory_limit\r\n");
            return nil;
        }
        NSError *convErr = nil;
        Mat gray = zx_cvMatGrayFromCGImage(cropped, &convErr);
        CGImageRelease(cropped);
        if (gray.empty()) {
            if (error) {
                *error = convErr ?: [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to convert screenshot to mat.\r\n"}];
            }
            return nil;
        }

        auto pendingImage = std::make_shared<ZXImageObject>();
        ZXImageObject &image = *pendingImage;
        image.charge = std::move(charge);
        image.gray = std::move(gray);
        image.w = image.gray.cols;
        image.h = image.gray.rows;
        image.createdAtMs = zx_nowMs();
        image.ttlMs = 0;
        zx_applyImageOwner(image, data, 5);
        __block uint32_t imageId = 0;
        TLinkNativeDispatchSync(zx_imageQueue(), ^{
            imageId = zx_storeImageLocked(pendingImage);
        });
        if (imageId == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image object limit reached. Release unused images.\r\n"}];
            }
            return nil;
        }
        return [NSString stringWithFormat:@"%u;;%d;;%d", imageId, image.w, image.h];
    }
    return nil;
}
