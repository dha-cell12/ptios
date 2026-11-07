- (NSDictionary *)seekWhence:(NSString *)whence offset:(long long)offset
{
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        NSString *value = [[whence ?: @"set" lowercaseString]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        int origin = SEEK_SET;
        if ([value isEqualToString:@"cur"] || [value isEqualToString:@"current"]) origin = SEEK_CUR;
        else if ([value isEqualToString:@"end"]) origin = SEEK_END;
        else if (![value isEqualToString:@"set"] && ![value isEqualToString:@"start"]) {
            return TLinkJSFileError(@"file_seek_invalid_whence", self.path);
        }
        off_t result = lseek(_fd, (off_t)offset, origin);
        if (result < 0) return TLinkJSFileError([NSString stringWithFormat:@"file_seek_failed errno=%d %s", errno, strerror(errno)], self.path);
        return @{@"ok": @YES, @"offset": @((long long)result), @"path": self.path ?: @""};
    }
}

