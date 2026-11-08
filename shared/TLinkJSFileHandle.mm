#import "TLinkJSFileHandle.h"
#include "TLinkJSFileLine.h"
#include "TLinkJSFileLineInto.h"
#include "TLinkJSFileIO.h"
#include "TLinkJSFileReadStorage.h"
#include <memory>
#include "TLinkJSFileOpen.h"
#include "TLinkUTF8Data.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// BEGIN owned file read storage.
using TLinkJSFileReadDataFactory=NSData *(*)(const std::shared_ptr<TLinkJSFileReadStorage::Buffer> &);
static NSData *TLinkJSFileReadCreateData(const std::shared_ptr<TLinkJSFileReadStorage::Buffer> &owner)
{
    if(!owner||!owner->size())return [NSData data];
    const auto held=owner;
    return [[NSData alloc] initWithBytesNoCopy:const_cast<uint8_t *>(owner->data()) length:owner->size()
        deallocator:^(void *bytes,NSUInteger length){(void)bytes;(void)length;(void)held->size();}];
}
static NSData *TLinkJSFileReadFinish(TLinkJSFileReadStorage::Buffer &&storage,NSUInteger produced,
                                    TLinkJSFileReadDataFactory factory=TLinkJSFileReadCreateData)
{
    if(!factory||!storage.seal(produced))return nil;
    auto owner=std::make_shared<TLinkJSFileReadStorage::Buffer>(std::move(storage));
    NSData *data=factory(owner);
    return data&&data.length==produced?data:nil;
}
// END owned file read storage.

static NSString *TLinkJSFileNormalizeMode(NSString *mode)
{
    @autoreleasepool {
    NSString *value = [[mode ?: @"r" lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value isEqualToString:@"r+b"]) return @"rb+";
    if ([value isEqualToString:@"w+b"]) return @"wb+";
    if ([value isEqualToString:@"a+b"]) return @"ab+";
    return value;
    }
}

static BOOL TLinkJSFileNormalizedModeIsValid(NSString *value)
{
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

BOOL TLinkJSFileModeIsValid(NSString *mode)
{
    return TLinkJSFileNormalizedModeIsValid(TLinkJSFileNormalizeMode(mode));
}

BOOL TLinkJSFileModeWrites(NSString *mode)
{
    NSString *value = TLinkJSFileNormalizeMode(mode);
    return [value hasPrefix:@"w"] || [value hasPrefix:@"a"] || [value containsString:@"+"];
}

// BEGIN prepared file mode.
TLinkJSFileModePlan TLinkJSFilePrepareMode(NSString *mode)
{
    TLinkJSFileModePlan plan;
    @autoreleasepool {
        plan.mode_=[TLinkJSFileNormalizeMode(mode) copy];
        plan.valid_=plan.mode_&&TLinkJSFileNormalizedModeIsValid(plan.mode_);
        if(plan.valid_){
        plan.plus_=[plan.mode_ containsString:@"+"];
        plan.writing_=[plan.mode_ hasPrefix:@"w"]||[plan.mode_ hasPrefix:@"a"]||plan.plus_;
        plan.flags_=plan.plus_?O_RDWR:(plan.writing_?O_WRONLY:O_RDONLY);
        if([plan.mode_ hasPrefix:@"w"])plan.flags_|=O_CREAT|O_TRUNC;
        if([plan.mode_ hasPrefix:@"a"])plan.flags_|=O_CREAT|O_APPEND;
#ifdef O_NOFOLLOW
        plan.flags_|=O_NOFOLLOW;
#endif
        }
    }
    return plan;
}
// END prepared file mode.

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

// BEGIN selected file reads.
enum class TLinkJSFileRepresentation { Legacy, Text, Base64 };
static NSDictionary *TLinkJSFileSelectedDataResult(NSData *data, BOOL eof, BOOL truncated,
                                                  TLinkJSFileRepresentation representation)
{
    if (representation == TLinkJSFileRepresentation::Legacy) return TLinkJSFileDataResult(data, eof, truncated);
    if (representation == TLinkJSFileRepresentation::Base64) {
        return @{
            @"ok": @YES,
            @"base64": [data base64EncodedStringWithOptions:0] ?: @"",
            @"bytes": @(data.length),
            @"eof": @(eof),
            @"truncated": @(truncated),
            @"encoding": @"base64",
        };
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return @{
        @"ok": @YES,
        @"data": text ?: @"",
        @"bytes": @(data.length),
        @"eof": @(eof),
        @"truncated": @(truncated),
        @"encoding": text ? @"utf8" : @"binary",
    };
}
// END selected file reads.

// BEGIN direct file line result.
static NSMutableDictionary *TLinkJSFileLineDataResult(NSData *data, BOOL eof, BOOL truncated,
                                                     TLinkJSFileRepresentation representation)
{
    NSString *text = representation == TLinkJSFileRepresentation::Base64 ? nil : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *encoded = representation == TLinkJSFileRepresentation::Text ? nil : ([data base64EncodedStringWithOptions:0] ?: @"");
    if (representation == TLinkJSFileRepresentation::Base64) {
        return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @YES, @"ok", encoded, @"base64", @(data.length), @"bytes",
            @(eof), @"eof", @(truncated), @"truncated", @"base64", @"encoding", nil];
    }
    NSString *value = text ?: @"";
    NSString *encoding = text ? @"utf8" : @"binary";
    if (representation == TLinkJSFileRepresentation::Text) {
        return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @YES, @"ok", value, @"data", value, @"line", @(data.length), @"bytes",
            @(eof), @"eof", @(truncated), @"truncated", encoding, @"encoding", nil];
    }
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
        @YES, @"ok", value, @"data", value, @"line", encoded, @"base64", @(data.length), @"bytes",
        @(eof), @"eof", @(truncated), @"truncated", encoding, @"encoding", nil];
}
// END direct file line result.

@interface TLinkJSFileHandle () {
    int _fd;
    BOOL _readable;
    BOOL _writable;
    BOOL _lineReadChunked;
    NSUInteger _maxTransferBytes;
}
// BEGIN prepared physical open declaration.
+ (instancetype)openPath:(NSString *)path normalizedMode:(NSString *)normalizedMode flags:(int)flags writing:(BOOL)writing plus:(BOOL)plus handleId:(NSUInteger)handleId maxTransferBytes:(NSUInteger)maxTransferBytes error:(NSString **)error;
// END prepared physical open declaration.
// BEGIN selected file read declarations.
- (NSDictionary *)readRequest:(id)request representation:(TLinkJSFileRepresentation)representation;
- (NSDictionary *)readLineRepresentation:(TLinkJSFileRepresentation)representation;
// END selected file read declarations.
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
    BOOL normalizedValid = normalizedMode && TLinkJSFileNormalizedModeIsValid(normalizedMode);
    if (!normalizedValid && !TLinkJSFileModeIsValid(normalizedMode)) {
        if (error) *error = @"invalid_file_mode";
        return nil;
    }

    BOOL plus = [normalizedMode containsString:@"+"];
    BOOL writing = normalizedValid
        ? ([normalizedMode hasPrefix:@"w"] || [normalizedMode hasPrefix:@"a"] || plus)
        : TLinkJSFileModeWrites(normalizedMode);
    int flags = plus ? O_RDWR : (writing ? O_WRONLY : O_RDONLY);
    if ([normalizedMode hasPrefix:@"w"]) flags |= O_CREAT | O_TRUNC;
    if ([normalizedMode hasPrefix:@"a"]) flags |= O_CREAT | O_APPEND;
#ifdef O_NOFOLLOW
    flags |= O_NOFOLLOW;
#endif

    return [self openPath:path normalizedMode:normalizedMode flags:flags writing:writing plus:plus handleId:handleId maxTransferBytes:maxTransferBytes error:error];
}

+ (instancetype)openPath:(NSString *)path
             preparedMode:(const TLinkJSFileModePlan &)plan
                 handleId:(NSUInteger)handleId
         maxTransferBytes:(NSUInteger)maxTransferBytes
                    error:(NSString **)error
{
    if(!plan.valid()){if(error)*error=@"invalid_file_mode";return nil;}
    return [self openPath:path normalizedMode:plan.mode() flags:plan.flags() writing:plan.writing() plus:plan.plus() handleId:handleId maxTransferBytes:maxTransferBytes error:error];
}

+ (instancetype)openPath:(NSString *)path
             normalizedMode:(NSString *)normalizedMode
                      flags:(int)flags
                    writing:(BOOL)writing
                       plus:(BOOL)plus
                   handleId:(NSUInteger)handleId
           maxTransferBytes:(NSUInteger)maxTransferBytes
                      error:(NSString **)error
{
    const char *filePath = [path fileSystemRepresentation];
    BOOL existedBeforeOpen = access(filePath, F_OK) == 0;
    int fd = open(filePath, flags, 0664);
    if (fd < 0) {
        if (error) *error = [NSString stringWithFormat:@"file_open_failed errno=%d %s", errno, strerror(errno)];
        return nil;
    }
    TLinkJSFileOpenOwner pending(fd);
    @try {
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
        if (error) *error = [NSString stringWithFormat:@"file_seek_failed errno=%d %s", seekError, strerror(seekError)];
        return nil;
    }

    TLinkJSFileHandle *handle = [[self alloc] init];
    if (!handle) {
        if (error) *error = [NSString stringWithFormat:@"file_open_failed errno=%d %s", ENOMEM, strerror(ENOMEM)];
        return nil;
    }
    handle->_readable = !writing || plus;
    handle->_writable = writing;
    handle->_maxTransferBytes = MAX((NSUInteger)1, maxTransferBytes);
    struct stat lineStat;
    handle->_lineReadChunked = handle->_readable && fstat(fd, &lineStat) == 0 && S_ISREG(lineStat.st_mode) && lseek(fd, 0, SEEK_CUR) >= 0;
    handle.handleId = handleId;
    handle.path = path ?: @"";
    handle.mode = normalizedMode;
    handle.closed = NO;
    handle->_fd = pending.release();
    return handle;
    } @finally {
        pending.retire([](int value){::close(value);});
    }
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _fd = -1;
        _closed = YES;
        _path = @"";
        _mode = @"r";
    }
    return self;
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
    return [self readRequest:request representation:TLinkJSFileRepresentation::Legacy];
}

- (NSDictionary *)readTextRequest:(id)request
{
    return [self readRequest:request representation:TLinkJSFileRepresentation::Text];
}

- (NSDictionary *)readBase64Request:(id)request
{
    return [self readRequest:request representation:TLinkJSFileRepresentation::Base64];
}

- (NSDictionary *)readRequest:(id)request representation:(TLinkJSFileRepresentation)representation
{
    @autoreleasepool {
    if ([request isKindOfClass:[NSString class]]) {
        NSString *kind = [(NSString *)request lowercaseString];
        if ([kind isEqualToString:@"*l"] || [kind isEqualToString:@"line"]) {
            if (representation == TLinkJSFileRepresentation::Legacy) return [self readLine];
            return [self readLineRepresentation:representation];
        }
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
        if (requested == 0) return TLinkJSFileSelectedDataResult([NSData data], NO, NO, representation);

        TLinkJSFileReadStorage::Buffer storage(requested);
        const int fd=_fd;
        const auto input=TLinkJSFileIO::ReadInto(requested,
            [&storage](size_t used,size_t amount)->uint8_t * { return storage.destination(used,amount); },
            [fd](uint8_t *bytes,size_t amount)->int64_t{return ::read(fd,bytes,amount);});
        if(input.error)return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s",input.error,strerror(input.error)],self.path);
        NSData *data=TLinkJSFileReadFinish(std::move(storage),input.bytes);
        if(!data)return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s",ENOMEM,strerror(ENOMEM)],self.path);
        BOOL eof=input.eof;
        BOOL truncated = readAll && !eof && data.length == _maxTransferBytes;
        return TLinkJSFileSelectedDataResult(data, eof, truncated, representation);
    }
    }
}

- (NSDictionary *)readLine
{
    return [self readLineRepresentation:TLinkJSFileRepresentation::Legacy];
}

- (NSDictionary *)readLineRepresentation:(TLinkJSFileRepresentation)representation
{
    @autoreleasepool {
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        if (!_readable) return TLinkJSFileError(@"file_not_open_for_reading", self.path);

        TLinkJSFileReadStorage::Buffer storage(_maxTransferBytes);
        const int fd = _fd;
        const auto line = TLinkJSFileReadLineInto(_maxTransferBytes, _lineReadChunked,
            [&storage](size_t used,size_t count)->uint8_t * { return storage.destination(used,count); },
            [fd](uint8_t *bytes, size_t count)->int64_t { return ::read(fd, bytes, count); },
            [fd](size_t count)->bool { return ::lseek(fd, -static_cast<off_t>(count), SEEK_CUR) >= 0; });
        if (line.error) return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s", line.error, strerror(line.error)], self.path);
        NSUInteger produced=line.bytes;
        if(produced&&storage.data()[produced-1]=='\r')--produced;
        NSData *data=TLinkJSFileReadFinish(std::move(storage),produced);
        if(!data)return TLinkJSFileError([NSString stringWithFormat:@"file_read_failed errno=%d %s",ENOMEM,strerror(ENOMEM)],self.path);
        BOOL eof = line.eof;
        BOOL truncated = !eof && data.length == _maxTransferBytes;
        return TLinkJSFileLineDataResult(data, eof, truncated, representation);
    }
    }
}

- (NSDictionary *)writeData:(NSData *)data
{
    if (self.closed || _fd < 0) return [self closedError];
    if (!_writable) return TLinkJSFileError(@"file_not_open_for_writing", self.path);
    if (data.length > _maxTransferBytes) return TLinkJSFileError(@"file_write_exceeds_transfer_limit", self.path);

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger remaining = data.length;
    const int fd=_fd;
    const auto output=TLinkJSFileIO::WriteAll(bytes,remaining,[fd](const uint8_t *buffer,size_t amount)->int64_t{return ::write(fd,buffer,amount);});
    if(output.error)return TLinkJSFileError([NSString stringWithFormat:@"file_write_failed errno=%d %s",output.error,strerror(output.error)],self.path);
    if(output.zeroWrite)return TLinkJSFileError(@"file_write_returned_zero",self.path);
    return @{@"ok": @YES, @"bytes": @(data.length), @"path": self.path ?: @""};
}

- (NSDictionary *)writeText:(NSString *)text
{
    @autoreleasepool {
    @synchronized (self) {
        NSData *data = TLinkUTF8DataFromString(text ?: @"") ?: [NSData data];
        return [self writeData:data];
    }
    }
}

- (NSDictionary *)writeBase64:(NSString *)base64
{
    @autoreleasepool {
    @synchronized (self) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 ?: @"" options:0];
        if (!data) return TLinkJSFileError(@"file_write_invalid_base64", self.path);
        return [self writeData:data];
    }
    }
}

- (NSDictionary *)seekWhence:(NSString *)whence offset:(long long)offset
{
    @autoreleasepool {
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        int origin = SEEK_SET;
        if ([whence isEqualToString:@"cur"] || [whence isEqualToString:@"current"]) origin = SEEK_CUR;
        else if ([whence isEqualToString:@"end"]) origin = SEEK_END;
        else if (![whence isEqualToString:@"set"] && ![whence isEqualToString:@"start"]) {
            NSString *value = [[whence ?: @"set" lowercaseString]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([value isEqualToString:@"cur"] || [value isEqualToString:@"current"]) origin = SEEK_CUR;
            else if ([value isEqualToString:@"end"]) origin = SEEK_END;
            else if (![value isEqualToString:@"set"] && ![value isEqualToString:@"start"]) {
                return TLinkJSFileError(@"file_seek_invalid_whence", self.path);
            }
        }
        off_t result = lseek(_fd, (off_t)offset, origin);
        if (result < 0) return TLinkJSFileError([NSString stringWithFormat:@"file_seek_failed errno=%d %s", errno, strerror(errno)], self.path);
        return @{@"ok": @YES, @"offset": @((long long)result), @"path": self.path ?: @""};
    }
    }
}

- (NSDictionary *)tell
{
    return [self seekWhence:@"cur" offset:0];
}

- (NSDictionary *)flush
{
    @autoreleasepool {
    @synchronized (self) {
        if (self.closed || _fd < 0) return [self closedError];
        if (!_writable) return @{@"ok": @YES, @"path": self.path ?: @""};
        if (fsync(_fd) != 0) return TLinkJSFileError([NSString stringWithFormat:@"file_flush_failed errno=%d %s", errno, strerror(errno)], self.path);
        return @{@"ok": @YES, @"path": self.path ?: @""};
    }
    }
}

- (NSDictionary *)close
{
    @autoreleasepool {
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
}

@end

JSValue *TLinkJSFileHandleCreateJSObject(JSContext *context,
                                         TLinkJSFileHandle *handle,
                                         void (^didClose)(NSUInteger handleId))
{
    @autoreleasepool {
    JSValue *object = [JSValue valueWithNewObjectInContext:context];
    object[@"ok"] = @YES;
    object[@"id"] = @(handle.handleId);
    object[@"path"] = handle.path ?: @"";
    object[@"mode"] = handle.mode ?: @"r";
    object[@"read"] = ^NSDictionary *(JSValue *request) {
        @autoreleasepool {
        id value = (!request || [request isUndefined] || [request isNull]) ? @"*a" : [request toObject];
        return [handle readRequest:value];
        }
    };
    // BEGIN selected file read bindings.
    object[@"readText"] = ^NSDictionary *(JSValue *request) {
        @autoreleasepool {
        id value = (!request || [request isUndefined] || [request isNull]) ? @"*a" : [request toObject];
        return [handle readTextRequest:value];
        }
    };
    object[@"readBase64"] = ^NSDictionary *(JSValue *request) {
        @autoreleasepool {
        id value = (!request || [request isUndefined] || [request isNull]) ? @"*a" : [request toObject];
        return [handle readBase64Request:value];
        }
    };
    // END selected file read bindings.
    object[@"readLine"] = ^NSDictionary *{ @autoreleasepool { return [handle readLine]; } };
    object[@"write"] = ^NSDictionary *(JSValue *value) { @autoreleasepool { return [handle writeText:[value toString] ?: @""]; } };
    object[@"writeBase64"] = ^NSDictionary *(NSString *base64) { @autoreleasepool { return [handle writeBase64:base64 ?: @""]; } };
    object[@"seek"] = ^NSDictionary *(NSString *whence, double offset) {
        @autoreleasepool {
        return [handle seekWhence:whence ?: @"set" offset:(long long)offset];
        }
    };
    object[@"tell"] = ^NSDictionary *{ @autoreleasepool { return [handle tell]; } };
    object[@"flush"] = ^NSDictionary *{ @autoreleasepool { return [handle flush]; } };
    object[@"isClosed"] = ^BOOL { @autoreleasepool { return handle.isClosed; } };
    object[@"close"] = ^NSDictionary *{
        @autoreleasepool {
        NSDictionary *result = [handle close];
        if (didClose) didClose(handle.handleId);
        return result;
        }
    };
    return object;
    }
}
