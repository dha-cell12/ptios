static BOOL TLinkRunHistoryRepairJSON(NSDictionary *expected, NSString *path, NSString *operation)
{
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingPrettyPrinted error:nil];
    if (!encoded) { TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_invalid_index"); return NO; }
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
    if (fd < 0 && errno != ENOENT) {
        TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed");
        return NO;
    }
    if (fd >= 0) {
        @try {
            struct stat info;
            if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size < 0) {
                TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed");
                return NO;
            }
            // Different sizes already prove a mismatch. Never read an arbitrary
            // artifact's full length; cap reads at the authoritative JSON size.
            if ((uint64_t)info.st_size == encoded.length) {
                NSMutableData *data = nil;
                const auto comparison = TLinkHistoryRecoveryCompare::Compare(
                    (const uint8_t *)encoded.bytes, encoded.length,
                    [fd](uint8_t *bytes, size_t count) {
                        const ssize_t got = read(fd, bytes, count);
                        return TLinkHistoryRecoveryCompare::Read(got, got < 0 ? errno : 0);
                    },
                    [&data](size_t length) -> uint8_t * {
                        data = [NSMutableData dataWithLength:length];
                        return (uint8_t *)data.mutableBytes;
                    });
                if (comparison == TLinkHistoryRecoveryCompare::Result::Exact) return YES;
                if (comparison != TLinkHistoryRecoveryCompare::Result::Different) {
                    TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed");
                    return NO;
                }
                id stored = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([stored isEqual:expected]) return YES;
            }
        } @finally { close(fd); }
    }
    BOOL repaired = NO;
    @autoreleasepool {
        if ([NSJSONSerialization isValidJSONObject:expected] && path.length > 0)
            repaired = TLinkRunHistoryWriteJSONData(encoded, path);
    }
    if (!repaired) {
        TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_write_failed");
        return NO;
    }
    return YES;
}

