static NSData *TLinkUITreeJSONResponse(NSDictionary *result)
{
    if (![result isKindOfClass:[NSDictionary class]]) return TLinkError(@"ui_result_invalid");
    if (!TLinkAXResultSucceeded(result)) {
        NSString *code = [result[@"error"] isKindOfClass:[NSString class]]
            ? result[@"error"] : @"ui_operation_failed";
        return TLinkError(code);
    }
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:&error];
    if (json.length == 0) return TLinkError(@"ui_result_json_failed");
    size_t wireBytes = 0;
    if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {
        return TLinkError(@"ui_response_too_large");
    }
    return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @"");
}

