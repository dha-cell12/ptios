static NSDictionary *nodePoolCall(bool current,NSDictionary *options=@{}){
    return current?TLinkAXCopySnapshotUnlocked(123,@"fixture.bundle",options):PrePoolAXCopySnapshotUnlocked(123,@"fixture.bundle",options);
}
static void nodePoolOwnerCounts(uint64_t live,uint64_t peak,uint64_t created,uint64_t dropped,const char *phase){
    const bool matches=TLinkAXFixtureLiveOwners()==live&&TLinkAXFixturePeakOwners()==peak&&
        TLinkAXFixtureCreatedOwners()==created&&TLinkAXFixtureDroppedOwners()==dropped;
    if(!matches)std::fprintf(stderr,"AX node owner mismatch (%s): live=%llu/%llu peak=%llu/%llu created=%llu/%llu dropped=%llu/%llu\n",phase,
        (unsigned long long)TLinkAXFixtureLiveOwners(),(unsigned long long)live,
        (unsigned long long)TLinkAXFixturePeakOwners(),(unsigned long long)peak,
        (unsigned long long)TLinkAXFixtureCreatedOwners(),(unsigned long long)created,
        (unsigned long long)TLinkAXFixtureDroppedOwners(),(unsigned long long)dropped);
    assert(matches);
}
static void nodePoolGoldenCases(){
    for(unsigned n=0;n<128;++n){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();sourceCount=n%13;nodeCost=(n%3)*1000000ULL;failEvery=n%5==0?3:0;
                NSDictionary *options=@{@"visible_only":@((n&1)!=0),@"clickable_only":@((n&2)!=0),
                    @"max_elements":@(1+n%7),@"max_scanned_elements":@(1+n%11)};
                NSDictionary *value=nodePoolCall(current,options);
                if(current){
                    assert([value isEqual:expected]);
                    NSData *oldJSON=[NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingSortedKeys error:NULL];
                    NSData *newJSON=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:NULL];
                    assert(oldJSON&&[newJSON isEqual:oldJSON]);
                }else expected=value;
                assert(rootRetains==rootDrops);
            }
            assert(!returnedArray);
        }
    }
}
static void nodePoolFilteredCases(){
    for(unsigned kind=0;kind<3;++kind){
        for(bool current:{false,true}){
            TLinkAXFixtureResetOwners();
            @autoreleasepool{
                reset();trackNodeOwners=true;sourceCount=128;
                if(kind==0)forceHidden=true;
                if(kind==1)forceNotClickable=true;
                if(kind==2)failEvery=1;
                NSDictionary *value=nodePoolCall(current,@{@"clickable_only":@YES});
                assert([value[@"count"] unsignedIntValue]==0&&serialized==128);
                assert([value[@"serialization_failure_count"] unsignedIntValue]==(kind==2?128U:0U));
                nodePoolOwnerCounts(current?0:128,current?1:128,128,current?128:0,current?"current filtered":"preceding filtered");
                assert(rootRetains==rootDrops);
            }
            assert(!returnedArray&&TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==128);
        }
    }
}
static void nodePoolAcceptedLifetime(){
    for(bool current:{false,true}){
        TLinkAXFixtureResetOwners();NSDictionary *held=nil;
        @autoreleasepool{
            reset();trackNodeOwners=true;sourceCount=12;held=nodePoolCall(current);
            assert([held[@"count"] unsignedIntValue]==6&&serialized==12);
            nodePoolOwnerCounts(current?6:12,current?7:12,12,current?6:0,current?"current mixed":"preceding mixed");
        }
        assert(!returnedArray&&TLinkAXFixtureLiveOwners()==6&&TLinkAXFixtureDroppedOwners()==6);
        @autoreleasepool{
            for(unsigned n=0;n<6;++n){
                NSDictionary *row=held[@"elements"][n];
                NSString *expected=[NSString stringWithFormat:@"node-%u",n*2];
                assert([row[@"index"] unsignedIntValue]==n*2&&[row[@"label"] isEqualToString:expected]&&row[@"fixture_owner"]);
            }
            held=nil;
        }
        assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==12);
    }
}
static void nodePoolExitCases(){
    // Return, break and continue drain normally. Use a rejected first row so
    // the caller-owned rows array cannot obscure the pool's lifetime effect.
    for(unsigned kind=0;kind<7;++kind){
        TLinkAXFixtureResetOwners();NSDictionary *held=nil;
        @autoreleasepool{
            reset();trackNodeOwners=true;sourceCount=1;
            if(kind==0)failEvery=1;
            if(kind==1)nodeCost=120000000ULL;
            if(kind==2)outputCap=1;
            if(kind==3)cancelAt=1;
            if(kind==4){forceHidden=true;cancelAt=1;}
            if(kind==5){forceHidden=true;sourceCount=8;}
            if(kind==6)outputCap=1024;
            held=nodePoolCall(true,@{@"timeout_ms":@100,@"visible_only":@(kind>=4),@"max_scanned_elements":@1});
            if(kind==2||kind==6)expectError(held,@"ui_response_too_large");
            else if(kind==3||kind==4)expectError(held,@"ui_cancelled_or_timed_out");
            else assert([held[@"partial"] boolValue]&&[held[@"count"] unsignedIntValue]==0);
            assert(serialized==1&&TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==1);
            assert(rootRetains==rootDrops);
        }
        assert(!returnedArray&&held&&!TLinkAXResultCompleteForAction(held));held=nil;
    }
    for(bool current:{false,true}){
        for(unsigned kind=0;kind<2;++kind){
            TLinkAXFixtureResetOwners();bool caught=false;
            @autoreleasepool{
                reset();trackNodeOwners=true;throwNode=kind==0;throwNodeCPP=kind==1;
                @try{try{
                    @autoreleasepool{nodePoolCall(current);}
                }catch(const std::runtime_error &){caught=kind==1;}}
                @catch(NSException *exception){caught=kind==0&&[exception.name isEqualToString:@"AXSnapshotFixture"];}
                assert(caught&&serialized==1&&rootRetains==rootDrops);
            }
            // Clang leaves exception-exited pools undrained; normal outer exit
            // drains them. Do not assert destruction inside either catch.
            assert(!returnedArray&&TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureCreatedOwners()==1&&TLinkAXFixtureDroppedOwners()==1);
        }
    }
}
static void nodePoolDrainDeadline(){
    for(bool current:{false,true}){
        TLinkAXFixtureResetOwners();
        @autoreleasepool{
            reset();trackNodeOwners=true;sourceCount=8;forceHidden=true;ownerDropCost=30000000ULL;
            NSDictionary *value=nodePoolCall(current,@{@"timeout_ms":@100});
            assert(serialized==(current?4U:8U)&&[value[@"count"] unsignedIntValue]==0);
            assert([value[@"duration_ms"] intValue]==(current?120:0));
            assert([value[@"partial"] boolValue]==current&&TLinkAXResultCompleteForAction(value)==!current);
            assert(TLinkAXFixtureLiveOwners()==(current?0U:8U));
        }
        assert(!returnedArray&&TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureCreatedOwners()==TLinkAXFixtureDroppedOwners());
    }
}
static void nodePoolCases(){
    std::puts("AX node pools: complete current/frozen loops and explicit MRC autorelease owners; AX/serializer/clock controlled");
    nodePoolGoldenCases();nodePoolFilteredCases();nodePoolAcceptedLifetime();nodePoolExitCases();nodePoolDrainDeadline();
    for(unsigned n=0;n<128;++n){
        TLinkAXFixtureResetOwners();
        @autoreleasepool{
            reset();trackNodeOwners=true;sourceCount=16;
            NSDictionary *value=nodePoolCall(true,@{@"visible_only":@NO,@"clickable_only":@((n&1)!=0)});
            assert([value[@"ok"] boolValue]&&TLinkAXFixtureCreatedOwners()==16&&rootRetains==rootDrops);
        }
        assert(!returnedArray&&TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==16);
    }
    reset();
    std::puts("AX node pools passed: 128 frozen full graph/JSON cases, hidden/unclickable/invalid peak 1 versus 128, accepted-row/label lifetime, normal continue/break/error returns, NS/C++ outer drain, cleanup-time deadline and 128 balanced lifecycles. Foundation allocation/RSS/AX/device gains remain unqualified.");
}
