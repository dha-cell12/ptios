+ (instancetype)openPath:(NSString *)path
                     mode:(NSString *)mode
                 handleId:(NSUInteger)handleId
         maxTransferBytes:(NSUInteger)maxTransferBytes
                    error:(NSString **)error
{
    NSString *normalizedMode = TLinkJSFileNormalizeMode(mode);
    if (!TLinkJSFileModeIsValid(normalizedMode)) {
        if (error) *error = @"invalid_file_mode";
        return nil;
    }

    BOOL plus = [normalizedMode containsString:@"+"];
    BOOL writing = TLinkJSFileModeWrites(normalizedMode);
    int flags = plus ? O_RDWR : (writing ? O_WRONLY : O_RDONLY);
    if ([normalizedMode hasPrefix:@"w"]) flags |= O_CREAT | O_TRUNC;
    if ([normalizedMode hasPrefix:@"a"]) flags |= O_CREAT | O_APPEND;
#ifdef O_NOFOLLOW
    flags |= O_NOFOLLOW;
#endif

    const char *filePath = [path fileSystemRepresentation];
    BOOL existedBeforeOpen = access(filePath, F_OK) == 0;
    int fd = open(filePath, flags, 0664);
    if (fd < 0) {
        if (error) *error = [NSString stringWithFormat:@"file_open_failed errno=%d %s", errno, strerror(errno)];
        return nil;
    }
    if (!existedBeforeOpen && writing) {
        struct stat parentStat;
        NSString *parent = [path stringByDeletingLastPathComponent];
        if (stat([parent fileSystemRepresentation], &parentStat) == 0) {
            (void)fchown(fd, parentStat.st_uid, parentStat.st_gid);
        }
        (void)fchmod(fd, 0664);
    }
    if ([normalizedMode hasPrefix:@"a"] && lseek(fd, 0, SEEK_END) < 0) {
        int seekError = errno;
        close(fd);
        if (error) *error = [NSString stringWithFormat:@"file_seek_failed errno=%d %s", seekError, strerror(seekError)];
        return nil;
    }

    TLinkJSFileHandle *handle = [[self alloc] init];
    handle->_fd = fd;
    handle->_readable = !writing || plus;
    handle->_writable = writing;
    handle->_maxTransferBytes = MAX((NSUInteger)1, maxTransferBytes);
    struct stat lineStat;
    handle->_lineReadChunked = handle->_readable && fstat(fd, &lineStat) == 0 && S_ISREG(lineStat.st_mode) && lseek(fd, 0, SEEK_CUR) >= 0;
    handle.handleId = handleId;
    handle.path = path ?: @"";
    handle.mode = normalizedMode;
    handle.closed = NO;
    return handle;
}

