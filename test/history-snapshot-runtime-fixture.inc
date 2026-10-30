// C03t: actual public status must preserve failed persistence authority and recovery state.
static void historySnapshotRejected(NSString *code,NSString *stage) {
    NSString *root=Current::fixtureRoot,*lock=[root stringByAppendingPathComponent:@"history.lock"];
    NSDictionary *files=historyDiskBytes(root);const NSUInteger writes=historyWriteAttempts.count,events=historyEvents.count;
    const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
    const BOOL recovered=Current::sTLinkRunHistoryRecovered;
    const size_t recoveryOpens=historyRecoveryOpens,markers=historyMarkerChanges;
    NSDictionary *reply=Current::TLinkRunHistorySnapshot(50);
    assert([reply[@"schema"] isEqualToString:@"run_history_v1"]&&[reply[@"state"] isEqualToString:@"error"]&&[reply[@"error"] isEqualToString:code]);
    assert([reply[@"runs"] count]==0&&[reply[@"total_count"] intValue]==0&&[reply[@"failed_count"] intValue]==0);
    assert([reply[@"retention_max_runs"] intValue]==50&&[reply[@"status_log_tail_max_lines"] intValue]==3);
    NSDictionary *diagnostics=reply[@"persistence_diagnostics"],*last=diagnostics[@"last_failure"];
    assert([diagnostics[@"failure_count"] unsignedLongLongValue]==(failures==UINT64_MAX?failures:failures+1));
    assert([last[@"operation"] isEqualToString:@"snapshot"]&&[last[@"stage"] isEqualToString:stage]);
    assert(Current::sTLinkRunHistoryRecovered==recovered&&historyRecoveryOpens==recoveryOpens&&historyMarkerChanges==markers);
    assert(historyWriteAttempts.count==writes&&historyEvents.count==events&&[files isEqual:historyDiskBytes(root)]);
    assert(historyLocks.empty()&&historyRecoveryFds.empty()&&historyChildCanLock(lock));
    assert([NSJSONSerialization isValidJSONObject:reply]);
}
static void historyCheckedSnapshotCases() {
    fputs("History checked snapshot Foundation: shared index validation, fixed errors and unchanged files/recovery\n",stderr);
    NSString *savedRoot=Current::fixtureRoot;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"checked-snapshot"];
    NSFileManager *fm=[NSFileManager defaultManager];NSString *path=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
    const BOOL recovered=Current::sTLinkRunHistoryRecovered;
    const size_t opens=historyRecoveryOpens,markers=historyMarkerChanges;
    NSDictionary *empty=Current::TLinkRunHistorySnapshot(0);
    assert([empty[@"state"] isEqualToString:@"implemented"]&&[empty[@"runs"] count]==0&&![fm fileExistsAtPath:path]);
    assert(Current::sTLinkRunHistoryRecovered==recovered&&historyRecoveryOpens==opens&&historyMarkerChanges==markers);
    NSArray *invalid=@[@"",@"not-json",@"null",@"[]",@"{}",@"{\"runs\":[]}",
        @"{\"schema\":\"future\",\"runs\":[]}",@"{\"schema\":1,\"runs\":[]}",
        @"{\"schema\":\"run_history_v1\",\"runs\":42}",@"{\"schema\":\"run_history_v1\",\"runs\":null}",
        @"{\"schema\":\"run_history_v1\",\"runs\":[42]}",@"{\"schema\":\"run_history_v1\",\"runs\":[null]}",
        @"{\"schema\":\"run_history_v1\",\"runs\":[{}]}",@"{\"schema\":\"run_history_v1\",\"runs\":[{\"run_id\":42}]}",
        @"{\"schema\":\"run_history_v1\",\"runs\":[{\"run_id\":\"\"}]}",
        @"{\"schema\":\"run_history_v1\",\"runs\":[{\"run_id\":\"same\"},{\"run_id\":\"same\"}]}"];
    for(NSString *text in invalid) @autoreleasepool {
        assert([[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
        historySnapshotRejected(@"history_snapshot_invalid_index",@"read");
    }
    NSData *healthy=[@"{\"schema\":\"run_history_v1\",\"runs\":[],\"extension\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    assert([healthy writeToFile:path atomically:YES]);
    for(unsigned fault=1;fault<=3;++fault){historySnapshotReadFault=fault;historySnapshotRejected(@"history_snapshot_read_failed",@"read");historySnapshotReadFault=0;}
    for(unsigned fault=1;fault<=2;++fault){historyReadFault=fault;historySnapshotRejected(@"history_snapshot_exception",@"read");historyReadFault=0;}
    for(bool cpp:{false,true}){
        historyStatusHook=[cpp]{assert(historyLocks.empty());if(cpp)throw std::runtime_error("snapshot format failed");[NSException raise:@"HistoryFixture" format:@"snapshot format failed"];};
        historySnapshotRejected(@"history_snapshot_exception",@"format");historyStatusHook={};
    }
    const size_t reads=historyIndexReads;historyLockDenied=true;historySnapshotRejected(@"history_snapshot_lock_failed",@"lock");historyLockDenied=false;
    assert(historyIndexReads==reads);
    assert([fm removeItemAtPath:path error:nil]&&[fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
    historySnapshotRejected(@"history_snapshot_read_failed",@"read");
    assert([fm removeItemAtPath:path error:nil]&&[healthy writeToFile:path atomically:YES]);
    // A valid envelope with an unusable formatting field fails without leaking an exception.
    NSData *badState=[@"{\"schema\":\"run_history_v1\",\"runs\":[{\"run_id\":\"bad-state\",\"state\":42}]}" dataUsingEncoding:NSUTF8StringEncoding];
    assert([badState writeToFile:path atomically:YES]);historySnapshotRejected(@"history_snapshot_exception",@"format");
    assert([healthy writeToFile:path atomically:YES]);
    const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
    NSDictionary *restored=Current::TLinkRunHistorySnapshot(0);
    assert([restored[@"state"] isEqualToString:@"implemented"]&&!restored[@"error"]&&Current::sTLinkRunHistoryPersistenceFailures==failures);
    assert([healthy isEqual:[NSData dataWithContentsOfFile:path]]&&Current::sTLinkRunHistoryRecovered==recovered);
    assert(historyRecoveryOpens==opens&&historyMarkerChanges==markers);
    Current::fixtureRoot=savedRoot;
    puts("History checked snapshot passed: missing/valid empty bootstrap, 16 schema/identity failures, read domain/permission/nil-error, lock denial with zero index reads, NS/C++ read/format faults, real directory, malformed state, fixed JSON error envelopes and explicit repair. No writes/events/marker/recovery effects; device qualification pending.");
}
