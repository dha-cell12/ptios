static void TLinkRunHistoryPrune(NSArray<NSDictionary *> *retired, NSArray<NSDictionary *> *runs)
{
    if (retired.count == 0) return;
    @try { try {
        NSMutableSet<NSString *> *retained = [NSMutableSet set];
        for (NSDictionary *record in runs) {
            NSDictionary *evidence = [record[@"failure_evidence"] isKindOfClass:[NSDictionary class]] ? record[@"failure_evidence"] : @{};
            for (id path in @[record[@"record_path"] ?: @"", evidence[@"metadata_path"] ?: @"", evidence[@"screenshot_path"] ?: @""]) {
                if ([path isKindOfClass:[NSString class]] && [path length] > 0) [retained addObject:[path stringByStandardizingPath]];
            }
        }
        for (NSDictionary *oldest in retired) {
            @try { try {
                NSString *runId = [oldest[@"run_id"] isKindOfClass:[NSString class]] ? oldest[@"run_id"] : @"";
                if (runId.length == 0) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"path_not_owned"); continue; }
                NSString *name = TLinkRunHistorySanitize(runId);
                TLinkRunHistoryPruneArtifact(oldest[@"record_path"], [TLinkRunHistoryRunsPath() stringByAppendingPathComponent:[name stringByAppendingString:@".json"]], retained);
                NSDictionary *evidence = [oldest[@"failure_evidence"] isKindOfClass:[NSDictionary class]] ? oldest[@"failure_evidence"] : @{};
                TLinkRunHistoryPruneArtifact(evidence[@"metadata_path"], [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[name stringByAppendingString:@".json"]], retained);
                TLinkRunHistoryPruneArtifact(evidence[@"screenshot_path"], [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[name stringByAppendingString:@".png"]], retained);
            } catch (...) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); } }
            @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); }
        }
    } catch (...) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); } }
    @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); }
}

