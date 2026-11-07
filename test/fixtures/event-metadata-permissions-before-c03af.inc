static BOOL TLinkEventEnsureDirectory(void)
{
    NSString *root = TLinkEventChannelRootPath();
    struct stat info;
    if (lstat(root.fileSystemRepresentation, &info) != 0) {
        if (errno != ENOENT) return NO;
        [[NSFileManager defaultManager] createDirectoryAtPath:root
                                withIntermediateDirectories:YES
                                                 attributes:@{NSFilePosixPermissions: @0750}
                                                      error:nil];
        if (lstat(root.fileSystemRepresentation, &info) != 0) return NO;
    }
    if (!S_ISDIR(info.st_mode)) return NO;
    chmod(root.fileSystemRepresentation, 0750);
    lchown(root.fileSystemRepresentation, 501, 501);
    return YES;
}

static int TLinkEventAcquireFileLock(BOOL reader, BOOL nonBlocking)
{
    if (!TLinkEventEnsureDirectory()) return -1;
    NSString *path = TLinkEventLockPath();
    int fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0640);
    if (fd < 0) return -1;
    struct stat opened;
    if (fstat(fd, &opened) != 0 || !S_ISREG(opened.st_mode) || opened.st_nlink != 1) {
        close(fd);
        return -1;
    }
    int operation = reader ? LOCK_SH : LOCK_EX;
    if (nonBlocking) operation |= LOCK_NB;
    if (flock(fd, operation) != 0) {
        close(fd);
        return -1;
    }
    struct stat current, root;
    if (lstat(path.fileSystemRepresentation, &current) != 0 || !S_ISREG(current.st_mode) || current.st_nlink != 1 ||
        current.st_dev != opened.st_dev || current.st_ino != opened.st_ino ||
        lstat(TLinkEventChannelRootPath().fileSystemRepresentation, &root) != 0 || !S_ISDIR(root.st_mode)) {
        flock(fd, LOCK_UN);
        close(fd);
        return -1;
    }
    // Permissions target the validated descriptor, never a replacement pathname.
    fchmod(fd, 0640);
    fchown(fd, 501, 501);
    return fd;
}

