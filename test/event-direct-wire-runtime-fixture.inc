static void fixtureDirectEventWireCases(){
    puts("Direct event wire Foundation: exact preceding encoder, real NSData/Foundation base64 and final-buffer/JSON pool ownership");fflush(stdout);
    uint32_t state=0x79a34bcd;
    const auto next=[&](){state^=state<<13;state^=state>>17;state^=state<<5;return state;};
    for(NSUInteger length=0;length<1000;++length){@autoreleasepool {
        NSMutableData *json=[NSMutableData dataWithLength:length];uint8_t *bytes=(uint8_t *)json.mutableBytes;
        for(NSUInteger n=0;n<length;++n)bytes[n]=uint8_t(next());
        fixtureBatchJSONOverride=json;
        NSData *expected=FixtureBeforeDirectEventWire(@{});
        fixtureDirectWireAllocations=fixtureDirectWireEncodes=0;
        fixtureDirectWireTrack=true;
        NSData *actual=TLinkEventLegacyBatchResponse(@{});
        fixtureDirectWireTrack=false;
        assert((!expected&&!actual)||[expected isEqual:actual]);
        assert(fixtureDirectWireAllocations==(length?1U:0U)&&fixtureDirectWireEncodes==(length?1U:0U));
        if(actual){assert([actual isKindOfClass:[NSMutableData class]]);assert(actual==fixtureDirectWireBuffer);}
        fixtureBatchJSONOverride=nil;
    }}
    for(unsigned fault=1;fault<=4;++fault){
        @autoreleasepool {
            TLinkAXFixtureResetOwners();fixtureDirectWireTrack=true;fixtureDirectWireFault=fault;
            fixtureDirectWireAllocations=fixtureDirectWireEncodes=0;
            fixtureBatchJSONOverride=[@"{}" dataUsingEncoding:NSUTF8StringEncoding];bool caught=false;
            NSData *result=nil;
            @try {try {result=TLinkEventLegacyBatchResponse(@{});}catch(const std::runtime_error &){assert(fault==4);caught=true;}}
            @catch(NSException *exception){assert(fault==3&&[exception.name isEqual:@"EventDirectWireFixture"]);caught=true;}
            assert(!result&&fixtureDirectWireAllocations==1&&fixtureDirectWireEncodes==(fault==2?1U:0U)&&caught==(fault>=3));
            if(fault<3){
                assert(TLinkAXFixtureLiveOwners()==0&&!fixtureDirectWireBuffer);
                NSData *root=zx_eventBatchResponse(@{},nil),*troll=POCEventBatchResponse(@{},nil);
                NSData *error=[@"-1;;event_channel_json_failed\r\n" dataUsingEncoding:NSUTF8StringEncoding];
                assert([root isEqual:error]&&[troll isEqual:error]);
            }
            fixtureDirectWireFault=0;fixtureDirectWireTrack=false;fixtureBatchJSONOverride=nil;
        }
        assert(TLinkAXFixtureLiveOwners()==0);
    }
    for(bool modern:{false,true}){
        for(unsigned fault=0;fault<=2;++fault){
            NSData *held=nil;
            @autoreleasepool {
                TLinkAXFixtureResetOwners();fixtureDirectWireTrack=true;fixtureBatchEncodeFault=fault;
                for(unsigned n=0;n<32;++n){
                    held=modern?TLinkEventLegacyBatchResponse(@{@"n":@(n)}):FixtureBeforeDirectEventWire(@{@"n":@(n)});
                    if(modern)assert(TLinkAXFixtureLiveOwners()==0);
                    else assert(TLinkAXFixtureLiveOwners()>=n+1);
                    assert((held!=nil)==(fault==0));
                }
                if(modern)assert(TLinkAXFixturePeakOwners()<=(fault?1U:2U));
                fixtureDirectWireTrack=false;fixtureBatchEncodeFault=0;
            }
            assert(TLinkAXFixtureLiveOwners()==0);
            if(held){assert(held.length>5);}
        }
    }
    __strong NSData *held=nil;__weak NSMutableData *weak=nil;
    @autoreleasepool {
        fixtureDirectWireTrack=true;
        held=TLinkEventLegacyBatchResponse(@{@"nested":@[@"ảnh\0测试😀"]});
        fixtureDirectWireTrack=false;
        weak=fixtureDirectWireBuffer;assert(held&&weak);
    }
    @autoreleasepool {
        assert(weak&&[decodeLegacy(held)[@"nested"][0] isEqual:@"ảnh\0测试😀"]);
        held=nil;
    }
    assert(!weak&&!fixtureDirectWireTrack&&!fixtureDirectWireFault&&!fixtureBatchEncodeFault&&!fixtureBatchJSONOverride);
    puts("Direct event wire Foundation passed: 1000 exact Foundation byte/padding comparisons, one final mutable buffer, nil/short/NS/C++ allocation faults without partial success, unchanged root/TrollStore errors, JSON owner retirement and retained response lifetime. Existing maximum/large/sync/remote transport cases retained; device performance pending.");
}
