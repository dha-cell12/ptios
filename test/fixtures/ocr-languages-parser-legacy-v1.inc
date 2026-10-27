// Frozen 86c0974 OCR languages compatibility oracle.
NSString *handleTesseractOCRTaskFromRawData(UInt8 *eventData, NSError **error)
{

#if ENABLE_TESSERACT_OCR
    const uint64_t enteredAt = TLinkNativeNowNs();
#endif
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData] ?: @"";
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([[raw lowercaseString] isEqualToString:@"check_langs"]) {
        return zx_tessCheckLangs();
    }

#if !ENABLE_TESSERACT_OCR
    if (error) *error = zx_tessError(@"disabled", @"Tesseract OCR is not enabled in this build.");
    return nil;
#else
    TLinkOCRAdmission admission(sZXTessActive);
    if (!admission) { sZXTessBusy.fetch_add(1); if (error) *error = zx_tessError(@"ocr_busy", @"Only two OCR requests may be active or queued."); return nil; }
    auto requestBudget = std::make_shared<TLinkOCRRequestBudget>(TLinkCurrentNativeBudget(), enteredAt);
    NSArray<NSString *> *data = zx_tessSplitEventData(eventData);
    if ([data count] < 13) {
        if (error) *error = zx_tessError(@"bad_format", @"Format: frame_id;;x;;y;;w;;h;;lang;;oem;;psm;;whitelist_b64;;scale_up;;threshold_mode;;coord;;max_age_ms");
        return nil;
    }

    uint32_t frameId = (uint32_t)[data[0] intValue];
    int x = [data[1] intValue];
    int y = [data[2] intValue];
    int w = [data[3] intValue];
    int h = [data[4] intValue];
    NSString *lang = ([data[5] length] > 0) ? data[5] : @"vie";
    int oem = ([data[6] length] > 0) ? [data[6] intValue] : 1;
    int psm = ([data[7] length] > 0) ? [data[7] intValue] : 7;
    NSString *whitelist = zx_tessDecodeBase64(data[8]);
    int scaleUp = ([data[9] length] > 0) ? [data[9] intValue] : 2;
    int thresholdMode = ([data[10] length] > 0) ? [data[10] intValue] : 0;
    NSString *coord = ([data[11] length] > 0) ? data[11] : @"pixel";
    uint64_t maxAgeMs = (uint64_t)MAX(0, [data[12] longLongValue]);
    if (maxAgeMs == 0) maxAgeMs = 1000;

    TLinkNativeFrameOCRRequest request;request.frameId=frameId;request.x=x;request.y=y;request.width=w;request.height=h;
    request.lang=lang;request.oem=oem;request.psm=psm;request.whitelist=whitelist;request.scaleUp=scaleUp;request.thresholdMode=thresholdMode;request.coord=coord;request.maxAgeMs=maxAgeMs;
    TLinkNativeFrameOCRValue value;
    return zx_tessRecognizeFrame(request,value,error,requestBudget)?value.body:nil;
#endif
}

