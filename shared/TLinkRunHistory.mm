#import "TLinkRunHistory.h"
#import "TLinkEventChannel.h"

#include <fcntl.h>
#include <errno.h>
#include <stdint.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

NSString * const TLinkRunHistorySchemaV1 = @"run_history_v1";
NSString * const TLinkFailureEvidenceSchemaV1 = @"failure_evidence_v1";

static const NSUInteger kTLinkRunHistoryMaxRecords = 50;
static const NSUInteger kTLinkRunHistoryIndexMaxBytes = 32 * 1024 * 1024;
static const NSUInteger kTLinkRunHistorySnapshotDefault = 20;
static const NSUInteger kTLinkRunHistorySnapshotMax = 50;
static const NSUInteger kTLinkFailureLogTailMaxLines = 50;
static const NSUInteger kTLinkFailureLogLineMaxCharacters = 1000;
static const NSUInteger kTLinkFailureErrorMaxCharacters = 4000;
static const NSUInteger kTLinkStatusLogTailMaxLines = 3;
static const NSUInteger kTLinkStatusLogLineMaxCharacters = 240;
static const NSUInteger kTLinkStatusErrorMaxCharacters = 500;
static const unsigned long long kTLinkFailureConsoleLogMaxBytes = 256 * 1024;

static NSObject *TLinkRunHistoryLock(void)
{
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [[NSObject alloc] init]; });
    return lock;
}

static uint64_t TLinkRunHistoryNowMs(void)
{
    return (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

NSString *TLinkRunHistoryRootPath(void)
{
    return @"/var/mobile/Library/TLinkauto/run-history";
}

NSString *TLinkRunHistoryRunsPath(void)
{
    return [TLinkRunHistoryRootPath() stringByAppendingPathComponent:@"runs"];
}

NSString *TLinkRunHistoryEvidencePath(void)
{
    return [TLinkRunHistoryRootPath() stringByAppendingPathComponent:@"evidence"];
}

static NSString *TLinkRunHistoryIndexPath(void)
{
    return [TLinkRunHistoryRootPath() stringByAppendingPathComponent:@"index.json"];
}

static NSString *TLinkRunHistoryFileLockPath(void)
{
    return [TLinkRunHistoryRootPath() stringByAppendingPathComponent:@"history.lock"];
}

static NSString *TLinkRunHistorySanitize(NSString *value)
{
    NSString *source = [value isKindOfClass:[NSString class]] ? value : @"";
    NSMutableString *safe = [NSMutableString stringWithCapacity:source.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."];
    for (NSUInteger i = 0; i < source.length && safe.length < 96; i++) {
        unichar c = [source characterAtIndex:i];
        [safe appendString:[allowed characterIsMember:c] ? [NSString stringWithCharacters:&c length:1] : @"_"];
    }
    return safe.length > 0 ? safe : @"run";
}

static void TLinkRunHistoryEnsureDirectories(void)
{
    NSDictionary *attributes = @{NSFilePosixPermissions: @0750};
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in @[TLinkRunHistoryRootPath(), TLinkRunHistoryRunsPath(), TLinkRunHistoryEvidencePath()]) {
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:attributes error:nil];
        chmod(path.fileSystemRepresentation, 0750);
        lchown(path.fileSystemRepresentation, 501, 501);
    }
}

static int TLinkRunHistoryAcquireFileLock(void)
{
    NSString *path = TLinkRunHistoryFileLockPath();
    int fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0640);
    if (fd < 0) return -1;
    chmod(path.fileSystemRepresentation, 0640);
    lchown(path.fileSystemRepresentation, 501, 501);
    if (flock(fd, LOCK_EX) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void TLinkRunHistoryReleaseFileLock(int fd)
{
    if (fd < 0) return;
    flock(fd, LOCK_UN);
    close(fd);
}

static BOOL TLinkRunHistoryWriteJSON(id object, NSString *path, NSJSONWritingOptions options = NSJSONWritingPrettyPrinted)
{
    if (![NSJSONSerialization isValidJSONObject:object] || path.length == 0) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:options error:nil];
    if (!data || ([path isEqualToString:TLinkRunHistoryIndexPath()] && data.length > kTLinkRunHistoryIndexMaxBytes) ||
        ![data writeToFile:path atomically:YES]) return NO;
    chmod(path.fileSystemRepresentation, 0640);
    lchown(path.fileSystemRepresentation, 501, 501);
    return YES;
}

static BOOL TLinkRunHistoryWriteIndex(NSArray<NSDictionary *> *runs)
{
    return TLinkRunHistoryWriteJSON(@{
        @"schema": TLinkRunHistorySchemaV1,
        @"updated_at_ms": @(TLinkRunHistoryNowMs()),
        @"runs": runs ?: @[],
    }, TLinkRunHistoryIndexPath(), 0);
}

static NSArray<NSRegularExpression *> *TLinkRunHistoryRedactionPatterns(void)
{
    static NSArray<NSRegularExpression *> *compiled = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *patterns = @[
        @"(?i)(license[_-]?key|setup[_-]?secret|vpn[_-]?password|shared[_-]?secret|private[_-]?key|admin[_-]?token)[\"']?\\s*[:=]\\s*[\"']?([^\\s,;\"']+)",
        @"(?i)bearer\\s+[A-Za-z0-9._~+\\/-]+=*",
        ];
        NSMutableArray<NSRegularExpression *> *expressions = [NSMutableArray arrayWithCapacity:patterns.count];
        for (NSString *pattern in patterns) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
            [expressions addObject:regex];
        }
        compiled = [expressions copy];
    });
    return compiled;
}

static NSString *TLinkRunHistoryRedactText(NSString *value)
{
    NSString *text = [value isKindOfClass:[NSString class]] ? value : @"";
    NSArray<NSRegularExpression *> *patterns = TLinkRunHistoryRedactionPatterns();
    for (NSUInteger index = 0; index < patterns.count; index++) {
        NSRegularExpression *regex = patterns[index];
        NSString *replacement = index == 0 ? @"$1=[REDACTED]" : @"Bearer [REDACTED]";
        text = [regex stringByReplacingMatchesInString:text
                                                options:0
                                                  range:NSMakeRange(0, text.length)
                                           withTemplate:replacement];
    }
    return text;
}

static NSArray<NSString *> *TLinkRunHistoryBoundedLogTail(NSArray<NSString *> *lines)
{
    if (![lines isKindOfClass:[NSArray class]] || lines.count == 0) return @[];
    NSUInteger start = lines.count > kTLinkFailureLogTailMaxLines ? lines.count - kTLinkFailureLogTailMaxLines : 0;
    NSMutableArray<NSString *> *tail = [NSMutableArray array];
    for (NSUInteger i = start; i < lines.count; i++) {
        id raw = lines[i];
        NSString *line = TLinkRunHistoryRedactText([raw isKindOfClass:[NSString class]] ? raw : [raw description]);
        if (line.length > kTLinkFailureLogLineMaxCharacters) line = [line substringToIndex:kTLinkFailureLogLineMaxCharacters];
        [tail addObject:line ?: @""];
    }
    while (tail.count > 0 && [tail.firstObject length] == 0) [tail removeObjectAtIndex:0];
    return tail;
}

static NSArray<NSString *> *TLinkRunHistoryTailFromConsoleFile(NSString *path)
{
    if (path.length == 0) return @[];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long size = [attributes fileSize];
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return @[];
    @try {
        if (size > kTLinkFailureConsoleLogMaxBytes) [handle seekToFileOffset:size - kTLinkFailureConsoleLogMaxBytes];
        NSData *data = [handle readDataToEndOfFile];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        return TLinkRunHistoryBoundedLogTail([text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
    } @catch (__unused NSException *exception) {
        return @[];
    } @finally {
        [handle closeFile];
    }
}

static BOOL TLinkRunHistoryRemoveArtifact(NSString *path)
{
    int result;
    do { result = unlink(path.fileSystemRepresentation); } while (result != 0 && errno == EINTR);
    return result == 0 || errno == ENOENT;
}

static uint64_t sTLinkRunHistoryPersistenceFailures = 0;
static NSDictionary *sTLinkRunHistoryLastPersistenceFailure = nil;
static BOOL sTLinkRunHistoryRecovered = NO;

// All accesses are protected by the existing process-local history monitor.
static void TLinkRunHistoryPersistenceFailure(NSString *operation, NSString *stage, NSString *code)
{
    // A required mutation write may have changed files before reporting failure.
    // Recheck the authoritative index on the next mutation in this process.
    if (([operation isEqualToString:@"begin"] || [operation isEqualToString:@"finish"]) &&
        ([stage isEqualToString:@"evidence"] || [stage isEqualToString:@"record"] || [stage isEqualToString:@"index"])) {
        sTLinkRunHistoryRecovered = NO;
    }
    if (sTLinkRunHistoryPersistenceFailures != UINT64_MAX) sTLinkRunHistoryPersistenceFailures++;
    sTLinkRunHistoryLastPersistenceFailure = @{
        @"operation": operation, @"stage": stage, @"code": code,
        @"at_ms": @(TLinkRunHistoryNowMs()),
    };
}

// Bounded index reads: caller holds the history monitor and file lock.
static NSData *TLinkRunHistoryReadIndexData(BOOL *missing, NSString **code)
{
    int fd = open(TLinkRunHistoryIndexPath().fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        if (errno == ENOENT) *missing = YES;
        else *code = @"read_failed";
        return nil;
    }
    @try {
        struct stat indexInfo;
        if (fstat(fd, &indexInfo) != 0 || !S_ISREG(indexInfo.st_mode) || indexInfo.st_size < 0) {
            *code = @"read_failed"; return nil;
        }
        if ((uint64_t)indexInfo.st_size > kTLinkRunHistoryIndexMaxBytes) {
            *code = @"index_too_large"; return nil;
        }
        NSMutableData *indexData = [NSMutableData dataWithLength:(NSUInteger)indexInfo.st_size];
        if (!indexData) { *code = @"read_failed"; return nil; }
        NSUInteger offset = 0;
        while (offset < indexData.length) {
            size_t count = MIN(indexData.length - offset, (NSUInteger)65536);
            ssize_t got = read(fd, (uint8_t *)indexData.mutableBytes + offset, count);
            if (got < 0 && errno == EINTR) continue;
            if (got <= 0) { *code = @"read_failed"; return nil; }
            offset += (NSUInteger)got;
        }
        // Cooperating atomic replacements leave this opened inode stable.
        uint8_t extra;
        ssize_t got;
        do { got = read(fd, &extra, 1); } while (got < 0 && errno == EINTR);
        if (got != 0) {
            *code = got > 0 && indexData.length == kTLinkRunHistoryIndexMaxBytes ? @"index_too_large" : @"read_failed";
            return nil;
        }
        return indexData;
    } @finally { close(fd); }
}

// All persisted reads distinguish a first run from unreadable or damaged history.
// Read-only status never repairs metadata or rebuilds an index from artifacts.
static NSMutableArray<NSDictionary *> *TLinkRunHistoryReadCheckedIndex(NSString *operation)
{
    BOOL missing = NO;
    NSString *code = nil;
    NSData *data = TLinkRunHistoryReadIndexData(&missing, &code);
    if (!data) {
        if (missing) return [NSMutableArray array];
        TLinkRunHistoryPersistenceFailure(operation, @"read", code ?: @"read_failed");
        return nil;
    }
    id object = data.length > 0
        ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    BOOL valid = [object isKindOfClass:[NSDictionary class]];
    id schema = valid ? object[@"schema"] : nil;
    id records = valid ? object[@"runs"] : nil;
    valid = [schema isKindOfClass:[NSString class]] && [schema isEqualToString:TLinkRunHistorySchemaV1] &&
        [records isKindOfClass:[NSArray class]];
    NSMutableSet<NSString *> *identities = [NSMutableSet set];
    if (valid) {
        for (id record in records) {
            id runId = [record isKindOfClass:[NSDictionary class]] ? record[@"run_id"] : nil;
            if (![runId isKindOfClass:[NSString class]] || [runId length] == 0 || [identities containsObject:runId]) {
                valid = NO;
                break;
            }
            [identities addObject:runId];
        }
    }
    if (!valid) {
        TLinkRunHistoryPersistenceFailure(operation, @"read", @"invalid_index");
        return nil;
    }
    return [records mutableCopy];
}

// Repair only committed, retained metadata. Caller holds the monitor and flock.
static BOOL TLinkRunHistoryRepairJSON(NSDictionary *expected, NSString *path, NSString *operation)
{
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingPrettyPrinted error:nil];
    if (!encoded) { TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_invalid_index"); return NO; }
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
    if (fd < 0 && errno != ENOENT) {
        TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed");
        return NO;
    }
    if (fd >= 0) {
        @try {
            struct stat info;
            if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size < 0) {
                TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed");
                return NO;
            }
            // Different sizes already prove a mismatch. Never read an arbitrary
            // artifact's full length; cap reads at the authoritative JSON size.
            if ((uint64_t)info.st_size == encoded.length) {
                NSMutableData *data = [NSMutableData dataWithLength:encoded.length];
                NSUInteger offset = 0;
                while (offset < data.length) {
                    size_t count = MIN(data.length - offset, (NSUInteger)65536);
                    ssize_t got = read(fd, (uint8_t *)data.mutableBytes + offset, count);
                    if (got < 0 && errno == EINTR) continue;
                    if (got <= 0) { TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed"); return NO; }
                    offset += (NSUInteger)got;
                }
                id stored = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([stored isEqual:expected]) return YES;
            }
        } @finally { close(fd); }
    }
    if (!TLinkRunHistoryWriteJSON(expected, path)) {
        TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_write_failed");
        return NO;
    }
    return YES;
}

static BOOL TLinkRunHistoryRecover(NSArray<NSDictionary *> *runs, NSString *operation)
{
    if (sTLinkRunHistoryRecovered) return YES;
    // Preflight the whole repair set before touching any file. Never follow
    // persisted paths outside the exact per-ID locations or alias two IDs.
    BOOL valid = runs.count <= kTLinkRunHistoryMaxRecords;
    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    for (NSDictionary *record in runs) {
        NSString *runId = record[@"run_id"];
        NSString *name = [TLinkRunHistorySanitize(runId) stringByAppendingString:@".json"];
        NSString *recordPath = [TLinkRunHistoryRunsPath() stringByAppendingPathComponent:name];
        id evidence = record[@"failure_evidence"];
        valid = valid && [record[@"schema"] isEqual:TLinkRunHistorySchemaV1] &&
            [record[@"record_path"] isKindOfClass:[NSString class]] && [record[@"record_path"] isEqual:recordPath] &&
            ![paths containsObject:recordPath] && [evidence isKindOfClass:[NSDictionary class]];
        if (valid && [evidence count] > 0) {
            NSString *metadataPath = [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:name];
            valid = [evidence[@"schema"] isEqual:TLinkFailureEvidenceSchemaV1] &&
                [evidence[@"run_id"] isEqual:runId] && [evidence[@"metadata_path"] isEqual:metadataPath];
        }
        if (!valid) break;
        [paths addObject:recordPath];
    }
    if (!valid) { TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_invalid_index"); return NO; }
    for (NSString *directory in @[TLinkRunHistoryRootPath(), TLinkRunHistoryRunsPath(), TLinkRunHistoryEvidencePath()]) {
        struct stat info;
        if (lstat(directory.fileSystemRepresentation, &info) != 0 || !S_ISDIR(info.st_mode)) {
            TLinkRunHistoryPersistenceFailure(operation, @"recovery", @"recovery_read_failed");
            return NO;
        }
    }
    for (NSDictionary *record in runs) {
        @autoreleasepool {
            NSDictionary *evidence = record[@"failure_evidence"];
            if (evidence.count > 0 && !TLinkRunHistoryRepairJSON(evidence, evidence[@"metadata_path"], operation)) return NO;
            if (!TLinkRunHistoryRepairJSON(record, record[@"record_path"], operation)) return NO;
        }
    }
    sTLinkRunHistoryRecovered = YES;
    return YES;
}

// The held lock inode is also the intent marker: length 0 clean, 1 pending.
// Cooperating writers never replace/unlink it. No power-loss ordering is implied.
static BOOL TLinkRunHistorySetPending(int lockFd, BOOL pending, NSString *operation, NSString *stage)
{
    int result;
    do { result = ftruncate(lockFd, pending ? 1 : 0); } while (result != 0 && errno == EINTR);
    if (result == 0) return YES;
    sTLinkRunHistoryRecovered = NO;
    TLinkRunHistoryPersistenceFailure(operation, stage, @"history_marker_write_failed");
    return NO;
}

static BOOL TLinkRunHistoryPrepareRecovery(NSArray<NSDictionary *> *runs, NSString *operation, int lockFd)
{
    struct stat marker, root;
    if (lstat(TLinkRunHistoryRootPath().fileSystemRepresentation, &root) != 0 || !S_ISDIR(root.st_mode) ||
        fstat(lockFd, &marker) != 0) {
        sTLinkRunHistoryRecovered = NO;
        TLinkRunHistoryPersistenceFailure(operation, @"recovery_marker", @"history_marker_read_failed");
        return NO;
    }
    if (!S_ISREG(marker.st_mode) || marker.st_nlink != 1 || marker.st_size < 0 || marker.st_size > 1) {
        sTLinkRunHistoryRecovered = NO;
        TLinkRunHistoryPersistenceFailure(operation, @"recovery_marker", @"history_marker_invalid");
        return NO;
    }
    if (marker.st_size == 1) sTLinkRunHistoryRecovered = NO;
    if (!sTLinkRunHistoryRecovered && marker.st_size == 0 &&
        !TLinkRunHistorySetPending(lockFd, YES, operation, @"recovery_marker")) return NO;
    return TLinkRunHistoryRecover(runs, operation);
}

static NSArray<NSDictionary *> *TLinkRunHistoryTrim(NSMutableArray<NSDictionary *> *runs)
{
    NSMutableArray<NSDictionary *> *retired = [NSMutableArray array];
    while (runs.count > kTLinkRunHistoryMaxRecords) {
        [retired addObject:runs.lastObject];
        [runs removeLastObject];
    }
    return retired;
}

// Retirement owns only exact per-ID leaves, never control files or directories.
static void TLinkRunHistoryPruneArtifact(id rawPath, NSString *expected, NSSet<NSString *> *retained)
{
    if (![rawPath isKindOfClass:[NSString class]] || [rawPath length] == 0) return;
    NSString *path = [rawPath stringByStandardizingPath];
    if (![path hasPrefix:[TLinkRunHistoryRootPath() stringByAppendingString:@"/"]]) return;
    if ([retained containsObject:path]) return;
    if (![path isEqualToString:expected]) {
        TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"path_not_owned");
        return;
    }
    for (NSString *directory in @[TLinkRunHistoryRootPath(), path.stringByDeletingLastPathComponent]) {
        struct stat info;
        if (lstat(directory.fileSystemRepresentation, &info) != 0) {
            if (errno != ENOENT) TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"remove_failed");
            return;
        }
        if (!S_ISDIR(info.st_mode)) {
            TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"path_not_owned");
            return;
        }
    }
    if (!TLinkRunHistoryRemoveArtifact(path)) TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"remove_failed");
}

static void TLinkRunHistoryPrune(NSArray<NSDictionary *> *retired, NSArray<NSDictionary *> *runs)
{
    if (retired.count == 0) return;
    @try { try {
        NSMutableSet<NSString *> *retained = [NSMutableSet set];
        for (NSDictionary *record in runs) {
            NSDictionary *evidence = [record[@"failure_evidence"] isKindOfClass:[NSDictionary class]] ? record[@"failure_evidence"] : @{};
            for (id path in @[record[@"record_path"] ?: @"", evidence[@"metadata_path"] ?: @"", evidence[@"screenshot_path"] ?: @""]) {
                if ([path isKindOfClass:[NSString class]] && [path length] > 0) [retained addObject:[path stringByStandardizingPath]];
            }
        }
        for (NSDictionary *oldest in retired) {
            @try { try {
                NSString *runId = [oldest[@"run_id"] isKindOfClass:[NSString class]] ? oldest[@"run_id"] : @"";
                if (runId.length == 0) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"path_not_owned"); continue; }
                NSString *name = TLinkRunHistorySanitize(runId);
                TLinkRunHistoryPruneArtifact(oldest[@"record_path"], [TLinkRunHistoryRunsPath() stringByAppendingPathComponent:[name stringByAppendingString:@".json"]], retained);
                NSDictionary *evidence = [oldest[@"failure_evidence"] isKindOfClass:[NSDictionary class]] ? oldest[@"failure_evidence"] : @{};
                TLinkRunHistoryPruneArtifact(evidence[@"metadata_path"], [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[name stringByAppendingString:@".json"]], retained);
                TLinkRunHistoryPruneArtifact(evidence[@"screenshot_path"], [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:[name stringByAppendingString:@".png"]], retained);
            } catch (...) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); } }
            @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); }
        }
    } catch (...) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); } }
    @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"prune", @"artifacts", @"exception"); }
}

NSDictionary *TLinkRunHistoryBegin(NSString *runtime,
                                   NSString *bundlePath,
                                   NSString *entryPath,
                                   NSDictionary *playSettings)
{
    @synchronized (TLinkRunHistoryLock()) {
        TLinkRunHistoryEnsureDirectories();
        int lockFd = TLinkRunHistoryAcquireFileLock();
        if (lockFd < 0) { TLinkRunHistoryPersistenceFailure(@"begin", @"lock", @"history_lock_failed"); return @{}; }
        NSString *runId = nil;
        NSDictionary *record = nil;
        NSString *stage = @"prepare";
        @try { try {
            runId = [NSUUID UUID].UUIDString.lowercaseString;
            uint64_t now = TLinkRunHistoryNowMs();
            NSString *recordPath = [TLinkRunHistoryRunsPath() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@.json", TLinkRunHistorySanitize(runId)]];
            record = @{
                @"schema": TLinkRunHistorySchemaV1,
                @"run_id": runId,
                @"runtime": runtime ?: @"unknown",
                @"bundle_path": bundlePath ?: @"",
                @"entry_path": entryPath ?: @"",
                @"state": @"running",
                @"started_at_ms": @(now),
                @"ended_at_ms": @0,
                @"duration_ms": @0,
                @"error": @"",
                @"play_settings": [playSettings isKindOfClass:[NSDictionary class]] ? playSettings : @{},
                @"failure_evidence": @{},
                @"record_path": recordPath,
            };
            stage = @"read";
            NSMutableArray *runs = TLinkRunHistoryReadCheckedIndex(@"begin");
            if (!runs) return @{};
            stage = @"recovery";
            if (!TLinkRunHistoryPrepareRecovery(runs, @"begin", lockFd)) return @{};
            [runs insertObject:record atIndex:0];
            NSArray *retired = TLinkRunHistoryTrim(runs);
            stage = @"intent";
            if (!TLinkRunHistorySetPending(lockFd, YES, @"begin", stage)) return @{};
            stage = @"record";
            if (!TLinkRunHistoryWriteJSON(record, recordPath)) { TLinkRunHistoryPersistenceFailure(@"begin", stage, @"write_failed"); return @{}; }
            stage = @"index";
            if (!TLinkRunHistoryWriteIndex(runs)) { TLinkRunHistoryPersistenceFailure(@"begin", stage, @"write_failed"); return @{}; }
            stage = @"commit_marker";
            (void)TLinkRunHistorySetPending(lockFd, NO, @"begin", stage);
            TLinkRunHistoryPrune(retired, runs);
        } catch (...) { TLinkRunHistoryPersistenceFailure(@"begin", stage, @"exception"); return @{}; } }
        @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"begin", stage, @"exception"); return @{}; }
        @finally { TLinkRunHistoryReleaseFileLock(lockFd); }
        TLinkEventChannelPublish(runtime ?: @"unknown",
                                 @"script.run",
                                 @"started",
                                 @{
                                     @"run_id": runId,
                                     @"bundle_path": bundlePath ?: @"",
                                     @"entry_path": entryPath ?: @"",
                                 });
        return record;
    }
}

NSDictionary *TLinkRunHistoryFinish(NSString *runId,
                                    NSString *state,
                                    NSString *error,
                                    NSArray<NSString *> *logTail,
                                    NSString *consoleLogPath,
                                    NSString *screenshotPath,
                                    NSString *screenshotError,
                                    NSDictionary *extra)
{
    if (runId.length == 0) return @{};
    @synchronized (TLinkRunHistoryLock()) {
        TLinkRunHistoryEnsureDirectories();
        // Preparation is process-serialized, but does not hold the shared file lock.
        NSString *terminalState = state.length > 0 ? state : @"finished";
        NSString *redactedError = TLinkRunHistoryRedactText(error ?: @"");
        if (redactedError.length > kTLinkFailureErrorMaxCharacters) {
            redactedError = [redactedError substringToIndex:kTLinkFailureErrorMaxCharacters];
        }
        BOOL failed = [terminalState isEqualToString:@"failed"] || [terminalState isEqualToString:@"license_revoked"];
        NSArray *tail = @[];
        if (failed) {
            tail = TLinkRunHistoryBoundedLogTail(logTail);
            if (tail.count == 0) tail = TLinkRunHistoryTailFromConsoleFile(consoleLogPath);
        }
        int lockFd = TLinkRunHistoryAcquireFileLock();
        if (lockFd < 0) { TLinkRunHistoryPersistenceFailure(@"finish", @"lock", @"history_lock_failed"); return @{}; }
        NSMutableDictionary *record = nil;
        NSString *stage = @"read";
        @try { try {
            NSMutableArray<NSDictionary *> *runs = TLinkRunHistoryReadCheckedIndex(@"finish");
            if (!runs) return @{};
            stage = @"recovery";
            if (!TLinkRunHistoryPrepareRecovery(runs, @"finish", lockFd)) return @{};
            stage = @"prepare";
            NSUInteger index = [runs indexOfObjectPassingTest:^BOOL(NSDictionary *record, NSUInteger idx, BOOL *stop) {
                (void)idx;
                if ([record[@"run_id"] isEqualToString:runId]) { *stop = YES; return YES; }
                return NO;
            }];
            record = index != NSNotFound ? [runs[index] mutableCopy] : [NSMutableDictionary dictionary];
            uint64_t endedAt = TLinkRunHistoryNowMs();
            uint64_t startedAt = [record[@"started_at_ms"] unsignedLongLongValue];
            record[@"schema"] = TLinkRunHistorySchemaV1;
            record[@"run_id"] = runId;
            record[@"state"] = terminalState;
            record[@"ended_at_ms"] = @(endedAt);
            record[@"duration_ms"] = @(endedAt >= startedAt ? endedAt - startedAt : 0);
            record[@"error"] = redactedError;
            if (extra.count > 0) record[@"extra"] = extra;

            stage = @"intent";
            if (!TLinkRunHistorySetPending(lockFd, YES, @"finish", stage)) return @{};
            if (failed) {
                stage = @"evidence";
                NSString *metadataPath = [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.json", TLinkRunHistorySanitize(runId)]];
                NSDictionary *screenshotAttributes = screenshotPath.length > 0
                    ? [[NSFileManager defaultManager] attributesOfItemAtPath:screenshotPath error:nil] : nil;
                BOOL screenshotPresent = [screenshotAttributes fileSize] > 0;
                if (screenshotPresent) {
                    chmod(screenshotPath.fileSystemRepresentation, 0640);
                    lchown(screenshotPath.fileSystemRepresentation, 501, 501);
                }
                NSDictionary *evidence = @{
                    @"schema": TLinkFailureEvidenceSchemaV1,
                    @"run_id": runId,
                    @"captured_at_ms": @(endedAt),
                    @"error": redactedError,
                    @"log_tail": tail ?: @[],
                    @"log_tail_truncated": @([logTail isKindOfClass:[NSArray class]] && logTail.count > kTLinkFailureLogTailMaxLines),
                    @"console_log_path": consoleLogPath ?: @"",
                    @"screenshot_path": screenshotPresent ? screenshotPath : @"",
                    @"screenshot_captured": @(screenshotPresent),
                    @"screenshot_error": screenshotPresent ? @"" : (screenshotError ?: @"not_captured"),
                    @"metadata_path": metadataPath,
                };
                if (!TLinkRunHistoryWriteJSON(evidence, metadataPath)) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"write_failed"); return @{}; }
                record[@"failure_evidence"] = evidence;
            } else {
                record[@"failure_evidence"] = @{};
            }

            NSString *recordPath = [record[@"record_path"] isKindOfClass:[NSString class]] ? record[@"record_path"] : @"";
            if (recordPath.length == 0) {
                recordPath = [TLinkRunHistoryRunsPath() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.json", TLinkRunHistorySanitize(runId)]];
                record[@"record_path"] = recordPath;
            }
            if (index != NSNotFound) [runs replaceObjectAtIndex:index withObject:record];
            else [runs insertObject:record atIndex:0];
            NSArray *retired = TLinkRunHistoryTrim(runs);
            stage = @"record";
            if (!TLinkRunHistoryWriteJSON(record, recordPath)) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"write_failed"); return @{}; }
            stage = @"index";
            if (!TLinkRunHistoryWriteIndex(runs)) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"write_failed"); return @{}; }
            stage = @"commit_marker";
            (void)TLinkRunHistorySetPending(lockFd, NO, @"finish", stage);
            TLinkRunHistoryPrune(retired, runs);
        } catch (...) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"exception"); return @{}; } }
        @catch (__unused NSException *exception) { TLinkRunHistoryPersistenceFailure(@"finish", stage, @"exception"); return @{}; }
        @finally { TLinkRunHistoryReleaseFileLock(lockFd); }
        TLinkEventChannelPublish(record[@"runtime"] ?: @"unknown",
                                 @"script.run",
                                 terminalState,
                                 @{
                                     @"run_id": runId,
                                     @"state": terminalState,
                                     @"duration_ms": record[@"duration_ms"] ?: @0,
                                     @"error": redactedError ?: @"",
                                     @"evidence_available": @([record[@"failure_evidence"] count] > 0),
                                 });
        return record;
    }
}

// Failed status counts/runs are unknown placeholders, never an empty-history acknowledgment.
static NSDictionary *TLinkRunHistorySnapshotFailure(NSString *code)
{
    return @{
            @"schema": TLinkRunHistorySchemaV1,
            @"state": @"error",
            @"error": code,
            @"root_path": TLinkRunHistoryRootPath(),
            @"persistence_diagnostics": @{@"scope": @"process", @"failure_count": @(sTLinkRunHistoryPersistenceFailures), @"last_failure": sTLinkRunHistoryLastPersistenceFailure ?: @{}},
            @"retention_max_runs": @(kTLinkRunHistoryMaxRecords),
            @"failure_log_tail_max_lines": @(kTLinkFailureLogTailMaxLines),
            @"failure_error_max_characters": @(kTLinkFailureErrorMaxCharacters),
            @"status_log_tail_max_lines": @(kTLinkStatusLogTailMaxLines),
            @"status_log_line_max_characters": @(kTLinkStatusLogLineMaxCharacters),
            @"status_error_max_characters": @(kTLinkStatusErrorMaxCharacters),
            @"failure_console_read_max_bytes": @(kTLinkFailureConsoleLogMaxBytes),
            @"total_count": @0,
            @"failed_count": @0,
            @"runs": @[],
    };
}

NSDictionary *TLinkRunHistorySnapshot(NSUInteger limit)
{
    @synchronized (TLinkRunHistoryLock()) {
        NSString *stage = @"prepare";
        @try { try {
            TLinkRunHistoryEnsureDirectories();
            stage = @"lock";
            int lockFd = TLinkRunHistoryAcquireFileLock();
            if (lockFd < 0) {
                TLinkRunHistoryPersistenceFailure(@"snapshot", stage, @"history_lock_failed");
                return TLinkRunHistorySnapshotFailure(@"history_snapshot_lock_failed");
            }
            stage = @"read";
            NSMutableArray<NSDictionary *> *runs = nil;
            @try {
                runs = TLinkRunHistoryReadCheckedIndex(@"snapshot");
            } @finally {
                TLinkRunHistoryReleaseFileLock(lockFd);
            }
            if (!runs) return TLinkRunHistorySnapshotFailure(
                [sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"invalid_index"]
                    ? @"history_snapshot_invalid_index" :
                ([sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"index_too_large"]
                    ? @"history_snapshot_too_large" : @"history_snapshot_read_failed"));
            stage = @"format";
            // The decoded graph belongs to this call; formatting needs no file lock.
            NSUInteger bounded = limit == 0 ? kTLinkRunHistorySnapshotDefault : MIN(limit, kTLinkRunHistorySnapshotMax);
            NSArray *selected = runs.count > bounded ? [runs subarrayWithRange:NSMakeRange(0, bounded)] : [runs copy];
            NSMutableArray<NSDictionary *> *statusRuns = [NSMutableArray arrayWithCapacity:selected.count];
            for (NSDictionary *source in selected) {
                NSMutableDictionary *run = [source mutableCopy];
                NSString *sourceError = [source[@"error"] isKindOfClass:[NSString class]] ? source[@"error"] : @"";
                if (sourceError.length > kTLinkStatusErrorMaxCharacters) {
                    run[@"error"] = [sourceError substringToIndex:kTLinkStatusErrorMaxCharacters];
                    run[@"status_error_truncated"] = @YES;
                }
                NSDictionary *sourceEvidence = [source[@"failure_evidence"] isKindOfClass:[NSDictionary class]]
                    ? source[@"failure_evidence"] : @{};
                if (sourceEvidence.count > 0) {
                    NSMutableDictionary *evidence = [sourceEvidence mutableCopy];
                    NSString *evidenceError = [sourceEvidence[@"error"] isKindOfClass:[NSString class]]
                        ? sourceEvidence[@"error"] : @"";
                    if (evidenceError.length > kTLinkStatusErrorMaxCharacters) {
                        evidence[@"error"] = [evidenceError substringToIndex:kTLinkStatusErrorMaxCharacters];
                        evidence[@"status_error_truncated"] = @YES;
                    }
                    NSArray *sourceTail = [sourceEvidence[@"log_tail"] isKindOfClass:[NSArray class]]
                        ? sourceEvidence[@"log_tail"] : @[];
                    NSUInteger start = sourceTail.count > kTLinkStatusLogTailMaxLines
                        ? sourceTail.count - kTLinkStatusLogTailMaxLines : 0;
                    NSMutableArray<NSString *> *tail = [NSMutableArray array];
                    for (NSUInteger index = start; index < sourceTail.count; index++) {
                        NSString *line = [sourceTail[index] isKindOfClass:[NSString class]]
                            ? sourceTail[index] : [sourceTail[index] description];
                        if (line.length > kTLinkStatusLogLineMaxCharacters) {
                            line = [line substringToIndex:kTLinkStatusLogLineMaxCharacters];
                        }
                        [tail addObject:line ?: @""];
                    }
                    evidence[@"log_tail"] = tail;
                    evidence[@"status_log_tail_truncated"] = @(sourceTail.count > tail.count);
                    run[@"failure_evidence"] = evidence;
                }
                [statusRuns addObject:run];
            }
            NSUInteger failed = 0;
            for (NSDictionary *run in runs) {
                NSString *state = run[@"state"];
                if ([state isEqualToString:@"failed"] || [state isEqualToString:@"license_revoked"]) failed++;
            }
            NSDictionary *snapshot = @{
                @"schema": TLinkRunHistorySchemaV1,
                @"state": @"implemented",
                @"root_path": TLinkRunHistoryRootPath(),
                @"persistence_diagnostics": @{@"scope": @"process", @"failure_count": @(sTLinkRunHistoryPersistenceFailures), @"last_failure": sTLinkRunHistoryLastPersistenceFailure ?: @{}},
                @"retention_max_runs": @(kTLinkRunHistoryMaxRecords),
                @"failure_log_tail_max_lines": @(kTLinkFailureLogTailMaxLines),
                @"failure_error_max_characters": @(kTLinkFailureErrorMaxCharacters),
                @"status_log_tail_max_lines": @(kTLinkStatusLogTailMaxLines),
                @"status_log_line_max_characters": @(kTLinkStatusLogLineMaxCharacters),
                @"status_error_max_characters": @(kTLinkStatusErrorMaxCharacters),
                @"failure_console_read_max_bytes": @(kTLinkFailureConsoleLogMaxBytes),
                @"total_count": @(runs.count),
                @"failed_count": @(failed),
                @"runs": statusRuns,
            };
            return snapshot;
        } catch (...) {} }
        @catch (__unused NSException *exception) {}
        TLinkRunHistoryPersistenceFailure(@"snapshot", stage, @"exception");
        return TLinkRunHistorySnapshotFailure(@"history_snapshot_exception");
    }
}
