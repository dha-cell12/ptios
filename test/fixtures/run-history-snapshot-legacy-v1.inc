// Frozen C03s snapshot from c20c70d9; successful fields and old failure behavior.
NSDictionary *TLinkRunHistorySnapshot(NSUInteger limit)
{
    @synchronized (TLinkRunHistoryLock()) {
        TLinkRunHistoryEnsureDirectories();
        int lockFd = TLinkRunHistoryAcquireFileLock();
        NSMutableArray<NSDictionary *> *runs = nil;
        @try {
            runs = TLinkRunHistoryReadIndex();
        } @finally {
            TLinkRunHistoryReleaseFileLock(lockFd);
        }
        // The decoded graph belongs to this call; formatting needs no file lock.
        NSUInteger bounded = limit == 0 ? kTLinkRunHistorySnapshotDefault : MIN(limit, kTLinkRunHistorySnapshotMax);
        NSArray *selected = runs.count > bounded ? [runs subarrayWithRange:NSMakeRange(0, bounded)] : [runs copy];
        NSMutableArray<NSDictionary *> *statusRuns = [NSMutableArray arrayWithCapacity:selected.count];
        for (NSDictionary *source in selected) {
            NSMutableDictionary *run = [source mutableCopy];
            NSString *sourceError = [source[@"error"] isKindOfClass:[NSString class]] ? source[@"error"] : @"";
            if (sourceError.length > kTLinkStatusErrorMaxCharacters) {
                run[@"error"] = [sourceError substringToIndex:kTLinkStatusErrorMaxCharacters];
                run[@"status_error_truncated"] = @YES;
            }
            NSDictionary *sourceEvidence = [source[@"failure_evidence"] isKindOfClass:[NSDictionary class]]
                ? source[@"failure_evidence"] : @{};
            if (sourceEvidence.count > 0) {
                NSMutableDictionary *evidence = [sourceEvidence mutableCopy];
                NSString *evidenceError = [sourceEvidence[@"error"] isKindOfClass:[NSString class]]
                    ? sourceEvidence[@"error"] : @"";
                if (evidenceError.length > kTLinkStatusErrorMaxCharacters) {
                    evidence[@"error"] = [evidenceError substringToIndex:kTLinkStatusErrorMaxCharacters];
                    evidence[@"status_error_truncated"] = @YES;
                }
                NSArray *sourceTail = [sourceEvidence[@"log_tail"] isKindOfClass:[NSArray class]]
                    ? sourceEvidence[@"log_tail"] : @[];
                NSUInteger start = sourceTail.count > kTLinkStatusLogTailMaxLines
                    ? sourceTail.count - kTLinkStatusLogTailMaxLines : 0;
                NSMutableArray<NSString *> *tail = [NSMutableArray array];
                for (NSUInteger index = start; index < sourceTail.count; index++) {
                    NSString *line = [sourceTail[index] isKindOfClass:[NSString class]]
                        ? sourceTail[index] : [sourceTail[index] description];
                    if (line.length > kTLinkStatusLogLineMaxCharacters) {
                        line = [line substringToIndex:kTLinkStatusLogLineMaxCharacters];
                    }
                    [tail addObject:line ?: @""];
                }
                evidence[@"log_tail"] = tail;
                evidence[@"status_log_tail_truncated"] = @(sourceTail.count > tail.count);
                run[@"failure_evidence"] = evidence;
            }
            [statusRuns addObject:run];
        }
        NSUInteger failed = 0;
        for (NSDictionary *run in runs) {
            NSString *state = run[@"state"];
            if ([state isEqualToString:@"failed"] || [state isEqualToString:@"license_revoked"]) failed++;
        }
        NSDictionary *snapshot = @{
            @"schema": TLinkRunHistorySchemaV1,
            @"state": @"implemented",
            @"root_path": TLinkRunHistoryRootPath(),
            @"persistence_diagnostics": @{@"scope": @"process", @"failure_count": @(sTLinkRunHistoryPersistenceFailures), @"last_failure": sTLinkRunHistoryLastPersistenceFailure ?: @{}},
            @"retention_max_runs": @(kTLinkRunHistoryMaxRecords),
            @"failure_log_tail_max_lines": @(kTLinkFailureLogTailMaxLines),
            @"failure_error_max_characters": @(kTLinkFailureErrorMaxCharacters),
            @"status_log_tail_max_lines": @(kTLinkStatusLogTailMaxLines),
            @"status_log_line_max_characters": @(kTLinkStatusLogLineMaxCharacters),
            @"status_error_max_characters": @(kTLinkStatusErrorMaxCharacters),
            @"failure_console_read_max_bytes": @(kTLinkFailureConsoleLogMaxBytes),
            @"total_count": @(runs.count),
            @"failed_count": @(failed),
            @"runs": statusRuns,
        };
        return snapshot;
    }
}
