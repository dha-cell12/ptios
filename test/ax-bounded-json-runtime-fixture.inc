static TLinkAXJSONStream *heldJSONStream;
static unsigned jsonWriterMode=0;
static NSInteger controlledJSONWriter(id object,NSOutputStream *output,NSError *__autoreleasing *error){
    (void)object;heldJSONStream=(TLinkAXJSONStream *)output;assert(output.streamStatus==NSStreamStatusOpen);
    const uint8_t body[]={'{','}'};assert([output write:body maxLength:2]==2);
    switch(jsonWriterMode){
        case 1:case 8:{
            NSMutableData *large=[NSMutableData dataWithLength:TLinkAXJSONOutput::MaxJSONBytes+1];
            assert([output write:(const uint8_t *)large.bytes maxLength:large.length]==-1);
            return jsonWriterMode==8?2:0;
        }
        case 2:return 1;
        case 3:if(error)*error=[NSError errorWithDomain:@"JSONWriterFixture" code:3 userInfo:nil];return 2;
        case 4:[output close];return 2;
        case 5:[NSException raise:@"JSONWriterFixture" format:@"writer"];return 0;
        case 6:throw std::runtime_error("writer");
        case 7:return 0;
        default:return 2;
    }
}
static NSData *beforeBoundedCall(bool root,bool capability,NSDictionary *value){
    if(root){
        if(capability)BeforeBoundedRootCapability(NULL);else BeforeBoundedRootResponse(value,NULL);
        return captured;
    }
    return capability?BeforeBoundedTrollCapability():BeforeBoundedTrollResponse(value);
}
static void boundedWriterCases(){
    for(unsigned mode=0;mode<=8;++mode){
        __weak TLinkAXJSONStream *weakStream=nil;
        @autoreleasepool{
            BOOL tooLarge=YES;NSData *result=nil;bool caught=false;jsonWriterMode=mode;
            @try{try{result=TLinkAXJSONDataWithWriter(@{},&tooLarge,controlledJSONWriter);}
                catch(const std::runtime_error &){caught=mode==6;}}
            @catch(NSException *exception){caught=mode==5&&[exception.name isEqualToString:@"JSONWriterFixture"];}
            assert(caught==(mode==5||mode==6));assert(heldJSONStream.streamStatus==NSStreamStatusClosed);
            assert(heldJSONStream.bytes.length==2&&heldJSONStream.acceptedBytes==2);
            if(mode==0)assert([result isEqualToData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]]&&!tooLarge);
            else assert(!result&&tooLarge==(mode==1||mode==8));
            if(tooLarge)assert(heldJSONStream.streamError.code==1);
            weakStream=heldJSONStream;heldJSONStream=nil;
        }
        assert(!weakStream);
    }
    @autoreleasepool{
        TLinkAXJSONStream *stream=[TLinkAXJSONStream new];const uint8_t one='x';
        assert(stream.streamStatus==NSStreamStatusNotOpen&&!stream.hasSpaceAvailable);
        assert([stream write:&one maxLength:1]==-1&&stream.bytes.length==0);
        [stream close];[stream close];assert(stream.streamStatus==NSStreamStatusClosed);
        stream=[TLinkAXJSONStream new];[stream open];[stream open];assert([stream write:&one maxLength:0]==0);
        NSMutableData *data=[NSMutableData dataWithLength:TLinkAXJSONOutput::MaxJSONBytes];
        assert([stream write:(const uint8_t *)data.bytes maxLength:data.length]==(NSInteger)data.length);
        assert(stream.hasSpaceAvailable&&stream.bytes.length==data.length);
        assert([stream write:&one maxLength:1]==-1&&stream.limitExceeded&&stream.bytes.length==data.length);
        assert(!stream.hasSpaceAvailable);[stream close];[stream open];assert(stream.streamStatus==NSStreamStatusClosed);
    }
}
static void boundedCodecCases(){
    for(bool root:{false,true})for(bool capability:{false,true}){
        for(unsigned n=0;n<128;++n){
            NSDictionary *expected=nil;
            for(bool current:{false,true}){@autoreleasepool{
                reset();NSDictionary *graph=@{@"ok":@YES,@"text":@"Ứng dụng 测试😀\n\"\\",@"n":@(n),@"empty":@[],@"null":[NSNull null]};
                fixtureCapability=graph;
                NSData *reply=current?call(root,capability,true,graph):beforeBoundedCall(root,capability,graph);
                NSDictionary *value=decoded(reply);if(current)assert([value isEqual:expected]);else expected=value;
                assert(jsonCalls==1&&base64Calls==1&&lastJSON.length<=TLinkAXJSONOutput::MaxJSONBytes);
            }}
        }
        @autoreleasepool{
            reset();NSDictionary *graph=sizedGraph(root,capability,TLinkAXJSONOutput::MaxJSONBytes+1);
            errorReply(beforeBoundedCall(root,capability,graph),@"ui_response_too_large");
            assert(lastJSON.length==TLinkAXJSONOutput::MaxJSONBytes+1&&base64Calls==0);
            jsonCalls=base64Calls=0;lastJSON=captured=nil;
            errorReply(call(root,capability,true,graph),@"ui_response_too_large");
            assert(!lastJSON&&base64Calls==0&&jsonCalls==1);
        }
    }
    NSData *held=nil;
    @autoreleasepool{
        NSMutableDictionary *graph=[@{@"text":@"before"} mutableCopy];BOOL tooLarge=YES;
        held=TLinkAXBoundedJSONData(graph,&tooLarge);graph[@"text"]=@"after";assert(held&&!tooLarge);
    }
    NSDictionary *snapshot=[NSJSONSerialization JSONObjectWithData:held options:0 error:NULL];assert([snapshot[@"text"] isEqualToString:@"before"]);
    for(unsigned n=0;n<128;++n){@autoreleasepool{
        BOOL tooLarge=NO;NSString *large=[@"" stringByPaddingToLength:TLinkAXJSONOutput::MaxJSONBytes+1 withString:@"x" startingAtIndex:0];
        assert(!TLinkAXBoundedJSONData(@{@"text":large},&tooLarge)&&tooLarge);
        tooLarge=YES;NSData *data=TLinkAXBoundedJSONData(@{@"n":@(n)},&tooLarge);assert(data&&!tooLarge);
    }}
}
static void boundedJSONCases(){
    std::puts("AX bounded JSON: actual NSOutputStream/NSJSONSerialization writer, bounded quota and current/C05s four-codec comparison");
    boundedWriterCases();boundedCodecCases();
    std::puts("AX bounded JSON passed: complete stream/byte-count/error coherence, no partial prefix success, exact quota/overflow, NS/C++ close/unwind, immutable result pool lifetime, four C05s graph/Unicode routes, rejected JSON release and 128 recovery cycles. Foundation internal allocation/device memory remain unqualified.");
}
