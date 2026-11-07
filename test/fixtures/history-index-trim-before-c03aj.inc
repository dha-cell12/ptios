static NSArray<NSDictionary *> *TLinkRunHistoryTrim(NSMutableArray<NSDictionary *> *runs)
{
    NSMutableArray<NSDictionary *> *retired = [NSMutableArray array];
    while (runs.count > kTLinkRunHistoryMaxRecords) {
        [retired addObject:runs.lastObject];
        [runs removeLastObject];
    }
    return retired;
}

