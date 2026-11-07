NSDictionary *TLinkRunHistoryFinish(NSString *runId,
                                    NSString *state,
                                    NSString *error,
                                    NSArray<NSString *> *logTail,
                                    NSString *consoleLogPath,
                                    NSString *screenshotPath,
                                    NSString *screenshotError,
                                    NSDictionary *extra)
{
    if (runId.length == 0) return @{};
    @synchronized (TLinkRunHistoryLock()) {
        TLinkRunHistoryEnsureDirectories();
        // Preparation is process-serialized, but does not hold the shared file lock.
        NSString *terminalState = state.length > 0 ? state : @"finished";
        NSString *redactedError = TLinkRunHistoryRedactText(error ?: @"");
        if (redactedError.length > kTLinkFailureErrorMaxCharacters) {
            redactedError = [redactedError substringToIndex:kTLinkFailureErrorMaxCharacters];
        }
        BOOL failed = [terminalState isEqualToString:@"failed"] || [terminalState isEqualToString:@"license_revoked"];
        NSArray *tail = @[];
        if (failed) {
            tail = TLinkRunHistoryBoundedLogTail(logTail);
            if (tail.count == 0) tail = TLinkRunHistoryTailFromConsoleFile(consoleLogPath);
        }
        int lockFd = TLinkRunHistoryAcquireFileLock();
        if (lockFd < 0) { TLinkRunHistoryPersistenceFailure(@"finish", @"lock", @"history_lock_failed"); return @{}; }
        NSMutableDictionary *record = nil;
        NSString *stage = @"read";
        @try { try {
            NSMutableArray<NSDictionary *> *runs = TLinkRunHistoryReadCheckedIndex(@"finish");
            if (!runs) return @{};
            stage = @"recovery";
            if (!TLinkRunHistoryPrepareRecovery(runs, @"finish", lockFd)) return @{};
            stage = @"prepare";
            NSUInteger index = [runs indexOfObjectPassingTest:^BOOL(NSDictionary *record, NSUInteger idx, BOOL *stop) {
                (void)idx;
                if ([record[@"run_id"] isEqualToString:runId]) { *stop = YES; return YES; }
                return NO;
            }];
            record = index != NSNotFound ? [runs[index] mutableCopy] : [NSMutableDictionary dictionary];
            uint64_t endedAt = TLinkRunHistoryNowMs();
            uint64_t startedAt = [record[@"started_at_ms"] unsignedLongLongValue];
            record[@"schema"] = TLinkRunHistorySchemaV1;
            record[@"run_id"] = runId;
            record[@"state"] = terminalState;
            record[@"ended_at_ms"] = @(endedAt);
            record[@"duration_ms"] = @(TLinkRunHistoryDuration(runId, startedAt, endedAt));
            record[@"error"] = redactedError;
            if (extra.count > 0) record[@"extra"] = extra;

            stage = @"intent";
            if (!TLinkRunHistorySetPending(lockFd, YES, @"finish", stage)) return @{};
            if (failed) {
                stage = @"evidence";
                NSString *metadataPath = [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.json", TLinkRunHistorySanitize(runId)]];
                NSDictionary *screenshotAttributes = screenshotPath.length > 0
                    ? [[NSFileManager defaultManager] attributesOfItemAtPath:screenshotPath error:nil] : nil;
                BOOL screenshotPresent = [screenshotAttributes fileSize] > 0;
                if (screenshotPresent) {
                    chmod(screenshotPath.fileSystemRepresentation, 0640);
                    lchown(screenshotPath.fileSystemRepresentation, 501, 501);
                }
                NSDictionary *evidence = @{
                    @"schema": TLinkFailureEvidenceSchemaV1,
                    @"run_id": runId,
                    @"captured_at_ms": @(endedAt),
                    @"error": redactedError,
                    @"log_tail": tail ?: @[],
                    @"log_tail_truncated": @([logTail isKindOfClass:[NSArray class]] && logTail.count > kTLinkFailureLogTailMaxLines),
                    @"console_log_path": consoleLogPath ?: @"",
                    @"screenshot_path": screenshotPresent ? screenshotPath : @"",
                    @"screenshot_captured": @(screenshotPresent),
                    @"screenshot_error": screenshotPresent ? @"" : (screenshotError ?: @"not_captured"),
                    @"metadata_path": metadataPath,
                };
                if (!TLinkRunHistoryWriteJSON(evidence, metadataPath)) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"write_failed"); return @{}; }
                record[@"failure_evidence"] = evidence;
            } else {
                record[@"failure_evidence"] = @{};
            }

            NSString *recordPath = [record[@"record_path"] isKindOfClass:[NSString class]] ? record[@"record_path"] : @"";
            if (recordPath.length == 0) {
                recordPath = [TLinkRunHistoryRunsPath() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.json", TLinkRunHistorySanitize(runId)]];
                record[@"record_path"] = recordPath;
            }
            if (index != NSNotFound) [runs replaceObjectAtIndex:index withObject:record];
            else [runs insertObject:record atIndex:0];
            NSArray *retired = TLinkRunHistoryTrim(runs);
            stage = @"record";
            if (!TLinkRunHistoryWriteJSON(record, recordPath)) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"write_failed"); return @{}; }
            stage = @"index";
            if (!TLinkRunHistoryWriteIndex(runs)) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"write_failed"); return @{}; }
            TLinkRunHistoryForgetElapsed(runId);
            stage = @"commit_marker";
            (void)TLinkRunHistorySetPending(lockFd, NO, @"finish", stage);
            TLinkRunHistoryPrune(retired, runs);
        } catch (...) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"exception"); return @{}; } }
        @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"exception"); return @{}; }
        @finally { TLinkRunHistoryReleaseFileLock(lockFd); }
        TLinkEventChannelPublish(record[@"runtime"] ?: @"unknown",
                                 @"script.run",
                                 terminalState,
                                 @{
                                     @"run_id": runId,
                                     @"state": terminalState,
                                     @"duration_ms": record[@"duration_ms"] ?: @0,
                                     @"error": redactedError ?: @"",
                                     @"evidence_available": @([record[@"failure_evidence"] count] > 0),
                                 });
        return record;
    }
}

