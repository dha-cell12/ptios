        NSMutableData *data = [NSMutableData data];
        const int fd = _fd;
        const auto line = TLinkJSFileReadLineInto(_maxTransferBytes, _lineReadChunked,
            [data](size_t used, size_t count)->uint8_t * {
                [data setLength:used+count];
                uint8_t *base=(uint8_t *)data.mutableBytes;
                return base?base+used:nullptr;
            },
            [fd](uint8_t *bytes, size_t count)->int64_t { return ::read(fd, bytes, count); },
            [fd](size_t count)->bool { return ::lseek(fd, -static_cast<off_t>(count), SEEK_CUR) >= 0; });
        if (line.error) return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s", line.error, strerror(line.error)], self.path);
        [data setLength:line.bytes];
        BOOL eof = line.eof;
        if (data.length > 0) {
            const uint8_t *bytes = (const uint8_t *)data.bytes;
            if (bytes[data.length - 1] == '\r') [data setLength:data.length - 1];
        }
