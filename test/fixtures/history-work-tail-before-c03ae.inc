static NSArray<NSString *> *TLinkRunHistoryBoundedLogTail(NSArray<NSString *> *lines)
{
    if (![lines isKindOfClass:[NSArray class]] || lines.count == 0) return @[];
    NSUInteger start = lines.count > kTLinkFailureLogTailMaxLines ? lines.count - kTLinkFailureLogTailMaxLines : 0;
    NSMutableArray<NSString *> *tail = [NSMutableArray array];
    for (NSUInteger i = start; i < lines.count; i++) {
        id raw = lines[i];
        NSString *line = TLinkRunHistoryRedactText([raw isKindOfClass:[NSString class]] ? raw : [raw description]);
        if (line.length > kTLinkFailureLogLineMaxCharacters) line = [line substringToIndex:kTLinkFailureLogLineMaxCharacters];
        [tail addObject:line ?: @""];
    }
    while (tail.count > 0 && [tail.firstObject length] == 0) [tail removeObjectAtIndex:0];
    return tail;
}

static NSArray<NSString *> *TLinkRunHistoryTailFromConsoleFile(NSString *path)
{
    if (path.length == 0) return @[];
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) return @[];
    @try {
        struct stat consoleInfo;
        if (fstat(fd, &consoleInfo) != 0 || !S_ISREG(consoleInfo.st_mode) || consoleInfo.st_size <= 0) return @[];
        // Fix the window from this descriptor's size; concurrent appends cannot extend it.
        off_t start = consoleInfo.st_size > (off_t)kTLinkFailureConsoleLogMaxBytes
            ? consoleInfo.st_size - (off_t)kTLinkFailureConsoleLogMaxBytes : 0;
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)(consoleInfo.st_size - start)];
        NSUInteger offset = 0;
        while (offset < data.length) {
            size_t count = MIN(data.length - offset, (NSUInteger)65536);
            ssize_t got = pread(fd, (uint8_t *)data.mutableBytes + offset, count, start + (off_t)offset);
            if (got < 0 && errno == EINTR) continue;
            if (got <= 0) return @[];
            offset += (NSUInteger)got;
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        return TLinkRunHistoryBoundedLogTail([text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
    } @catch (__unused NSException *exception) {
        return @[];
    } @finally {
        close(fd);
    }
}

