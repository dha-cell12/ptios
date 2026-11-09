NSDictionary *TLinkEventChannelStatus(void)
{
    @autoreleasepool {
    NSString *readError = nil;
    NSDictionary *journal = TLinkEventLoadSnapshot(NO, NULL, &readError);
    NSDictionary *batch = journal ? TLinkEventBatchFromJournal(journal, UINT64_MAX, [NSSet set], 1, NO) : @{};
    NSDictionary *status = @{
        @"schema": TLinkEventChannelSchemaV1, @"state": journal ? @"implemented" : @"error", @"transport": @"task95_long_poll_v1",
        @"journal_max_events": @(kTLinkEventJournalMaxEvents), @"poll_timeout_max_ms": @(kTLinkEventPollMaxTimeoutMs),
        @"poll_max_events": @(kTLinkEventPollMaxEvents), @"max_concurrent_polls": @(kTLinkEventMaxConcurrentPolls),
        @"latest_cursor": batch[@"latest_cursor"] ?: @0, @"active_polls": @(sTLinkEventActivePolls.load()),
        @"active_authorizations": @(sTLinkEventAuthorizations.load()), @"authorization_timeout_ms": @5000,
        @"journal_read_count": @(sTLinkEventJournalReads.load()), @"metadata_check_count": @(sTLinkEventMetadataChecks.load()),
        @"wait_strategy": @"darwin_notify_async_v1", @"reconcile_interval_ms": @(kTLinkEventReconcileMs),
        @"root_path": TLinkEventChannelRootPath(),
    };
    if (!journal) {
        NSMutableDictionary *failed = [status mutableCopy];
        failed[@"error"] = readError ?: @"event_journal_unavailable";
        return [failed copy];
    }
    return status;
    }
}
