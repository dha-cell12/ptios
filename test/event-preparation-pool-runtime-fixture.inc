static void fixturePreparationRequire(bool condition,unsigned line){
    if(!condition)fprintf(stderr,"Event preparation pool failure line %u: created=%llu live=%llu dropped=%llu locks=%zu lockFDs=%zu journalFDs=%zu readFault=%u writeFault=%u\n",line,
        (unsigned long long)TLinkAXFixtureCreatedOwners(),(unsigned long long)TLinkAXFixtureLiveOwners(),(unsigned long long)TLinkAXFixtureDroppedOwners(),
        fixtureEventLocks.size(),fixtureEventFds.size(),fixtureJournalFds.size(),fixtureReadFault.load(),fixtureWriteFault.load());
    assert(condition);
}
#define PREPARATION_REQUIRE(condition) fixturePreparationRequire((condition),__LINE__)
static void fixturePreparationPoolCases(){
    NSString *path=TLinkEventJournalPath();NSData *saved=[NSData dataWithContentsOfFile:path];
    NSDictionary *heldEvent=nil,*heldStatus=nil;
    @autoreleasepool{
        TLinkAXFixtureResetOwners();fixtureTrackPreparationOwners=true;
        heldEvent=TLinkEventChannelPublish(@"Fixture",@"Script.Run",@"Updated",@{@"held":@"ảnh 😀"});
        PREPARATION_REQUIRE(heldEvent[@"sequence"]&&TLinkAXFixtureCreatedOwners()==2&&TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==2);
        heldStatus=TLinkEventChannelStatus();
        PREPARATION_REQUIRE([heldStatus[@"state"] isEqual:@"implemented"]&&TLinkAXFixtureCreatedOwners()==3&&TLinkAXFixtureDroppedOwners()==3&&TLinkAXFixtureLiveOwners()==0);
        fixtureTrackPreparationOwners=false;
    }
    assert([heldEvent[@"payload"][@"held"] isEqual:@"ảnh 😀"]&&[heldStatus[@"latest_cursor"] isEqual:heldEvent[@"sequence"]]);
    // The encoding phase may now drain inside its held flock. Read/public
    // witnesses still retire only after unlock.
    @autoreleasepool{
        TLinkAXFixtureResetOwners();fixtureTrackPreparationOwners=true;fixturePreparationReadOnly=true;
        NSDictionary *readHeld=TLinkEventChannelPublish(@"fixture",@"script.run",@"updated",@{});
        PREPARATION_REQUIRE(readHeld[@"sequence"]&&TLinkAXFixtureCreatedOwners()==1&&TLinkAXFixtureLiveOwners()==0);
        PREPARATION_REQUIRE([TLinkEventChannelStatus()[@"state"] isEqual:@"implemented"]&&TLinkAXFixtureCreatedOwners()==2&&TLinkAXFixtureLiveOwners()==0);
        fixtureTrackPreparationOwners=false;fixturePreparationReadOnly=false;
    }
    for(bool reading:{false,true}){
        for(unsigned kind:{1U,2U}){
            @autoreleasepool{
                TLinkAXFixtureResetOwners();fixtureTrackPreparationOwners=true;
                if(reading)fixtureReadFault=kind+3;else fixtureWriteFault=kind+1;
                NSDictionary *failure=TLinkEventChannelPublish(@"fixture",@"script.run",@"updated",@{});
                PREPARATION_REQUIRE([failure[@"error"] isEqual:@"event_journal_exception"]&&TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureCreatedOwners()==TLinkAXFixtureDroppedOwners());
                if(reading){
                    failure=TLinkEventChannelStatus();
                    PREPARATION_REQUIRE([failure[@"error"] isEqual:@"event_journal_exception"]&&TLinkAXFixtureLiveOwners()==0);
                }
                fixtureReadFault=fixtureWriteFault=0;fixtureTrackPreparationOwners=false;
                assert(fixtureEventLocks.empty()&&fixtureEventFds.empty()&&fixtureJournalFds.empty());
            }
        }
    }
    if(saved)assert([saved writeToFile:path atomically:YES]);else assert([[NSFileManager defaultManager] removeItemAtPath:path error:nil]);
    assert(TLinkAXFixtureLiveOwners()==0);
    puts("Event preparation pools passed: real POSIX/JSON publish/status retirement after unlock, held Unicode result graphs and handled NS/C++ read/write failures with zero pending witnesses/locks. Foundation allocation/device memory remains unqualified.");
}
#undef PREPARATION_REQUIRE
