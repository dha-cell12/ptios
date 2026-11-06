static void zx_uiTreeNotifyResult(NSDictionary *result, CFWriteStreamRef stream)
{
    if (!TLinkAXResultSucceeded(result)) {
        NSString *code = [result[@"error"] isKindOfClass:[NSString class]]
            ? result[@"error"] : @"ui_operation_failed";
        notifyClient((UInt8 *)[[NSString stringWithFormat:@"-1;;%@\r\n", code] UTF8String], stream);
        return;
    }
    const auto wireBudget = TLinkCurrentNativeBudget();
    BOOL jsonTooLarge = false, jsonStopped = false;
    NSData *json = TLinkAXBoundedJSONDataWithStop(result, &jsonTooLarge, &jsonStopped);
    if (jsonStopped) {
        notifyClient((UInt8 *)"-1;;ui_cancelled_or_timed_out\r\n", stream);
        return;
    }
    if (jsonTooLarge) {
        notifyClient((UInt8 *)"-1;;ui_response_too_large\r\n", stream);
        return;
    }
    if (json.length == 0) {
        notifyClient((UInt8 *)"-1;;ui_result_json_failed\r\n", stream);
        return;
    }
    size_t wireBytes = 0;
    if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {
        notifyClient((UInt8 *)"-1;;ui_response_too_large\r\n", stream);
        return;
    }
    NSString *base64 = nil;
    @autoreleasepool {
        base64 = [json base64EncodedStringWithOptions:0] ?: @"";
    }
    auto admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);
    if (admission != TLinkAXWireBudget::Admission::Ready) {
        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);
        return;
    }
    __attribute__((objc_precise_lifetime)) NSString *response = nil;
    @autoreleasepool {
        response = [NSString stringWithFormat:@"0;;%@\r\n", base64];
    }
    const char *responseBytes = response.UTF8String;
    admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);
    if (admission != TLinkAXWireBudget::Admission::Ready) {
        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);
        return;
    }
    notifyClient((UInt8 *)responseBytes, stream);
}

