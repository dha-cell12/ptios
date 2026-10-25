// Frozen 0200261 successful formatter and JS metadata conversion before C02b21.
static NSString *legacyImageOpenBody(const TLinkNativeImageValue &v){return [NSString stringWithFormat:@"%u;;%d;;%d",v.id,v.width,v.height];}
static NSDictionary *legacyImageOpenResult(const TLinkNativeImageValue &v){
    NSString *raw=[NSString stringWithFormat:@"0;;%@\r\n",legacyImageOpenBody(v)];
    NSArray *parts=[[raw stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsSeparatedByString:@";;"];
    return @{@"ok":@(true),@"raw":raw,@"parts":parts,@"id":@([parts[1] intValue]),@"width":@([parts[2] intValue]),@"height":@([parts[3] intValue])};
}
static void imageOpenResultCases(){
    const uint32_t ids[]={0,1,41,uint32_t(INT_MAX),UINT32_MAX};
    const int dimensions[]={0,1,8192,INT_MAX,INT_MIN,-1};
    for(unsigned n=0;n<1000;++n){
        TLinkNativeImageValue v;v.id=ids[n%5];v.width=dimensions[(n/5)%6];v.height=dimensions[(n/30)%6];
        NSDictionary *actual=TLinkNativeImageResult(v),*expected=legacyImageOpenResult(v);
        assert([actual isEqual:expected]);assert([TLinkNativeImageBody(v) isEqual:legacyImageOpenBody(v)]);
        assert([actual[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<1024);
    }
    NSDictionary *held=nil;@autoreleasepool{TLinkNativeImageValue v;v.id=41;v.width=2;v.height=3;held=TLinkNativeImageResult(v);}
    assert([held[@"id"] intValue]==41&&[held[@"raw"] isEqual:@"0;;41;;2;;3\r\n"]);
    puts("Image open result passed: 1000 frozen full-wire/structured integer cases, exact raw/parts/metadata, ID conversion, geometry formatting boundaries and ARC pool lifetime.");
}
