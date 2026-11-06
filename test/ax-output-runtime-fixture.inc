// Only used on refusal paths: prove UTF-16 admission precedes encoding work.
// This method seam is not a string subclass and is never serialized as UI text.
@interface AXOutputTextProbe:NSObject
@property(nonatomic) NSUInteger units;
@property(nonatomic) NSUInteger bytes;
@property(nonatomic) unsigned byteCalls;
-(NSUInteger)length;
-(NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding;
@end
@implementation AXOutputTextProbe
-(NSUInteger)length{return self.units;}
-(NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding{
    assert(encoding==NSUTF8StringEncoding);++_byteCalls;return self.bytes;
}
@end
static NSDictionary *outputCall(bool current,NSDictionary *options=@{}){
    return current?TLinkAXCopySnapshotUnlocked(123,@"fixture.bundle",options):BeforeOutputAXCopySnapshotUnlocked(123,@"fixture.bundle",options);
}
static NSString *outputRepeated(NSString *unit,NSUInteger count){
    return [@"" stringByPaddingToLength:unit.length*count withString:unit startingAtIndex:0];
}
static void outputTextBoundaryCases(){
    const unichar nul=0;NSString *nulText=[NSString stringWithCharacters:&nul length:1];
    NSArray *texts=@[@"",outputRepeated(@"a",65536),outputRepeated(@"a",65537),
        outputRepeated(@"测",21845),outputRepeated(@"测",21846),
        outputRepeated(@"😀",16384),outputRepeated(@"😀",16385),
        outputRepeated(nulText,65536),outputRepeated(@"\"",65536),outputRepeated(@"\\",65536)];
    for(NSString *field in @[@"label",@"value",@"identifier",@"role"]){
        for(NSString *text in texts){
            NSDictionary *expected=nil;
            const bool oversize=[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>65536;
            for(bool current:{false,true}){
                @autoreleasepool{
                    reset();sourceCount=1;outputTextValue=text;outputTextField=field;
                    NSDictionary *value=outputCall(current);
                    if(current&&oversize){expectError(value,@"ui_response_too_large");assert([value[@"partial"] boolValue]);}
                    else{
                        assert([value[@"ok"] boolValue]);
                        if(current){assert([value isEqual:expected]&&[findJSON(value) isEqualToData:findJSON(expected)]);}
                        else expected=value;
                        assert(value[@"elements"][0][field]==text);
                    }
                    assert(serialized==1&&rootRetains==rootDrops&&rawOutRetains==1&&arrayDrops==0);
                }
                assert(!returnedArray);
            }
        }
    }
    for(unsigned kind=0;kind<2;++kind){
        @autoreleasepool{
            reset();sourceCount=1;AXOutputTextProbe *probe=[AXOutputTextProbe new];
            probe.units=kind?1:65537;probe.bytes=std::numeric_limits<size_t>::max();outputTextValue=probe;
            expectError(outputCall(true),@"ui_response_too_large");
            assert(probe.byteCalls==(kind?1U:0U)&&rootRetains==rootDrops);
        }
        assert(!returnedArray);
    }
}
static void outputAggregateCases(){
    for(unsigned n=0;n<128;++n){
        NSDictionary *expected=nil;unsigned oldSerialized=0;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();sourceCount=1+n%71;outputTextValue=outputRepeated(n%2?@"测":@"a",n%5?1000:0);
                outputCap=32768+n*997;
                NSDictionary *value=outputCall(current,@{@"visible_only":@NO,@"max_elements":@1000});
                if(current){assert([value isEqual:expected]&&[findJSON(value) isEqualToData:findJSON(expected)]&&serialized==oldSerialized);}
                else{expected=value;oldSerialized=serialized;}
                assert(rootRetains==rootDrops);
            }
            assert(!returnedArray);
        }
    }
    // Existing caller cap, exact wire fit and first byte beyond it.
    size_t row=768,next=0,wire=0;
    for(NSString *text in @[@"x",@"value",@"id",@"element"])
        assert(TLinkAXSnapshotOutput::AddString([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding],row));
    assert(TLinkAXSnapshotOutput::AppendRow(row,0,next,wire));
    for(bool current:{false,true}){
        for(bool exact:{false,true}){
            @autoreleasepool{
                reset();sourceCount=1;outputTextValue=@"x";outputCap=wire-(exact?0:1);
                NSDictionary *value=outputCall(current);
                if(exact)assert([value[@"ok"] boolValue]);else expectError(value,@"ui_response_too_large");
                assert(rootRetains==rootDrops);
            }
            assert(!returnedArray);
        }
        // Unreturned rows keep the existing visibility/clickability precedence.
        @autoreleasepool{
            reset();sourceCount=4;forceHidden=true;outputTextValue=outputRepeated(@"a",65537);
            NSDictionary *value=outputCall(current);assert([value[@"ok"] boolValue]&&[value[@"count"] unsignedIntValue]==0);
        }
        assert(!returnedArray);
    }
}
static void snapshotOutputCases(){
    std::puts("AX snapshot strings: actual/C05p rows, real Unicode/JSON, controlled text/CF providers");
    outputTextBoundaryCases();outputAggregateCases();
    NSDictionary *held=nil;
    @autoreleasepool{reset();sourceCount=1;outputTextValue=outputRepeated(@"测",21845);held=outputCall(true);assert([held[@"ok"] boolValue]);outputTextValue=nil;}
    assert([held[@"elements"][0][@"label"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]==65535);
    held=nil;
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            reset();sourceCount=1;outputTextValue=outputRepeated(@"😀",16385);
            NSDictionary *value=outputCall(true);expectError(value,@"ui_response_too_large");
            assert(!TLinkAXResultCompleteForAction(value)&&rootRetains==rootDrops);
        }
        assert(!returnedArray);
        @autoreleasepool{reset();assert([outputCall(true)[@"ok"] boolValue]);}
        assert(!returnedArray);
    }
    reset();
    std::puts("AX snapshot strings passed: four fields, exact ASCII/Unicode/NUL/escaping 64-KiB boundaries, UTF16 preflight, 128 frozen aggregate/output cases, exact wire cap, filter priority, held text and 128 refusal/recovery lifecycles. Provider/root/hit-test/device bounds remain pending.");
}
