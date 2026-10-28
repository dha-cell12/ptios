// Compile the former text/re-encoding consumer independently from the new codec.
#define TLinkautoJSBase64Decode legacyMetadataBase64Decode
#define TLinkautoJSBase64JSON legacyMetadataBase64JSON
#include "fixtures/native-base64-json-legacy-v1.inc"
#undef TLinkautoJSBase64JSON
#undef TLinkautoJSBase64Decode
static void base64JSONCases(){
    puts("Base64 JSON Foundation: frozen UTF8 text/re-encode versus validated original bytes");fflush(stdout);
    const auto parity=[](id input)->id{
        id expected=legacyMetadataBase64JSON((NSString *)input),actual=TLinkautoJSBase64JSON((NSString *)input);
        const bool same=actual==expected||[actual isEqual:expected];
        if(!same){fprintf(stdout,"Base64 JSON parity failure: %s\n",[NSString stringWithFormat:@"input=%@ expected=%@ actual=%@",input,expected,actual].UTF8String);fflush(stdout);}assert(same);
        return actual;
    };
    const auto encoded=[](const std::string &bytes)->NSString *{return [[NSData dataWithBytes:bytes.data() length:bytes.size()] base64EncodedStringWithOptions:0];};
    for(unsigned n=0;n<160;++n){@autoreleasepool{
        NSDictionary *object=@{@"items":@[@{@"bundle_id":[NSString stringWithFormat:@"com.example.%u",n],@"name":@"ảnh 测试 😀",@"nested":@[@(true),@(false),[NSNull null],@(-0.0),@(n),@"a;;b,,c\r\n"]}]};
        NSData *data=[NSJSONSerialization dataWithJSONObject:object options:0 error:nil];assert(data);
        assert([parity([data base64EncodedStringWithOptions:0]) isEqual:object]);
    }}
    for(NSString *text in @[@"",@" ",@"{}",@"[]",@"null",@"1",@"true",@"\"fragment\"",@"{\"items\":[]}",@"{\"items\":null}",@"{\"items\":{}}",@"{\"items\":17}",@"{\"items\":[1,\"x\",null]}",@"{\"items\":[{\"name\":\"e\\u0301/\\u0000/😀\"}]}",@"{\"a\":1,\"a\":2}",@"{\"a\":-0.0,\"b\":1e300,\"c\":9007199254740993}",@"{\"a\":NaN}",@"{\"a\":Infinity}",@"{\"a\":\"\\ud800\"}",@"{\"a\":\"\\udc00\"}",@"{} trailing",@"/*comment*/{}",@"{\"a\":}"]){
        for(NSStringEncoding encoding:{NSUTF8StringEncoding,NSUTF16StringEncoding,NSUTF16LittleEndianStringEncoding,NSUTF16BigEndianStringEncoding,NSUTF32StringEncoding,NSUTF32LittleEndianStringEncoding,NSUTF32BigEndianStringEncoding}){
            NSData *data=[text dataUsingEncoding:encoding];assert(data);parity([data base64EncodedStringWithOptions:0]);
        }
    }
    const std::vector<std::string> bytes={std::string("\xef\xbb\xbf")+"{}",std::string("\xef\xbb\xbf\xef\xbb\xbf")+"{}",std::string("{\"a\":\"")+"\xef\xbf\xbe"+"\"}",
        "\xff","\x80","\xc0\xaf","\xe0\x80\xaf","\xed\xa0\x80","\xf4\x90\x80\x80","\xf5\x80\x80\x80","\xc2","\xe2\x82","\xf0\x9f\x98",std::string("{}\0tail",7)};
    for(const auto &value:bytes)parity(encoded(value));
    for(id input in @[@"",@"a",@"====",@"e30=",@"e30",@"e30===",@" e30=",@"e30=\n",@"e!30=",@42,[NSNull null]])parity(input);
    parity(nil);
    const unichar nul=0,high=0xd800;parity([NSString stringWithCharacters:&nul length:1]);parity([NSString stringWithCharacters:&high length:1]);
    // Large accepted wire-sized metadata and retained immutable JSON objects.
    const std::string large="{\"items\":[{\"name\":\""+std::string(700*1024,'x')+"\"}]}";
    id held=nil;@autoreleasepool{NSMutableString *source=[encoded(large) mutableCopy];held=parity(source);[source setString:@"changed"];}
    assert([held isKindOfClass:[NSDictionary class]]&&[held[@"items"][0][@"name"] length]==700*1024);
    for(unsigned n=0;n<128;++n){@autoreleasepool{parity(@"e30=");parity(@"/w==");}}
    assert([held[@"items"][0][@"name"] length]==700*1024);
    puts("Base64 JSON passed: frozen objects/nil parity, Unicode/NUL/BOM/UTF16/UTF32/malformed UTF8 and base64, fragments/types/numbers/errors, large metadata, mutable input and cross-pool ownership; ordinary decoded NSData feeds JSON directly, leading BOM retains text compatibility.");
}
