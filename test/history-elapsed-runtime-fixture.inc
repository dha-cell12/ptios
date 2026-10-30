// C03ab: only duration uses an optional local elapsed clock; persisted epochs stay wall based.
static NSDictionary *historyElapsedBegin(uint64_t mono=100){
    historyClockMs.store(10000);historyMonotonicMs=mono;
    NSDictionary *start=Current::TLinkRunHistoryBegin(@"rootfull",@"bundle",@"elapsed.js",@{});
    assert(start.count&&[start[@"started_at_ms"] unsignedLongLongValue]==10000);return start;
}
static NSDictionary *historyElapsedFinish(NSDictionary *start,uint64_t wall,uint64_t mono){
    historyClockMs.store(wall);historyMonotonicMs=mono;
    return Current::TLinkRunHistoryFinish(start[@"run_id"],@"finished",@"",@[],@"",@"",nil,@{});
}
static void historyElapsedCases(){
    fputs("History elapsed Foundation: committed local tracking, wall jumps, authority and optional failures\n",stderr);
    NSString *savedRoot=Current::fixtureRoot;const uint64_t savedClock=historyClockMs.load();
    const BOOL savedReady=Current::sTLinkRunHistoryRecovered;
    const uint64_t savedFailures=Current::sTLinkRunHistoryPersistenceFailures;
    NSDictionary *savedLast=Current::sTLinkRunHistoryLastPersistenceFailure;
    TLinkRunElapsed<50> savedElapsed=Current::sTLinkRunHistoryElapsed;
    Current::sTLinkRunHistoryElapsed=TLinkRunElapsed<50>{};historyMonotonicOverride=true;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"monotonic-history"];
    for(uint64_t ended:{UINT64_C(5000),UINT64_C(900000),UINT64_C(10000)}){
        NSDictionary *start=historyElapsedBegin(),*done=historyElapsedFinish(start,ended,350);
        assert([done[@"duration_ms"] unsignedLongLongValue]==250&&[done[@"ended_at_ms"] unsignedLongLongValue]==ended);
        assert([done[@"started_at_ms"] isEqual:start[@"started_at_ms"]]&&Current::sTLinkRunHistoryElapsed.size()==0);
        assert([historyReadJSON(done[@"record_path"])[@"duration_ms"] unsignedLongLongValue]==250);
        NSDictionary *snapshot=Current::TLinkRunHistorySnapshot(0);
        assert([snapshot[@"runs"][0][@"duration_ms"] unsignedLongLongValue]==250);
        assert([historyEvents.lastObject[@"payload"][@"duration_ms"] unsignedLongLongValue]==250);
    }
    NSDictionary *start=historyElapsedBegin();Current::sTLinkRunHistoryElapsed=TLinkRunElapsed<50>{};
    assert([historyElapsedFinish(start,10250,999999)[@"duration_ms"] unsignedLongLongValue]==250); // restart/untracked
    start=historyElapsedBegin(UINT64_MAX);assert(Current::sTLinkRunHistoryElapsed.size()==0);
    assert([historyElapsedFinish(start,13000,500)[@"duration_ms"] unsignedLongLongValue]==3000);
    start=historyElapsedBegin();assert([historyElapsedFinish(start,12500,UINT64_MAX)[@"duration_ms"] unsignedLongLongValue]==2500);
    start=historyElapsedBegin();assert([historyElapsedFinish(start,12500,99)[@"duration_ms"] unsignedLongLongValue]==2500);
    // A cooperating actor replaces the authoritative start; a stale local clock cannot override it.
    start=historyElapsedBegin();NSString *index=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
    NSMutableDictionary *graph=[historyReadJSON(index) mutableCopy];NSMutableArray *runs=[graph[@"runs"] mutableCopy];
    NSMutableDictionary *changed=[runs[0] mutableCopy];changed[@"started_at_ms"]=@9000;runs[0]=changed;graph[@"runs"]=runs;
    assert([[NSJSONSerialization dataWithJSONObject:graph options:0 error:nil] writeToFile:index atomically:YES]);
    assert([historyElapsedFinish(start,13000,350)[@"duration_ms"] unsignedLongLongValue]==4000);
    // Rejected or uncertain finishes retain tracking until an acknowledged index write.
    NSArray *stages=@[@"record",@"index",@"index"];
    for(unsigned n=0;n<3;++n){
        start=historyElapsedBegin();historyWriteStage=stages[n];historyWriteFault=n==2?4:1;
        assert(!historyElapsedFinish(start,5000,200).count&&Current::sTLinkRunHistoryElapsed.size()==1);
        historyWriteFault=0;historyWriteStage=nil;
        assert([historyElapsedFinish(start,6000,450)[@"duration_ms"] unsignedLongLongValue]==350);
        assert(Current::sTLinkRunHistoryElapsed.size()==0);
    }
    historyWriteStage=@"index";historyWriteFault=1;
    historyClockMs.store(10000);historyMonotonicMs=100;
    assert(!Current::TLinkRunHistoryBegin(@"rootfull",@"bundle",@"rejected.js",@{}).count&&Current::sTLinkRunHistoryElapsed.size()==0);
    historyWriteFault=0;historyWriteStage=nil;
    for(unsigned fault=1;fault<=2;++fault){
        const uint64_t failures=Current::sTLinkRunHistoryPersistenceFailures;
        historyElapsedRememberFault=fault;start=historyElapsedBegin();historyElapsedRememberFault=0;
        assert(Current::sTLinkRunHistoryElapsed.size()==0&&Current::sTLinkRunHistoryPersistenceFailures==failures);
        assert([historyElapsedFinish(start,10123,800)[@"duration_ms"] unsignedLongLongValue]==123);
    }
    start=historyElapsedBegin();NSString *withNul=[start[@"run_id"] stringByAppendingString:@"\0suffix"];
    assert(Current::TLinkRunHistoryDuration(withNul,10000,5000)==0);
    Current::TLinkRunHistoryForgetElapsed(withNul);assert(Current::sTLinkRunHistoryElapsed.size()==1);
    assert([historyElapsedFinish(start,5000,350)[@"duration_ms"] unsignedLongLongValue]==250);
    assert(Current::sTLinkRunHistoryElapsed.size()==0&&historyLocks.empty()&&historyLockFds.empty());
    Current::sTLinkRunHistoryElapsed=std::move(savedElapsed);historyMonotonicOverride=false;historyClockMs.store(savedClock);
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=savedReady;
    Current::sTLinkRunHistoryPersistenceFailures=savedFailures;Current::sTLinkRunHistoryLastPersistenceFailure=savedLast;
    puts("History elapsed passed: forward/backward/paused wall clocks, persisted epochs/artifact/status/event duration parity, untracked/start-mismatch/invalid-clock fallback, record/index/post-write failures, retry/ACK retirement, NS/C++ optional registration failures and NUL identity fence. Cross-process/restart duration remains legacy fallback; device clock/sleep qualification pending.");
}
