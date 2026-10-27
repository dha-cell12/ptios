// Frozen 86c0974 OCR languages compatibility oracle.
static NSString *zx_tessBase64(NSString *s)
{
    NSData *data = [(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return [data base64EncodedStringWithOptions:0] ?: @"";
}

static NSError *zx_tessError(NSString *code, NSString *message)
{
    NSString *resp = [NSString stringWithFormat:@"1;;%@;;%@\r\n", code ?: @"ocr_error", zx_tessBase64(message ?: @"")];
    return [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp.ocr"
                               code:999
                           userInfo:@{NSLocalizedDescriptionKey:resp}];
}

