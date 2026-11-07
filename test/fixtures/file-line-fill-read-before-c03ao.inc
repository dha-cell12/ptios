- (NSDictionary *)readLineRepresentation:(TLinkJSFileRepresentation)representation
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
        NSMutableDictionary *result = [TLinkJSFileSelectedDataResult(data, eof, truncated, representation) mutableCopy];
        if (representation != TLinkJSFileRepresentation::Base64) result[@"line"] = result[@"data"] ?: @"";
        return result;
    }
    }
}

