static NSData *TLinkEventReadJournalData(BOOL *missing, NSString **error)
{
    NSString *path = TLinkEventJournalPath();
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        if (errno == ENOENT) *missing = YES;
        else *error = @"event_journal_read_failed";
        return nil;
    }
    @try {
        struct stat info;
        if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size < 0) {
            *error = @"event_journal_read_failed"; return nil;
        }
        if ((uint64_t)info.st_size > kTLinkEventJournalMaxBytes) {
            *error = @"event_journal_too_large"; return nil;
        }
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
        if (!data) { *error = @"event_journal_read_failed"; return nil; }
        NSUInteger offset = 0;
        while (offset < data.length) {
            size_t count = MIN(data.length - offset, (NSUInteger)65536);
            ssize_t got = read(fd, (uint8_t *)data.mutableBytes + offset, count);
            if (got < 0 && errno == EINTR) continue;
            if (got <= 0) { *error = @"event_journal_read_failed"; return nil; }
            offset += (NSUInteger)got;
        }
        // Atomic cooperating writers leave this opened inode stable. Refuse observed growth.
        uint8_t extra;
        ssize_t got;
        do { got = read(fd, &extra, 1); } while (got < 0 && errno == EINTR);
        if (got != 0) {
            *error = got > 0 && data.length == kTLinkEventJournalMaxBytes ? @"event_journal_too_large" : @"event_journal_read_failed";
            return nil;
        }
        return data;
    } @finally { close(fd); }
}

