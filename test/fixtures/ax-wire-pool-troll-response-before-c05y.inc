static NSData *TLinkUITreeJSONResponse(NSDictionary *result)
{
    if (![result isKindOfClass:[NSDictionary class]]) return TLinkError(@"ui_result_invalid");
    if (!TLinkAXResultSucceeded(result)) {
        NSString *code = [result[@"error"] isKindOfClass:[NSString class]]
            ? result[@"error"] : @"ui_operation_failed";
        return TLinkError(code);
    }
    const auto wireBudget = TLinkCurrentNativeBudget();
    BOOL jsonTooLarge = false, jsonStopped = false;
    NSData *json = TLinkAXBoundedJSONDataWithStop(result, &jsonTooLarge, &jsonStopped);
    if (jsonStopped) {
        return TLinkError(@"ui_cancelled_or_timed_out");
    }
    if (jsonTooLarge) {
        return TLinkError(@"ui_response_too_large");
    }
    if (json.length == 0) return TLinkError(@"ui_result_json_failed");
    size_t wireBytes = 0;
    if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {
        return TLinkError(@"ui_response_too_large");
    }
    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @"";
    auto admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);
    if (admission != TLinkAXWireBudget::Admission::Ready) {
        return TLinkError(admission == TLinkAXWireBudget::Admission::Stopped
            ? @"ui_cancelled_or_timed_out" : @"ui_response_too_large");
    }
    NSData *response = TLinkSuccess(base64);
    admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);
    if (admission != TLinkAXWireBudget::Admission::Ready) {
        return TLinkError(admission == TLinkAXWireBudget::Admission::Stopped
            ? @"ui_cancelled_or_timed_out" : @"ui_response_too_large");
    }
    return response;
}

