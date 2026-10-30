// C03y: actual admission/permission code with real filesystem identity and
// controlled mode/uid/gid plus permission syscalls (no host ownership changes).
static void historyPermissionPass(BOOL shared){
    Current::TLinkRunHistoryEnsureDirectories();
    const int fd=Current::TLinkRunHistoryAcquireFileLock(shared);assert(fd>=0);
    Current::TLinkRunHistoryReleaseFileLock(fd);
    assert(historyLocks.empty()&&historyLockFds.empty());
}
static void historyPermissionReset(unsigned mask){
    for(unsigned n=0;n<4;++n){
        historyPermissionState[n]={n==3?(mode_t)0640:(mode_t)0750,501,501};
        if(mask&(1U<<(2*n)))historyPermissionState[n].mode|=07000;
        if(mask&(2U<<(2*n))){historyPermissionState[n].uid=502;historyPermissionState[n].gid=503;}
    }
    [historyPermissionRepairs removeAllObjects];
}
static void historyConditionalPermissionCases(){
    fputs("History permission Foundation: actual validated admission, conditional mode/owner repair and retry\n",stderr);
    NSString *savedRoot=Current::fixtureRoot,*legacyRoot=Legacy::fixtureRoot;
    const BOOL savedReady=Current::sTLinkRunHistoryRecovered;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"conditional-history-permissions"];
    assert([Current::TLinkRunHistorySnapshot(0)[@"state"] isEqualToString:@"implemented"]);
    historyPermissionTargets=@[Current::fixtureRoot,Current::TLinkRunHistoryRunsPath(),Current::TLinkRunHistoryEvidencePath(),[Current::fixtureRoot stringByAppendingPathComponent:@"history.lock"]];
    historyPermissionRepairs=[NSMutableArray array];historyPermissionReset(0);
    const size_t markers=historyMarkerChanges;const NSUInteger writes=historyWriteAttempts.count,events=historyEvents.count;
    // Every combination across three directories and the stable lock. Mode repair
    // includes sticky/set-ID bits, and both lock modes use identical predicates.
    for(unsigned mask=0;mask<256;++mask){
        historyPermissionReset(mask);NSMutableArray *expected=[NSMutableArray array];
        for(unsigned n=0;n<4;++n){
            if(mask&(1U<<(2*n)))[expected addObject:[NSString stringWithFormat:@"mode:%u",n]];
            if(mask&(2U<<(2*n)))[expected addObject:[NSString stringWithFormat:@"owner:%u",n]];
        }
        historyPermissionPass((mask&1)?YES:NO);
        assert([historyPermissionRepairs isEqualToArray:expected]);
        [historyPermissionRepairs removeAllObjects];historyPermissionPass((mask&1)?NO:YES);
        assert(!historyPermissionRepairs.count);
    }
    // UID-only or GID-only changes still require an ownership repair.
    for(unsigned n=0;n<4;++n)for(unsigned field=0;field<2;++field){
        historyPermissionReset(0);if(field)historyPermissionState[n].gid=502;else historyPermissionState[n].uid=502;
        historyPermissionPass(YES);NSString *expected=[NSString stringWithFormat:@"owner:%u",n];
        assert(historyPermissionRepairs.count==1&&[historyPermissionRepairs[0] isEqualToString:expected]);
    }
    // The post-flock metadata decides lock repairs, even if it changes while waiting.
    historyPermissionReset(0);
    historyAfterLock=[]{historyPermissionState[3].mode=0600;historyPermissionState[3].uid=502;};
    historyPermissionPass(YES);historyAfterLock={};
    NSArray *lockRepairs=@[@"mode:3",@"owner:3"];assert([historyPermissionRepairs isEqualToArray:lockRepairs]);
    // Failed best-effort calls remain eligible on the next operation; no success cache.
    for(unsigned failure:{1U,2U,4U,8U}){
        historyPermissionReset(255);historyPermissionFailureMask=failure;historyPermissionPass(NO);
        assert(historyPermissionRepairs.count==8);[historyPermissionRepairs removeAllObjects];historyPermissionPass(YES);
        NSArray *retry=[historyPermissionRepairs copy];assert(retry.count==(failure<4?3U:1U));
        [historyPermissionRepairs removeAllObjects];historyPermissionFailureMask=0;historyPermissionPass(NO);
        assert([historyPermissionRepairs isEqualToArray:retry]);
        [historyPermissionRepairs removeAllObjects];historyPermissionPass(YES);assert(!historyPermissionRepairs.count);
    }
    assert(historyMarkerChanges==markers&&historyWriteAttempts.count==writes&&historyEvents.count==events);
    // Controlled syscall evidence: original public status does eight permission
    // calls, updated status does none when every observed mode/owner is correct.
    historyPermissionReset(0);Legacy::fixtureRoot=Current::fixtureRoot;
    assert([Legacy::TLinkRunHistorySnapshot(0)[@"state"] isEqualToString:@"implemented"]);
    assert(historyPermissionRepairs.count==8);[historyPermissionRepairs removeAllObjects];
    const size_t reads=historyIndexReads;
    for(unsigned n=0;n<128;++n)assert([Current::TLinkRunHistorySnapshot(0)[@"state"] isEqualToString:@"implemented"]);
    assert(!historyPermissionRepairs.count&&historyIndexReads==reads+128&&historyMarkerChanges==markers);
    assert(historyMutation(true).count&&historyMutation(false).count&&!historyPermissionRepairs.count);
    assert(historyLocks.empty()&&historyLockFds.empty());
    historyPermissionTargets=nil;historyPermissionRepairs=nil;
    Current::fixtureRoot=savedRoot;Legacy::fixtureRoot=legacyRoot;Current::sTLinkRunHistoryRecovered=savedReady;
    puts("History permissions passed: 256 mode/owner combinations, UID/GID-only drift, post-flock repair selection, four failure/retry classes, actual status eight-to-zero controlled permission calls, 128 uncached reads and normal writer ACK. Identity checks remain real; ownership syscalls controlled, device IO qualification pending.");
}
