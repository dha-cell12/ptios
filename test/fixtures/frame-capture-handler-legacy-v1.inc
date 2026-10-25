// Frozen pre-C02b18 handler at 62a9c90; helper/function names isolated.
static void legacyApplyFrameCaptureOwner(ZXFrameObject &frame, NSArray *data, NSUInteger startIndex)
{
    frame.ownerSessionId = zx_stringFromPart(data, startIndex, "");
    frame.ownerRunId = zx_stringFromPart(data, startIndex + 1, "");
    frame.ownerRuntime = zx_stringFromPart(data, startIndex + 2, "legacy");
}

NSString* legacyFrameCaptureTaskFromRawData(UInt8 *eventData, NSError **error)
{
    TLinkImageWork work(gImageCompute);
    if (!work) { if (error) *error = zx_frameError(@"1;;image_compute_busy\r\n"); return nil; }

    NSArray<NSString *> *data = zx_splitEventData(eventData);
    bool needGray = true;
    bool needBGRA = true;
    uint64_t ttlMs = kDefaultFrameTtlMs;
    if ([data count] >= 1 && [data[0] length] > 0) needGray = [data[0] intValue] != 0;
    if ([data count] >= 2 && [data[1] length] > 0) needBGRA = [data[1] intValue] != 0;
    if ([data count] >= 3 && [data[2] length] > 0) ttlMs = (uint64_t)MAX(0, [data[2] longLongValue]);
    if (!needGray && !needBGRA) {
        needGray = true;
        needBGRA = true;
    }
    if (ttlMs == 0) ttlMs = kDefaultFrameTtlMs;
    if (ttlMs > kHardFrameTtlMs) ttlMs = kHardFrameTtlMs;

    CFAbsoluteTime total0 = TLinkImageNowSeconds();
    CFAbsoluteTime capture0 = TLinkImageNowSeconds();
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    double captureMs = (TLinkImageNowSeconds() - capture0) * 1000.0;
    if (!screen) {
        if (error) *error = zx_frameError(@"1;;capture_failed\r\n");
        return nil;
    }

    size_t pixels = 0;
    if (!TLinkImagePixels(CGImageGetWidth(screen), CGImageGetHeight(screen), kMaxImagePixels, &pixels)) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;frame_pixel_limit\r\n");
        return nil;
    }
    auto charge = zx_reservePayload(TLinkImageKind::Frame, pixels * ((needBGRA ? 4 : 0) + (needGray ? 1 : 0)));
    if (!charge) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;frame_memory_budget\r\n");
        return nil;
    }
    auto pendingFrame = std::make_shared<ZXFrameObject>();
    pendingFrame->charge = std::move(charge);
    ZXFrameObject &frame = *pendingFrame;
    frame.width = (int)CGImageGetWidth(screen);
    frame.height = (int)CGImageGetHeight(screen);
    frame.bytesPerRow = frame.width * 4;
    frame.scale = [Screen getScale];
    frame.createdAtMs = zx_nowMs();
    frame.expiresAtMs = TLinkImageExpiry(frame.createdAtMs, ttlMs);
    frame.capturedAtMs = (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000.0);
    frame.ttlMs = ttlMs;
    legacyApplyFrameCaptureOwner(frame, data, 3);
    frame.hasBGRA = false;
    frame.hasGray = false;

    std::vector<uint8_t> tmpBGRA;
    int w = 0, h = 0, bpr = 0;
    CFAbsoluteTime bgra0 = TLinkImageNowSeconds();
    if (!zx_renderBGRAFromCGImage(screen, needBGRA ? frame.bgra : tmpBGRA, &w, &h, &bpr)) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;bgra_render_failed\r\n");
        return nil;
    }
    double bgraMs = (TLinkImageNowSeconds() - bgra0) * 1000.0;
    CGImageRelease(screen);
    frame.width = w;
    frame.height = h;
    frame.bytesPerRow = bpr;
    frame.hasBGRA = needBGRA;

    CFAbsoluteTime gray0 = TLinkImageNowSeconds();
    if (needGray) {
        std::vector<uint8_t> &source = needBGRA ? frame.bgra : tmpBGRA;
        cv::Mat bgraMat(frame.height, frame.width, CV_8UC4, source.data(), frame.bytesPerRow);
        cv::cvtColor(bgraMat, frame.gray, COLOR_BGRA2GRAY);
        frame.hasGray = !frame.gray.empty();
    }
    double grayMs = (TLinkImageNowSeconds() - gray0) * 1000.0;
    if (needGray && !frame.hasGray) {
        if (error) *error = zx_frameError(@"1;;gray_convert_failed\r\n");
        return nil;
    }

    __block uint32_t frameId = 0;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        frameId = zx_storeFrameLocked(pendingFrame);
    });
    if (!frameId) {
        if (error) *error = zx_frameError(@"1;;frame_publish_failed\r\n");
        return nil;
    }
    double totalMs = (TLinkImageNowSeconds() - total0) * 1000.0;
    return [NSString stringWithFormat:@"%u;;%d;;%d;;%d;;%.3f;;pixel;;BGRA;;%d;;%d;;%llu;;%.3f;;%.3f;;%.3f;;%.3f",
            frameId, frame.width, frame.height, frame.bytesPerRow, frame.scale,
            frame.hasBGRA ? 1 : 0, frame.hasGray ? 1 : 0,
            (unsigned long long)frame.capturedAtMs,
            captureMs, bgraMs, grayMs, totalMs];
}

