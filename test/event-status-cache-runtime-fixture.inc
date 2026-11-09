static NSDictionary *fixtureStatusComparable(NSDictionary *value){
    NSMutableDictionary *copy=[value mutableCopy];[copy removeObjectForKey:@"journal_read_count"];[copy removeObjectForKey:@"metadata_check_count"];return copy;
}
static void fixtureEventStatusMemoCases(){
    @autoreleasepool {
    puts("Event status memo Foundation: checked fresh files, frozen status graphs and exact-content decode reuse");
    NSString *path=TLinkEventJournalPath();NSData *saved=[NSData dataWithContentsOfFile:path];assert(saved);
    NSData *healthy=fixtureJournalData(fixtureJournal(8,@[fixtureStoredEvent(7)]));assert([healthy writeToFile:path atomically:YES]);TLinkEventStatusMemo().clear();
    const unsigned decodes=fixtureStatusDecodes.load(),reads=fixturePublishReads.load();
    for(unsigned n=0;n<129;++n){NSDictionary *value=TLinkEventChannelStatus();assert([value[@"state"] isEqual:@"implemented"]&&[value[@"latest_cursor"] unsignedLongLongValue]==7);}
    assert(fixtureStatusDecodes==decodes+1&&fixturePublishReads==reads+129&&TLinkEventStatusMemo().retainedBytes()==healthy.length);
    assert([fixtureStatusComparable(TLinkEventChannelStatus()) isEqual:fixtureStatusComparable(FixtureBeforeEventStatus())]);
    const unsigned stable=fixtureStatusDecodes.load();assert([healthy writeToFile:path atomically:YES]);TLinkEventChannelStatus();assert(fixtureStatusDecodes==stable);
    for(uint64_t next:{uint64_t(1),uint64_t(9),uint64_t(UINT64_MAX)}){
        NSData *changed=fixtureJournalData(fixtureJournal(next,@[]));assert([changed writeToFile:path atomically:YES]);
        NSDictionary *value=TLinkEventChannelStatus();assert([value[@"latest_cursor"] unsignedLongLongValue]==next-1);
        assert([fixtureStatusComparable(value) isEqual:fixtureStatusComparable(FixtureBeforeEventStatus())]);
        const unsigned warm=fixtureStatusDecodes.load();TLinkEventChannelStatus();assert(fixtureStatusDecodes==warm);
    }
    assert([healthy writeToFile:path atomically:YES]);
    for(unsigned fault:{1U,4U,5U}){
        TLinkEventChannelStatus();assert(TLinkEventStatusMemo().retainedBytes()>0);fixtureReadFault=fault;
        NSDictionary *value=TLinkEventChannelStatus();fixtureReadFault=0;
        assert([value[@"state"] isEqual:@"error"]&&[value[@"error"] isEqual:(fault==1?@"event_journal_read_failed":@"event_journal_exception")]&&TLinkEventStatusMemo().retainedBytes()==0);
        assert(fixtureEventLocks.empty()&&fixtureJournalFds.empty());
    }
    for(unsigned fault=1;fault<=2;++fault){
        TLinkEventStatusMemo().clear();fixtureStatusDecodeFault=fault;NSDictionary *value=TLinkEventChannelStatus();fixtureStatusDecodeFault=0;
        assert([value[@"error"] isEqual:@"event_journal_exception"]&&TLinkEventStatusMemo().retainedBytes()==0&&fixtureEventLocks.empty());
        fixtureStatusAllocationFault=fault;TLinkEventStatusMemo().clear();const unsigned before=fixtureStatusDecodes.load();
        for(unsigned n=0;n<2;++n){assert([TLinkEventChannelStatus()[@"state"] isEqual:@"implemented"]&&TLinkEventStatusMemo().retainedBytes()==0);}
        assert(fixtureStatusDecodes==before+2);fixtureStatusAllocationFault=0;
    }
    TLinkEventChannelStatus();assert(TLinkEventStatusMemo().retainedBytes()>0);
    NSData *bad=[@"not-json" dataUsingEncoding:NSUTF8StringEncoding];assert([bad writeToFile:path atomically:YES]);
    assert([TLinkEventChannelStatus()[@"error"] isEqual:@"event_journal_invalid"]&&TLinkEventStatusMemo().retainedBytes()==0);
    assert([fixtureStatusComparable(TLinkEventChannelStatus()) isEqual:fixtureStatusComparable(FixtureBeforeEventStatus())]);
    NSFileManager *fm=[NSFileManager defaultManager];assert([fm removeItemAtPath:path error:nil]);
    NSDictionary *missing=TLinkEventChannelStatus();assert([missing[@"state"] isEqual:@"implemented"]&&[missing[@"latest_cursor"] unsignedLongLongValue]==0&&TLinkEventStatusMemo().retainedBytes()==0);
    assert(![fm fileExistsAtPath:path]);assert([healthy writeToFile:path atomically:YES]);TLinkEventChannelStatus();
    assert([fm removeItemAtPath:path error:nil]&&[fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
    assert([TLinkEventChannelStatus()[@"error"] isEqual:@"event_journal_read_failed"]&&TLinkEventStatusMemo().retainedBytes()==0);
    assert([fm removeItemAtPath:path error:nil]);assert(::mkfifo(path.fileSystemRepresentation,0600)==0);
    assert([TLinkEventChannelStatus()[@"error"] isEqual:@"event_journal_read_failed"]&&TLinkEventStatusMemo().retainedBytes()==0);assert(::unlink(path.fileSystemRepresentation)==0);
    assert([healthy writeToFile:path atomically:YES]);TLinkEventChannelStatus();
    NSString *badRoot=[TLinkEventChannelRootPath() stringByAppendingPathComponent:@"status-bad-root"];
    assert([[NSData data] writeToFile:badRoot atomically:YES]);fixtureEventRootOverride=badRoot;
    assert([TLinkEventChannelStatus()[@"error"] isEqual:@"event_journal_unavailable"]&&TLinkEventStatusMemo().retainedBytes()==0);fixtureEventRootOverride=nil;assert([fm removeItemAtPath:badRoot error:nil]);
    NSMutableDictionary *large=[fixtureJournal(12,@[]) mutableCopy];large[@"padding"]=[@"x" stringByPaddingToLength:TLinkEventStatusCache::Limit+1 withString:@"x" startingAtIndex:0];
    assert([fixtureJournalData(large) writeToFile:path atomically:YES]);const unsigned beforeLarge=fixtureStatusDecodes.load();
    for(unsigned n=0;n<2;++n){assert([TLinkEventChannelStatus()[@"latest_cursor"] unsignedLongLongValue]==11&&TLinkEventStatusMemo().retainedBytes()==0);}
    assert(fixtureStatusDecodes==beforeLarge+2);assert([saved writeToFile:path atomically:YES]);TLinkEventStatusMemo().clear();
    assert(fixtureEventLocks.empty()&&fixtureJournalFds.empty());
    puts("Event status memo passed: frozen status/cursor graphs, 129 checked fresh reads with one decode, identical replacement hits, changed/zero/UINT64_MAX cursors, missing/corrupt/read/NS/C++/unsafe-root/type failures without stale success, allocation refusal fallback and uncached large journals. IO remains fresh; device performance pending.");
    }
}
