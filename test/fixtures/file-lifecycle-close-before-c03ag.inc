- (NSDictionary *)close
{
    @synchronized (self) {
        if (self.closed || _fd < 0) return @{@"ok": @YES, @"closed": @YES, @"alreadyClosed": @YES, @"path": self.path ?: @""};
        int fd = _fd;
        _fd = -1;
        self.closed = YES;
        int result = close(fd);
        if (result != 0) return TLinkJSFileError([NSString stringWithFormat:@"file_close_failed errno=%d %s", errno, strerror(errno)], self.path);
        return @{@"ok": @YES, @"closed": @YES, @"path": self.path ?: @""};
    }
}
