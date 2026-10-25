// Frozen C02b18 response contract (765d989): full formatter, split and JS enrichment.
static NSString *legacyFrameCaptureBody(const TLinkNativeFrameCaptureValue &v){
    return [NSString stringWithFormat:@"%u;;%d;;%d;;%d;;%.3f;;pixel;;BGRA;;%d;;%d;;%llu;;%.3f;;%.3f;;%.3f;;%.3f",
        v.id,v.width,v.height,v.bytesPerRow,v.scale,v.hasBGRA?1:0,v.hasGray?1:0,
        (unsigned long long)v.capturedAtMs,v.captureMs,v.bgraMs,v.grayMs,v.totalMs];
}
static NSDictionary *legacyFrameCaptureResult(const TLinkNativeFrameCaptureValue &v){
    NSString *raw=[NSString stringWithFormat:@"0;;%@\r\n",legacyFrameCaptureBody(v)];
    NSArray *parts=[[raw stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsSeparatedByString:@";;"];
    return @{@"ok":@(true),@"raw":raw,@"parts":parts,@"id":@([parts[1] intValue]),
        @"width":@([parts[2] intValue]),@"height":@([parts[3] intValue]),@"bytesPerRow":@([parts[4] intValue]),
        @"scale":@([parts[5] doubleValue]),@"coord":parts[6],@"format":parts[7],
        @"hasBGRA":@([parts[8] intValue]!=0),@"hasGray":@([parts[9] intValue]!=0),
        @"createdAtMs":@([parts[10] longLongValue]),@"captureMs":@([parts[11] doubleValue]),
        @"bgraMs":@([parts[12] doubleValue]),@"grayMs":@([parts[13] doubleValue]),@"totalMs":@([parts[14] doubleValue])};
}
static void frameCaptureResultCases(){
    const double values[]={0.,-0.,.00049,.0005,.00051,1.23449,1.2345,1.23451,-1.2345,2.125,123456.78951,1e100,1.7976931348623157e308};
    const uint64_t stamps[]={0,123456,UINT64_C(9007199254740993),UINT64_C(9223372036854775807),UINT64_MAX};
    const uint32_t ids[]={1,41,uint32_t(INT_MAX),UINT32_MAX};
    for(unsigned n=0;n<3000;++n){
        TLinkNativeFrameCaptureValue v;v.id=ids[n%4];v.width=int(n);v.height=int(n)+1;v.bytesPerRow=int(n)*4;
        v.hasBGRA=n%2;v.hasGray=(n/2)%2;v.capturedAtMs=stamps[n%5];
        v.scale=values[n%13];v.captureMs=values[(n+1)%13];v.bgraMs=values[(n+3)%13];v.grayMs=values[(n+5)%13];v.totalMs=values[(n+7)%13];
        NSDictionary *expected=legacyFrameCaptureResult(v),*actual=TLinkNativeFrameCaptureResult(v);
        assert([actual isEqual:expected]);assert([TLinkNativeFrameCaptureBody(v) isEqual:legacyFrameCaptureBody(v)]);
    }
    puts("Frame capture result passed: 3000 frozen full-wire/structured cases, exact raw/parts/metadata, three-decimal rounding, unsigned ID/timestamp conversion and large finite output.");
}
