- (NSDictionary *)flush
{
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        if (!_writable) return @{@"ok": @YES, @"path": self.path ?: @""};
        if (fsync(_fd) != 0) return TLinkJSFileError([NSString stringWithFormat:@"file_flush_failed errno=%d %s", errno, strerror(errno)], self.path);
        return @{@"ok": @YES, @"path": self.path ?: @""};
    }
}

