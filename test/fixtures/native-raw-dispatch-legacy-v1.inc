// Frozen from be14508; RAW response compatibility oracle.
// BEGIN bounded native dispatch (also exercised by the macOS integration harness).
- (NSDictionary *)executeRawPayload:(NSString *)payload context:(TLinkTaskExecutionContext *)context
{
    if (![payload isKindOfClass:[NSString class]] || payload.length < 2)
        return TLinkNativeFailure(@"invalid_payload");
    // NSString.length is UTF-16 units; byte length is checked independently before dispatch.
    if (payload.length > 8192) return TLinkNativeFailure(@"input_too_large");
    NSMutableData *payloadData = [[payload dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (!payloadData || payloadData.length > 32 * 1024 || memchr(payloadData.bytes, 0, payloadData.length))
        return TLinkNativeFailure(@"invalid_payload");
    const BOOL cleanup = [payload hasPrefix:@"67"] || [payload hasPrefix:@"483;;"] || [payload hasPrefix:@"300;;"];
    const BOOL frameCreate = [payload hasPrefix:@"66"];
    const BOOL imageCreate = [payload hasPrefix:@"481;;"] || [payload hasPrefix:@"482;;"];
    TLinkTaskExecutionContext *call = TLinkNativeCallContext(context, cleanup, YES);
    auto budget = [call nativeBudget];
    TLinkNativeBudgetScope scope(budget);
    if (budget->stopped()) return TLinkNativeFailure(TLinkNativeStopCode(budget->reason()));
    // Ensure an allocation's small ID response can always be retained for rollback on abort.
    if ((frameCreate || imageCreate) && budget->outputLimit() < 1024) return TLinkNativeFailure(@"response_too_large");
    UInt8 zero = 0;
    [payloadData appendBytes:&zero length:1];
    // Compatibility token for handlers that branch on non-NULL stream. All Task writers use
    // notifyClient; its scoped native sink owns the response and admits each bounded chunk.
    UInt8 compatibilityByte = 0;
    CFWriteStreamRef stream = CFWriteStreamCreateWithBuffer(kCFAllocatorDefault, &compatibilityByte, 1);
    if (!stream) return TLinkNativeFailure(@"stream_create_failed");
    @try {
        if (!CFWriteStreamOpen(stream)) return TLinkNativeFailure(@"stream_open_failed");
        processTaskWithContext((UInt8 *)payloadData.mutableBytes, [payloadData length] - 1, stream, call);
    } @catch (__unused NSException *exception) {
        return TLinkNativeFailure(@"native_exception");
    } @finally { CFWriteStreamClose(stream); CFRelease(stream); }
    const auto &written = budget->response();
    NSData *data = [NSData dataWithBytes:written.data() length:written.size()];
    NSString *raw = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"0\r\n";
    if (!raw) return TLinkNativeFailure(@"invalid_response_encoding");
    NSArray<NSString *> *parts = [[raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"];
    NSString *status = parts.count ? parts[0] : @"1";
    if (budget->stopped()) {
        if ((frameCreate || imageCreate) && [status isEqualToString:@"0"] && parts.count > 1 && [parts[1] longLongValue] > 0) {
            NSString *release = [NSString stringWithFormat:frameCreate ? @"67%@%@" : @"483;;%@%@", parts[1], TLinkautoJSOwnerSuffix(context)];
            [self executeRawPayload:release context:context];
        }
        return TLinkNativeFailure(TLinkNativeStopCode(budget->reason()));
    }
    return @{ @"ok": @([status isEqualToString:@"0"]), @"raw": raw, @"parts": parts ?: @[] };
}
