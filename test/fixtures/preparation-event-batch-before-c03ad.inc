static NSDictionary *TLinkEventBatchFromJournal(NSDictionary *journal, uint64_t cursor,
    NSSet<NSString *> *topics, NSUInteger maxEvents, BOOL timedOut)
{
    NSArray *events = [journal[@"events"] isKindOfClass:[NSArray class]] ? journal[@"events"] : @[];
    uint64_t latest = [journal[@"next_sequence"] unsignedLongLongValue];
    latest = latest > 0 ? latest - 1 : 0;
    uint64_t oldest = events.count > 0 ? [events.firstObject[@"sequence"] unsignedLongLongValue] : latest + 1;
    BOOL gap = (events.count > 0 && cursor > 0 && oldest > 0 && cursor < oldest - 1) || cursor > latest;
    NSMutableArray *selected = [NSMutableArray array];
    TLinkEventBatchCursor scan(cursor, maxEvents);
    for (NSDictionary *event in events) {
        auto action = scan.scan([event[@"sequence"] unsignedLongLongValue], TLinkEventTopicMatches(event[@"topic"], topics));
        if (action == TLinkEventBatchCursor::Stop) break;
        if (action == TLinkEventBatchCursor::Select) [selected addObject:event];
    }
    uint64_t nextCursor = scan.nextCursor(latest);
    BOOL hasMore = scan.more;
    NSDictionary *result = @{
        @"schema": TLinkEventChannelSchemaV1,
        @"state": @"ready",
        @"cursor": @(cursor),
        @"next_cursor": @(nextCursor),
        @"oldest_cursor": @(oldest > 0 ? oldest - 1 : 0),
        @"latest_cursor": @(latest),
        @"gap": @(gap),
        @"has_more": @(hasMore),
        @"timed_out": @(timedOut),
        @"events": selected,
    };
    return result;
}

