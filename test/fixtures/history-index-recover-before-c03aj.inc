static BOOL TLinkRunHistoryRecover(NSArray<NSDictionary *> *runs, NSString *operation)
{
    if (sTLinkRunHistoryRecovered) return YES;
    // Preflight the whole repair set before touching any file. Never follow
    // persisted paths outside the exact per-ID locations or alias two IDs.
    BOOL valid = runs.count <= kTLinkRunHistoryMaxRecords;
    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    for (NSDictionary *record in runs) {
        NSString *runId = record[@"run_id"];
        NSString *name = [TLinkRunHistorySanitize(runId) stringByAppendingString:@".json"];
        NSString *recordPath = [TLinkRunHistoryRunsPath() stringByAppendingPathComponent:name];
        id evidence = record[@"failure_evidence"];
        valid = valid && [record[@"schema"] isEqual:TLinkRunHistorySchemaV1] &&
            [record[@"record_path"] isKindOfClass:[NSString class]] && [record[@"record_path"] isEqual:recordPath] &&
            ![paths containsObject:recordPath] && [evidence isKindOfClass:[NSDictionary class]];
        if (valid && [evidence count] > 0) {
            NSString *metadataPath = [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:name];
            valid = [evidence[@"schema"] isEqual:TLinkFailureEvidenceSchemaV1] &&
                [evidence[@"run_id"] isEqual:runId] && [evidence[@"metadata_path"] isEqual:metadataPath];
        }
        if (!valid) break;
        [paths addObject:recordPath];
    }
    if (!valid) { TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_invalid_index"); return NO; }
    for (NSString *directory in @[TLinkRunHistoryRootPath(), TLinkRunHistoryRunsPath(), TLinkRunHistoryEvidencePath()]) {
        struct stat info;
        if (lstat(directory.fileSystemRepresentation, &info) != 0 || !S_ISDIR(info.st_mode)) {
            TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed");
            return NO;
        }
    }
    for (NSDictionary *record in runs) {
        @autoreleasepool {
            NSDictionary *evidence = record[@"failure_evidence"];
            if (evidence.count > 0 && !TLinkRunHistoryRepairJSON(evidence, evidence[@"metadata_path"], operation)) return NO;
            if (!TLinkRunHistoryRepairJSON(record, record[@"record_path"], operation)) return NO;
        }
    }
    sTLinkRunHistoryRecovered = YES;
    return YES;
}

