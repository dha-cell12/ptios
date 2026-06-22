#import "TLinkautoJSLogSink.h"

static const unsigned long long kTLinkautoJSMaxConsoleLogBytes = 512 * 1024;

@implementation TLinkautoJSFileLogSink {
    NSString *_runId;
    NSString *_bundlePath;
    NSString *_currentLogPath;
    NSString *_latestLogPath;
    NSFileHandle *_currentLogHandle;
    NSFileHandle *_latestLogHandle;
}

- (instancetype)initWithRunId:(NSString *)runId bundlePath:(NSString *)bundlePath {
    self = [super init];
    if (self) {
        _runId = runId;
        _bundlePath = bundlePath;
        [self prepareConsoleLogFiles];
    }
    return self;
}

- (void)prepareConsoleLogFiles {
    if (!_bundlePath) return;

    NSString *logsDir = [_bundlePath stringByAppendingPathComponent:@"_logs"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:logsDir]) {
        [fm createDirectoryAtPath:logsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    _currentLogPath = [logsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.log", _runId ?: @"unknown"]];
    _latestLogPath = [logsDir stringByAppendingPathComponent:@"latest.log"];

    for (NSString *path in @[_currentLogPath, _latestLogPath]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if (attrs && [attrs fileSize] > kTLinkautoJSMaxConsoleLogBytes) {
            [fm removeItemAtPath:path error:nil];
        }
        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path contents:nil attributes:nil];
        }
    }

    _currentLogHandle = [NSFileHandle fileHandleForWritingAtPath:_currentLogPath];
    [_currentLogHandle seekToEndOfFile];

    _latestLogHandle = [NSFileHandle fileHandleForWritingAtPath:_latestLogPath];
    [_latestLogHandle seekToEndOfFile];
}

- (void)logWithLevel:(NSString *)level message:(NSString *)message {
    if (!message) return;

    NSString *bundleName = [[_bundlePath lastPathComponent] stringByDeletingPathExtension] ?: @"unknown";
    NSString *logString = [NSString stringWithFormat:@"[%@] [%@] %@\n", _runId ?: @"unknown", level ?: @"info", message];

    NSLog(@"com.tlinkauto.springboard: JS [%@] [%@] %@", bundleName, level, message);

    if (_currentLogHandle || _latestLogHandle) {
        NSData *data = [logString dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            @try {
                if (_currentLogHandle) {
                    [_currentLogHandle writeData:data];
                    [_currentLogHandle synchronizeFile];
                }
                if (_latestLogHandle) {
                    [_latestLogHandle writeData:data];
                    [_latestLogHandle synchronizeFile];
                }
            } @catch (NSException *e) {
                NSLog(@"com.tlinkauto.springboard: Failed to write JS log: %@", e);
            }
        }
    }
}

- (void)close {
    [_currentLogHandle closeFile];
    _currentLogHandle = nil;
    [_latestLogHandle closeFile];
    _latestLogHandle = nil;
}

- (NSString *)currentLogPath {
    return _currentLogPath;
}

- (NSString *)latestLogPath {
    return _latestLogPath;
}

@end
