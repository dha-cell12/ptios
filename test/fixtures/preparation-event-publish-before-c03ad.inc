NSDictionary *TLinkEventChannelPublish(NSString *runtime,
                                       NSString *topic,
                                       NSString *type,
                                       NSDictionary *payload)
{
    @synchronized (TLinkEventProcessLock()) {
        int lockFd = TLinkEventAcquireFileLock(NO, NO);
        if (lockFd < 0) return @{@"state": @"error", @"error": @"event_journal_lock_failed"};
        NSDictionary *event = nil;
        BOOL persisted = NO;
        @try { try {
            NSString *readError = nil;
            NSMutableDictionary *journal = TLinkEventReadJournal(&readError);
            if (!journal) return @{@"state": @"error", @"error": readError};
            NSMutableArray *events = [journal[@"events"] mutableCopy] ?: [NSMutableArray array];
            uint64_t sequence = [journal[@"next_sequence"] unsignedLongLongValue];
            if (sequence == UINT64_MAX) return @{@"state": @"error", @"error": @"event_journal_sequence_exhausted"};
            event = @{
                @"schema": TLinkEventSchemaV1,
                @"sequence": @(sequence),
                @"event_id": [NSUUID UUID].UUIDString.lowercaseString,
                @"timestamp_ms": @(TLinkEventNowMs()),
                @"runtime": TLinkEventToken(runtime, @"unknown"),
                @"topic": TLinkEventToken(topic, @"system"),
                @"type": TLinkEventToken(type, @"updated"),
                @"payload": TLinkEventBoundedPayload(payload),
            };
            [events addObject:event];
            while (events.count > kTLinkEventJournalMaxEvents) [events removeObjectAtIndex:0];
            journal[@"schema"] = TLinkEventChannelSchemaV1;
            journal[@"next_sequence"] = @(sequence + 1);
            journal[@"events"] = events;
            journal[@"updated_at_ms"] = @(TLinkEventNowMs());
            persisted = TLinkEventWriteJournal(journal);
        } catch (...) { return @{@"state": @"error", @"error": @"event_journal_exception"}; } }
        @catch (__unused NSException *exception) { return @{@"state": @"error", @"error": @"event_journal_exception"}; }
        @finally { TLinkEventReleaseFileLock(lockFd); }
        if (!persisted) return @{@"state": @"error", @"error": @"event_journal_write_failed"};
        notify_post(kTLinkEventNotification); // Wake hint only, after the journal commit and unlock.
        return event;
    }
}

