#import "TLinkJSFileHandle.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *TLinkJSFileNormalizeMode(NSString *mode)
{
    NSString *value = [[mode ?: @"r" lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value isEqualToString:@"r+b"]) return @"rb+";
    if ([value isEqualToString:@"w+b"]) return @"wb+";
    if ([value isEqualToString:@"a+b"]) return @"ab+";
    return value;
}

BOOL TLinkJSFileModeIsValid(NSString *mode)
{
    NSString *value = TLinkJSFileNormalizeMode(mode);
    static NSSet<NSString *> *validModes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        validModes = [NSSet setWithArray:@[
            @"r", @"rb", @"r+", @"rb+",
            @"w", @"wb", @"w+", @"wb+",
            @"a", @"ab", @"a+", @"ab+",
        ]];
    });
    return [validModes containsObject:value];
}

BOOL TLinkJSFileModeWrites(NSString *mode)
{
    NSString *value = TLinkJSFileNormalizeMode(mode);
    return [value hasPrefix:@"w"] || [value hasPrefix:@"a"] || [value containsString:@"+"];
}

static NSDictionary *TLinkJSFileError(NSString *error, NSString *path)
{
    return @{
        @"ok": @NO,
        @"error": error.length > 0 ? error : @"file_operation_failed",
        @"path": path ?: @"",
    };
}

static NSDictionary *TLinkJSFileDataResult(NSData *data, BOOL eof, BOOL truncated)
{
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return @{
        @"ok": @YES,
        @"data": text ?: @"",
        @"base64": [data base64EncodedStringWithOptions:0] ?: @"",
        @"bytes": @(data.length),
        @"eof": @(eof),
        @"truncated": @(truncated),
        @"encoding": text ? @"utf8" : @"binary",
    };
}

@interface TLinkJSFileHandle () {
    int _fd;
    BOOL _readable;
    BOOL _writable;
    NSUInteger _maxTransferBytes;
}
@property(nonatomic, readwrite) NSUInteger handleId;
@property(nonatomic, copy, readwrite) NSString *path;
@property(nonatomic, copy, readwrite) NSString *mode;
@property(nonatomic, readwrite, getter=isClosed) BOOL closed;
@end

@implementation TLinkJSFileHandle

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
    handle.handleId = handleId;
    handle.path = path ?: @"";
    handle.mode = normalizedMode;
    handle.closed = NO;
    return handle;
}

- (void)dealloc
{
    if (_fd >= 0) close(_fd);
}

- (NSDictionary *)closedError
{
    return TLinkJSFileError(@"file_handle_closed", self.path);
}

- (NSDictionary *)readRequest:(id)request
{
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
        BOOL eof = NO;
        while (data.length < requested) {
            NSUInteger remaining = requested - data.length;
            uint8_t buffer[8192];
            size_t amount = MIN(sizeof(buffer), remaining);
            ssize_t got = read(_fd, buffer, amount);
            if (got == 0) {
                eof = YES;
                break;
            }
            if (got < 0) {
                if (errno == EINTR) continue;
                return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s", errno, strerror(errno)], self.path);
            }
            [data appendBytes:buffer length:(NSUInteger)got];
        }
        BOOL truncated = readAll && !eof && data.length == _maxTransferBytes;
        return TLinkJSFileDataResult(data, eof, truncated);
    }
}

- (NSDictionary *)readLine
{
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        if (!_readable) return TLinkJSFileError(@"file_not_open_for_reading", self.path);

        NSMutableData *data = [NSMutableData data];
        BOOL eof = NO;
        while (data.length < _maxTransferBytes) {
            uint8_t byte = 0;
            ssize_t got = read(_fd, &byte, 1);
            if (got == 0) {
                eof = YES;
                break;
            }
            if (got < 0) {
                if (errno == EINTR) continue;
                return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s", errno, strerror(errno)], self.path);
            }
            if (byte == '\n') break;
            [data appendBytes:&byte length:1];
        }
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

- (NSDictionary *)writeData:(NSData *)data
{
    if (self.closed || _fd < 0) return [self closedError];
    if (!_writable) return TLinkJSFileError(@"file_not_open_for_writing", self.path);
    if (data.length > _maxTransferBytes) return TLinkJSFileError(@"file_write_exceeds_transfer_limit", self.path);

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t wrote = write(_fd, bytes, remaining);
        if (wrote < 0) {
            if (errno == EINTR) continue;
            return TLinkJSFileError([NSString stringWithFormat:@"file_write_failed errno=%d %s", errno, strerror(errno)], self.path);
        }
        if (wrote == 0) return TLinkJSFileError(@"file_write_returned_zero", self.path);
        bytes += wrote;
        remaining -= (NSUInteger)wrote;
    }
    return @{@"ok": @YES, @"bytes": @(data.length), @"path": self.path ?: @""};
}

- (NSDictionary *)writeText:(NSString *)text
{
    @synchronized (self) {
        NSData *data = [(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        return [self writeData:data];
    }
}

- (NSDictionary *)writeBase64:(NSString *)base64
{
    @synchronized (self) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 ?: @"" options:0];
        if (!data) return TLinkJSFileError(@"file_write_invalid_base64", self.path);
        return [self writeData:data];
    }
}

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

- (NSDictionary *)tell
{
    return [self seekWhence:@"cur" offset:0];
}

- (NSDictionary *)flush
{
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        if (!_writable) return @{@"ok": @YES, @"path": self.path ?: @""};
        if (fsync(_fd) != 0) return TLinkJSFileError([NSString stringWithFormat:@"file_flush_failed errno=%d %s", errno, strerror(errno)], self.path);
        return @{@"ok": @YES, @"path": self.path ?: @""};
    }
}

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

@end

JSValue *TLinkJSFileHandleCreateJSObject(JSContext *context,
                                         TLinkJSFileHandle *handle,
                                         void (^didClose)(NSUInteger handleId))
{
    JSValue *object = [JSValue valueWithNewObjectInContext:context];
    object[@"ok"] = @YES;
    object[@"id"] = @(handle.handleId);
    object[@"path"] = handle.path ?: @"";
    object[@"mode"] = handle.mode ?: @"r";
    object[@"read"] = ^NSDictionary *(JSValue *request) {
        id value = (!request || [request isUndefined] || [request isNull]) ? @"*a" : [request toObject];
        return [handle readRequest:value];
    };
    object[@"readLine"] = ^NSDictionary *{ return [handle readLine]; };
    object[@"write"] = ^NSDictionary *(JSValue *value) { return [handle writeText:[value toString] ?: @""]; };
    object[@"writeBase64"] = ^NSDictionary *(NSString *base64) { return [handle writeBase64:base64 ?: @""]; };
    object[@"seek"] = ^NSDictionary *(NSString *whence, double offset) {
        return [handle seekWhence:whence ?: @"set" offset:(long long)offset];
    };
    object[@"tell"] = ^NSDictionary *{ return [handle tell]; };
    object[@"flush"] = ^NSDictionary *{ return [handle flush]; };
    object[@"isClosed"] = ^BOOL { return handle.isClosed; };
    object[@"close"] = ^NSDictionary *{
        NSDictionary *result = [handle close];
        if (didClose) didClose(handle.handleId);
        return result;
    };
    return object;
}
