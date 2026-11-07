NSDictionary *TLinkRunHistoryBegin(NSString *runtime,
                                   NSString *bundlePath,
                                   NSString *entryPath,
                                   NSDictionary *playSettings)
{
    @synchronized (TLinkRunHistoryLock()) {
        TLinkRunHistoryEnsureDirectories();
        int lockFd = TLinkRunHistoryAcquireFileLock();
        if (lockFd < 0) { TLinkRunHistoryPersistenceFailure(@"begin", @"lock", @"history_lock_failed"); return @{}; }
        NSString *runId = nil;
        NSDictionary *record = nil;
        NSString *stage = @"prepare";
        @try { try {
            runId = [NSUUID UUID].UUIDString.lowercaseString;
            uint64_t now = TLinkRunHistoryNowMs();
            uint64_t monotonicStarted = TLinkRunHistoryMonotonicMs();
            NSString *recordPath = [TLinkRunHistoryRunsPath() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@.json", TLinkRunHistorySanitize(runId)]];
            record = @{
                @"schema": TLinkRunHistorySchemaV1,
                @"run_id": runId,
                @"runtime": runtime ?: @"unknown",
                @"bundle_path": bundlePath ?: @"",
                @"entry_path": entryPath ?: @"",
                @"state": @"running",
                @"started_at_ms": @(now),
                @"ended_at_ms": @0,
                @"duration_ms": @0,
                @"error": @"",
                @"play_settings": [playSettings isKindOfClass:[NSDictionary class]] ? playSettings : @{},
                @"failure_evidence": @{},
                @"record_path": recordPath,
            };
            stage = @"read";
            NSMutableArray *runs = TLinkRunHistoryReadCheckedIndex(@"begin");
            if (!runs) return @{};
            stage = @"recovery";
            if (!TLinkRunHistoryPrepareRecovery(runs, @"begin", lockFd)) return @{};
            [runs insertObject:record atIndex:0];
            NSArray *retired = TLinkRunHistoryTrim(runs);
            stage = @"intent";
            if (!TLinkRunHistorySetPending(lockFd, YES, @"begin", stage)) return @{};
            stage = @"record";
            if (!TLinkRunHistoryWriteJSON(record, recordPath)) { TLinkRunHistoryPersistenceFailure(@"begin", stage, @"write_failed"); return @{}; }
            stage = @"index";
            if (!TLinkRunHistoryWriteIndex(runs)) { TLinkRunHistoryPersistenceFailure(@"begin", stage, @"write_failed"); return @{}; }
            TLinkRunHistoryRememberElapsed(runId, now, monotonicStarted);
            stage = @"commit_marker";
            (void)TLinkRunHistorySetPending(lockFd, NO, @"begin", stage);
            TLinkRunHistoryPrune(retired, runs);
        } catch (...) { TLinkRunHistoryPersistenceFailure(@"begin", stage, @"exception"); return @{}; } }
        @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"begin", stage, @"exception"); return @{}; }
        @finally { TLinkRunHistoryReleaseFileLock(lockFd); }
        TLinkEventChannelPublish(runtime ?: @"unknown",
                                 @"script.run",
                                 @"started",
                                 @{
                                     @"run_id": runId,
                                     @"bundle_path": bundlePath ?: @"",
                                     @"entry_path": entryPath ?: @"",
                                 });
        return record;
    }
}

