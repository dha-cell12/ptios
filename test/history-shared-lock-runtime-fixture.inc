// C03w: real cross-process flock probes while actual reader/writer paths own the lock.
static void historySharedSnapshotLockCases(){
    fputs("History shared lock Foundation: actual snapshot/read and exclusive mutation admission\n",stderr);
    NSString *savedRoot=Current::fixtureRoot;
    const BOOL savedReady=Current::sTLinkRunHistoryRecovered;
    const uint64_t savedFailures=Current::sTLinkRunHistoryPersistenceFailures;
    NSDictionary *savedFailure=Current::sTLinkRunHistoryLastPersistenceFailure;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"shared-history-lock"];
    NSString *lock=[Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"];
    assert([Current::TLinkRunHistorySnapshot(0)[@"state"] isEqualToString:@"implemented"]);
    const size_t markers=historyMarkerChanges;const NSUInteger events=historyEvents.count,writes=historyWriteAttempts.count;
    // Independent open descriptions may hold shared locks together. Releasing one
    // must not admit a writer until the last reader has released its lock.
    for(unsigned n=0;n<32;++n){
        const int first=Current::TLinkRunHistoryAcquireFileLock(YES);assert(first>=0);
        const int second=Current::TLinkRunHistoryAcquireFileLock(YES);assert(second>=0);
        assert(historySharedLocks.size()==2&&historyChildCanLock(lock,LOCK_SH)&&!historyChildCanLock(lock));
        Current::TLinkRunHistoryReleaseFileLock(first);
        assert(historySharedLocks.size()==1&&!historyChildCanLock(lock));
        Current::TLinkRunHistoryReleaseFileLock(second);
        assert(historySharedLocks.empty()&&historyLocks.empty()&&historyChildCanLock(lock));
    }
    unsigned reads=0;
    historyIndexLockHook=[&reads,lock]{
        ++reads;assert(historySharedLocks.size()==1);
        assert(historyChildCanLock(lock,LOCK_SH)&&!historyChildCanLock(lock));
    };
    for(unsigned n=0;n<8;++n){
        NSDictionary *reply=Current::TLinkRunHistorySnapshot(n);
        assert([reply[@"state"] isEqualToString:@"implemented"]&&[reply[@"total_count"] unsignedIntegerValue]==0);
        assert(historyLocks.empty()&&historySharedLocks.empty()&&historyLockFds.empty()&&historyIndexFds.empty());
    }
    // NS/C++ exceptions during the shared read must still release the lock.
    for(unsigned fault=1;fault<=2;++fault){
        historyReadFault=fault;NSDictionary *reply=Current::TLinkRunHistorySnapshot(0);historyReadFault=0;
        assert([reply[@"error"] isEqualToString:@"history_snapshot_exception"]);
        assert(historyLocks.empty()&&historySharedLocks.empty()&&historyLockFds.empty()&&historyIndexFds.empty()&&historyChildCanLock(lock));
    }
    historyIndexLockHook={};assert(reads==10);
    assert(historyMarkerChanges==markers&&historyEvents.count==events&&historyWriteAttempts.count==writes);
    // Public begin/failed finish retain exclusive admission and block both peer modes.
    unsigned mutations=0;
    historyAfterLock=[&mutations,lock]{
        ++mutations;assert(historyLocks.size()==1&&historySharedLocks.empty());
        assert(!historyChildCanLock(lock,LOCK_SH)&&!historyChildCanLock(lock));
    };
    assert(historyMutation(true).count&&historyMutation(false).count);historyAfterLock={};assert(mutations==2);
    assert(historyPendingSize()==0&&historyLocks.empty()&&historySharedLocks.empty()&&historyLockFds.empty());
    assert(historyChildCanLock(lock,LOCK_SH)&&historyChildCanLock(lock));
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=savedReady;
    Current::sTLinkRunHistoryPersistenceFailures=savedFailures;Current::sTLinkRunHistoryLastPersistenceFailure=savedFailure;
    puts("History shared lock passed: 32 paired-reader lifecycles, actual snapshot read admits peer readers and excludes writers, last-reader release, NS/C++ read unwind, unchanged read effects and public begin/failed finish exclude both peer modes. Device contention/latency qualification pending.");
}
