- (NSDictionary *)readRequest:(id)request
{
    @autoreleasepool {
    if ([request isKindOfClass:[NSString class]]) {
        NSString *kind = [(NSString *)request lowercaseString];
        if ([kind isEqualToString:@"*l"] || [kind isEqualToString:@"line"]) return [self readLine];
    }
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        if (!_readable) return TLinkJSFileError(@"file_not_open_for_reading", self.path);

        if ([request isKindOfClass:[NSString class]]) {
            NSString *kind = [(NSString *)request lowercaseString];
            if (![kind isEqualToString:@"*a"] && ![kind isEqualToString:@"all"] && kind.length > 0) {
                return TLinkJSFileError(@"file_read_request_must_be_all_line_or_byte_count", self.path);
            }
        }

        NSUInteger requested = _maxTransferBytes;
        BOOL readAll = ![request respondsToSelector:@selector(unsignedLongLongValue)] || [request isKindOfClass:[NSString class]];
        if (!readAll) {
            unsigned long long value = [request unsignedLongLongValue];
            if (value > _maxTransferBytes) return TLinkJSFileError(@"file_read_exceeds_transfer_limit", self.path);
            requested = (NSUInteger)value;
        }
        if (requested == 0) return TLinkJSFileDataResult([NSData data], NO, NO);

        NSMutableData *data = [NSMutableData data];
        const int fd=_fd;
        const auto input=TLinkJSFileIO::ReadInto(requested,
            [data](size_t used,size_t amount)->uint8_t * {
                [data setLength:used+amount];
                uint8_t *base=(uint8_t *)data.mutableBytes;
                return base?base+used:nullptr;
            },[fd](uint8_t *bytes,size_t amount)->int64_t{return ::read(fd,bytes,amount);});
        if(input.error)return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s",input.error,strerror(input.error)],self.path);
        [data setLength:input.bytes];
        BOOL eof=input.eof;
        BOOL truncated = readAll && !eof && data.length == _maxTransferBytes;
        return TLinkJSFileDataResult(data, eof, truncated);
    }
    }
}

- (NSDictionary *)readLine
{
    @autoreleasepool {
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        if (!_readable) return TLinkJSFileError(@"file_not_open_for_reading", self.path);

        NSMutableData *data = [NSMutableData data];
        const int fd = _fd;
        const auto line = TLinkJSFileReadLine(_maxTransferBytes, _lineReadChunked,
            [fd](uint8_t *bytes, size_t count)->int64_t { return ::read(fd, bytes, count); },
            [fd](size_t count)->bool { return ::lseek(fd, -static_cast<off_t>(count), SEEK_CUR) >= 0; },
            [data](const uint8_t *bytes, size_t count) { [data appendBytes:bytes length:count]; });
        if (line.error) return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s", line.error, strerror(line.error)], self.path);
        BOOL eof = line.eof;
        if (data.length > 0) {
            const uint8_t *bytes = (const uint8_t *)data.bytes;
            if (bytes[data.length - 1] == '\r') [data setLength:data.length - 1];
        }
        BOOL truncated = !eof && data.length == _maxTransferBytes;
        NSMutableDictionary *result = [TLinkJSFileDataResult(data, eof, truncated) mutableCopy];
        result[@"line"] = result[@"data"] ?: @"";
        return result;
    }
    }
}

