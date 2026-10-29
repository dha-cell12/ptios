// C03s: require exact legacy bytes against the independently frozen root/TrollStore encoders.
static NSData *fixtureEventWireCompare(NSDictionary *batch,NSString *error) {
    const unsigned encodes=fixtureBatchEncodes.load(),conversions=fixtureCStringConversions.load(),strings=fixtureSuccessStringConversions.load();
    NSData *oldRoot=fixtureLegacyEventBatchResponse(batch,error);
    NSData *oldTroll=fixtureLegacyTrollEventBatchResponse(batch,error);
    const bool success=!error.length&&!fixtureBatchEncodeFault;
    assert(fixtureCStringConversions==conversions+1);
    assert(fixtureSuccessStringConversions==strings+(success?1:0));
    assert(fixtureBatchEncodes==encodes+(error.length?0:2));
    const unsigned parsed=fixtureLegacyParses.load(),converted=fixtureCStringConversions.load(),formatted=fixtureSuccessStringConversions.load();
    NSData *root=zx_eventBatchResponse(batch,error);
    NSData *troll=POCEventBatchResponse(batch,error);
    assert([root isEqual:oldRoot]&&[troll isEqual:oldTroll]);
    assert(fixtureBatchEncodes==encodes+(error.length?0:4));
    assert(fixtureLegacyParses==parsed&&fixtureSuccessStringConversions==formatted);
    assert(fixtureCStringConversions==converted+(success?0:1));
    if(success){
        assert([root isEqual:troll]&&root.length>=5);
        const uint8_t *bytes=(const uint8_t *)root.bytes;
        assert(!memcmp(bytes,"0;;",3)&&!memcmp(bytes+root.length-2,"\r\n",2));
        NSData *body=[root subdataWithRange:NSMakeRange(3,root.length-5)];
        NSData *decoded=[[NSData alloc] initWithBase64EncodedData:body options:0];
        assert(decoded&&[decoded isEqual:fixtureBatchJSONOverride]);
    }
    return root;
}
static void fixtureEventSyncCompare(NSDictionary *batch,NSString *error) {
    fixtureSyncBatch=batch;fixtureSyncError=error;
    const unsigned polls=fixtureSyncPolls,encodes=fixtureBatchEncodes.load();
    NSData *oldRoot=fixtureLegacyRootSyncResponse(@"fixture");
    NSData *oldTroll=fixtureLegacyTrollSyncResponse(95,@"fixture");
    const unsigned converted=fixtureCStringConversions.load(),formatted=fixtureSuccessStringConversions.load();
    NSData *root=zx_eventChannelResponse(@"fixture");
    NSData *troll=fixtureTrollSyncResponse(95,@"fixture");
    assert([oldRoot isEqual:root]&&[oldTroll isEqual:troll]&&fixtureSyncPolls==polls+4);
    assert(fixtureBatchEncodes==encodes+(error.length?0:4));
    assert(fixtureCStringConversions==converted+((error.length||fixtureBatchEncodeFault)?1:0));
    assert(fixtureSuccessStringConversions==formatted);
    fixtureSyncBatch=nil;fixtureSyncError=nil;
}
static void fixtureEventWireCases() {
    fputs("Event wire Foundation: actual shared NSData encoder and frozen root/TrollStore/sync bytes\n",stderr);
    unsigned residues=0;
    for(unsigned n=0;n<256;++n) @autoreleasepool {
        NSDictionary *batch=@{@"schema":TLinkEventChannelSchemaV1,@"state":n%2?@"ready":@"busy",
            @"events":@[],@"cursor":@(UINT64_MAX-n),@"extension":@{@"text":@"ảnh 测试;;\r\n/\\\"",
            @"nul":[NSString stringWithFormat:@"a%Cb",(unichar)0],@"padding":[@"a" stringByPaddingToLength:n withString:@"a" startingAtIndex:0],
            @"number":@(-1.25),@"boolean":@(n%2==0),@"null":[NSNull null]}};
        fixtureBatchJSONOverride=fixtureJournalData(batch);residues|=1U<<(fixtureBatchJSONOverride.length%3);
        NSData *wire=fixtureEventWireCompare(batch,nil);
        assert([decodeLegacy(wire) isEqual:batch]);
        if(n%17==0)fixtureEventSyncCompare(batch,nil);
        fixtureBatchJSONOverride=nil;
    }
    assert(residues==7);
    NSArray *errors=@[@"license_required",@"-1;;license_required\r\n",@"a;;b\n",@"ảnh 测试\r\n",@"-1;;",
        [NSString stringWithFormat:@"x%Cy",(unichar)0],[NSString stringWithFormat:@"-1;;a%Cb",(unichar)0]];
    for(NSString *error in errors){
        fixtureBatchEncodeFault=3; // Every wrapper must return errors without encoding a batch.
        (void)fixtureEventWireCompare(nil,error);fixtureEventSyncCompare(nil,error);
        fixtureBatchEncodeFault=0;
    }
    for(unsigned fault=1;fault<=2;++fault){
        fixtureBatchEncodeFault=fault;
        NSData *wire=fixtureEventWireCompare(@{},nil);fixtureEventSyncCompare(@{},nil);
        assert([wire isEqual:[@"-1;;event_channel_json_failed\r\n" dataUsingEncoding:NSUTF8StringEncoding]]);
    }
    for(unsigned fault=3;fault<=4;++fault)for(unsigned entry=0;entry<8;++entry){
        fixtureBatchEncodeFault=fault;bool objc=false,cpp=false;
        const unsigned conversions=fixtureCStringConversions.load(),strings=fixtureSuccessStringConversions.load();
        fixtureSyncBatch=@{};
        @try {try {
            switch(entry){
                case 0:(void)fixtureLegacyEventBatchResponse(@{},nil);break;
                case 1:(void)fixtureLegacyTrollEventBatchResponse(@{},nil);break;
                case 2:(void)zx_eventBatchResponse(@{},nil);break;
                case 3:(void)POCEventBatchResponse(@{},nil);break;
                case 4:(void)fixtureLegacyRootSyncResponse(@"fixture");break;
                case 5:(void)fixtureLegacyTrollSyncResponse(95,@"fixture");break;
                case 6:(void)zx_eventChannelResponse(@"fixture");break;
                case 7:(void)fixtureTrollSyncResponse(95,@"fixture");break;
            }
        }catch(const std::runtime_error &){cpp=true;}}
        @catch(NSException *exception){(void)exception;objc=true;}
        assert(objc==(fault==3)&&cpp==(fault==4));
        assert(fixtureCStringConversions==conversions&&fixtureSuccessStringConversions==strings);
        fixtureSyncBatch=nil;
    }
    fixtureBatchEncodeFault=0;
    assert(!fixtureTrollSyncResponse(94,@"fixture")&&!fixtureLegacyTrollSyncResponse(94,@"fixture"));
    // The legacy encoder introduces no new frame limit, including extension data above one MiB.
    __strong NSData *survivor;
    @autoreleasepool {
        NSMutableArray *events=[NSMutableArray array];
        for(unsigned n=0;n<32;++n){
            NSMutableDictionary *event=[fixtureStoredEvent(n+1) mutableCopy];
            event[@"payload"]=@{@"x":[@"a" stringByPaddingToLength:4088 withString:@"a" startingAtIndex:0]};
            [events addObject:event];
        }
        NSDictionary *batch=@{@"schema":TLinkEventChannelSchemaV1,@"events":events};
        fixtureBatchJSONOverride=fixtureJournalData(batch);survivor=fixtureEventWireCompare(batch,nil);
        fixtureEventSyncCompare(batch,nil);fixtureBatchJSONOverride=nil;
    }
    assert([decodeLegacy(survivor)[@"events"] count]==32);
    @autoreleasepool {
        NSDictionary *batch=@{@"extension":[@"a" stringByPaddingToLength:1024*1024 withString:@"a" startingAtIndex:0]};
        fixtureBatchJSONOverride=fixtureJournalData(batch);
        assert(fixtureEventWireCompare(batch,nil).length>1024*1024);
        fixtureEventSyncCompare(batch,nil);fixtureBatchJSONOverride=nil;
    }
    assert(!fixtureSyncBatch&&!fixtureSyncError&&!fixtureBatchEncodeFault&&!fixtureBatchJSONOverride);
    puts("Event wire Foundation passed: 256 frozen exact-byte/base64-padding cases, root/TrollStore/remote shared path, synchronous wrappers, Unicode/NUL/preformatted errors, nil/empty/NS/C++ faults, no success text conversions, maximum/large payloads and pool lifetime. Device allocation/latency/RSS qualification remains pending.");
}
