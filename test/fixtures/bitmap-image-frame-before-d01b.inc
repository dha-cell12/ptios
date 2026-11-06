static bool zx_captureFrame(const TLinkNativeFrameCaptureRequest &request,uint32_t &publishedId,TLinkNativeFrameCaptureValue &value,NSError **error){
    const bool needGray=request.gray||!request.bgra,needBGRA=request.bgra||!request.gray;
    static_assert(kDefaultFrameTtlMs==1000&&kHardFrameTtlMs==5000,"capture TTL compatibility changed");
    const uint64_t ttlMs=TLinkNativeFrameCaptureTTL(request.ttlMs);
    CFAbsoluteTime total0 = TLinkImageNowSeconds();
    CFAbsoluteTime capture0 = TLinkImageNowSeconds();
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    double captureMs = (TLinkImageNowSeconds() - capture0) * 1000.0;
    if (!screen) {
        if (error) *error = zx_frameError(@"1;;capture_failed\r\n");
        return false;
    }

    size_t pixels = 0;
    if (!TLinkImagePixels(CGImageGetWidth(screen), CGImageGetHeight(screen), kMaxImagePixels, &pixels)) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;frame_pixel_limit\r\n");
        return false;
    }
    auto charge = zx_reservePayload(TLinkImageKind::Frame, pixels * ((needBGRA ? 4 : 0) + (needGray ? 1 : 0)));
    if (!charge) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;frame_memory_budget\r\n");
        return false;
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
    zx_applyFrameOwner(frame, request);
    frame.hasBGRA = false;
    frame.hasGray = false;

    std::vector<uint8_t> tmpBGRA;
    int w = 0, h = 0, bpr = 0;
    CFAbsoluteTime bgra0 = TLinkImageNowSeconds();
    if (!zx_renderBGRAFromCGImage(screen, needBGRA ? frame.bgra : tmpBGRA, &w, &h, &bpr)) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;bgra_render_failed\r\n");
        return false;
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
        return false;
    }

    __block uint32_t frameId = 0;
    TLinkNativeDispatchSync(zx_imageQueue(), ^{
        frameId = zx_storeFrameLocked(pendingFrame);
    });
    publishedId=frameId;
    if (!frameId) {
        if (error) *error = zx_frameError(@"1;;frame_publish_failed\r\n");
        return false;
    }
    double totalMs = (TLinkImageNowSeconds() - total0) * 1000.0;
    value.id=frameId;value.width=frame.width;value.height=frame.height;value.bytesPerRow=frame.bytesPerRow;
    value.scale=frame.scale;value.hasBGRA=frame.hasBGRA;value.hasGray=frame.hasGray;value.capturedAtMs=frame.capturedAtMs;
    value.captureMs=captureMs;value.bgraMs=bgraMs;value.grayMs=grayMs;value.totalMs=totalMs;
    return true;
}

