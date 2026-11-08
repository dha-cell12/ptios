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
                NSMutableData *data = [NSMutableData dataWithLength:encoded.length];
                NSUInteger offset = 0;
                while (offset < data.length) {
                    size_t count = MIN(data.length - offset, (NSUInteger)65536);
                    ssize_t got = read(fd, (uint8_t *)data.mutableBytes + offset, count);
                    if (got < 0 && errno == EINTR) continue;
                    if (got <= 0) { TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed"); return NO; }
                    offset += (NSUInteger)got;
                }
                id stored = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([stored isEqual:expected]) return YES;
            }
        } @finally { close(fd); }
    }
    if (!TLinkRunHistoryWriteJSON(expected, path)) {
        TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_write_failed");
        return NO;
    }
    return YES;
}

