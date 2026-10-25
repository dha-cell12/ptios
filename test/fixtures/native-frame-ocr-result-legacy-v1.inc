// Frozen pre-C02b15 result formatting at 2475200; only helper names are isolated.
static NSString *frozenFrameOCRBase64(NSString *text){
    NSData *data=[(text?:@"") dataUsingEncoding:NSUTF8StringEncoding];
    return [data base64EncodedStringWithOptions:0]?:@"";
}
static NSString *frozenFrameOCRBody(NSString *text,double confidence,uint64_t frameAgeMs,double ocrMs,double preprocessMs,double totalMs){
        return [NSString stringWithFormat:@"%@;;%.2f;;%llu;;%.3f;;%.3f;;%.3f",
                frozenFrameOCRBase64(text),
                confidence,
                (unsigned long long)frameAgeMs,
                ocrMs,
                preprocessMs,
                totalMs];
}
