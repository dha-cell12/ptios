// Frozen from 208bf6a0; prepare/line writer/console enqueue compatibility oracle.
- (void)prepareConsoleLogFiles {
    if (![_bundlePath isKindOfClass:[NSString class]] || [_bundlePath length] == 0 ||
        ![_runId isKindOfClass:[NSString class]] || [_runId length] == 0) {
        return;
    }

    NSString *dir = [_bundlePath stringByAppendingPathComponent:@"_logs"];
    NSError *mkdirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&mkdirError]) {
        NSLog(@"com.tlinkauto.jsruntime: unable to create log directory: %@", mkdirError);
        return;
    }

    _consoleLogPath = [dir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.log", TLinkautoJSSanitizeFileComponent(_runId)]];
    _consoleLatestLogPath = [dir stringByAppendingPathComponent:@"latest.log"];

    NSString *header = [NSString stringWithFormat:@"[%@] run %@ started\n", [NSDate date], _runId];
    [header writeToFile:_consoleLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [header writeToFile:_consoleLatestLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)appendLine:(NSString *)line toConsolePath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || [path length] == 0 ||
        ![line isKindOfClass:[NSString class]]) {
        return;
    }

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkautoJSMaxConsoleLogBytes) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }

    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @finally {
        [handle closeFile];
    }
}

- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message {
    os_unfair_lock_lock(&_logStateLock);
    BOOL accepting = _acceptingLogs;
    os_unfair_lock_unlock(&_logStateLock);
    if (!accepting) return;

    NSString *safeLevel = TLinkautoJSSanitizeFileComponent(level ?: @"log");
    NSString *safeMessage = [message isKindOfClass:[NSString class]] ? message : [message description];
    safeMessage = [safeMessage ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\n",
                      [NSDate date], _runId ?: @"", safeLevel, safeMessage];
    NSString *runPath = [_consoleLogPath copy];
    NSString *latestPath = [_consoleLatestLogPath copy];

    dispatch_async(_logQueue, ^{
        [self appendLine:line toConsolePath:runPath];
        [self appendLine:line toConsolePath:latestPath];
    });
}

