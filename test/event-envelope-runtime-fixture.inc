// C03r: compare actual direct JSON-v1 encoding with the frozen C03q legacy pipeline.
static NSDictionary *fixtureEnvelopeFrameObject(NSData *wire) {
    assert(wire.length>=kZXTPHeaderSize);
    const uint8_t *bytes=(const uint8_t *)wire.bytes;
    assert(!memcmp(bytes,kZXTPMagic,4)&&bytes[4]==kZXTPVersion&&bytes[5]==0);
    const uint32_t length=((uint32_t)bytes[6]<<24)|((uint32_t)bytes[7]<<16)|((uint32_t)bytes[8]<<8)|bytes[9];
    assert(length==wire.length-kZXTPHeaderSize&&length<=kZXTPMaxBodySize);
    NSDictionary *object=[NSJSONSerialization JSONObjectWithData:[wire subdataWithRange:NSMakeRange(kZXTPHeaderSize,length)] options:0 error:nil];
    assert([object isKindOfClass:[NSDictionary class]]);return object;
}
static NSDictionary *fixtureEnvelopeCompare(NSDictionary *batch,NSString *error,NSNumber *requestId,bool fast) {
    const unsigned encodes=fixtureBatchEncodes.load(),conversions=fixtureCStringConversions.load(),parses=fixtureLegacyParses.load();
    NSDictionary *expected=FixtureEventLegacyJSON(fixtureLegacyEventBatchResponse(batch,error),requestId);
    assert(fixtureCStringConversions==conversions+1&&fixtureLegacyParses==parses+1);
    assert(fixtureBatchEncodes==encodes+(error.length?0:1));
    const unsigned encoded=fixtureBatchEncodes.load();
    NSDictionary *actual=zx_eventBatchJSONResponse(batch,error,requestId);
    assert([actual isEqual:expected]);
    assert(fixtureBatchEncodes==encoded+(error.length?0:1));
    assert(fixtureCStringConversions==conversions+(fast?1:2)&&fixtureLegacyParses==parses+(fast?1:2));
    NSDictionary *oldFrame=fixtureEnvelopeFrameObject(zx_frameJSONResponse(expected));
    NSDictionary *newFrame=fixtureEnvelopeFrameObject(zx_frameJSONResponse(actual));
    assert([oldFrame isEqual:newFrame]);return newFrame;
}
static void fixtureEventEnvelopeCases() {
    fputs("Event envelope Foundation: frozen legacy/base64/JSON-v1 parity and avoided conversions\n",stderr);
    for(unsigned n=0;n<160;++n) @autoreleasepool {
        NSMutableArray *events=[NSMutableArray array];
        for(unsigned i=0;i<n%33;++i){
            NSMutableDictionary *event=[fixtureStoredEvent((uint64_t)n*33+i+1) mutableCopy];
            event[@"payload"]=@{@"text":@"ảnh;测试;;\r\n/\\\"",@"nul":[NSString stringWithFormat:@"a%Cb",(unichar)0],
                @"flag":@(n%2==0),@"values":@[@(-1),@1.25,[NSNull null]]};
            [events addObject:event];
        }
        NSDictionary *batch=@{@"schema":TLinkEventChannelSchemaV1,@"state":n%2?@"ready":@"busy",@"events":events,
            @"cursor":@(UINT64_MAX-n),@"next_cursor":@(n),@"gap":@(n%3==0),@"timed_out":@(n%5==0),@"has_more":@(n%7==0)};
        fixtureBatchJSONOverride=fixtureJournalData(batch);
        NSNumber *requestId=n%4==0?nil:(n%4==1?@0:(n%4==2?@(-7):@(UINT64_MAX)));
        NSDictionary *framed=fixtureEnvelopeCompare(batch,nil,requestId,true);
        assert([framed[@"ok"] boolValue]&&[framed[@"id"] isEqual:requestId?:@0]);
        NSArray *data=framed[@"data"];assert(data.count==1&&[data[0] isKindOfClass:[NSString class]]);
        NSData *decoded=[[NSData alloc] initWithBase64EncodedString:data[0] options:0];
        assert([decoded isEqual:fixtureBatchJSONOverride]);
        assert([[NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil] isEqual:batch]);
        fixtureBatchJSONOverride=nil;
    }
    NSArray *errors=@[@"license_required",@"-1;;license_required\r\n",@"bad;;detail\r\n",@"-1;;x;;y\n",@"ảnh 测试\n",@"-1;;",
        [NSString stringWithFormat:@"-1;;a%Cb",(unichar)0]];
    for(NSString *error in errors){
        fixtureBatchEncodeFault=3; // Errors must not attempt batch serialization.
        NSDictionary *framed=fixtureEnvelopeCompare(nil,error,@42,false);
        assert(![framed[@"ok"] boolValue]&&framed[@"data"]==[NSNull null]);
        fixtureBatchEncodeFault=0;
    }
    for(unsigned mode=1;mode<=2;++mode){
        fixtureBatchEncodeFault=mode;
        NSDictionary *framed=fixtureEnvelopeCompare(@{},nil,nil,false);
        assert([framed[@"error"] isEqual:@"event_channel_json_failed"]);
    }
    for(unsigned mode=3;mode<=4;++mode) for(unsigned direct=0;direct<=1;++direct){
        fixtureBatchEncodeFault=mode;bool objc=false,cpp=false;
        const unsigned parses=fixtureLegacyParses.load(),conversions=fixtureCStringConversions.load();
        @try {try {
            if(direct)(void)zx_eventBatchJSONResponse(@{},nil,@42);
            else (void)fixtureLegacyEventBatchResponse(@{},nil);
        } catch(const std::runtime_error &) {cpp=true;}}
        @catch(NSException *exception){(void)exception;objc=true;}
        assert(objc==(mode==3)&&cpp==(mode==4)&&fixtureLegacyParses==parses&&fixtureCStringConversions==conversions);
    }
    fixtureBatchEncodeFault=0;
    // The existing frame encoder retains its one-MiB envelope limit on either path.
    bool accepted=false,rejected=false;
    for(unsigned n=0;n<=16;++n) @autoreleasepool {
        const NSUInteger length=kZXTPMaxBodySize*3/4-128+n*16;
        NSString *text=[@"a" stringByPaddingToLength:length withString:@"a" startingAtIndex:0];
        NSDictionary *batch=@{@"extension":text};fixtureBatchJSONOverride=fixtureJournalData(batch);
        NSDictionary *framed=fixtureEnvelopeCompare(batch,nil,@42,true);
        if([framed[@"ok"] boolValue])accepted=true;
        else {assert([framed[@"error"] isEqual:@"response_too_large"]);rejected=true;}
        fixtureBatchJSONOverride=nil;
    }
    assert(accepted&&rejected);
    // A canonical maximum reply fits, and the envelope owns its data across pools.
    __strong NSDictionary *survivor;
    @autoreleasepool {
        NSMutableArray *events=[NSMutableArray array];
        for(unsigned n=0;n<32;++n){
            NSMutableDictionary *event=[fixtureStoredEvent(n+1) mutableCopy];
            event[@"payload"]=@{@"x":[@"a" stringByPaddingToLength:4088 withString:@"a" startingAtIndex:0]};
            [events addObject:event];
        }
        NSDictionary *batch=@{@"schema":TLinkEventChannelSchemaV1,@"events":events};
        fixtureBatchJSONOverride=fixtureJournalData(batch);
        survivor=zx_eventBatchJSONResponse(batch,nil,@42);
        assert([fixtureEnvelopeCompare(batch,nil,@42,true)[@"ok"] boolValue]);
        fixtureBatchJSONOverride=nil;
    }
    NSData *decoded=[[NSData alloc] initWithBase64EncodedString:survivor[@"data"][0] options:0];
    NSDictionary *batch=[NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil];
    assert([batch[@"events"] count]==32);
    puts("Event envelope Foundation passed: 160 frozen graph/base64/id cases, preformatted/NUL/Unicode errors, encode nil/empty/NS/C++ faults, avoided legacy conversions, frame limits, 32 maximum payloads and pool lifetime. Real socket delivery remains covered separately.");
}
