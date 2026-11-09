static NSMutableArray<NSDictionary *> *TLinkRunHistoryReadCheckedIndex(NSString *operation)
{
    @autoreleasepool {
    BOOL missing = NO;
    NSString *code = nil;
    NSData *data = TLinkRunHistoryReadIndexData(&missing, &code);
    if (!data) {
        if (missing) return [NSMutableArray array];
        TLinkRunHistoryPersistenceFailure(operation, @"read", code ?: @"read_failed");
        return nil;
    }
    id object = data.length > 0
        ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    BOOL valid = [object isKindOfClass:[NSDictionary class]];
    id schema = valid ? object[@"schema"] : nil;
    id records = valid ? object[@"runs"] : nil;
    valid = [schema isKindOfClass:[NSString class]] && [schema isEqualToString:TLinkRunHistorySchemaV1] &&
        [records isKindOfClass:[NSArray class]];
    NSMutableSet<NSString *> *identities = [NSMutableSet setWithCapacity:valid ? MIN([(NSArray *)records count], kTLinkRunHistoryMaxRecords) : 0];
    if (valid) {
        for (id record in records) {
            @autoreleasepool {
            id runId = [record isKindOfClass:[NSDictionary class]] ? record[@"run_id"] : nil;
            if (![runId isKindOfClass:[NSString class]] || [runId length] == 0 || [identities containsObject:runId]) {
                valid = NO;
                break;
            }
            [identities addObject:runId];
            }
        }
    }
    if (!valid) {
        TLinkRunHistoryPersistenceFailure(operation, @"read", @"invalid_index");
        return nil;
    }
    return [records isKindOfClass:[NSMutableArray class]] ? records : [records mutableCopy];
    }
}

