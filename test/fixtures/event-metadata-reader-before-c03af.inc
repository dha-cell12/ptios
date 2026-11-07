static NSMutableDictionary *TLinkEventReadJournal(NSString **error)
{
    sTLinkEventJournalReads.fetch_add(1);
    BOOL missing = NO;
    NSData *data = TLinkEventReadJournalData(&missing, error);
    if (!data) {
        if (missing) return [@{@"schema": TLinkEventChannelSchemaV1, @"next_sequence": @1, @"events": @[]} mutableCopy];
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    uint64_t next = 0, previous = 0;
    BOOL valid = [object isKindOfClass:[NSDictionary class]] && [object[@"schema"] isEqual:TLinkEventChannelSchemaV1] &&
        TLinkEventJournalInteger(object[@"next_sequence"], &next) && next > 0 &&
        [object[@"events"] isKindOfClass:[NSArray class]] && [object[@"events"] count] <= kTLinkEventJournalMaxEvents;
    if (valid) for (id event in object[@"events"]) {
        uint64_t sequence = 0, timestamp = 0;
        valid = [event isKindOfClass:[NSDictionary class]] && [event[@"schema"] isEqual:TLinkEventSchemaV1] &&
            TLinkEventJournalInteger(event[@"sequence"], &sequence) && sequence > 0 && sequence < next &&
            (!previous || sequence == previous + 1) && TLinkEventJournalInteger(event[@"timestamp_ms"], &timestamp) &&
            [event[@"payload"] isKindOfClass:[NSDictionary class]];
        if (valid) for (NSString *key in @[@"event_id", @"runtime", @"topic", @"type"]) {
            if (![event[key] isKindOfClass:[NSString class]] || [event[key] length] == 0) { valid = NO; break; }
        }
        if (!valid) break;
        previous = sequence;
    }
    valid = valid && (!previous || previous == next - 1);
    if (!valid) { *error = @"event_journal_invalid"; return nil; }
    return [object mutableCopy];
}

