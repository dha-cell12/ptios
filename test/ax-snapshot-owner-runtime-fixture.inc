static NSDictionary *snapshotOwnerCall(bool current,NSDictionary *options=@{}){
    return current?TLinkAXCopySnapshotUnlocked(123,@"fixture.bundle",options):BeforeOwnerAXCopySnapshotUnlocked(123,@"fixture.bundle",options);
}
static void snapshotRawOwnersRetired(){
    const bool retired=rootRetains==rootDrops&&rawOutRetains==arrayDrops;
    if(!retired)std::fprintf(stderr,"AX snapshot raw owners: root=%u/%u payload=%u/%u\n",rootRetains,rootDrops,rawOutRetains,arrayDrops);
    assert(retired);
}
static void snapshotOwnerGoldenCases(){
    for(unsigned n=0;n<256;++n){
        NSDictionary *expected=nil;unsigned oldSerialized=0,oldQueries=0,oldRootDrops=0,oldArrayDrops=0;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();sourceCount=n%17;createCost=1000000ULL;queryCost=2000000ULL;nodeCost=(n%3)*1000000ULL;failEvery=n%7==0?3:0;
                queryError=n%11==0;wrongArray=n%13==0;queryMissing=n%17==0;rootMissing=n%19==0;prepared=n%23!=0;locked=n%29==0;
                NSDictionary *options=@{@"max_elements":@(1+n%8),@"max_scanned_elements":@(1+n%11),
                    @"timeout_ms":@100,@"visible_only":@((n&1)!=0),@"clickable_only":@((n&2)!=0)};
                NSDictionary *value=snapshotOwnerCall(current,options);
                if(current){
                    if(![value isEqual:expected])NSLog(@"AX snapshot owner parity seed=%u expected=%@ actual=%@",n,expected,value);
                    assert([value isEqual:expected]&&serialized==oldSerialized&&queries==oldQueries&&rootDrops==oldRootDrops&&arrayDrops==oldArrayDrops);
                    assert([findJSON(value) isEqualToData:findJSON(expected)]);
                }else{expected=value;oldSerialized=serialized;oldQueries=queries;oldRootDrops=rootDrops;oldArrayDrops=arrayDrops;}
                assert(rootRetains==rootDrops);
                if(queryError||wrongArray||queryMissing)snapshotRawOwnersRetired();
                else assert(arrayDrops==0);
            }
            assert(!returnedArray);
        }
    }
}
static void snapshotAcquisitionFaultCases(){
    for(unsigned site=1;site<=4;++site){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();ownerFaultSite=site;ownerFaultKind=1;
                NSDictionary *value=snapshotOwnerCall(current);expectError(value,@"ui_ax_exception");
                if(current)assert([value isEqual:expected]);else expected=value;
                snapshotRawOwnersRetired();assert(serialized==0);
                assert(creates==1&&queries==(site>=3?1U:0U)&&rawOutRetains==(site==4?1U:0U));
            }
            // A normal enclosing pool drains the provider's exception-exited
            // inner pool. Raw CF ownership must already be retired above.
            assert(!returnedArray);
        }
        @autoreleasepool{
            reset();ownerFaultSite=site;ownerFaultKind=2;bool caught=false;
            try{snapshotOwnerCall(true);}catch(const std::runtime_error &){caught=true;}
            assert(caught&&serialized==0);snapshotRawOwnersRetired();
            assert(rootRetains==(site==1?0U:1U)&&rawOutRetains==(site==4?1U:0U));
        }
        assert(!returnedArray);
        @autoreleasepool{reset();assert([snapshotOwnerCall(true)[@"ok"] boolValue]&&rootRetains==rootDrops);}
        assert(!returnedArray);
    }
    for(unsigned kind:{1U,2U}){
        @autoreleasepool{
            reset();throwNode=kind==1;throwNodeCPP=kind==2;bool caught=false;
            @try{try{snapshotOwnerCall(true);}catch(const std::runtime_error &){caught=kind==2;}}
            @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXSnapshotFixture"];}
            assert(caught&&rootRetains==rootDrops&&rawOutRetains==1&&arrayDrops==0);
        }
        assert(!returnedArray);
    }
}
static void snapshotOwnerCases(){
    std::puts("AX snapshot owners: complete current/C05k acquisition/traversal, real CF arrays/owners and controlled AX providers");
    snapshotOwnerGoldenCases();snapshotAcquisitionFaultCases();
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            reset();ownerFaultSite=4;ownerFaultKind=n%2+1;bool caught=false;
            @try{try{NSDictionary *value=snapshotOwnerCall(true);expectError(value,@"ui_ax_exception");caught=ownerFaultKind==1;}
                catch(const std::runtime_error &){caught=ownerFaultKind==2;}}
            @catch(NSException *exception){(void)exception;assert(false);}
            assert(caught);snapshotRawOwnersRetired();
        }
        assert(!returnedArray);
    }
    reset();
    std::puts("AX snapshot owners passed: 256 frozen graphs/JSON/count/timeout/error cases, four acquisition NS/C++ fault sites, after-out-value cleanup, successful ARC transfer/node unwind, recovery and 128 balanced failure cycles. Root materialization/AX/device qualification pending.");
}
