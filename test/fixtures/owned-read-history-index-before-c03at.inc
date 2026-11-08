static NSData *TLinkRunHistoryReadIndexData(BOOL *missing, NSString **code)
{
    int fd = open(TLinkRunHistoryIndexPath().fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        if (errno == ENOENT) *missing = YES;
        else *code = @"read_failed";
        return nil;
    }
    @try {
        struct stat indexInfo;
        if (fstat(fd, &indexInfo) != 0 || !S_ISREG(indexInfo.st_mode) || indexInfo.st_size < 0) {
            *code = @"read_failed"; return nil;
        }
        if ((uint64_t)indexInfo.st_size > kTLinkRunHistoryIndexMaxBytes) {
            *code = @"index_too_large"; return nil;
        }
        NSMutableData *indexData = [NSMutableData dataWithLength:(NSUInteger)indexInfo.st_size];
        if (!indexData) { *code = @"read_failed"; return nil; }
        NSUInteger offset = 0;
        while (offset < indexData.length) {
            size_t count = MIN(indexData.length - offset, (NSUInteger)65536);
            ssize_t got = read(fd, (uint8_t *)indexData.mutableBytes + offset, count);
            if (got < 0 && errno == EINTR) continue;
            if (got <= 0) { *code = @"read_failed"; return nil; }
            offset += (NSUInteger)got;
        }
        // Cooperating atomic replacements leave this opened inode stable.
        uint8_t extra;
        ssize_t got;
        do { got = read(fd, &extra, 1); } while (got < 0 && errno == EINTR);
        if (got != 0) {
            *code = got > 0 && indexData.length == kTLinkRunHistoryIndexMaxBytes ? @"index_too_large" : @"read_failed";
            return nil;
        }
        return indexData;
    } @finally { close(fd); }
}

