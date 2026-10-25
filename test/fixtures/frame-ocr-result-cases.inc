static void frameOCRResultCases(){
    unichar invalid=0xd800,nul=0;
    NSArray *texts=@[@"",@"Tiếng Việt ;; A\n🙂",[NSString stringWithCharacters:&invalid length:1],[NSString stringWithCharacters:&nul length:1]];
    const double numbers[]={-1.0,-0.0,0.0,.0005,.0015,.005,83.125,99.995,1e100,INFINITY,NAN};
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        NSString *text=texts[n%texts.count];const double confidence=numbers[n%11],ms=numbers[(n/11)%11];const uint64_t age=n%2?UINT64_MAX:42;
        TLinkNativeFrameOCRValue value=TLinkFormatFrameOCRValue(text,confidence,age,ms,ms+1,ms+2);
        NSString *wire=frozenFrameOCRBody(text,confidence,age,ms,ms+1,ms+2);NSArray *columns=[wire componentsSeparatedByString:@";;"];
        assert([value.body isEqualToString:wire]&&[value.columns isEqual:columns]&&value.columns.count==6);
        NSData *utf8=[[NSData alloc] initWithBase64EncodedString:columns[0] options:0];NSString *decoded=utf8?[[NSString alloc] initWithData:utf8 encoding:NSUTF8StringEncoding]:@"";
        assert([value.text isEqualToString:decoded?:@""]);
    }}
    TLinkNativeFrameOCRValue held;
    @autoreleasepool{NSMutableString *source=[NSMutableString stringWithString:@"owned OCR result"];held=TLinkFormatFrameOCRValue(source,83.125,42,1.2345,2.3455,3.4565);[source setString:@"changed after publication"];}
    assert([held.text isEqualToString:@"owned OCR result"]&&held.columns.count==6&&[held.body containsString:held.columns[0]]);
    puts("OCR result passed: 1000 frozen body/column/text cases, Unicode/NUL/invalid UTF16, decimal/nonfinite/age boundaries and immutable cross-pool ownership.");
}
