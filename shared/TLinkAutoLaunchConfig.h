#ifndef TLINK_AUTO_LAUNCH_CONFIG_H
#define TLINK_AUTO_LAUNCH_CONFIG_H

#import <Foundation/Foundation.h>
#include <cerrno>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

// Lock a stable sibling, never the plist inode replaced by an atomic save. Each transaction
// opens its own descriptor so flock also serializes threads in the same process on Darwin.
class TLinkAutoLaunchFileLock {
    int fd_ = -1;
public:
    explicit TLinkAutoLaunchFileLock(const char *path) {
        do { fd_ = open(path, O_CREAT | O_RDONLY | O_CLOEXEC, 0644); } while (fd_ < 0 && errno == EINTR);
        if (fd_ < 0) return;
        int status;
        do { status = flock(fd_, LOCK_EX); } while (status != 0 && errno == EINTR);
        if (status != 0) { close(fd_); fd_ = -1; }
    }
    ~TLinkAutoLaunchFileLock() { if (fd_ >= 0) { flock(fd_, LOCK_UN); close(fd_); } }
    bool acquired() const { return fd_ >= 0; }
    TLinkAutoLaunchFileLock(const TLinkAutoLaunchFileLock &) = delete;
    TLinkAutoLaunchFileLock &operator=(const TLinkAutoLaunchFileLock &) = delete;
};

static inline BOOL TLinkAutoLaunchError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

// Shared by every production writer. Preserve the flat name -> entry plist schema consumed
// by existing readers. Never replace an unreadable/malformed existing file with an empty map.
static inline BOOL TLinkAutoLaunchSetEntry(NSString *path, NSString *name, NSDictionary *entry, NSError **error)
{
    if (error) *error = nil;
    if (path.length == 0 || name.length == 0 || ![entry isKindOfClass:[NSDictionary class]])
        return TLinkAutoLaunchError(error, @"Auto launch requires a path, name and entry.");
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:path.stringByDeletingLastPathComponent
      withIntermediateDirectories:YES attributes:nil error:NULL])
        return TLinkAutoLaunchError(error, @"Failed to create auto launch directory.");
    NSString *lockPath = [path stringByAppendingString:@".lock"];
    TLinkAutoLaunchFileLock lock(lockPath.fileSystemRepresentation);
    if (!lock.acquired()) return TLinkAutoLaunchError(error, @"Failed to lock auto launch config.");

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    NSMutableDictionary *config = nil;
    if (data) {
        id object = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves
                                                              format:NULL error:NULL];
        if (![object isKindOfClass:[NSDictionary class]])
            return TLinkAutoLaunchError(error, @"Auto launch config is malformed; update refused.");
        config = object;
    } else if ([readError.domain isEqualToString:NSCocoaErrorDomain] && readError.code == NSFileReadNoSuchFileError) {
        config = [NSMutableDictionary dictionary];
    } else {
        return TLinkAutoLaunchError(error, @"Failed to read auto launch config.");
    }
    config[name] = entry;
    NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:config format:NSPropertyListXMLFormat_v1_0
                                                               options:0 error:NULL];
    if (!encoded || ![encoded writeToFile:path options:NSDataWritingAtomic error:NULL])
        return TLinkAutoLaunchError(error, @"Failed to save auto launch config.");
    return YES; // RAII unlock follows the completed atomic replacement, before caller ACK.
}
#endif
